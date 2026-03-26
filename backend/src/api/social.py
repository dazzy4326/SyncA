"""
social.py - ソーシャル / マッチング機能モジュール

屋内測位システムのソーシャル機能を提供する:
  1. スキル検索 + 位置情報
  2. 近くのユーザーマッチング
  3. コラボレーション掲示板
  4. インタラクション履歴
  5. ランチマッチング
  6. ソーシャルレコメンデーション
"""

import math
import logging
import random
from datetime import datetime, date, timedelta
from collections import defaultdict
from itertools import combinations

from sqlalchemy import text
from ..app import db

from .config_loader import ZONE_BOUNDARIES, POSITION_STALENESS_MINUTES

logger = logging.getLogger(__name__)


# ==========================================================
#  テーブル初期化
# ==========================================================

def init_social_tables():
    """
    ソーシャル機能に必要な5つのテーブルを作成する (存在しない場合のみ)
    - collaboration_posts
    - collaboration_responses
    - interaction_log
    - lunch_matches
    - user_availability
    """
    table_ddls = [
        text("""
            CREATE TABLE IF NOT EXISTS collaboration_posts (
                id            INT AUTO_INCREMENT PRIMARY KEY,
                beacon_id     VARCHAR(100) NOT NULL,
                user_name     VARCHAR(200),
                post_type     VARCHAR(50)  DEFAULT 'help',
                title         VARCHAR(500) NOT NULL,
                description   TEXT,
                required_skills VARCHAR(1000),
                status        VARCHAR(20)  DEFAULT 'open',
                created_at    DATETIME     DEFAULT CURRENT_TIMESTAMP,
                updated_at    DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            )
        """),
        text("""
            CREATE TABLE IF NOT EXISTS collaboration_responses (
                id            INT AUTO_INCREMENT PRIMARY KEY,
                post_id       INT NOT NULL,
                beacon_id     VARCHAR(100) NOT NULL,
                user_name     VARCHAR(200),
                message       TEXT,
                created_at    DATETIME     DEFAULT CURRENT_TIMESTAMP
            )
        """),
        text("""
            CREATE TABLE IF NOT EXISTS interaction_log (
                id            INT AUTO_INCREMENT PRIMARY KEY,
                beacon_id_a   VARCHAR(100) NOT NULL,
                beacon_id_b   VARCHAR(100) NOT NULL,
                distance_mm   FLOAT,
                zone_name     VARCHAR(100),
                recorded_at   DATETIME     DEFAULT CURRENT_TIMESTAMP
            )
        """),
        text("""
            CREATE TABLE IF NOT EXISTS lunch_matches (
                id            INT AUTO_INCREMENT PRIMARY KEY,
                beacon_id_a   VARCHAR(100) NOT NULL,
                beacon_id_b   VARCHAR(100) NOT NULL,
                match_type    VARCHAR(50)  DEFAULT 'random',
                match_date    DATE         NOT NULL,
                status        VARCHAR(20)  DEFAULT 'pending',
                common_interests VARCHAR(1000),
                created_at    DATETIME     DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY uq_lunch_pair_date (beacon_id_a, beacon_id_b, match_date)
            )
        """),
        text("""
            CREATE TABLE IF NOT EXISTS user_availability (
                beacon_id       VARCHAR(100) PRIMARY KEY,
                lunch_available BOOLEAN DEFAULT FALSE,
                collab_available BOOLEAN DEFAULT FALSE,
                focus_mode      BOOLEAN DEFAULT FALSE,
                status_message  VARCHAR(500),
                available_from  TIME,
                available_until TIME,
                updated_at      DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            )
        """),
    ]

    try:
        for ddl in table_ddls:
            db.session.execute(ddl)
        db.session.commit()
        logger.info("ソーシャルテーブルの初期化に成功しました")
        return True, None
    except Exception as e:
        db.session.rollback()
        logger.error(f"!!! ソーシャルテーブル初期化エラー: {e}", exc_info=True)
        return False, str(e)


# ==========================================================
#  ヘルパー: ゾーン判定
# ==========================================================

def _determine_zone(x, y):
    """
    座標 (x, y) がどのゾーンに属するかを判定する。
    ZONE_BOUNDARIES の各ゾーン矩形 (x_min, x_max, y_min, y_max) 内に
    座標が収まるかチェックし、最初にヒットしたゾーン名を返す。
    ZONE_BOUNDARIES の y は正の値で定義されているが、
    引数 y は物理座標系 (負の値) のため abs() で変換する。
    どのゾーンにも属さない場合は None を返す。
    """
    if not ZONE_BOUNDARIES:
        return None
    y_abs = abs(y) if y is not None else 0
    for zone_name, bounds in ZONE_BOUNDARIES.items():
        x_min = bounds.get("x_min", 0)
        x_max = bounds.get("x_max", 0)
        y_min = bounds.get("y_min", 0)
        y_max = bounds.get("y_max", 0)
        if x_min <= x <= x_max and y_min <= y_abs <= y_max:
            return zone_name
    return None


def _get_adjacent_zones(zone_name):
    """
    指定ゾーンに隣接するゾーンのリストを返す。
    隣接 = 境界矩形が辺または角で接触しているもの。
    """
    if not zone_name or zone_name not in ZONE_BOUNDARIES:
        return []
    target = ZONE_BOUNDARIES[zone_name]
    tx_min, tx_max = target.get("x_min", 0), target.get("x_max", 0)
    ty_min, ty_max = target.get("y_min", 0), target.get("y_max", 0)

    adjacent = []
    for other_name, bounds in ZONE_BOUNDARIES.items():
        if other_name == zone_name:
            continue
        ox_min, ox_max = bounds.get("x_min", 0), bounds.get("x_max", 0)
        oy_min, oy_max = bounds.get("y_min", 0), bounds.get("y_max", 0)
        # 重なりまたは接触判定
        if tx_min <= ox_max and tx_max >= ox_min and ty_min <= oy_max and ty_max >= oy_min:
            adjacent.append(other_name)
    return adjacent


# ==========================================================
#  Feature 1: スキル検索 + 位置情報
# ==========================================================

def search_users_with_position(skill=None):
    """
    スキルでユーザーを検索し、最新の位置情報を結合して返す。
    skill が None または空文字の場合は全ユーザーを返す。

    Returns:
        (list[dict], error_string | None)
        各dictは beacon_id, user_name, department, job_title, skills,
        matched_skill, profile_image, position ({x, y, status, zone}) を含む。
    """
    try:
        if skill and skill.strip():
            skill_pattern = f"%{skill.strip()}%"
            user_sql = text("""
                SELECT beacon_id, user_name, department, job_title,
                       skills, profile_image
                FROM user_profiles
                WHERE skills LIKE :skill_pattern
            """)
            user_result = db.session.execute(user_sql, {"skill_pattern": skill_pattern})
        else:
            user_sql = text("""
                SELECT beacon_id, user_name, department, job_title,
                       skills, profile_image
                FROM user_profiles
            """)
            user_result = db.session.execute(user_sql)

        users = [dict(row._mapping) for row in user_result]

        if not users:
            return [], None

        # 最新の位置情報を取得 (staleness フィルタ付き)
        pos_sql = text("""
            SELECT ep.beacon_id, ep.est_x, ep.est_y, ep.status
            FROM (
                SELECT *,
                       ROW_NUMBER() OVER(PARTITION BY beacon_id ORDER BY id DESC) as rn
                FROM estimated_positions
            ) AS ep
            WHERE ep.rn = 1
              AND ep.timestamp >= NOW() - INTERVAL :staleness MINUTE
        """)
        pos_result = db.session.execute(pos_sql, {"staleness": POSITION_STALENESS_MINUTES})
        pos_map = {}
        for row in pos_result:
            p = dict(row._mapping)
            pos_map[p["beacon_id"]] = p

        results = []
        for user in users:
            # マッチしたスキルを特定
            matched_skill = None
            if skill and skill.strip() and user.get("skills"):
                for s in user["skills"].split(","):
                    if skill.strip().lower() in s.strip().lower():
                        matched_skill = s.strip()
                        break

            pos_data = pos_map.get(user["beacon_id"])
            position = None
            if pos_data:
                x = float(pos_data["est_x"]) if pos_data["est_x"] is not None else None
                y = float(pos_data["est_y"]) if pos_data["est_y"] is not None else None
                zone = _determine_zone(x, y) if x is not None and y is not None else None
                position = {
                    "x": x,
                    "y": y,
                    "status": pos_data.get("status"),
                    "zone": zone,
                }

            results.append({
                "beacon_id": user["beacon_id"],
                "user_name": user["user_name"],
                "department": user["department"],
                "job_title": user["job_title"],
                "skills": user["skills"],
                "matched_skill": matched_skill,
                "profile_image": user.get("profile_image"),
                "position": position,
            })

        return results, None

    except Exception as e:
        logger.error(f"!!! search_users_with_position エラー: {e}", exc_info=True)
        return None, str(e)


# ==========================================================
#  Feature 2: 近くのユーザーマッチング
# ==========================================================

def get_matching_fields(profile_a, profile_b):
    """
    2つのプロフィール辞書を比較し、共通するスキル / 趣味のリストを返す。
    大文字小文字を無視して比較する。

    Returns:
        list[str] 例: ["skills:Python", "hobbies:ランニング"]
    """
    matching = []

    # スキル比較
    skills_a = {s.strip().lower(): s.strip() for s in (profile_a.get("skills") or "").split(",") if s.strip()}
    skills_b = {s.strip().lower(): s.strip() for s in (profile_b.get("skills") or "").split(",") if s.strip()}
    common_skills = set(skills_a.keys()) & set(skills_b.keys())
    for key in common_skills:
        matching.append(f"skills:{skills_a[key]}")

    # 趣味比較
    hobbies_a = {h.strip().lower(): h.strip() for h in (profile_a.get("hobbies") or "").split(",") if h.strip()}
    hobbies_b = {h.strip().lower(): h.strip() for h in (profile_b.get("hobbies") or "").split(",") if h.strip()}
    common_hobbies = set(hobbies_a.keys()) & set(hobbies_b.keys())
    for key in common_hobbies:
        matching.append(f"hobbies:{hobbies_a[key]}")

    return matching


def find_nearby_matches(beacon_id, radius_mm=3000):
    """
    指定ユーザーの現在位置から半径 radius_mm (mm) 以内にいるユーザーを検索し、
    共通スキル/趣味のマッチング情報を付与して返す。

    Returns:
        (list[dict], error_string | None)
    """
    try:
        # リクエスターの最新位置を取得
        my_pos_sql = text("""
            SELECT est_x, est_y
            FROM estimated_positions
            WHERE beacon_id = :bid
              AND timestamp >= NOW() - INTERVAL :staleness MINUTE
            ORDER BY id DESC
            LIMIT 1
        """)
        my_pos_result = db.session.execute(my_pos_sql, {
            "bid": beacon_id,
            "staleness": POSITION_STALENESS_MINUTES,
        })
        my_pos_row = my_pos_result.fetchone()

        if not my_pos_row:
            return [], "ユーザーの現在位置が見つかりません"

        my_pos = dict(my_pos_row._mapping)
        my_x = float(my_pos["est_x"])
        my_y = float(my_pos["est_y"])

        # 全ユーザーの最新位置を取得 (staleness フィルタ付き)
        all_pos_sql = text("""
            SELECT ep.beacon_id, ep.est_x, ep.est_y, ep.status
            FROM (
                SELECT *,
                       ROW_NUMBER() OVER(PARTITION BY beacon_id ORDER BY id DESC) as rn
                FROM estimated_positions
            ) AS ep
            WHERE ep.rn = 1
              AND ep.beacon_id != :bid
              AND ep.timestamp >= NOW() - INTERVAL :staleness MINUTE
        """)
        all_pos_result = db.session.execute(all_pos_sql, {
            "bid": beacon_id,
            "staleness": POSITION_STALENESS_MINUTES,
        })
        all_positions = [dict(row._mapping) for row in all_pos_result]

        # リクエスターのプロフィールを取得
        my_profile_result = db.session.execute(
            text("SELECT * FROM user_profiles WHERE beacon_id = :bid"),
            {"bid": beacon_id}
        )
        my_profile_row = my_profile_result.fetchone()
        my_profile = dict(my_profile_row._mapping) if my_profile_row else {}

        nearby = []
        for pos in all_positions:
            other_x = float(pos["est_x"]) if pos["est_x"] is not None else None
            other_y = float(pos["est_y"]) if pos["est_y"] is not None else None
            if other_x is None or other_y is None:
                continue

            distance = math.sqrt((my_x - other_x) ** 2 + (my_y - other_y) ** 2)
            if distance > radius_mm:
                continue

            # 対象ユーザーのプロフィールを取得
            other_profile_result = db.session.execute(
                text("SELECT * FROM user_profiles WHERE beacon_id = :bid"),
                {"bid": pos["beacon_id"]}
            )
            other_profile_row = other_profile_result.fetchone()
            other_profile = dict(other_profile_row._mapping) if other_profile_row else {}

            matching_fields = get_matching_fields(my_profile, other_profile)
            zone = _determine_zone(other_x, other_y)

            nearby.append({
                "beacon_id": pos["beacon_id"],
                "user_name": other_profile.get("user_name"),
                "department": other_profile.get("department"),
                "job_title": other_profile.get("job_title"),
                "skills": other_profile.get("skills"),
                "hobbies": other_profile.get("hobbies"),
                "profile_image": other_profile.get("profile_image"),
                "distance_mm": round(distance, 1),
                "position": {"x": other_x, "y": other_y, "status": pos.get("status"), "zone": zone},
                "matching_fields": matching_fields,
            })

        # 距離でソート
        nearby.sort(key=lambda x: x["distance_mm"])
        return nearby, None

    except Exception as e:
        logger.error(f"!!! find_nearby_matches エラー: {e}", exc_info=True)
        return None, str(e)


def get_user_availability(beacon_id):
    """
    指定ユーザーのアベイラビリティ情報を取得する。

    Returns:
        (dict | None, error_string | None)
    """
    try:
        result = db.session.execute(
            text("SELECT * FROM user_availability WHERE beacon_id = :bid"),
            {"bid": beacon_id}
        )
        row = result.fetchone()
        if row:
            return dict(row._mapping), None
        return None, None
    except Exception as e:
        logger.error(f"!!! get_user_availability エラー: {e}", exc_info=True)
        return None, str(e)


def upsert_user_availability(beacon_id, **kwargs):
    """
    ユーザーのアベイラビリティを作成/更新 (UPSERT) する。
    kwargs には lunch_available, collab_available, focus_mode,
    status_message, available_from, available_until を指定可能。

    Returns:
        (bool, error_string | None)
    """
    try:
        sql = text("""
            INSERT INTO user_availability
                (beacon_id, lunch_available, collab_available, focus_mode,
                 status_message, available_from, available_until)
            VALUES
                (:beacon_id, :lunch_available, :collab_available, :focus_mode,
                 :status_message, :available_from, :available_until)
            ON DUPLICATE KEY UPDATE
                lunch_available  = COALESCE(:lunch_available, lunch_available),
                collab_available = COALESCE(:collab_available, collab_available),
                focus_mode       = COALESCE(:focus_mode, focus_mode),
                status_message   = COALESCE(:status_message, status_message),
                available_from   = COALESCE(:available_from, available_from),
                available_until  = COALESCE(:available_until, available_until)
        """)
        db.session.execute(sql, {
            "beacon_id": beacon_id,
            "lunch_available": kwargs.get("lunch_available"),
            "collab_available": kwargs.get("collab_available"),
            "focus_mode": kwargs.get("focus_mode"),
            "status_message": kwargs.get("status_message"),
            "available_from": kwargs.get("available_from"),
            "available_until": kwargs.get("available_until"),
        })
        db.session.commit()
        return True, None
    except Exception as e:
        db.session.rollback()
        logger.error(f"!!! upsert_user_availability エラー: {e}", exc_info=True)
        return False, str(e)


# ==========================================================
#  Feature 3: コラボレーション掲示板
# ==========================================================

def get_collab_posts(status="open", skill=None, beacon_id=None, hours=None, post_type=None):
    """
    コラボレーション投稿一覧を取得する。
    - status でフィルタ
    - skill で required_skills を LIKE フィルタ
    - beacon_id が指定された場合、そのユーザーのスキルとの一致度 (skill_match) を付与

    Returns:
        (list[dict], error_string | None)
    """
    try:
        conditions = ["cp.status = :status"]
        params = {"status": status}

        if skill and skill.strip():
            conditions.append("cp.required_skills LIKE :skill_pattern")
            params["skill_pattern"] = f"%{skill.strip()}%"

        if hours is not None:
            conditions.append("cp.created_at >= NOW() - INTERVAL :hours HOUR")
            params["hours"] = int(hours)

        if post_type and post_type.strip():
            conditions.append("cp.post_type = :post_type")
            params["post_type"] = post_type.strip()

        where_clause = " AND ".join(conditions)

        sql = text(f"""
            SELECT cp.*,
                   up.profile_image,
                   COALESCE(NULLIF(cp.user_name, ''), up.user_name) AS user_name,
                   (SELECT COUNT(*) FROM collaboration_responses cr WHERE cr.post_id = cp.id) AS response_count
            FROM collaboration_posts cp
            LEFT JOIN user_profiles up ON cp.beacon_id = up.beacon_id
            WHERE {where_clause}
            ORDER BY cp.created_at DESC
        """)

        result = db.session.execute(sql, params)
        posts = [dict(row._mapping) for row in result]

        # datetime を文字列に変換 (jsonify 互換)
        for post in posts:
            for key in ("created_at", "updated_at"):
                if isinstance(post.get(key), datetime):
                    post[key] = post[key].strftime("%Y-%m-%d %H:%M:%S")
        if beacon_id:
            profile_result = db.session.execute(
                text("SELECT skills FROM user_profiles WHERE beacon_id = :bid"),
                {"bid": beacon_id}
            )
            profile_row = profile_result.fetchone()
            user_skills = set()
            if profile_row and profile_row._mapping.get("skills"):
                user_skills = {s.strip().lower() for s in profile_row._mapping["skills"].split(",") if s.strip()}

            for post in posts:
                if post.get("required_skills") and user_skills:
                    required = {s.strip().lower() for s in post["required_skills"].split(",") if s.strip()}
                    matched = user_skills & required
                    post["skill_match"] = list(matched)
                    post["skill_match_count"] = len(matched)
                else:
                    post["skill_match"] = []
                    post["skill_match_count"] = 0

        return posts, None

    except Exception as e:
        logger.error(f"!!! get_collab_posts エラー: {e}", exc_info=True)
        return None, str(e)


def create_collab_post(beacon_id, user_name, post_type, title, description, required_skills):
    """
    コラボレーション投稿を新規作成する。

    Returns:
        (bool, error_string | None)
    """
    try:
        sql = text("""
            INSERT INTO collaboration_posts
                (beacon_id, user_name, post_type, title, description, required_skills, status)
            VALUES
                (:beacon_id, :user_name, :post_type, :title, :description, :required_skills, 'open')
        """)
        db.session.execute(sql, {
            "beacon_id": beacon_id,
            "user_name": user_name,
            "post_type": post_type,
            "title": title,
            "description": description,
            "required_skills": required_skills,
        })
        db.session.commit()
        logger.info(f"コラボ投稿を作成: '{title}' by {user_name}")
        return True, None
    except Exception as e:
        db.session.rollback()
        logger.error(f"!!! create_collab_post エラー: {e}", exc_info=True)
        return False, str(e)


def respond_to_collab_post(post_id, beacon_id, user_name, message):
    """
    コラボレーション投稿に応答する。

    Returns:
        (bool, error_string | None)
    """
    try:
        sql = text("""
            INSERT INTO collaboration_responses
                (post_id, beacon_id, user_name, message)
            VALUES
                (:post_id, :beacon_id, :user_name, :message)
        """)
        db.session.execute(sql, {
            "post_id": post_id,
            "beacon_id": beacon_id,
            "user_name": user_name,
            "message": message,
        })
        db.session.commit()
        logger.info(f"コラボ投稿 #{post_id} に応答: {user_name}")
        return True, None
    except Exception as e:
        db.session.rollback()
        logger.error(f"!!! respond_to_collab_post エラー: {e}", exc_info=True)
        return False, str(e)


def get_collab_responses(post_id):
    """
    指定投稿への応答一覧を取得する。

    Returns:
        (list[dict], error_string | None)
    """
    try:
        sql = text("""
            SELECT cr.*,
                   up.profile_image,
                   COALESCE(NULLIF(cr.user_name, ''), up.user_name) AS user_name
            FROM collaboration_responses cr
            LEFT JOIN user_profiles up ON cr.beacon_id = up.beacon_id
            WHERE cr.post_id = :post_id
            ORDER BY cr.created_at ASC
        """)
        result = db.session.execute(sql, {"post_id": post_id})
        responses = [dict(row._mapping) for row in result]
        for resp in responses:
            if isinstance(resp.get("created_at"), datetime):
                resp["created_at"] = resp["created_at"].strftime("%Y-%m-%d %H:%M:%S")
        return responses, None
    except Exception as e:
        logger.error(f"!!! get_collab_responses エラー: {e}", exc_info=True)
        return None, str(e)


def close_collab_post(post_id, beacon_id):
    """
    コラボレーション投稿をクローズする。
    投稿者本人 (beacon_id一致) のみが操作可能。

    Returns:
        (bool, error_string | None)
    """
    try:
        sql = text("""
            UPDATE collaboration_posts
            SET status = 'closed'
            WHERE id = :post_id AND beacon_id = :beacon_id
        """)
        result = db.session.execute(sql, {
            "post_id": post_id,
            "beacon_id": beacon_id,
        })
        db.session.commit()

        if result.rowcount == 0:
            return False, "投稿が見つからないか、権限がありません"

        logger.info(f"コラボ投稿 #{post_id} をクローズしました")
        return True, None
    except Exception as e:
        db.session.rollback()
        logger.error(f"!!! close_collab_post エラー: {e}", exc_info=True)
        return False, str(e)


# ==========================================================
#  Feature 4: インタラクション履歴
# ==========================================================

def record_current_interactions(proximity_threshold_mm=3000):
    """
    現在の全ユーザー位置を取得し、近接ペアを interaction_log に記録する。
    定期タスク (cronなど) から呼び出される想定。

    Returns:
        (int, error_string | None)  -- 記録したペア数を返す
    """
    try:
        # 全ユーザーの最新位置を取得 (staleness フィルタ付き)
        pos_sql = text("""
            SELECT ep.beacon_id, ep.est_x, ep.est_y
            FROM (
                SELECT *,
                       ROW_NUMBER() OVER(PARTITION BY beacon_id ORDER BY id DESC) as rn
                FROM estimated_positions
            ) AS ep
            WHERE ep.rn = 1
              AND ep.timestamp >= NOW() - INTERVAL :staleness MINUTE
        """)
        pos_result = db.session.execute(pos_sql, {"staleness": POSITION_STALENESS_MINUTES})
        positions = [dict(row._mapping) for row in pos_result]

        if len(positions) < 2:
            return 0, None

        recorded_count = 0
        insert_sql = text("""
            INSERT INTO interaction_log (beacon_id_a, beacon_id_b, distance_mm, zone_name)
            VALUES (:bid_a, :bid_b, :distance, :zone)
        """)

        # ペアワイズ距離を計算
        for i, j in combinations(range(len(positions)), 2):
            pos_a = positions[i]
            pos_b = positions[j]

            x_a = float(pos_a["est_x"]) if pos_a["est_x"] is not None else None
            y_a = float(pos_a["est_y"]) if pos_a["est_y"] is not None else None
            x_b = float(pos_b["est_x"]) if pos_b["est_x"] is not None else None
            y_b = float(pos_b["est_y"]) if pos_b["est_y"] is not None else None

            if x_a is None or y_a is None or x_b is None or y_b is None:
                continue

            distance = math.sqrt((x_a - x_b) ** 2 + (y_a - y_b) ** 2)

            if distance <= proximity_threshold_mm:
                # ゾーン判定 (2人の中間点を使用)
                mid_x = (x_a + x_b) / 2
                mid_y = (y_a + y_b) / 2
                zone_name = _determine_zone(mid_x, mid_y)

                # beacon_id を辞書順で正規化 (a < b)
                bid_a, bid_b = sorted([pos_a["beacon_id"], pos_b["beacon_id"]])

                db.session.execute(insert_sql, {
                    "bid_a": bid_a,
                    "bid_b": bid_b,
                    "distance": round(distance, 1),
                    "zone": zone_name,
                })
                recorded_count += 1

        db.session.commit()
        logger.info(f"インタラクション記録: {recorded_count} ペアを記録")
        return recorded_count, None

    except Exception as e:
        db.session.rollback()
        logger.error(f"!!! record_current_interactions エラー: {e}", exc_info=True)
        return 0, str(e)


def get_interaction_stats(hours=168):
    """
    過去 N 時間のインタラクションログを集計し、
    部署間マトリクスと交流の少ない部署ペアへの提案を生成する。

    Returns:
        (dict, error_string | None)
        dict には department_matrix, suggestions, total_interactions を含む
    """
    try:
        sql = text("""
            SELECT il.beacon_id_a, il.beacon_id_b, il.zone_name, il.recorded_at
            FROM interaction_log il
            WHERE il.recorded_at >= NOW() - INTERVAL :hours HOUR
        """)
        result = db.session.execute(sql, {"hours": hours})
        interactions = [dict(row._mapping) for row in result]

        if not interactions:
            return {
                "department_matrix": {},
                "suggestions": [],
                "total_interactions": 0,
            }, None

        # 全ユーザーのプロフィール (beacon_id -> department) マップを取得
        profile_result = db.session.execute(text("SELECT beacon_id, department FROM user_profiles"))
        dept_map = {}
        for row in profile_result:
            p = dict(row._mapping)
            dept_map[p["beacon_id"]] = p.get("department") or "不明"

        # 部署間マトリクスを構築
        department_matrix = defaultdict(lambda: defaultdict(int))
        all_departments = set()

        for interaction in interactions:
            dept_a = dept_map.get(interaction["beacon_id_a"], "不明")
            dept_b = dept_map.get(interaction["beacon_id_b"], "不明")
            all_departments.add(dept_a)
            all_departments.add(dept_b)

            # 辞書順で正規化
            d1, d2 = sorted([dept_a, dept_b])
            department_matrix[d1][d2] += 1

        # defaultdict を通常のdictに変換
        department_matrix_dict = {k: dict(v) for k, v in department_matrix.items()}

        # 交流の少ない部署ペアを特定して提案を生成
        suggestions = []
        dept_list = sorted(all_departments)
        if len(dept_list) >= 2:
            for i, j in combinations(range(len(dept_list)), 2):
                d1, d2 = sorted([dept_list[i], dept_list[j]])
                count = department_matrix.get(d1, {}).get(d2, 0)
                if count < 3:  # 閾値: 交流が3回未満
                    suggestions.append({
                        "department_a": d1,
                        "department_b": d2,
                        "interaction_count": count,
                        "suggestion": f"{d1} と {d2} の交流が少ないです。合同ランチやプロジェクトコラボを検討してください。",
                    })

        # 交流数の少ない順にソート
        suggestions.sort(key=lambda x: x["interaction_count"])

        return {
            "department_matrix": department_matrix_dict,
            "suggestions": suggestions,
            "total_interactions": len(interactions),
        }, None

    except Exception as e:
        logger.error(f"!!! get_interaction_stats エラー: {e}", exc_info=True)
        return None, str(e)


def get_my_interactions(beacon_id, days=7):
    """
    指定ユーザーの過去 N 日間のインタラクション履歴を取得する。

    Returns:
        (dict, error_string | None)
        dict には frequent_contacts, total_unique_people, most_active_zone を含む
    """
    try:
        sql = text("""
            SELECT beacon_id_a, beacon_id_b, zone_name, recorded_at
            FROM interaction_log
            WHERE (beacon_id_a = :bid OR beacon_id_b = :bid)
              AND recorded_at >= NOW() - INTERVAL :days DAY
        """)
        result = db.session.execute(sql, {"bid": beacon_id, "days": days})
        interactions = [dict(row._mapping) for row in result]

        if not interactions:
            return {
                "frequent_contacts": [],
                "total_unique_people": 0,
                "most_active_zone": None,
            }, None

        # 接触相手をカウント
        contact_counts = defaultdict(int)
        zone_counts = defaultdict(int)

        for interaction in interactions:
            if interaction["beacon_id_a"] == beacon_id:
                other = interaction["beacon_id_b"]
            else:
                other = interaction["beacon_id_a"]
            contact_counts[other] += 1

            zone = interaction.get("zone_name")
            if zone:
                zone_counts[zone] += 1

        # プロフィール情報を取得して結合
        contact_ids = list(contact_counts.keys())
        frequent_contacts = []

        if contact_ids:
            # 各コンタクトのプロフィールを取得
            for cid in contact_ids:
                profile_result = db.session.execute(
                    text("SELECT user_name, department, job_title, profile_image FROM user_profiles WHERE beacon_id = :bid"),
                    {"bid": cid}
                )
                profile_row = profile_result.fetchone()
                profile = dict(profile_row._mapping) if profile_row else {}

                frequent_contacts.append({
                    "beacon_id": cid,
                    "user_name": profile.get("user_name"),
                    "department": profile.get("department"),
                    "job_title": profile.get("job_title"),
                    "profile_image": profile.get("profile_image"),
                    "interaction_count": contact_counts[cid],
                })

        # 頻度でソート
        frequent_contacts.sort(key=lambda x: x["interaction_count"], reverse=True)

        # 最もアクティブなゾーンを判定
        most_active_zone = None
        if zone_counts:
            most_active_zone = max(zone_counts, key=zone_counts.get)

        return {
            "frequent_contacts": frequent_contacts,
            "total_unique_people": len(contact_counts),
            "most_active_zone": most_active_zone,
        }, None

    except Exception as e:
        logger.error(f"!!! get_my_interactions エラー: {e}", exc_info=True)
        return None, str(e)


# ==========================================================
#  Feature 5: ランチマッチング
# ==========================================================

def generate_lunch_matches(match_type="interest_based"):
    """
    ランチマッチングを生成する。
    user_availability で lunch_available=True のユーザーを対象とする。

    match_type:
        - 'interest_based': 趣味/スキルの重複が多いペアを優先
        - 'cross_department': 異なる部署のペアを優先
        - 'random': ランダムにペアリング

    Returns:
        (list[dict], error_string | None)  -- 生成されたマッチのリスト
    """
    try:
        # ランチ可能なユーザーを取得
        avail_sql = text("""
            SELECT ua.beacon_id
            FROM user_availability ua
            WHERE ua.lunch_available = TRUE
        """)
        avail_result = db.session.execute(avail_sql)
        available_ids = [dict(row._mapping)["beacon_id"] for row in avail_result]

        if len(available_ids) < 2:
            return [], "ランチ可能なユーザーが2人未満です"

        # 各ユーザーのプロフィールを取得
        profiles = {}
        for bid in available_ids:
            result = db.session.execute(
                text("SELECT * FROM user_profiles WHERE beacon_id = :bid"),
                {"bid": bid}
            )
            row = result.fetchone()
            if row:
                profiles[bid] = dict(row._mapping)
            else:
                profiles[bid] = {"beacon_id": bid}

        # マッチタイプに応じてペアリング
        pairs = []
        remaining = list(available_ids)

        if match_type == "interest_based":
            # 共通の趣味/スキルが多いペアを優先
            scored_pairs = []
            for i, j in combinations(remaining, 2):
                profile_a = profiles.get(i, {})
                profile_b = profiles.get(j, {})
                matching = get_matching_fields(profile_a, profile_b)
                scored_pairs.append((i, j, len(matching), matching))

            # スコアの高い順にソート
            scored_pairs.sort(key=lambda x: x[2], reverse=True)

            used = set()
            for bid_a, bid_b, score, matching in scored_pairs:
                if bid_a not in used and bid_b not in used:
                    common_str = ", ".join(matching) if matching else None
                    pairs.append((bid_a, bid_b, common_str))
                    used.add(bid_a)
                    used.add(bid_b)

        elif match_type == "cross_department":
            # 異なる部署同士を優先
            random.shuffle(remaining)
            used = set()
            # まず異なる部署のペアを作成
            for i in range(len(remaining)):
                if remaining[i] in used:
                    continue
                for j in range(i + 1, len(remaining)):
                    if remaining[j] in used:
                        continue
                    dept_a = profiles.get(remaining[i], {}).get("department")
                    dept_b = profiles.get(remaining[j], {}).get("department")
                    if dept_a and dept_b and dept_a != dept_b:
                        matching = get_matching_fields(
                            profiles.get(remaining[i], {}),
                            profiles.get(remaining[j], {})
                        )
                        common_str = ", ".join(matching) if matching else None
                        pairs.append((remaining[i], remaining[j], common_str))
                        used.add(remaining[i])
                        used.add(remaining[j])
                        break

            # 残りのユーザーは同部署でもペアリング
            leftover = [bid for bid in remaining if bid not in used]
            for k in range(0, len(leftover) - 1, 2):
                matching = get_matching_fields(
                    profiles.get(leftover[k], {}),
                    profiles.get(leftover[k + 1], {})
                )
                common_str = ", ".join(matching) if matching else None
                pairs.append((leftover[k], leftover[k + 1], common_str))

        else:  # random
            random.shuffle(remaining)
            for k in range(0, len(remaining) - 1, 2):
                matching = get_matching_fields(
                    profiles.get(remaining[k], {}),
                    profiles.get(remaining[k + 1], {})
                )
                common_str = ", ".join(matching) if matching else None
                pairs.append((remaining[k], remaining[k + 1], common_str))

        # DB にマッチを保存
        insert_sql = text("""
            INSERT IGNORE INTO lunch_matches
                (beacon_id_a, beacon_id_b, match_type, match_date, status, common_interests)
            VALUES
                (:bid_a, :bid_b, :match_type, CURDATE(), 'pending', :common_interests)
        """)

        created_matches = []
        for bid_a, bid_b, common_interests in pairs:
            # beacon_id を辞書順で正規化
            a, b = sorted([bid_a, bid_b])
            db.session.execute(insert_sql, {
                "bid_a": a,
                "bid_b": b,
                "match_type": match_type,
                "common_interests": common_interests,
            })
            created_matches.append({
                "beacon_id_a": a,
                "beacon_id_b": b,
                "match_type": match_type,
                "common_interests": common_interests,
            })

        db.session.commit()
        logger.info(f"ランチマッチング生成: {len(created_matches)} ペア ({match_type})")
        return created_matches, None

    except Exception as e:
        db.session.rollback()
        logger.error(f"!!! generate_lunch_matches エラー: {e}", exc_info=True)
        return None, str(e)


def get_todays_match(beacon_id):
    """
    指定ユーザーの本日のランチマッチを取得する。
    パートナーのプロフィールと現在位置を含めて返す。

    Returns:
        (dict | None, error_string | None)
    """
    try:
        sql = text("""
            SELECT lm.*
            FROM lunch_matches lm
            WHERE lm.match_date = CURDATE()
              AND (lm.beacon_id_a = :bid OR lm.beacon_id_b = :bid)
            ORDER BY lm.created_at DESC
            LIMIT 1
        """)
        result = db.session.execute(sql, {"bid": beacon_id})
        row = result.fetchone()

        if not row:
            return None, None

        match = dict(row._mapping)

        # パートナーの beacon_id を特定
        if match["beacon_id_a"] == beacon_id:
            partner_id = match["beacon_id_b"]
        else:
            partner_id = match["beacon_id_a"]

        # パートナーのプロフィールを取得
        profile_result = db.session.execute(
            text("SELECT * FROM user_profiles WHERE beacon_id = :bid"),
            {"bid": partner_id}
        )
        profile_row = profile_result.fetchone()
        partner_profile = dict(profile_row._mapping) if profile_row else {}

        # パートナーの位置を取得
        pos_sql = text("""
            SELECT est_x, est_y, status
            FROM estimated_positions
            WHERE beacon_id = :bid
              AND timestamp >= NOW() - INTERVAL :staleness MINUTE
            ORDER BY id DESC
            LIMIT 1
        """)
        pos_result = db.session.execute(pos_sql, {
            "bid": partner_id,
            "staleness": POSITION_STALENESS_MINUTES,
        })
        pos_row = pos_result.fetchone()
        partner_position = None
        if pos_row:
            pos = dict(pos_row._mapping)
            x = float(pos["est_x"]) if pos["est_x"] is not None else None
            y = float(pos["est_y"]) if pos["est_y"] is not None else None
            zone = _determine_zone(x, y) if x is not None and y is not None else None
            partner_position = {"x": x, "y": y, "status": pos.get("status"), "zone": zone}

        match["partner"] = {
            "beacon_id": partner_id,
            "user_name": partner_profile.get("user_name"),
            "department": partner_profile.get("department"),
            "job_title": partner_profile.get("job_title"),
            "skills": partner_profile.get("skills"),
            "hobbies": partner_profile.get("hobbies"),
            "profile_image": partner_profile.get("profile_image"),
            "position": partner_position,
        }

        # iOS モデル互換: common_interests を match_reason としても返す
        match["match_reason"] = match.get("common_interests")

        # datetime を文字列に変換 (jsonify 互換)
        for key in ("match_date", "created_at"):
            if isinstance(match.get(key), (datetime, date)):
                match[key] = str(match[key])

        return match, None

    except Exception as e:
        logger.error(f"!!! get_todays_match エラー: {e}", exc_info=True)
        return None, str(e)


def respond_to_lunch_match(match_id, beacon_id, action):
    """
    ランチマッチへの応答 (accepted, declined, completed など)。

    Returns:
        (bool, error_string | None)
    """
    try:
        sql = text("""
            UPDATE lunch_matches
            SET status = :action
            WHERE id = :match_id
              AND (beacon_id_a = :bid OR beacon_id_b = :bid)
        """)
        result = db.session.execute(sql, {
            "action": action,
            "match_id": match_id,
            "bid": beacon_id,
        })
        db.session.commit()

        if result.rowcount == 0:
            return False, "マッチが見つからないか、権限がありません"

        logger.info(f"ランチマッチ #{match_id} のステータスを '{action}' に更新")
        return True, None

    except Exception as e:
        db.session.rollback()
        logger.error(f"!!! respond_to_lunch_match エラー: {e}", exc_info=True)
        return False, str(e)


# ==========================================================
#  Feature 6: ソーシャルレコメンデーション
# ==========================================================

def calculate_social_recommendations(beacon_id, pref_temp, pref_occupancy, pref_light,
                                     pref_humidity="any", pref_co2="any",
                                     near_person_id=None):
    """
    環境スコアとソーシャルスコア (特定の人の近くに行きたい) を組み合わせた
    最適エリアレコメンデーションを計算する。

    環境スコア (analysis.py の calculate_recommendations) を 0.7、
    ソーシャルスコアを 0.3 の重みで組み合わせる。

    near_person_id が指定された場合:
      - 同じゾーン = 1.0
      - 隣接ゾーン = 0.5
      - それ以外   = 0.0

    Returns:
        dict with best_zone, boundaries, custom_message, social_context, scores
    """
    try:
        # 環境スコアを取得
        from .analysis import calculate_recommendations

        env_result = calculate_recommendations(
            pref_temp=pref_temp,
            pref_occupancy=pref_occupancy,
            pref_light=pref_light,
            pref_humidity=pref_humidity,
            pref_co2=pref_co2,
        )

        if "error" in env_result:
            return env_result

        # near_person_id が指定されていない場合は環境スコアのみ返す
        if not near_person_id:
            return {
                "best_zone": env_result.get("best_zone"),
                "boundaries": env_result.get("boundaries"),
                "custom_message": env_result.get("custom_message"),
                "social_context": None,
                "scores": env_result.get("debug_analytics", {}),
            }

        # ターゲットユーザーの現在位置/ゾーンを取得
        target_pos_sql = text("""
            SELECT est_x, est_y
            FROM estimated_positions
            WHERE beacon_id = :bid
              AND timestamp >= NOW() - INTERVAL :staleness MINUTE
            ORDER BY id DESC
            LIMIT 1
        """)
        target_result = db.session.execute(target_pos_sql, {
            "bid": near_person_id,
            "staleness": POSITION_STALENESS_MINUTES,
        })
        target_row = target_result.fetchone()

        target_zone = None
        target_position = None
        if target_row:
            target_pos = dict(target_row._mapping)
            tx = float(target_pos["est_x"]) if target_pos["est_x"] is not None else None
            ty = float(target_pos["est_y"]) if target_pos["est_y"] is not None else None
            if tx is not None and ty is not None:
                target_zone = _determine_zone(tx, ty)
                target_position = {"x": tx, "y": ty, "zone": target_zone}

        # ターゲットの位置が不明な場合は環境スコアのみで返す
        if not target_zone:
            # ターゲットのプロフィール名を取得
            name_result = db.session.execute(
                text("SELECT user_name FROM user_profiles WHERE beacon_id = :bid"),
                {"bid": near_person_id}
            )
            name_row = name_result.fetchone()
            target_name = dict(name_row._mapping).get("user_name", near_person_id) if name_row else near_person_id

            return {
                "best_zone": env_result.get("best_zone"),
                "boundaries": env_result.get("boundaries"),
                "custom_message": env_result.get("custom_message") +
                    f"<br>{target_name} さんの位置情報が取得できないため、環境データのみで推薦しています。",
                "social_context": {
                    "target_person": near_person_id,
                    "target_zone": None,
                    "note": "位置情報なし",
                },
                "scores": env_result.get("debug_analytics", {}),
            }

        # 隣接ゾーンを取得
        adjacent_zones = _get_adjacent_zones(target_zone)

        # 各ゾーンのソーシャルスコアを計算
        zone_analytics = env_result.get("debug_analytics", {})
        social_scores = {}
        for zone_name in zone_analytics:
            if zone_name == target_zone:
                social_scores[zone_name] = 1.0
            elif zone_name in adjacent_zones:
                social_scores[zone_name] = 0.5
            else:
                social_scores[zone_name] = 0.0

        # 環境スコアを正規化して結合
        # 環境スコア: zone_analytics の各ゾーンに対し、
        # env_result の best_zone に近いほど高いスコアを算出
        # -> 簡易実装: 各ゾーンの環境適合度を、好みマッチ数で算出
        from .config_loader import RECOMMENDATION_THRESHOLDS

        env_scores = {}
        for zone_name, stats in zone_analytics.items():
            score = 0
            max_score = 0

            temp_cool_max = RECOMMENDATION_THRESHOLDS.get("temp_cool_max", 23.0)
            temp_warm_min = RECOMMENDATION_THRESHOLDS.get("temp_warm_min", 25.0)
            occ_quiet_max = RECOMMENDATION_THRESHOLDS.get("occupancy_quiet_max", 1)
            occ_busy_min = RECOMMENDATION_THRESHOLDS.get("occupancy_busy_min", 3)
            light_bright_min = RECOMMENDATION_THRESHOLDS.get("light_bright_min", 600)
            light_dark_max = RECOMMENDATION_THRESHOLDS.get("light_dark_max", 300)
            humidity_dry_max = RECOMMENDATION_THRESHOLDS.get("humidity_dry_max", 40.0)
            humidity_humid_min = RECOMMENDATION_THRESHOLDS.get("humidity_humid_min", 60.0)
            co2_fresh_max = RECOMMENDATION_THRESHOLDS.get("co2_fresh_max", 600.0)
            co2_stuffy_min = RECOMMENDATION_THRESHOLDS.get("co2_stuffy_min", 1000.0)

            for pref, key, check_low, check_high in [
                (pref_temp, "temp", temp_cool_max, temp_warm_min),
                (pref_light, "lux", light_dark_max, light_bright_min),
                (pref_humidity, "humidity", humidity_dry_max, humidity_humid_min),
                (pref_co2, "co2", co2_fresh_max, co2_stuffy_min),
            ]:
                max_score += 1
                if pref == "any":
                    score += 1
                elif pref in ("cool", "dark", "dry", "fresh"):
                    if stats.get(key, 0) < check_low:
                        score += 1
                elif pref in ("warm", "bright", "humid", "stuffy"):
                    if stats.get(key, 0) > check_high:
                        score += 1

            # 混雑度
            max_score += 1
            if pref_occupancy == "any":
                score += 1
            elif pref_occupancy == "quiet" and stats.get("beacon_count", 0) <= occ_quiet_max:
                score += 1
            elif pref_occupancy == "busy" and stats.get("beacon_count", 0) >= occ_busy_min:
                score += 1

            env_scores[zone_name] = score / max_score if max_score > 0 else 0

        # 結合スコアを計算
        combined_scores = {}
        for zone_name in zone_analytics:
            env_s = env_scores.get(zone_name, 0)
            social_s = social_scores.get(zone_name, 0)
            combined_scores[zone_name] = env_s * 0.7 + social_s * 0.3

        # 最高スコアのゾーンを選択
        best_zone = max(combined_scores, key=combined_scores.get) if combined_scores else "N/A"
        best_boundaries = ZONE_BOUNDARIES.get(best_zone)

        # ターゲットユーザーの名前を取得
        name_result = db.session.execute(
            text("SELECT user_name FROM user_profiles WHERE beacon_id = :bid"),
            {"bid": near_person_id}
        )
        name_row = name_result.fetchone()
        target_name = dict(name_row._mapping).get("user_name", near_person_id) if name_row else near_person_id

        # カスタムメッセージ生成
        if best_zone == target_zone:
            custom_message = (
                f"**{best_zone}** がおすすめです。"
                f"{target_name} さんと同じゾーンで、環境条件にも合っています。"
            )
        elif best_zone in adjacent_zones:
            custom_message = (
                f"**{best_zone}** がおすすめです。"
                f"{target_name} さんのいる {target_zone} の隣接エリアで、環境条件が良好です。"
            )
        else:
            custom_message = (
                f"環境条件に最も合う **{best_zone}** をおすすめします。"
                f"{target_name} さんは {target_zone} にいますが、環境面ではこちらが最適です。"
            )

        return {
            "best_zone": best_zone,
            "boundaries": best_boundaries,
            "custom_message": custom_message,
            "social_context": {
                "target_person": near_person_id,
                "target_name": target_name,
                "target_zone": target_zone,
                "target_position": target_position,
            },
            "scores": {
                zone: {
                    "env_score": round(env_scores.get(zone, 0), 3),
                    "social_score": round(social_scores.get(zone, 0), 3),
                    "combined_score": round(combined_scores.get(zone, 0), 3),
                }
                for zone in zone_analytics
            },
        }

    except Exception as e:
        logger.error(f"!!! calculate_social_recommendations エラー: {e}", exc_info=True)
        return {"error": f"ソーシャルレコメンデーション計算に失敗しました: {str(e)}"}
