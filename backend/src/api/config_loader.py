import json
import os
import logging
from shapely.geometry import shape, Point

# ロギング設定
logging.basicConfig(level=logging.DEBUG,
                    format='%(asctime)s %(levelname)s:%(name)s: %(message)s',
                    datefmt='%Y-%m-%d %H:%M:%S')
logger = logging.getLogger(__name__)

# --- グローバル変数の定義と設定ファイルの読み込み ---
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# config.json の読み込み
# backend/src/api/ → backend/data/
DATA_DIR = os.path.join(BASE_DIR, '..', '..', 'data')
CONFIG_JSON_PATH = os.path.join(DATA_DIR, 'config_lab.json')
try:
    with open(CONFIG_JSON_PATH, 'r', encoding='utf-8') as f:
        config = json.load(f)
    
    # JSONからグローバル変数に展開
    PI_LOCATIONS = config.get("PI_LOCATIONS", [])
    
    # JSONの配列 [x, y] を Pythonのタプル (x, y) に変換
    _ground_truth_raw = config.get("BEACON_GROUND_TRUTH", {})
    BEACON_GROUND_TRUTH = {key: tuple(value) for key, value in _ground_truth_raw.items()}
    ZONE_MAPPING = config.get("ZONE_MAPPING", {})
    ZONE_BOUNDARIES = config.get("ZONE_BOUNDARIES", {})
    BEACON_ACTUAL_DISTANCES = config.get("BEACON_ACTUAL_DISTANCES", {})
    MINOR_ID_TO_PI_NAME_MAP = config.get("MINOR_ID_TO_PI_NAME_MAP", {})
    
    # アプリケーション設定の読み込み
    MAP_SETTINGS = config.get("MAP_SETTINGS", {})
    SHAPELY_SETTINGS = config.get("SHAPELY_SETTINGS", {})
    POSITION_STALENESS_MINUTES = config.get("POSITION_STALENESS_MINUTES", 1)
    DASHBOARD_SETTINGS = config.get("DASHBOARD_SETTINGS", {})
    ALERT_THRESHOLDS = config.get("ALERT_THRESHOLDS", {})
    RECOMMENDATION_THRESHOLDS = config.get("RECOMMENDATION_THRESHOLDS", {})
    
    # フロアプラン画像とキャリブレーション設定の読み込み
    FLOORPLAN_IMAGE_CONFIG = config.get("FLOORPLAN_IMAGE", {"url": "", "width": 0, "height": 0})
    CALIBRATION_CONFIG = config.get("CALIBRATION", {"origin_px": {"x": 0, "y": 0}, "scale_mm_per_px": 1.0})
    FLOOR_BOUNDARY_CONFIG = config.get("FLOOR_BOUNDARY", [])
    FLOOR_OBJECTS_CONFIG = config.get("FLOOR_OBJECTS", [])
    ADMIN_PASSWORD = config.get("ADMIN_PASSWORD", "admin")

    logger.info(f"設定ファイル {CONFIG_JSON_PATH} の読み込み成功")
    
except Exception as e:
    logger.error(f"!!! 設定ファイル {CONFIG_JSON_PATH} の読み込みに失敗: {e}")
    PI_LOCATIONS = []
    BEACON_GROUND_TRUTH = {}
    ZONE_MAPPING = {}
    ZONE_BOUNDARIES = {}
    MAP_SETTINGS = {}
    SHAPELY_SETTINGS = {}
    POSITION_STALENESS_MINUTES = 1
    DASHBOARD_SETTINGS = {}
    ALERT_THRESHOLDS = {}
    RECOMMENDATION_THRESHOLDS = {}
    FLOORPLAN_IMAGE_CONFIG = {"url": "", "width": 0, "height": 0}
    CALIBRATION_CONFIG = {"origin_px": {"x": 0, "y": 0}, "scale_mm_per_px": 1.0}
    FLOOR_BOUNDARY_CONFIG = []
    FLOOR_OBJECTS_CONFIG = []
    ADMIN_PASSWORD = "admin"

# 派生変数の定義 (config.json からロードした後に実行)
PI_IDS = [pi['ras_pi_id'] for pi in PI_LOCATIONS]
BEACON_POSITIONS = {pi['ras_pi_id']: (pi['x'], pi['y']) for pi in PI_LOCATIONS}

# フロアプランデータの読み込み
FLOORPLAN_JSON_PATH = os.path.join(DATA_DIR, 'lab_coord.json')

# フロアプランデータをグローバル変数として一度だけ読み込む
try:
    with open(FLOORPLAN_JSON_PATH, 'r', encoding='utf-8') as f:
        floorplan_data_cache = json.load(f)
    logger.info(f"フロアプラン {FLOORPLAN_JSON_PATH} の読み込み成功")
except Exception as e:
    logger.error(f"!!! フロアプラン {FLOORPLAN_JSON_PATH} の読み込みに失敗: {e}")
    floorplan_data_cache = []


def reload_config():
    """設定ファイルを再読込してグローバル変数を更新する"""
    global PI_LOCATIONS, BEACON_GROUND_TRUTH, ZONE_MAPPING, ZONE_BOUNDARIES
    global BEACON_ACTUAL_DISTANCES, MINOR_ID_TO_PI_NAME_MAP
    global MAP_SETTINGS, SHAPELY_SETTINGS, POSITION_STALENESS_MINUTES
    global DASHBOARD_SETTINGS, ALERT_THRESHOLDS, RECOMMENDATION_THRESHOLDS
    global FLOORPLAN_IMAGE_CONFIG, CALIBRATION_CONFIG, FLOOR_BOUNDARY_CONFIG
    global FLOOR_OBJECTS_CONFIG
    global ADMIN_PASSWORD, PI_IDS, BEACON_POSITIONS

    try:
        with open(CONFIG_JSON_PATH, 'r', encoding='utf-8') as f:
            cfg = json.load(f)

        PI_LOCATIONS = cfg.get("PI_LOCATIONS", [])
        _gt_raw = cfg.get("BEACON_GROUND_TRUTH", {})
        BEACON_GROUND_TRUTH = {k: tuple(v) for k, v in _gt_raw.items()}
        ZONE_MAPPING = cfg.get("ZONE_MAPPING", {})
        ZONE_BOUNDARIES = cfg.get("ZONE_BOUNDARIES", {})
        BEACON_ACTUAL_DISTANCES = cfg.get("BEACON_ACTUAL_DISTANCES", {})
        MINOR_ID_TO_PI_NAME_MAP = cfg.get("MINOR_ID_TO_PI_NAME_MAP", {})
        MAP_SETTINGS = cfg.get("MAP_SETTINGS", {})
        SHAPELY_SETTINGS = cfg.get("SHAPELY_SETTINGS", {})
        POSITION_STALENESS_MINUTES = cfg.get("POSITION_STALENESS_MINUTES", 1)
        DASHBOARD_SETTINGS = cfg.get("DASHBOARD_SETTINGS", {})
        ALERT_THRESHOLDS = cfg.get("ALERT_THRESHOLDS", {})
        RECOMMENDATION_THRESHOLDS = cfg.get("RECOMMENDATION_THRESHOLDS", {})

        FLOORPLAN_IMAGE_CONFIG = cfg.get("FLOORPLAN_IMAGE", {"url": "", "width": 0, "height": 0})
        CALIBRATION_CONFIG = cfg.get("CALIBRATION", {"origin_px": {"x": 0, "y": 0}, "scale_mm_per_px": 1.0})
        FLOOR_BOUNDARY_CONFIG = cfg.get("FLOOR_BOUNDARY", [])
        FLOOR_OBJECTS_CONFIG = cfg.get("FLOOR_OBJECTS", [])
        ADMIN_PASSWORD = cfg.get("ADMIN_PASSWORD", "admin")
        PI_IDS = [pi['ras_pi_id'] for pi in PI_LOCATIONS]
        BEACON_POSITIONS = {pi['ras_pi_id']: (pi['x'], pi['y']) for pi in PI_LOCATIONS}

        logger.info("設定ファイルの再読込に成功しました")
        return True
    except Exception as e:
        logger.error(f"設定ファイルの再読込に失敗: {e}")
        return False
