import numpy as np
from scipy.stats import gaussian_kde
import logging
import pandas as pd

from .data_provider import get_real_sensor_data, get_latest_iphone_positions
from .config_loader import ZONE_MAPPING, ZONE_BOUNDARIES, RECOMMENDATION_THRESHOLDS

logger = logging.getLogger(__name__)


def calculate_beacon_density(beacon_positions, x_range, y_range, grid_resolution=100):
    """
    ビーコン位置リストからカーネル密度推定(KDE)を計算する
    """
    if not beacon_positions: return None
    x_coords = np.array([p['x'] for p in beacon_positions if p['x'] is not None])
    y_coords = np.array([p['y'] for p in beacon_positions if p['y'] is not None])
    if len(x_coords) < 2: 
        logger.debug("密度計算: 有効点2未満スキップ")
        return None
    values = np.vstack([x_coords, y_coords])
    try:
        kde = gaussian_kde(values)
        kde.set_bandwidth(bw_method=kde.factor / 2.)
    except Exception as e: 
        logger.error(f"KDEオブジェクトエラー: {e}")
        return None
    xi, yi = np.mgrid[x_range[0]:x_range[1]:grid_resolution*1j, y_range[0]:y_range[1]:grid_resolution*1j]
    positions = np.vstack([xi.ravel(), yi.ravel()])
    try:
        zi = kde(positions).reshape(xi.shape)
    except Exception as e: 
        logger.error(f"KDE密度計算エラー: {e}")
        return None
    return {'x': xi[:, 0].tolist(), 'y': yi[0, :].tolist(), 'z': zi.T.tolist()}


def get_zone_analytics():
    """
    ゾーンごとの平均環境とビーコン数を計算する
    """
    try:
        # 1. 最新のセンサーデータを取得
        sensor_data = get_real_sensor_data() # (x, y, temp, co2...) のリスト
        sensor_map = {d['id']: d for d in sensor_data} # 高速検索用のマップ

        # 2. 最新のビーコン位置を取得
        beacon_positions, _ = get_latest_iphone_positions() # (id, x, y) のリスト
        
        zone_analytics = {}

        for zone_name, pi_ids in ZONE_MAPPING.items():
            
            # 3. ゾーンの環境データを集計
            zone_sensors = [sensor_map[pi_id] for pi_id in pi_ids if pi_id in sensor_map]
            
            if not zone_sensors:
                continue # このゾーンのデータがなければスキップ

            zone_analytics[zone_name] = {
                'temp': np.mean([d['temp'] for d in zone_sensors]),
                'humidity': np.mean([d['humidity'] for d in zone_sensors]),
                'lux': np.mean([d['lux'] for d in zone_sensors]),
                'co2': np.mean([d['co2'] for d in zone_sensors]),
                'beacon_count': 0 # ビーコン数を初期化
            }

            # 4. ゾーン内のビーコン数をカウント
            bounds = ZONE_BOUNDARIES.get(zone_name)
            if bounds:
                for beacon in beacon_positions:
                    beacon_y_abs = abs(beacon['y']) if beacon['y'] is not None else 0
                    if (bounds['x_min'] <= beacon['x'] <= bounds['x_max'] and
                        bounds['y_min'] <= beacon_y_abs <= bounds['y_max']):
                        zone_analytics[zone_name]['beacon_count'] += 1
                        
        return zone_analytics

    except Exception as e:
        logger.error(f"ゾーン分析エラー: {e}", exc_info=True)
        return {}


def _gaussian_similarity(value, target, sigma):
    """
    ガウシアン類似度: valueがtargetに近いほど1.0、離れるほど0.0に近づく
    sigma が小さいほど厳密なマッチング（急峻なカーブ）
    """
    return float(np.exp(-0.5 * ((value - target) / sigma) ** 2))


def _calc_preference_score(pref, value, thresholds_cfg):
    """
    1つの好み項目について連続スコア(0.0〜1.0)を計算する。
    二値判定ではなくガウシアン類似度で滑らかに評価。
    戻り値: (score, 理由テキスト)
    """
    if pref == 'any':
        return None, None  # 「こだわりなし」は評価対象外

    # --- 温度 ---
    if pref == 'cool':
        target = thresholds_cfg.get('temp_cool_max', 23.0) - 2.0  # 理想は閾値より低め
        sigma = thresholds_cfg.get('temp_sigma', 3.0)
        score = _gaussian_similarity(value, target, sigma)
        desc = f"温度 {value:.1f}°C（涼しさ適合度 {score:.0%}）"
        return score, desc
    if pref == 'warm':
        target = thresholds_cfg.get('temp_warm_min', 25.0) + 2.0
        sigma = thresholds_cfg.get('temp_sigma', 3.0)
        score = _gaussian_similarity(value, target, sigma)
        desc = f"温度 {value:.1f}°C（暖かさ適合度 {score:.0%}）"
        return score, desc

    # --- 混雑度 ---
    if pref == 'quiet':
        target = 0.0  # 少ないほど良い
        sigma = thresholds_cfg.get('occupancy_sigma', 2.0)
        score = _gaussian_similarity(value, target, sigma)
        desc = f"在室 {int(value)}人（静けさ適合度 {score:.0%}）"
        return score, desc
    if pref == 'busy':
        target = thresholds_cfg.get('occupancy_busy_min', 3) + 2.0
        sigma = thresholds_cfg.get('occupancy_sigma', 2.0)
        score = _gaussian_similarity(value, target, sigma)
        desc = f"在室 {int(value)}人（にぎわい適合度 {score:.0%}）"
        return score, desc

    # --- 明るさ ---
    if pref == 'bright':
        target = thresholds_cfg.get('light_bright_min', 600) + 200
        sigma = thresholds_cfg.get('light_sigma', 250.0)
        score = _gaussian_similarity(value, target, sigma)
        desc = f"照度 {value:.0f}lx（明るさ適合度 {score:.0%}）"
        return score, desc
    if pref == 'dark':
        target = thresholds_cfg.get('light_dark_max', 300) - 100
        sigma = thresholds_cfg.get('light_sigma', 250.0)
        score = _gaussian_similarity(value, target, sigma)
        desc = f"照度 {value:.0f}lx（暗さ適合度 {score:.0%}）"
        return score, desc

    # --- 湿度 ---
    if pref == 'dry':
        target = thresholds_cfg.get('humidity_dry_max', 40.0) - 10.0
        sigma = thresholds_cfg.get('humidity_sigma', 15.0)
        score = _gaussian_similarity(value, target, sigma)
        desc = f"湿度 {value:.1f}%（乾燥適合度 {score:.0%}）"
        return score, desc
    if pref == 'humid':
        target = thresholds_cfg.get('humidity_humid_min', 60.0) + 10.0
        sigma = thresholds_cfg.get('humidity_sigma', 15.0)
        score = _gaussian_similarity(value, target, sigma)
        desc = f"湿度 {value:.1f}%（潤い適合度 {score:.0%}）"
        return score, desc

    # --- CO2 ---
    if pref == 'fresh':
        target = thresholds_cfg.get('co2_fresh_max', 600.0) - 200.0
        sigma = thresholds_cfg.get('co2_sigma', 200.0)
        score = _gaussian_similarity(value, target, sigma)
        desc = f"CO2 {value:.0f}ppm（空気清浄度 {score:.0%}）"
        return score, desc
    if pref == 'stuffy':
        target = thresholds_cfg.get('co2_stuffy_min', 1000.0)
        sigma = thresholds_cfg.get('co2_sigma', 200.0)
        score = _gaussian_similarity(value, target, sigma)
        desc = f"CO2 {value:.0f}ppm"
        return score, desc

    return None, None


def _generate_reason(zone_name, total_score, details, rank):
    """
    マッチ度合いに基づいてパーソナライズされた理由文を生成する
    """
    if total_score >= 0.8:
        prefix = "とても良い条件が揃っています"
    elif total_score >= 0.5:
        prefix = "概ね好みに合っています"
    else:
        prefix = "部分的に合致しています"

    detail_str = "、".join(details)
    return f"{prefix}（{detail_str}）"


def calculate_recommendations(pref_temp, pref_occupancy, pref_light, pref_humidity='any', pref_co2='any'):
    """
    ユーザーの好みに基づいて最適なエリアを計算し、提案メッセージを生成する。
    ガウシアン類似度による連続スコアリングで、各項目の適合度を滑らかに評価。
    """
    try:
        zone_analytics = get_zone_analytics()
        if not zone_analytics:
            return {
                "static_message": "現在、分析データがありません。",
                "custom_message": "現在、分析データがありません。",
                "best_zone": "N/A",
                "boundaries": None,
                "debug_analytics": {}
            }

        # --- 静的なおすすめメッセージ生成 ---
        messages = []
        analytics_items = zone_analytics.items()

        def safe_sort(items, key):
            valid_items = [item for item in items if pd.notna(item[1].get(key))]
            if not valid_items:
                return None
            return sorted(valid_items, key=lambda item: item[1][key])

        sorted_by_temp = safe_sort(analytics_items, 'temp')
        if sorted_by_temp:
            messages.append(f"現在、**{sorted_by_temp[-1][0]}** ({sorted_by_temp[-1][1]['temp']:.1f}°C) が最も暑く、**{sorted_by_temp[0][0]}** ({sorted_by_temp[0][1]['temp']:.1f}°C) が最も涼しいです。")

        sorted_by_beacon = safe_sort(analytics_items, 'beacon_count')
        if sorted_by_beacon:
            if sorted_by_beacon[-1][1]['beacon_count'] > sorted_by_beacon[0][1]['beacon_count']:
                messages.append(f"**{sorted_by_beacon[0][0]}** (ビーコン {sorted_by_beacon[0][1]['beacon_count']}個) が最も空いており、**{sorted_by_beacon[-1][0]}** (ビーコン {sorted_by_beacon[-1][1]['beacon_count']}個) が最も混雑しています。")
            else:
                messages.append(f"現在、全エリアの混雑度は同じです (ビーコン {sorted_by_beacon[0][1]['beacon_count']}個)。")

        sorted_by_co2 = safe_sort(analytics_items, 'co2')
        if sorted_by_co2:
            messages.append(f"空気は **{sorted_by_co2[0][0]}** ({sorted_by_co2[0][1]['co2']:.0f} ppm) が最も新鮮で、**{sorted_by_co2[-1][0]}** ({sorted_by_co2[-1][1]['co2']:.0f} ppm) が最もよどんでいます。")

        sorted_by_humidity = safe_sort(analytics_items, 'humidity')
        if sorted_by_humidity:
            messages.append(f"湿度は **{sorted_by_humidity[0][0]}** ({sorted_by_humidity[0][1]['humidity']:.1f}%) が最も低く、**{sorted_by_humidity[-1][0]}** ({sorted_by_humidity[-1][1]['humidity']:.1f}%) が最も高くなっています。")

        sorted_by_lux = safe_sort(analytics_items, 'lux')
        if sorted_by_lux:
            messages.append(f"**{sorted_by_lux[-1][0]}** ({sorted_by_lux[-1][1]['lux']:.0f} lx) が最も明るく、**{sorted_by_lux[0][0]}** ({sorted_by_lux[0][1]['lux']:.0f} lx) が最も暗いエリアです。")

        static_message = "<br>".join(messages)

        # --- ガウシアン類似度ベースのおすすめロジック ---
        best_zone_name = "N/A"
        best_zone_boundaries = None
        custom_message = "お好みを選択してください。"

        prefs = {
            'temp': pref_temp,
            'occupancy': pref_occupancy,
            'light': pref_light,
            'humidity': pref_humidity,
            'co2': pref_co2,
        }
        active_prefs = {k: v for k, v in prefs.items() if v != 'any'}

        if active_prefs:
            zone_scores = []

            for zone_name, stats in zone_analytics.items():
                scores = []
                details = []

                # 各好み項目のガウシアン類似度を計算
                pref_to_value = {
                    'temp': stats.get('temp', 0),
                    'occupancy': stats.get('beacon_count', 0),
                    'light': stats.get('lux', 0),
                    'humidity': stats.get('humidity', 0),
                    'co2': stats.get('co2', 0),
                }

                for key, pref_val in active_prefs.items():
                    value = pref_to_value[key]
                    score, desc = _calc_preference_score(pref_val, value, RECOMMENDATION_THRESHOLDS)
                    if score is not None:
                        scores.append(score)
                        details.append(desc)

                # 加重平均スコア（全項目同等重み、ただし極端に低い項目はペナルティ）
                if scores:
                    avg_score = float(np.mean(scores))
                    min_score = float(np.min(scores))
                    # 最低スコアにペナルティ: 1項目でも大きく外れると全体が下がる
                    combined = 0.7 * avg_score + 0.3 * min_score
                else:
                    combined = 0.0
                    details = []

                zone_scores.append({
                    'zone': zone_name,
                    'score': combined,
                    'details': details,
                })

            # スコア降順でソート
            zone_scores.sort(key=lambda x: x['score'], reverse=True)

            if zone_scores:
                best = zone_scores[0]
                best_zone_name = best['zone']
                best_zone_boundaries = ZONE_BOUNDARIES.get(best_zone_name)

                reason = _generate_reason(
                    best_zone_name, best['score'], best['details'], rank=1
                )
                custom_message = f"お客様の好みには **{best_zone_name}** が最適です。{reason}"

                # 2位との差が小さい場合は代替案も提示
                if len(zone_scores) >= 2:
                    runner = zone_scores[1]
                    if runner['score'] > 0 and (best['score'] - runner['score']) < 0.15:
                        custom_message += f"<br>**{runner['zone']}** も近い条件です。"

        return {
            "static_message": static_message,
            "custom_message": custom_message,
            "best_zone": best_zone_name,
            "boundaries": best_zone_boundaries,
            "debug_analytics": zone_analytics
        }

    except Exception as e:
        logger.error(f"レコメンデーション計算エラー: {e}", exc_info=True)
        return {"error": "Failed to generate recommendations"}
