// ===== アプリケーション設定 =====
// サーバーの config.json から取得した値を保持する変数
// (初期値はフォールバック用のデフォルト値)

export let PI_LOCATIONS = [];
export let ZONE_BOUNDARIES = {};
export let MAP_SETTINGS = {
    x_range: [-1000, 9000],
    y_range: [-2500, 9500],
    entrance_annotations: [],
    pi_annotation_y_offset: 500
};
export let ALERT_THRESHOLDS = {
    temp_low: 23.0,
    temp_high: 25.0,
    humidity_low: 30.0,
    humidity_high: 70.0,
    lux_low: 200.0,
    lux_high: 600.0,
    co2_high: 400.0
};
export let DASHBOARD_SETTINGS = {
    update_interval_ms: 10000,
    max_line_chart_points: 20
};
export let FLOORPLAN_IMAGE = {
    url: '',
    width: 0,
    height: 0
};
export let CALIBRATION = {
    origin_px: { x: 0, y: 0 },
    scale_mm_per_px: 1.0
};
export let FLOOR_BOUNDARY = []; // [{x, y}, ...] フロア外枠のポリゴン (物理座標mm)

/**
 * サーバーから設定を取得して各変数を更新する
 * アプリ起動時に1回だけ呼び出す
 */
export async function loadAppConfig() {
    try {
        const response = await fetch('/api/app_config');
        if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
        const config = await response.json();

        if (config.PI_LOCATIONS) PI_LOCATIONS = config.PI_LOCATIONS;
        if (config.ZONE_BOUNDARIES) ZONE_BOUNDARIES = config.ZONE_BOUNDARIES;
        if (config.MAP_SETTINGS) MAP_SETTINGS = { ...MAP_SETTINGS, ...config.MAP_SETTINGS };
        if (config.ALERT_THRESHOLDS) ALERT_THRESHOLDS = { ...ALERT_THRESHOLDS, ...config.ALERT_THRESHOLDS };
        if (config.DASHBOARD_SETTINGS) DASHBOARD_SETTINGS = { ...DASHBOARD_SETTINGS, ...config.DASHBOARD_SETTINGS };
        if (config.FLOORPLAN_IMAGE) FLOORPLAN_IMAGE = { ...FLOORPLAN_IMAGE, ...config.FLOORPLAN_IMAGE };
        if (config.CALIBRATION) CALIBRATION = { ...CALIBRATION, ...config.CALIBRATION };
        if (config.FLOOR_BOUNDARY) FLOOR_BOUNDARY = config.FLOOR_BOUNDARY;

        console.log("アプリ設定をサーバーから読み込みました:", config);
    } catch (error) {
        console.error("アプリ設定の取得に失敗しました。デフォルト値を使用します:", error);
    }
}

// センサーごとの設定を共通化
export const sensorSettings = {
    'temp': {
        label: '温度',
        unit: '°C',
        gaugeMax: 40
    },
    'humidity': {
        label: '湿度',
        unit: '%',
        gaugeMax: 100
    },
    'lux': {
        label: '照度',
        unit: 'lx',
        gaugeMax: 1200
    },
    'co2': {
        label: 'CO2濃度',
        unit: 'ppm',
        gaugeMax: 1000
    }
};
