from sqlalchemy import text
from ..app import db
import pandas as pd
from shapely.geometry import Point
import time
import logging
import numpy as np
from shapely.geometry import Point, Polygon
from shapely.ops import nearest_points
import json

from .config_loader import (
    PI_LOCATIONS,
    PI_IDS,
    BEACON_POSITIONS,
    MINOR_ID_TO_PI_NAME_MAP,
    BEACON_GROUND_TRUTH,
    BEACON_ACTUAL_DISTANCES,
    CONFIG_JSON_PATH,
    floorplan_data_cache,
    MAP_SETTINGS,
    SHAPELY_SETTINGS,
    POSITION_STALENESS_MINUTES,
    FLOORPLAN_IMAGE_CONFIG,
    CALIBRATION_CONFIG,
    FLOOR_BOUNDARY_CONFIG
)

logger = logging.getLogger(__name__)

def get_real_sensor_data():
    """
    MySQLから最新のセンサーデータを取得する
    """
    # env_dataから各ras_pi_idの最新レコードを取得するSQL
    sql_query = text("""
    SELECT t1.ras_pi_id, t1.temperature, t1.humidity, t1.illuminance, t1.co2
    FROM env_data t1
    JOIN (
        SELECT ras_pi_id, MAX(id) as max_id
        FROM env_data
        WHERE ras_pi_id IN :pi_ids
        GROUP BY ras_pi_id
    ) t2 ON t1.id = t2.max_id;
    """)

    # db.session を使ってクエリを実行
    result = db.session.execute(sql_query, {'pi_ids': PI_IDS})

    # { 'ras_01': { ... }, 'ras_02': { ... } } の辞書形式に変換
    latest_data_map = {row.ras_pi_id: row for row in result}

    sensor_data_list = []

    # PI_LOCATIONS をループ
    for pi in PI_LOCATIONS:
        pi_id = pi['ras_pi_id']

        if pi_id in latest_data_map:
            # データベースにデータがあった場合
            data = latest_data_map[pi_id]
            sensor_data_list.append({
                'id': pi_id,
                'x': pi['x'],
                'y': pi['y'],
                'temp': float(data.temperature or 0),
                'humidity': float(data.humidity or 0),
                'lux': float(data.illuminance or 0),
                'co2': float(data.co2 or 0),
            })
        else:
            # データベースにまだデータがない場合
            sensor_data_list.append({
                'id': pi_id, 'x': pi['x'], 'y': pi['y'],
                'temp': 0, 'humidity': 0, 'lux': 0, 'co2': 0,
            })

    return sensor_data_list


# def get_real_position_data(save_to_db=False):
#     """
#     ★修正: MySQLから距離データを取得し、フィルタリング条件を緩和して3点測位を実行
#     """
#     start_time = time.time() 
    
#     # 1. DBから直近10秒間の位置データをすべて取得 (変更なし)
#     sql_query = text("""
#         SELECT beacon_id, ras_pi_id, distance
#         FROM location_data;  
#     """)
    
#     try:
#         result = db.session.execute(sql_query)
#         raw_df = pd.DataFrame(result.fetchall(), columns=result.keys())
#         if raw_df.empty: return [] 

#         # --- 2. 前処理 (変更なし) ---
#         # スキャン回数カウント (後で使わないが、念のため残す)
#         scan_count_per_beacon = raw_df.groupby(['beacon_id', 'ras_pi_id']).size().to_dict() 
#         # 中央値計算
#         median_df = raw_df.groupby(['beacon_id', 'ras_pi_id'])['distance'].median().reset_index()
#         median_df['Median_Distance_mm'] = median_df['distance'] * 1000

#         # --- 3. 測位ロジック実行 (フィルタリング削除) ---
#         js_position_list = [] 
#         for address, addr_group in median_df.groupby("beacon_id"):
            
#             all_detected_beacons = addr_group["ras_pi_id"].tolist()
            
#             if len(all_detected_beacons) < 3: 
#                 continue

#             dists = { row["ras_pi_id"]: row["Median_Distance_mm"] for _, row in addr_group.iterrows() }
            
#             selected = sorted(dists.items(), key=lambda x: x[1])[:3]
#             selected_ids = [b for b, _ in selected] 
#             selected_distances = [d for _, d in selected] 

#             try: 
#                 x_coords = [BEACON_POSITIONS[b][0] for b in selected_ids]
#                 y_coords = [BEACON_POSITIONS[b][1] for b in selected_ids]
#                 radii = selected_distances
#             except KeyError as e: 
#                 continue 
            
#             circle1 = Point(x_coords[0], y_coords[0]).buffer(radii[0])
#             circle2 = Point(x_coords[1], y_coords[1]).buffer(radii[1])
#             circle3 = Point(x_coords[2], y_coords[2]).buffer(radii[2])
#             intersection = circle1.intersection(circle2).intersection(circle3)
            
#             expand_percent = 10
#             max_expand = 10
#             expand_count = 0
            
#             while intersection.is_empty and expand_count < max_expand:
#                 radii = [r * (1 + expand_percent / 100) for r in radii]
#                 circle1 = Point(x_coords[0], y_coords[0]).buffer(radii[0])
#                 circle2 = Point(x_coords[1], y_coords[1]).buffer(radii[1])
#                 circle3 = Point(x_coords[2], y_coords[2]).buffer(radii[2])
#                 intersection = circle1.intersection(circle2).intersection(circle3)
#                 expand_count += 1
                
#             if not intersection.is_empty:
#                 centroid = intersection.centroid
#                 est_x, est_y = centroid.x, centroid.y
#                 js_position_list.append({"id": address, "x": est_x, "y": est_y})
                
#                 if save_to_db:
#                     try:
#                         pi_ids_str = ",".join(selected_ids)
                        
#                         check_sql = text("""
#                             SELECT est_x, est_y, pi_ids_used 
#                             FROM estimated_positions 
#                             WHERE beacon_id = :beacon 
#                             ORDER BY id DESC 
#                             LIMIT 1
#                         """)
#                         last_entry = db.session.execute(check_sql, {"beacon": address}).fetchone()

#                         is_duplicate = False
#                         if last_entry:
#                             if (abs(float(last_entry[0]) - est_x) < 0.001 and
#                                 abs(float(last_entry[1]) - est_y) < 0.001 and
#                                 last_entry[2] == pi_ids_str):
#                                 is_duplicate = True
#                                 logger.debug(f" -> '{address}' の推定結果が重複するため、DB保存をスキップします。")
                        
#                         if not is_duplicate:
#                             ground_truth = BEACON_GROUND_TRUTH.get(address)
#                             actual_x = ground_truth[0] if ground_truth else None
#                             actual_y = ground_truth[1] if ground_truth else None

#                             insert_sql = text("""
#                                 INSERT INTO estimated_positions 
#                                 (beacon_id, est_x, est_y, pi_ids_used, actual_x, actual_y)
#                                 VALUES (:beacon, :est_x, :est_y, :pis, :actual_x, :actual_y)
#                             """)
                            
#                             db.session.execute(insert_sql, {
#                                 "beacon": address,
#                                 "est_x": est_x,
#                                 "est_y": est_y,
#                                 "pis": pi_ids_str,
#                                 "actual_x": actual_x,
#                                 "actual_y": actual_y
#                             })
                            
#                             db.session.commit()
#                             logger.debug(f" -> '{address}' の推定結果をDBに保存しました。")
                        
#                     except Exception as e:
#                         db.session.rollback() 
#                         logger.error(f"!!! '{address}' の推定結果DB保存中にエラー: {e}", exc_info=True)
            
#         return js_position_list 

#     except Exception as e:
#         logger.error(f"!!! Position calculation error: {e}", exc_info=True) 
#         return []

    
def get_real_floorplan_data():
    """
    キャッシュされたフロアプランデータを返す
    """
    return floorplan_data_cache


# --- ここからiPhone連携用の関数 ---

def _clamp_to_floor_boundary(x, y):
    """
    フロア境界ポリゴン内に座標をクランプする。
    境界外の場合、最近傍の境界上の点を返す。
    """
    if not FLOOR_BOUNDARY_CONFIG or len(FLOOR_BOUNDARY_CONFIG) < 3:
        return x, y
    try:
        boundary_coords = [(p['x'], p['y']) for p in FLOOR_BOUNDARY_CONFIG]
        floor_polygon = Polygon(boundary_coords)
        point = Point(x, y)
        if floor_polygon.contains(point):
            return x, y
        # 境界外 → 最近傍の境界上の点にクランプ
        nearest_pt = nearest_points(point, floor_polygon.exterior)[1]
        logger.debug(f"境界クランプ: ({x}, {y}) → ({nearest_pt.x}, {nearest_pt.y})")
        return nearest_pt.x, nearest_pt.y
    except Exception as e:
        logger.error(f"境界クランプエラー: {e}")
        return x, y


def snap_position_to_map(raw_x, raw_y):
    """
    計算された座標をフロア境界内にクランプする（椅子・廊下スナップは廃止）
    """
    raw_x, raw_y = _clamp_to_floor_boundary(raw_x, raw_y)
    return raw_x, raw_y
    
def save_estimated_position_all(beacon_id, user_name, job_title, department, status,lsm_x, lsm_y, kf_x, kf_y, final_x, final_y, pi_ids_list, calc_method, is_moving=False):
    """
    [API -> DB] (詳細ログON) 3種類すべての座標を estimated_positions に保存する
    """
    pi_ids_used_str = ",".join(map(str, pi_ids_list))
    try:
        ground_truth = BEACON_GROUND_TRUTH.get(beacon_id)
        actual_x = ground_truth[0] if ground_truth else None
        actual_y = ground_truth[1] if ground_truth else None

        sql = text("""
            INSERT INTO estimated_positions
            (timestamp, beacon_id,
             obs_x, obs_y, kf_x, kf_y, est_x, est_y,
             pi_ids_used, actual_x, actual_y, calc_method,
             user_name, job_title, department, status, is_moving)
            VALUES (
             NOW(), :beacon_id,
             :obs_x, :obs_y, :kf_x, :kf_y, :est_x, :est_y,
             :pi_ids_str, :actual_x, :actual_y, :calc_method,
             :user_name, :job_title, :dept, :status, :is_moving)
        """)

        db.session.execute(sql, {
            "beacon_id": beacon_id,
            "user_name": user_name,
            "job_title": job_title,
            "dept": department,
            "status": status,
            "is_moving": 1 if is_moving else 0,
            "obs_x": lsm_x, "obs_y": lsm_y,
            "kf_x": kf_x, "kf_y": kf_y,
            "est_x": final_x, "est_y": final_y,
            "pi_ids_str": pi_ids_used_str,
            "actual_x": actual_x, "actual_y": actual_y,
            "calc_method": calc_method,
        })
        db.session.commit()
        return True, None
    except Exception as e:
        db.session.rollback()
        logger.error(f"!!! iPhone全座標DB保存中にエラー: {e}", exc_info=True)
        return False, str(e)


def save_estimated_position_snapped_only(beacon_id, user_name, final_x, final_y, pi_ids_list, calc_method,
                                         job_title=None, department=None, status=None, is_moving=False):
    """
    [API -> DB] (詳細ログOFF) スナップ後の最終座標「のみ」を保存する
    """
    pi_ids_used_str = ",".join(map(str, pi_ids_list))
    try:
        ground_truth = BEACON_GROUND_TRUTH.get(beacon_id)
        actual_x = ground_truth[0] if ground_truth else None
        actual_y = ground_truth[1] if ground_truth else None

        sql = text("""
            INSERT INTO estimated_positions
            (timestamp, beacon_id,
             obs_x, obs_y, kf_x, kf_y, est_x, est_y,
             pi_ids_used, actual_x, actual_y, calc_method,
             user_name, job_title, department, status, is_moving)
            VALUES (
             NOW(), :beacon_id,
             NULL, NULL, NULL, NULL, :est_x, :est_y,
             :pi_ids_str, :actual_x, :actual_y, :calc_method,
             :user_name, :job_title, :dept, :status, :is_moving)
        """)

        db.session.execute(sql, {
            "beacon_id": beacon_id,
            "user_name": user_name,
            "job_title": job_title,
            "dept": department,
            "status": status,
            "is_moving": 1 if is_moving else 0,
            "est_x": final_x,
            "est_y": final_y,
            "pi_ids_str": pi_ids_used_str,
            "actual_x": actual_x,
            "actual_y": actual_y,
            "calc_method": calc_method
        })
        db.session.commit()
        return True, None
    except Exception as e:
        db.session.rollback()
        logger.error(f"!!! iPhone(スナップのみ)DB保存中にエラー: {e}", exc_info=True)
        return False, str(e)

def save_raw_location_data(beacon_id, raw_data_list):
    """
    [iPhone -> DB] iPhoneが計算に使った「中央値の距離データ」を location_data に保存
    ★ テーブルの制約を解除したため、単純な INSERT に戻す ★
    """
    try:
        insert_data = []
        actual_distance_map = BEACON_ACTUAL_DISTANCES.get(beacon_id, {})
        
        for item in raw_data_list:
            ras_pi_id = item.get('ras_pi_id')
            distance_mm = item.get('distance') # iPhoneからは(mm)単位
            
            if ras_pi_id is None or distance_mm is None:
                continue

            actual_distance = actual_distance_map.get(str(ras_pi_id), None)
            
            insert_data.append({
                "ras_pi_id": ras_pi_id,
                "beacon_id": beacon_id,
                "distance": distance_mm,
                "actual_distance": actual_distance
            })

        if not insert_data:
            return False, "No valid data in raw_data list"
        
        # SQLAlchemyセッションで実行
        sql = text("""
            INSERT INTO location_data 
            (ras_pi_id, beacon_id, timestamp, distance, actual_distance) 
            VALUES (:ras_pi_id, :beacon_id, NOW(), :distance, :actual_distance)
        """)

        # executemany で一括挿入
        db.session.execute(sql, insert_data)
        db.session.commit()
        logger.debug(f" -> iPhone '{beacon_id}' の生データ {len(insert_data)}件 をDBに保存しました。")
        return True, None 

    except Exception as e:
        db.session.rollback()
        logger.error(f"!!! iPhone生データDB保存中にエラー: {e}", exc_info=True)
        return False, str(e)

def get_latest_iphone_positions():
    """
    [DB -> JS] 'estimated_positions' から最新のiPhone座標をJSダッシュボードに渡す
    user_profiles と LEFT JOIN してプロフィール画像も返す
    """
    sql_query = text("""
        SELECT
            ep.beacon_id AS id,
            ep.user_name AS name,
            ep.job_title AS job,
            ep.department AS dept,
            ep.status,
            ep.est_x AS x,
            ep.est_y AS y,
            COALESCE(ep.is_moving, 0) AS is_moving,
            up.profile_image
        FROM (
            SELECT
                *,
                ROW_NUMBER() OVER(PARTITION BY beacon_id ORDER BY id DESC) as rn
            FROM
                estimated_positions
        ) AS ep
        LEFT JOIN user_profiles up ON ep.beacon_id = up.beacon_id
        WHERE
            ep.rn = 1
            AND ep.timestamp >= NOW() - INTERVAL :staleness_minutes MINUTE;
    """)

    try:
        result = db.session.execute(sql_query, {
            "staleness_minutes": POSITION_STALENESS_MINUTES
        })
        # DECIMAL型をfloatに変換 + is_movingをbool化
        positions = []
        for row in result:
            d = dict(row._mapping)
            for key in ('x', 'y'):
                if d.get(key) is not None:
                    d[key] = float(d[key])
            d['is_moving'] = bool(d.get('is_moving', 0))
            positions.append(d)
        return positions, None

    except Exception as e:
        logger.error(f"!!! /api/get_iphone_positions ERROR: {e}", exc_info=True)
        return None, str(e)
    
def save_env_data(ras_pi_id, timestamp, temp, humidity, illuminance, co2):
    """
    [Sensor Pi -> DB] ラズパイセンサーからの環境データを 'env_data' に保存
    """
    try:
        sql = text("""
            INSERT INTO env_data 
            (ras_pi_id, timestamp, temperature, humidity, illuminance, co2) 
            VALUES (:ras_pi_id, :timestamp, :temp, :humidity, :lux, :co2)
        """)
        
        db.session.execute(sql, {
            "ras_pi_id": ras_pi_id,
            "timestamp": timestamp,
            "temp": temp,
            "humidity": humidity,
            "lux": illuminance,
            "co2": co2
        })
        
        db.session.commit()
        logger.debug(f" -> センサー '{ras_pi_id}' の環境データをDBに保存しました。")
        return True, None # 成功

    except Exception as e:
        db.session.rollback()
        logger.error(f"!!! センサー環境データDB保存中にエラー: {e}", exc_info=True)
        return False, str(e) # 失敗

def calculate_position_with_shapely(raw_data_list):
    """
    iPhoneから受け取った距離データリストを使い、
    Shapelyのロジック（円の交差・重心）で測位計算を行う
    
    raw_data_list の形式: [ {"ras_pi_id": 8, "distance": 2500}, ... ]
    """
    
    if len(raw_data_list) < SHAPELY_SETTINGS.get("min_beacons_required", 3):
        logger.warning("Shapely計算: 3台未満のデータのためスキップ")
        return None, "Not enough data"

    # 1. 距離でソートし、近いN台を選ぶ
    try:
        sorted_data = sorted(raw_data_list, key=lambda item: item['distance'])
        beacons_to_use = sorted_data[:SHAPELY_SETTINGS.get("beacons_to_use", 3)]
        
        selected_ids_minor = [item['ras_pi_id'] for item in beacons_to_use]
        selected_ids_pi_name = [MINOR_ID_TO_PI_NAME_MAP[str(b_id)] for b_id in selected_ids_minor]
        
        # config (BEACON_POSITIONS) から座標(mm)を取得
        x_coords = [BEACON_POSITIONS[pi_name][0] for pi_name in selected_ids_pi_name]
        y_coords = [BEACON_POSITIONS[pi_name][1] for pi_name in selected_ids_pi_name]
        radii = [item['distance'] for item in beacons_to_use]
        
    except KeyError as e:
        logger.error(f"Shapely計算: BEACON_POSITIONS に Minor ID {e} が見つかりません")
        return None, "Beacon position not configured"
    except Exception as e:
        logger.error(f"Shapely計算: データ準備エラー: {e}")
        return None, "Data processing error"

    # 2. Shapelyで円の交点を計算
    try:
        circle1 = Point(x_coords[0], y_coords[0]).buffer(radii[0])
        circle2 = Point(x_coords[1], y_coords[1]).buffer(radii[1])
        circle3 = Point(x_coords[2], y_coords[2]).buffer(radii[2])
        intersection = circle1.intersection(circle2).intersection(circle3)
        
        # 3. もし交点がない場合、円を拡大して再試行
        expand_percent = SHAPELY_SETTINGS.get("expand_percent", 10)
        max_expand = SHAPELY_SETTINGS.get("max_expand", 10)
        expand_count = 0
        
        while intersection.is_empty and expand_count < max_expand:
            
            expand_count += 1 
            
            logger.debug(f"Shapely計算: 交点なし。拡大して再試行 ({expand_count}/{max_expand})")
            
            expansion_factor = (1 + expand_percent / 100) ** expand_count 
            radii_expanded = [r * expansion_factor for r in radii] 
            
            circle1 = Point(x_coords[0], y_coords[0]).buffer(radii_expanded[0])
            circle2 = Point(x_coords[1], y_coords[1]).buffer(radii_expanded[1])
            circle3 = Point(x_coords[2], y_coords[2]).buffer(radii_expanded[2])
            intersection = circle1.intersection(circle2).intersection(circle3)
            
        if not intersection.is_empty:
            # 4. 交点（領域）の重心を計算
            centroid = intersection.centroid
            est_x, est_y = centroid.x, centroid.y
            
            # 5. 計算結果を返す
            return {"x": est_x, "y": est_y, "pi_ids_used": selected_ids_minor}, None
            
        else:
            logger.warning("Shapely計算: 10回拡大しても交点が見つかりませんでした。")
            return None, "No intersection found"

    except Exception as e:
        logger.error(f"Shapely計算ロジックエラー: {e}", exc_info=True)
        return None, "Shapely calculation error"

# def calculate_least_squares_position(raw_data_list):
#     """
#     iPhoneから受け取った距離データリスト (N>=3) を使い、
#     最小二乗法 (LSM) で測位計算を行う
    
#     raw_data_list の形式: [ {"ras_pi_id": 8, "distance": 2500}, ... ]
#     """
    
#     if len(raw_data_list) < 3:
#         logger.warning("LSM計算: 3台未満のデータのためスキップ")
#         return None, "Not enough data"

#     try:
#         # 1. データを準備 (行列A と ベクトルb)
#         # (利用可能な全データ（例: 9台）を使うため、近い3台に絞り込む処理は行わない)
#         num_equations = len(raw_data_list) - 1
        
#         # (N-1) x 2 の行列 A と、 (N-1) x 1 のベクトル b
#         matrix_a = np.zeros((num_equations, 2))
#         vector_b = np.zeros(num_equations)

#         # 基準点（アンカー0）をリストの最初のビーコンとする
#         item_0 = raw_data_list[0]
#         pi_name_0 = MINOR_ID_TO_PI_NAME_MAP.get(str(item_0['ras_pi_id']))
#         if not pi_name_0: raise KeyError(f"Minor ID {item_0['ras_pi_id']} がマッピングにありません")
        
#         x0 = BEACON_POSITIONS[pi_name_0][0]
#         y0 = BEACON_POSITIONS[pi_name_0][1]
#         d0_sq = item_0['distance'] ** 2
#         k0 = x0**2 + y0**2

#         # (N-1)個の方程式を作成 (i=1 から N-1 まで)
#         for i in range(num_equations):
#             item_i = raw_data_list[i + 1]
#             pi_name_i = MINOR_ID_TO_PI_NAME_MAP.get(str(item_i['ras_pi_id']))
#             if not pi_name_i: raise KeyError(f"Minor ID {item_i['ras_pi_id']} がマッピングにありません")

#             xi = BEACON_POSITIONS[pi_name_i][0]
#             yi = BEACON_POSITIONS[pi_name_i][1]
#             di_sq = item_i['distance'] ** 2
#             ki = xi**2 + yi**2

#             # A行列のi行目
#             matrix_a[i, 0] = 2.0 * (x0 - xi)
#             matrix_a[i, 1] = 2.0 * (y0 - yi)
            
#             # bベクトルのi行目
#             vector_b[i] = (di_sq - d0_sq) - (ki - k0)

#     except KeyError as e:
#         logger.error(f"LSM計算: BEACON_POSITIONS またはマッピングに Minor ID {e} が見つかりません")
#         return None, "Beacon position not configured"
#     except Exception as e:
#         logger.error(f"LSM計算: データ準備エラー: {e}")
#         return None, "Data processing error"

#     # 2. NumPyを使って最小二乗法 (A * x = b) を解く
#     try:
#         # np.linalg.lstsq は、x (解) と、残差 (誤差) などを返す
#         solution, residuals, rank, s = np.linalg.lstsq(matrix_a, vector_b, rcond=None)
        
#         est_x = solution[0]
#         est_y = solution[1]
        
#         # 3. 計算結果を返す (pi_ids_used には入力データすべてのIDを返す)
#         pi_ids_used = [item['ras_pi_id'] for item in raw_data_list]
        
#         return {"x": est_x, "y": est_y, "pi_ids_used": pi_ids_used}, None

#     except np.linalg.LinAlgError as e:
#         # 特異行列などで計算が失敗した場合
#         logger.error(f"LSM計算ロジックエラー (LinAlgError): {e}", exc_info=True)
#         return None, "LSM calculation error"
#     except Exception as e:
#         logger.error(f"LSM計算ロジックエラー: {e}", exc_info=True)
#         return None, "Unknown LSM error"

# # --- ▲▲▲ 追加ここまで ▲▲▲ ---

def save_beacon_config(new_beacon_positions, new_minor_map):
    """
    [Settings Modal -> config.json] ビーコン設定を上書き保存する
    """
    try:
        # 1. 現在の config.json を読み込む
        with open(CONFIG_JSON_PATH, 'r', encoding='utf-8') as f:
            config_data = json.load(f)

        # 2. ビーコン設定を更新 (データがある場合のみ)
        if new_beacon_positions:
            config_data["BEACON_POSITIONS"] = new_beacon_positions
            config_data["MINOR_ID_TO_PI_NAME_MAP"] = new_minor_map

            # PI_LOCATIONS も自動で更新する
            new_pi_locations = []
            existing_pi_map = {pi.get("ras_pi_id"): pi for pi in config_data.get("PI_LOCATIONS", [])}

            for ras_pi_id, coords in new_beacon_positions.items():
                new_entry = {
                    "ras_pi_id": ras_pi_id,
                    "x": coords[0],
                    "y": coords[1]
                }
                if ras_pi_id in existing_pi_map:
                    new_entry["ip"] = existing_pi_map[ras_pi_id].get("ip")
                new_pi_locations.append(new_entry)

            config_data["PI_LOCATIONS"] = new_pi_locations

        # 3. config.json を上書き保存
        with open(CONFIG_JSON_PATH, 'w', encoding='utf-8') as f:
            json.dump(config_data, f, indent=2, ensure_ascii=False)

        logger.info(f"config.json の設定が更新されました。")
        return True, "設定が保存されました。サーバーを再起動してください。"

    except Exception as e:
        logger.error(f"!!! config.json の保存に失敗: {e}", exc_info=True)
        return False, str(e)


def save_floorplan_config(image_url, width=0, height=0):
    """
    [Settings Modal -> config.json] フロアプラン画像パスと寸法を保存する
    """
    try:
        with open(CONFIG_JSON_PATH, 'r', encoding='utf-8') as f:
            config_data = json.load(f)

        if 'FLOORPLAN_IMAGE' not in config_data:
            config_data['FLOORPLAN_IMAGE'] = {}
        config_data['FLOORPLAN_IMAGE']['url'] = image_url
        config_data['FLOORPLAN_IMAGE']['width'] = width
        config_data['FLOORPLAN_IMAGE']['height'] = height

        with open(CONFIG_JSON_PATH, 'w', encoding='utf-8') as f:
            json.dump(config_data, f, indent=2, ensure_ascii=False)

        logger.info(f"フロアプラン画像パスを config.json に保存: {image_url}")
        return True, "フロアプラン画像パスを保存しました。"
    except Exception as e:
        logger.error(f"!!! フロアプラン設定の保存に失敗: {e}", exc_info=True)
        return False, str(e)


def save_calibration_data(calibration):
    """
    [Settings Modal -> config.json] キャリブレーションデータを保存する
    """
    try:
        with open(CONFIG_JSON_PATH, 'r', encoding='utf-8') as f:
            config_data = json.load(f)

        config_data['CALIBRATION'] = calibration

        with open(CONFIG_JSON_PATH, 'w', encoding='utf-8') as f:
            json.dump(config_data, f, indent=2, ensure_ascii=False)

        logger.info("キャリブレーションデータを config.json に保存しました。")
        return True, "キャリブレーションデータを保存しました。"
    except Exception as e:
        logger.error(f"!!! キャリブレーション設定の保存に失敗: {e}", exc_info=True)
        return False, str(e)


def save_floor_boundary(boundary):
    """
    [Settings Modal -> config.json] フロア外枠ポリゴンを保存する
    boundary: [{x, y}, ...] のリスト (物理座標mm)
    """
    try:
        with open(CONFIG_JSON_PATH, 'r', encoding='utf-8') as f:
            config_data = json.load(f)

        config_data['FLOOR_BOUNDARY'] = boundary

        with open(CONFIG_JSON_PATH, 'w', encoding='utf-8') as f:
            json.dump(config_data, f, indent=2, ensure_ascii=False)

        logger.info("フロア外枠ポリゴンを config.json に保存しました。")
        return True, "フロア外枠ポリゴンを保存しました。"
    except Exception as e:
        logger.error(f"!!! フロア外枠ポリゴンの保存に失敗: {e}", exc_info=True)
        return False, str(e)


def save_floor_objects(objects):
    """
    [Settings Modal -> config.json] フロアオブジェクト (壁・机・柱) を保存する
    objects: [{"type": "wall"|"desk"|"pillar", "x1": mm, "y1": mm, "x2": mm, "y2": mm, "height": mm, "label": str}, ...]
    """
    try:
        with open(CONFIG_JSON_PATH, 'r', encoding='utf-8') as f:
            config_data = json.load(f)

        config_data['FLOOR_OBJECTS'] = objects

        with open(CONFIG_JSON_PATH, 'w', encoding='utf-8') as f:
            json.dump(config_data, f, indent=2, ensure_ascii=False)

        logger.info(f"フロアオブジェクト {len(objects)}件 を config.json に保存しました。")
        return True, f"フロアオブジェクト {len(objects)}件 を保存しました。"
    except Exception as e:
        logger.error(f"!!! フロアオブジェクトの保存に失敗: {e}", exc_info=True)
        return False, str(e)


# ==========================================================
#  ユーザープロフィール CRUD
# ==========================================================

def get_all_user_profiles():
    """全ユーザープロフィールを取得"""
    try:
        result = db.session.execute(text("SELECT * FROM user_profiles"))
        profiles = [dict(row._mapping) for row in result]
        return profiles, None
    except Exception as e:
        logger.error(f"!!! user_profiles 取得エラー: {e}", exc_info=True)
        return None, str(e)


def get_user_profile(beacon_id):
    """特定ユーザーのプロフィールを取得"""
    try:
        result = db.session.execute(
            text("SELECT * FROM user_profiles WHERE beacon_id = :bid"),
            {"bid": beacon_id}
        )
        row = result.fetchone()
        if row:
            return dict(row._mapping), None
        return None, None
    except Exception as e:
        logger.error(f"!!! user_profile 取得エラー: {e}", exc_info=True)
        return None, str(e)


def delete_user_profile(beacon_id):
    """ユーザープロフィールを削除"""
    try:
        db.session.execute(
            text("DELETE FROM user_profiles WHERE beacon_id = :bid"),
            {"bid": beacon_id}
        )
        db.session.commit()
        return True, "プロフィールを削除しました。"
    except Exception as e:
        db.session.rollback()
        logger.error(f"!!! user_profile 削除エラー: {e}", exc_info=True)
        return False, str(e)


def upsert_user_profile(beacon_id, user_name=None, job_title=None, department=None,
                         skills=None, hobbies=None, projects=None, email=None, phone=None, profile_image=None):
    """ユーザープロフィールを作成/更新 (UPSERT)"""
    try:
        sql = text("""
            INSERT INTO user_profiles
                (beacon_id, user_name, job_title, department, skills, hobbies, projects, email, phone, profile_image)
            VALUES
                (:beacon_id, :user_name, :job_title, :department, :skills, :hobbies, :projects, :email, :phone, :profile_image)
            ON DUPLICATE KEY UPDATE
                user_name     = COALESCE(:user_name, user_name),
                job_title     = COALESCE(:job_title, job_title),
                department    = COALESCE(:department, department),
                skills        = COALESCE(:skills, skills),
                hobbies       = COALESCE(:hobbies, hobbies),
                projects      = COALESCE(:projects, projects),
                email         = COALESCE(:email, email),
                phone         = COALESCE(:phone, phone),
                profile_image = COALESCE(:profile_image, profile_image)
        """)
        db.session.execute(sql, {
            "beacon_id": beacon_id,
            "user_name": user_name,
            "job_title": job_title,
            "department": department,
            "skills": skills,
            "hobbies": hobbies,
            "projects": projects,
            "email": email,
            "phone": phone,
            "profile_image": profile_image
        })
        db.session.commit()
        return True, "プロフィールを保存しました。"
    except Exception as e:
        db.session.rollback()
        logger.error(f"!!! user_profile 保存エラー: {e}", exc_info=True)
        return False, str(e)


def delete_user_profile(beacon_id):
    """ユーザープロフィールを削除"""
    try:
        db.session.execute(
            text("DELETE FROM user_profiles WHERE beacon_id = :bid"),
            {"bid": beacon_id}
        )
        db.session.commit()
        return True, "プロフィールを削除しました。"
    except Exception as e:
        db.session.rollback()
        logger.error(f"!!! user_profile 削除エラー: {e}", exc_info=True)
        return False, str(e)


def search_user_profiles(query, department=None, job_title=None, sort_by='name'):
    """
    ユーザープロフィールをキーワード検索する
    user_name, job_title, department, skills, projects を LIKE で検索
    オプションで department / job_title 絞り込み、sort_by で並び替え
    """
    try:
        conditions = []
        params = {}

        if query:
            like_pattern = f"%{query}%"
            conditions.append("""
                (user_name LIKE :q
                 OR job_title  LIKE :q
                 OR department LIKE :q
                 OR skills     LIKE :q
                 OR projects   LIKE :q)
            """)
            params["q"] = like_pattern

        if department:
            conditions.append("department = :dept")
            params["dept"] = department

        if job_title:
            conditions.append("job_title = :job")
            params["job"] = job_title

        where_clause = " AND ".join(conditions) if conditions else "1=1"

        # 並び替え
        order_map = {
            'name': 'user_name ASC',
            'name_desc': 'user_name DESC',
            'department': 'department ASC, user_name ASC',
            'job_title': 'job_title ASC, user_name ASC',
            'updated': 'updated_at DESC',
        }
        order_clause = order_map.get(sort_by, 'user_name ASC')

        sql = text(f"""
            SELECT * FROM user_profiles
            WHERE {where_clause}
            ORDER BY {order_clause}
        """)
        result = db.session.execute(sql, params)
        profiles = [dict(row._mapping) for row in result]
        return profiles, None
    except Exception as e:
        logger.error(f"!!! user_profile 検索エラー: {e}", exc_info=True)
        return None, str(e)