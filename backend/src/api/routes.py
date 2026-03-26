from flask import Blueprint, jsonify, request, current_app
from sqlalchemy import text
from shapely.geometry import Point
import os
from werkzeug.utils import secure_filename

from .analysis import calculate_beacon_density, calculate_recommendations
from .config_loader import ZONE_MAPPING, ZONE_BOUNDARIES, BEACON_GROUND_TRUTH, MAP_SETTINGS, ALERT_THRESHOLDS, RECOMMENDATION_THRESHOLDS, DASHBOARD_SETTINGS, PI_LOCATIONS, FLOORPLAN_IMAGE_CONFIG, CALIBRATION_CONFIG, FLOOR_BOUNDARY_CONFIG, FLOOR_OBJECTS_CONFIG, ADMIN_PASSWORD, BEACON_POSITIONS, MINOR_ID_TO_PI_NAME_MAP, reload_config
from .import config_loader as _cfg
from .data_provider import (
    get_real_sensor_data,
    get_real_floorplan_data,
    save_raw_location_data,
    get_latest_iphone_positions,
    save_env_data,
    calculate_position_with_shapely,
    save_beacon_config,
    save_floorplan_config,
    save_calibration_data,
    save_floor_boundary,
    save_floor_objects,
    get_all_user_profiles,
    get_user_profile,
    upsert_user_profile,
    delete_user_profile,
    search_user_profiles
)
from .social import (
    init_social_tables,
    search_users_with_position,
    find_nearby_matches,
    get_user_availability,
    upsert_user_availability,
    get_collab_posts,
    create_collab_post,
    respond_to_collab_post,
    get_collab_responses,
    close_collab_post,
    record_current_interactions,
    get_interaction_stats,
    get_my_interactions,
    generate_lunch_matches,
    get_todays_match,
    respond_to_lunch_match,
    calculate_social_recommendations
)
import logging
import time as _time

logger = logging.getLogger(__name__)


# 'api'という名前でBlueprintを作成
api_bp = Blueprint('api', __name__, url_prefix='/api')

_social_tables_initialized = False
_last_interaction_record = 0

@api_bp.before_app_request
def _ensure_social_tables():
    global _social_tables_initialized
    if not _social_tables_initialized:
        try:
            init_social_tables()
            _social_tables_initialized = True
        except Exception as e:
            logger.error(f"Social tables init error: {e}")
            _social_tables_initialized = True  # Don't retry

@api_bp.route('/sensor-data')
def get_sensor_data_endpoint():
    try:
        data = get_real_sensor_data()
        return jsonify(data)
    except Exception as e:
        logger.error(f"Error getting sensor data: {e}", exc_info=True)
        return jsonify({"error": "Failed to retrieve sensor data"}), 500

# @api_bp.route('/beacon-positions')
# def get_position_data_endpoint():
#     try:
#         data = get_real_position_data(save_to_db=True)
#         return jsonify(data)
#     except Exception as e:
#         print(f"Error getting position data: {e}")
#         return jsonify({"error": "Failed to retrieve position data"}), 500

@api_bp.route('/floorplan-data')
def get_floorplan_endpoint():
    try:
        data = get_real_floorplan_data()
        return jsonify(data)
    except Exception as e:
        logger.error(f"Error getting floorplan data: {e}", exc_info=True)
        return jsonify({"error": "Failed to retrieve floorplan data"}), 500

@api_bp.route('/app_config')
def get_app_config_endpoint():
    """
    [Config -> JS] フロントエンドが必要とするアプリケーション設定を返す
    """
    try:
        return jsonify({
            "PI_LOCATIONS": [{"id": pi["ras_pi_id"], "x": pi["x"], "y": pi["y"]} for pi in _cfg.PI_LOCATIONS],
            "ZONE_BOUNDARIES": _cfg.ZONE_BOUNDARIES,
            "MAP_SETTINGS": _cfg.MAP_SETTINGS,
            "ALERT_THRESHOLDS": _cfg.ALERT_THRESHOLDS,
            "RECOMMENDATION_THRESHOLDS": _cfg.RECOMMENDATION_THRESHOLDS,
            "DASHBOARD_SETTINGS": _cfg.DASHBOARD_SETTINGS,
            "FLOORPLAN_IMAGE": _cfg.FLOORPLAN_IMAGE_CONFIG,
            "CALIBRATION": _cfg.CALIBRATION_CONFIG,
            "FLOOR_BOUNDARY": _cfg.FLOOR_BOUNDARY_CONFIG,
            "BEACON_POSITIONS": {k: list(v) for k, v in _cfg.BEACON_POSITIONS.items()},
            "MINOR_ID_TO_PI_NAME_MAP": _cfg.MINOR_ID_TO_PI_NAME_MAP,
            "FLOOR_OBJECTS": _cfg.FLOOR_OBJECTS_CONFIG,
        })
    except Exception as e:
        logger.error(f"!!! /api/app_config ERROR: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500

@api_bp.route('/beacon-density') 
def get_beacon_density_endpoint():
    """
    ビーコン密度ヒートマップ用のデータを返すエンドポイント
    """
    logger.debug("--- /api/beacon-density リクエスト受信 ---")
    try:
        current_positions, _ = get_latest_iphone_positions() # 最新のiPhone座標を取得
        logger.debug(f"密度計算用 元データ: {len(current_positions)} 件")
        if not current_positions: return jsonify({})

        x_range = MAP_SETTINGS.get("x_range", [-1000, 9000])
        y_range = MAP_SETTINGS.get("y_range", [-2500, 9500])
        density_data = calculate_beacon_density(current_positions, x_range, y_range)

        if density_data:
            logger.debug(f"密度計算成功: X={len(density_data['x'])}, Y={len(density_data['y'])}, Z={len(density_data['z'])}x{len(density_data['z'][0])}")
            return jsonify(density_data) # ★ 計算結果を返す
        else:
            logger.debug("密度計算失敗またはデータ不足")
            return jsonify({}) # 空で返す

    except Exception as e:
        logger.error(f"Error getting beacon density: {e}", exc_info=True)
        return jsonify({"error": "Failed to retrieve beacon density"}), 500
    
@api_bp.route('/recommendations')
def get_recommendations():
    """
    ユーザーの好みに基づいて最適なエリアを提案する
    クエリパラメータ: ?temp=cool&occupancy=quiet&light=bright&humidity=dry&co2=fresh
    """
    try:
        # 1. ユーザーの好みを取得
        pref_temp = request.args.get('temp', 'any')
        pref_occupancy = request.args.get('occupancy', 'any')
        pref_light = request.args.get('light', 'any')
        pref_humidity = request.args.get('humidity', 'any')
        pref_co2 = request.args.get('co2', 'any')

        # 2. 分析モジュールからレコメンデーションを取得
        recommendation_data = calculate_recommendations(pref_temp, pref_occupancy, pref_light, pref_humidity, pref_co2)

        if "error" in recommendation_data:
            return jsonify(recommendation_data), 500
            
        return jsonify(recommendation_data)

    except Exception as e:
        logger.error(f"レコメンデーションAPIエラー: {e}", exc_info=True)
        return jsonify({"error": "Failed to generate recommendations"}), 500

# --- ▼▼▼ iPhone連携用のAPI ▼▼▼ ---

@api_bp.route('/add_location', methods=['POST'])
def api_add_location():
    """
    [iPhone -> DB] KF補正後の「最終座標」を受け取り、
    ★ スナップ/ログトグルに基づき処理、スナップ後の座標をiPhoneに返す ★
    """
    data = request.get_json()
    if not data:
        return jsonify({'status': 'error', 'message': 'No data provided'}), 400
    
    try:
        # 1. iPhoneからすべての座標データを取得
        beacon_id = data.get('beacon_id')
        user_name = data.get('user_name', 'Unknown')
        job_title = data.get('job_title', 'unknown')
        department = data.get('department', 'other')
        status = data.get('status', 'available')
        is_moving = data.get('is_moving', False)
        lsm_x = data.get('lsm_x')
        lsm_y = data.get('lsm_y')
        kf_x = data.get('kf_x')
        kf_y = data.get('kf_y')
        pi_ids_list = data.get('pi_ids_used')

        # 2. 2つのトグルの状態を取得
        snap_enabled = data.get('snap_enabled', True)
        detailed_logging = data.get('detailed_logging', False)
        calc_method = data.get('calc_method', 'UNKNOWN')

        if not all([beacon_id, kf_x is not None, kf_y is not None, pi_ids_list]):
             return jsonify({'status': 'error', 'message': 'Missing required fields'}), 400

        # 3. 境界クランプ（常に実行）+ スナップ処理
        from .data_provider import snap_position_to_map, _clamp_to_floor_boundary, save_estimated_position_all, save_estimated_position_snapped_only

        # 境界クランプはsnap_enabledに関係なく常に実行（フロア外に出ないように）
        final_x, final_y = _clamp_to_floor_boundary(kf_x, kf_y)
        logger.debug(f" -> 境界クランプ: ({kf_x}, {kf_y}) → ({final_x}, {final_y})")
            
        # --- ▼▼▼ ★ 4. ログトグルでDB保存を切り替え ★ ▼▼▼ ---
        
        if detailed_logging:
            # 「詳細ロギング」ON: 3種類すべての座標を保存
            logger.debug(" -> 詳細ロギングが有効です。全座標を保存します。")
            success, err_msg = save_estimated_position_all(
                beacon_id=beacon_id,
                user_name=user_name,
                job_title=job_title,
                department=department,
                status=status,
                lsm_x=lsm_x, lsm_y=lsm_y,
                kf_x=kf_x, kf_y=kf_y,
                final_x=final_x, final_y=final_y,
                pi_ids_list=pi_ids_list,
                calc_method=calc_method,
                is_moving=is_moving
            )
        else:
            logger.debug(" -> 詳細ロギングが無効です。スナップ後の座標のみ保存します。")
            success, err_msg = save_estimated_position_snapped_only(
                beacon_id=beacon_id,
                user_name=user_name,
                job_title=job_title,
                department=department,
                status=status,
                final_x=final_x,
                final_y=final_y,
                pi_ids_list=pi_ids_list,
                calc_method=calc_method,
                is_moving=is_moving
            )
        
        # --- ▲▲▲ 修正ここまで ▲▲▲ ---
        
        if not success:
            return jsonify({'status': 'error', 'message': err_msg}), 500

        # 5. iPhoneに「スナップ後の座標」を返す
        return jsonify({
            'status': 'success', 
            'snapped_x': final_x,
            'snapped_y': final_y
        }), 201

    except Exception as e:
        logger.error(f"!!! /api/add_location (snap) ERROR: {e}", exc_info=True)
        return jsonify({'status': 'error', 'message': str(e)}), 500

@api_bp.route('/add_raw_data_batch', methods=['POST'])
def api_add_raw_data_batch():
    """
    [iPhone -> DB] 生の距離データを受け取る窓口
    """
    data = request.get_json()
    if not data:
        return jsonify({'status': 'error', 'message': 'No data provided'}), 400

    success, err_msg = save_raw_location_data(
        beacon_id=data.get('beacon_id'),
        raw_data_list=data.get('raw_data')
    )
    
    if success:
        return jsonify({'status': 'success', 'message': f'Raw data records added'}), 201
    else:
        return jsonify({'status': 'error', 'message': err_msg}), 500

@api_bp.route('/get_iphone_positions')
def api_get_iphone_positions():
    """
    [DB -> JS] 最新のiPhone座標をJSに渡す窓口
    """
    positions, err_msg = get_latest_iphone_positions()

    if positions is not None:
        global _last_interaction_record
        now = _time.time()
        if now - _last_interaction_record > 60:
            _last_interaction_record = now
            try:
                record_current_interactions()
            except Exception as e:
                logger.error(f"Interaction recording error: {e}")
        return jsonify(positions)
    else:
        return jsonify({"error": err_msg}), 500
    
@api_bp.route('/add_env_data', methods=['POST'])
def api_add_env_data():
    """
    [Sensor Pi -> DB] センサーからの環境データを受け取る窓口
    JSON: { "ras_pi_id": "ras_02", "timestamp": "...", "temperature": ..., ... }
    """
    data = request.get_json()
    if not data:
        return jsonify({'status': 'error', 'message': 'No data provided'}), 400

    # (Noneを許可するため、キーの存在のみチェック)
    required_keys = ["ras_pi_id", "timestamp", "temperature", "humidity", "illuminance", "co2"]
    if not all(key in data for key in required_keys):
        return jsonify({'status': 'error', 'message': 'Missing required fields'}), 400

    success, err_msg = save_env_data(
        ras_pi_id=data.get('ras_pi_id'),
        timestamp=data.get('timestamp'),
        temp=data.get('temperature'),
        humidity=data.get('humidity'),
        illuminance=data.get('illuminance'),
        co2=data.get('co2')
    )
    
    if success:
        return jsonify({'status': 'success', 'message': 'Sensor data added successfully'}), 201
    else:
        return jsonify({'status': 'error', 'message': err_msg}), 500

@api_bp.route('/calculate_from_iphone', methods=['POST'])
# def api_calculate_from_iphone():
#     """
#     [iPhone -> Server(LSM) -> iPhone]
#     LSMで測位計算し、結果（座標）をiPhoneに返す
#     """
#     data = request.get_json()
#     if not data:
#         return jsonify({'status': 'error', 'message': 'No data provided'}), 400

#     beacon_id = data.get('beacon_id')
#     raw_data_list = data.get('raw_data') 

#     if not beacon_id or not raw_data_list:
#         return jsonify({'status': 'error', 'message': 'Missing beacon_id or raw_data'}), 400

#     # 1. (DB保存) 生データを location_data に保存
#     save_raw_location_data(beacon_id, raw_data_list)
    
#     # 2. (計算) ★ LSMで測位 ★
#     result_data, err_msg = calculate_least_squares_position(raw_data_list)
    
#     if err_msg:
#         logger.warning(f"LSM計算が失敗したためiPhoneにエラーを返します: {err_msg}")
#         return jsonify({'status': 'error', 'message': err_msg}), 500
        
#     # 3. (iPhoneに応答) 計算結果の座標 + pi_ids_used をJSONで返す
#     logger.debug(f"iPhone '{beacon_id}' にLSM計算結果 {result_data} を返します。")
#     return jsonify({
#         "status": "success",
#         "x": result_data['x'],
#         "y": result_data['y'],
#         "pi_ids_used": result_data['pi_ids_used']
#     }), 200
    
def api_calculate_from_iphone():
    """
    [iPhone -> Server(Shapely) -> iPhone]
    iPhoneから中央値の距離データを受け取り、Shapelyで測位計算し、
    結果（座標）をiPhoneに返す
    """
    data = request.get_json()
    if not data:
        return jsonify({'status': 'error', 'message': 'No data provided'}), 400

    beacon_id = data.get('beacon_id')
    raw_data_list = data.get('raw_data') # [ {"ras_pi_id": 8, "distance": 2500}, ... ]

    if not beacon_id or not raw_data_list:
        return jsonify({'status': 'error', 'message': 'Missing beacon_id or raw_data'}), 400

    # 1. (DB保存) 生データを location_data に保存
    save_raw_location_data(beacon_id, raw_data_list)
    
    # 2. (計算) Shapelyで測位
    result_data, err_msg = calculate_position_with_shapely(raw_data_list)
    
    if err_msg:
        logger.warning(f"Shapely計算が失敗したためiPhoneにエラーを返します: {err_msg}")
        return jsonify({'status': 'error', 'message': err_msg}), 500
        
    # # 3. (DB保存) 計算結果を estimated_positions に保存
    # save_estimated_position(
    #     beacon_id=beacon_id,
    #     est_x=result_data['x'],
    #     est_y=result_data['y'],
    #     pi_ids_list=result_data['pi_ids_used']
    # )
    
    
    
    # 4. 境界クランプ（フロア外に出ないように）
    from .data_provider import _clamp_to_floor_boundary
    clamped_x, clamped_y = _clamp_to_floor_boundary(result_data['x'], result_data['y'])

    # 5. (iPhoneに応答) 計算結果の座標 + pi_ids_used をJSONで返す
    logger.debug(f"iPhone '{beacon_id}' に計算結果 ({clamped_x}, {clamped_y}) を返します。")
    return jsonify({
        "status": "success",
        "x": clamped_x,
        "y": clamped_y,
        "pi_ids_used": result_data['pi_ids_used']
    }), 200
    

@api_bp.route('/update_beacon_config', methods=['POST'])
def api_update_beacon_config():
    """
    [Admin JS -> DB] JSのキャリブレーションツールから
    新しいビーコン設定 (BEACON_POSITIONS, MINOR_ID_TO_PI_NAME_MAP) を受け取り、
    config.json を上書き保存する
    """
    data = request.get_json()
    if not data:
        return jsonify({'status': 'error', 'message': 'No data provided'}), 400

    new_positions = data.get("BEACON_POSITIONS", {})
    new_map = data.get("MINOR_ID_TO_PI_NAME_MAP", {})
    success, message = save_beacon_config(new_positions, new_map)

    if success:
        reload_config()
        return jsonify({'status': 'success', 'message': message}), 200
    else:
        return jsonify({'status': 'error', 'message': message}), 500


ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg'}

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

@api_bp.route('/upload_floorplan', methods=['POST'])
def upload_floorplan():
    """
    [Settings Modal -> Server] フロアプラン画像をアップロードして保存する
    """
    if 'floorplan' not in request.files:
        return jsonify({'status': 'error', 'message': 'No file provided'}), 400

    file = request.files['floorplan']
    if file.filename == '':
        return jsonify({'status': 'error', 'message': 'No file selected'}), 400

    if file and allowed_file(file.filename):
        filename = secure_filename(file.filename)
        upload_dir = os.path.join(current_app.static_folder, 'images')
        os.makedirs(upload_dir, exist_ok=True)
        filepath = os.path.join(upload_dir, filename)
        file.save(filepath)

        image_url = f'/static/images/{filename}'

        # 画像の幅と高さを取得
        width, height = 0, 0
        try:
            from PIL import Image
            with Image.open(filepath) as img:
                width, height = img.size
        except Exception as e:
            logger.warning(f"画像サイズの取得に失敗 (PILが必要): {e}")

        save_floorplan_config(image_url, width, height)
        reload_config()

        return jsonify({
            'status': 'success',
            'filename': filename,
            'url': image_url,
            'width': width,
            'height': height
        }), 200

    return jsonify({'status': 'error', 'message': 'Invalid file type. Allowed: png, jpg, jpeg'}), 400


@api_bp.route('/update_calibration', methods=['POST'])
def update_calibration():
    """
    [Settings Modal -> Server] キャリブレーションデータを保存する
    """
    data = request.get_json()
    if not data:
        return jsonify({'status': 'error', 'message': 'No data provided'}), 400

    success, message = save_calibration_data(data)
    if success:
        reload_config()
        return jsonify({'status': 'success', 'message': message}), 200
    else:
        return jsonify({'status': 'error', 'message': message}), 500


@api_bp.route('/update_floor_boundary', methods=['POST'])
def update_floor_boundary():
    """
    [Settings Modal -> Server] フロア外枠ポリゴンを保存する
    """
    data = request.get_json()
    if data is None:
        return jsonify({'status': 'error', 'message': 'No data provided'}), 400

    boundary = data.get('FLOOR_BOUNDARY', [])
    success, message = save_floor_boundary(boundary)
    if success:
        reload_config()
        return jsonify({'status': 'success', 'message': message}), 200
    else:
        return jsonify({'status': 'error', 'message': message}), 500


@api_bp.route('/update_floor_objects', methods=['POST'])
def update_floor_objects():
    """
    [Settings Modal -> Server] フロアオブジェクト (壁・机・柱) を保存する
    """
    data = request.get_json()
    if data is None:
        return jsonify({'status': 'error', 'message': 'No data provided'}), 400

    objects = data.get('FLOOR_OBJECTS', [])
    success, message = save_floor_objects(objects)
    if success:
        reload_config()
        return jsonify({'status': 'success', 'message': message}), 200
    else:
        return jsonify({'status': 'error', 'message': message}), 500


@api_bp.route('/verify_admin_password', methods=['POST'])
def verify_admin_password():
    """
    [Settings Modal -> Server] 管理者パスワードを検証する
    """
    data = request.get_json()
    if not data:
        return jsonify({'status': 'error', 'message': 'No data provided'}), 400

    password = data.get('password', '')
    if password == ADMIN_PASSWORD:
        return jsonify({'status': 'success'}), 200
    else:
        return jsonify({'status': 'error', 'message': 'パスワードが正しくありません'}), 401


# ==========================================================
#  ユーザープロフィール API
# ==========================================================

@api_bp.route('/user_profiles', methods=['GET'])
def api_get_user_profiles():
    """全ユーザープロフィールを取得"""
    profiles, err = get_all_user_profiles()
    if profiles is not None:
        return jsonify(profiles)
    return jsonify({'error': err}), 500


@api_bp.route('/user_profile/<beacon_id>', methods=['GET'])
def api_get_user_profile(beacon_id):
    """特定ユーザーのプロフィールを取得"""
    profile, err = get_user_profile(beacon_id)
    if err:
        return jsonify({'error': err}), 500
    if profile:
        return jsonify(profile)
    return jsonify({'error': 'Not found'}), 404


@api_bp.route('/update_user_profile', methods=['POST'])
def api_update_user_profile():
    """ユーザープロフィールを作成/更新"""
    data = request.get_json()
    if not data or 'beacon_id' not in data:
        return jsonify({'status': 'error', 'message': 'beacon_id is required'}), 400

    success, message = upsert_user_profile(
        beacon_id=data['beacon_id'],
        user_name=data.get('user_name'),
        job_title=data.get('job_title'),
        department=data.get('department'),
        skills=data.get('skills'),
        hobbies=data.get('hobbies'),
        projects=data.get('projects'),
        email=data.get('email'),
        phone=data.get('phone'),
        profile_image=data.get('profile_image')
    )
    if success:
        return jsonify({'status': 'success', 'message': message}), 200
    return jsonify({'status': 'error', 'message': message}), 500


@api_bp.route('/delete_user_profile/<beacon_id>', methods=['DELETE'])
def api_delete_user_profile(beacon_id):
    """ユーザープロフィールを削除"""
    success, message = delete_user_profile(beacon_id)
    if success:
        return jsonify({'status': 'success', 'message': message}), 200
    return jsonify({'status': 'error', 'message': message}), 500


@api_bp.route('/upload_profile_image', methods=['POST'])
def api_upload_profile_image():
    """プロフィール画像をアップロード"""
    if 'image' not in request.files:
        return jsonify({'status': 'error', 'message': 'No image file'}), 400

    beacon_id = request.form.get('beacon_id')
    if not beacon_id:
        return jsonify({'status': 'error', 'message': 'beacon_id is required'}), 400

    file = request.files['image']
    if file.filename == '':
        return jsonify({'status': 'error', 'message': 'No file selected'}), 400

    allowed = {'png', 'jpg', 'jpeg', 'gif', 'webp'}
    ext = file.filename.rsplit('.', 1)[-1].lower() if '.' in file.filename else ''
    if ext not in allowed:
        return jsonify({'status': 'error', 'message': 'Invalid file type'}), 400

    filename = secure_filename(f"{beacon_id}.{ext}")
    save_dir = os.path.join(current_app.static_folder, 'images', 'profiles')
    os.makedirs(save_dir, exist_ok=True)

    # 既存ファイルを削除 (拡張子が違う場合の対応)
    for old_ext in allowed:
        old_path = os.path.join(save_dir, f"{secure_filename(beacon_id)}.{old_ext}")
        if os.path.exists(old_path):
            os.remove(old_path)

    filepath = os.path.join(save_dir, filename)
    file.save(filepath)

    image_url = f"/static/images/profiles/{filename}"

    # DB のプロフィールにも画像パスを保存
    upsert_user_profile(beacon_id=beacon_id, profile_image=image_url)

    return jsonify({'status': 'success', 'image_url': image_url}), 200


@api_bp.route('/search_users', methods=['GET'])
def api_search_users():
    """ユーザープロフィールをキーワード検索 (絞り込み・並べ替え対応)"""
    query = request.args.get('q', '').strip()
    department = request.args.get('department', '').strip() or None
    job_title = request.args.get('job_title', '').strip() or None
    sort_by = request.args.get('sort', 'name').strip()

    # キーワードもフィルタも両方空の場合は空配列
    if not query and not department and not job_title:
        return jsonify([])

    profiles, err = search_user_profiles(query, department=department, job_title=job_title, sort_by=sort_by)
    if profiles is not None:
        return jsonify(profiles)
    return jsonify({'error': err}), 500


# ===== ソーシャル機能 API =====

@api_bp.route('/skill_search')
def api_skill_search():
    skill = request.args.get('skill', '')
    try:
        results, err = search_users_with_position(skill=skill)
        if err:
            return jsonify({"error": err}), 500
        return jsonify(results or [])
    except Exception as e:
        logger.error(f"Skill search error: {e}")
        return jsonify({"error": str(e)}), 500

@api_bp.route('/nearby_matches')
def api_nearby_matches():
    beacon_id = request.args.get('beacon_id', '')
    radius_mm = int(request.args.get('radius_mm', 3000))
    try:
        matches, err = find_nearby_matches(beacon_id, radius_mm)
        if err:
            return jsonify({"matches": [], "message": err})
        return jsonify({"matches": matches or []})
    except Exception as e:
        logger.error(f"Nearby matches error: {e}")
        return jsonify({"error": str(e)}), 500

@api_bp.route('/user_availability/<beacon_id>')
def api_get_user_availability(beacon_id):
    try:
        avail, err = get_user_availability(beacon_id)
        if err:
            return jsonify({"error": err}), 500
        if avail:
            return jsonify(avail)
        return jsonify({"beacon_id": beacon_id, "nearby_notify_enabled": True, "notify_radius_mm": 3000, "lunch_available": False, "match_on_skills": True, "match_on_hobbies": True})
    except Exception as e:
        logger.error(f"Get availability error: {e}")
        return jsonify({"error": str(e)}), 500

@api_bp.route('/update_user_availability', methods=['POST'])
def api_update_user_availability():
    data = request.get_json(force=True)
    beacon_id = data.get('beacon_id')
    if not beacon_id:
        return jsonify({"error": "beacon_id required"}), 400
    try:
        success, msg = upsert_user_availability(
            beacon_id,
            nearby_notify_enabled=data.get('nearby_notify_enabled'),
            notify_radius_mm=data.get('notify_radius_mm'),
            lunch_available=data.get('lunch_available'),
            match_on_skills=data.get('match_on_skills'),
            match_on_hobbies=data.get('match_on_hobbies')
        )
        return jsonify({"success": success, "message": msg})
    except Exception as e:
        logger.error(f"Update availability error: {e}")
        return jsonify({"error": str(e)}), 500

@api_bp.route('/collab_posts')
def api_get_collab_posts():
    status = request.args.get('status', 'open')
    skill = request.args.get('skill')
    beacon_id = request.args.get('beacon_id')
    hours = request.args.get('hours', type=int)
    post_type = request.args.get('post_type')
    try:
        posts, err = get_collab_posts(status=status, skill=skill, beacon_id=beacon_id, hours=hours, post_type=post_type)
        if err:
            return jsonify({"error": err}), 500
        return jsonify(posts)
    except Exception as e:
        logger.error(f"Get collab posts error: {e}")
        return jsonify({"error": str(e)}), 500

@api_bp.route('/collab_posts', methods=['POST'])
def api_create_collab_post():
    data = request.get_json(force=True)
    try:
        success, msg = create_collab_post(
            beacon_id=data.get('beacon_id', ''),
            user_name=data.get('user_name'),
            post_type=data.get('post_type', 'help_wanted'),
            title=data.get('title', ''),
            description=data.get('description'),
            required_skills=data.get('required_skills')
        )
        return jsonify({"success": success, "message": msg})
    except Exception as e:
        logger.error(f"Create collab post error: {e}")
        return jsonify({"error": str(e)}), 500

@api_bp.route('/collab_posts/<int:post_id>/respond', methods=['POST'])
def api_respond_collab_post(post_id):
    data = request.get_json(force=True)
    try:
        success, msg = respond_to_collab_post(
            post_id=post_id,
            beacon_id=data.get('beacon_id', ''),
            user_name=data.get('user_name'),
            message=data.get('message')
        )
        return jsonify({"success": success, "message": msg})
    except Exception as e:
        logger.error(f"Respond collab post error: {e}")
        return jsonify({"error": str(e)}), 500

@api_bp.route('/collab_posts/<int:post_id>/responses')
def api_get_collab_responses(post_id):
    try:
        responses, err = get_collab_responses(post_id)
        if err:
            return jsonify({"error": err}), 500
        return jsonify(responses)
    except Exception as e:
        logger.error(f"Get collab responses error: {e}")
        return jsonify({"error": str(e)}), 500

@api_bp.route('/collab_posts/<int:post_id>/close', methods=['PUT'])
def api_close_collab_post(post_id):
    data = request.get_json(force=True)
    try:
        success, msg = close_collab_post(post_id=post_id, beacon_id=data.get('beacon_id', ''))
        return jsonify({"success": success, "message": msg})
    except Exception as e:
        logger.error(f"Close collab post error: {e}")
        return jsonify({"error": str(e)}), 500

@api_bp.route('/interaction_stats')
def api_interaction_stats():
    hours = request.args.get('hours')
    days = request.args.get('days')
    if hours is not None:
        total_hours = int(hours)
    elif days is not None:
        total_hours = int(days) * 24
    else:
        total_hours = 7 * 24
    try:
        stats, err = get_interaction_stats(hours=total_hours)
        if err:
            return jsonify({"error": err}), 500
        return jsonify(stats or {})
    except Exception as e:
        logger.error(f"Interaction stats error: {e}")
        return jsonify({"error": str(e)}), 500

@api_bp.route('/my_interactions')
def api_my_interactions():
    beacon_id = request.args.get('beacon_id', '')
    days = int(request.args.get('days', 7))
    try:
        interactions, err = get_my_interactions(beacon_id=beacon_id, days=days)
        if err:
            return jsonify({"error": err}), 500
        return jsonify(interactions or {})
    except Exception as e:
        logger.error(f"My interactions error: {e}")
        return jsonify({"error": str(e)}), 500

@api_bp.route('/lunch_match/generate', methods=['POST'])
def api_generate_lunch_match():
    data = request.get_json(force=True) if request.is_json else {}
    match_type = data.get('match_type', 'interest_based')
    try:
        matches, msg = generate_lunch_matches(match_type=match_type)
        return jsonify({"matches": matches or [], "message": msg})
    except Exception as e:
        logger.error(f"Generate lunch match error: {e}")
        return jsonify({"error": str(e)}), 500

@api_bp.route('/lunch_match/today')
def api_todays_lunch_match():
    beacon_id = request.args.get('beacon_id', '')
    try:
        match, err = get_todays_match(beacon_id=beacon_id)
        if err:
            return jsonify({"error": err}), 500
        return jsonify({"match": match})
    except Exception as e:
        logger.error(f"Today's lunch match error: {e}")
        return jsonify({"error": str(e)}), 500

@api_bp.route('/lunch_match/<int:match_id>/respond', methods=['POST'])
def api_respond_lunch_match(match_id):
    data = request.get_json(force=True)
    try:
        success, msg = respond_to_lunch_match(
            match_id=match_id,
            beacon_id=data.get('beacon_id', ''),
            action=data.get('action', 'accept')
        )
        return jsonify({"success": success, "message": msg})
    except Exception as e:
        logger.error(f"Respond lunch match error: {e}")
        return jsonify({"error": str(e)}), 500

@api_bp.route('/social_recommendations')
def api_social_recommendations():
    beacon_id = request.args.get('beacon_id', '')
    temp = request.args.get('temp', 'any')
    occupancy = request.args.get('occupancy', 'any')
    light = request.args.get('light', 'any')
    humidity = request.args.get('humidity', 'any')
    co2 = request.args.get('co2', 'any')
    near_person = request.args.get('near_person')
    try:
        result = calculate_social_recommendations(
            beacon_id=beacon_id, pref_temp=temp, pref_occupancy=occupancy,
            pref_light=light, pref_humidity=humidity, pref_co2=co2,
            near_person_id=near_person
        )
        return jsonify(result)
    except Exception as e:
        logger.error(f"Social recommendations error: {e}")
        return jsonify({"error": str(e)}), 500