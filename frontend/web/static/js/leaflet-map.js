// leaflet-map.js -- Leaflet.jsによるフロアマップモジュール
import { PI_LOCATIONS, MAP_SETTINGS, ZONE_BOUNDARIES, FLOORPLAN_IMAGE, CALIBRATION, FLOOR_BOUNDARY } from './config.js';

// --- モジュールレベルの状態 ---
let map = null;
let imageOverlay = null;
let heatOverlay = null;  // Canvas描画ヒートマップ用 L.imageOverlay
let piMarkerGroup = null;
let personMarkerGroup = null;
let imageBounds = null;

// レコメンド用ミニマップ
let recMap = null;
let recZoneGroup = null;
let recImageOverlay = null;

// 定数
const deptColors = {
    'dev_team': '#007bff',
    'sales_team': '#dc3545',
    'hr_team': '#28a745',
    'other': '#6c757d'
};

const jobIcons = {
    'engineer': '\u{1F468}\u200D\u{1F4BB}',
    'manager': '\u{1F454}',
    'sales': '\u{1F4BC}',
    'admin': '\u{1F4C4}',
    'unknown': '\u{1F464}'
};

const jobLabels = {
    'engineer': 'エンジニア',
    'manager': 'マネージャー',
    'sales': '営業',
    'admin': '事務',
    'unknown': '未設定'
};

const deptLabels = {
    'dev_team': '開発部',
    'sales_team': '営業部',
    'hr_team': '総務部',
    'other': 'その他'
};

const statusLabels = {
    'available': '取込可',
    'busy': '取込中',
    'meeting': '会議中',
    'break': '休憩中'
};

const statusColors = {
    'available': '#28a745',
    'busy': '#dc3545',
    'meeting': '#fd7e14',
    'break': '#17a2b8'
};

// --- 座標変換 ---

function pxToMm(px_x, px_y) {
    const cal = CALIBRATION;
    const mm_x = (px_x - cal.origin_px.x) * cal.scale_mm_per_px;
    const mm_y = -(px_y - cal.origin_px.y) * cal.scale_mm_per_px;
    return { x: mm_x, y: mm_y };
}

/**
 * 物理座標(mm)をLeaflet LatLngに変換
 * 物理座標系: Y負 = 画像下方向 → Leaflet: Y反転して表示
 */
function mmToLatLng(x_mm, y_mm) {
    return L.latLng(-y_mm, x_mm);
}

function calculateImageBounds() {
    const cal = CALIBRATION;
    const img = FLOORPLAN_IMAGE;

    if (!img.width || !img.height || !cal.scale_mm_per_px) {
        const xr = MAP_SETTINGS.x_range || [-1000, 9000];
        const yr = MAP_SETTINGS.y_range || [-2500, 9500];
        return L.latLngBounds(
            L.latLng(yr[0], xr[0]),
            L.latLng(yr[1], xr[1])
        );
    }

    const bottomLeftMm = pxToMm(0, 0);
    const topRightMm = pxToMm(img.width, img.height);
    const southWest = mmToLatLng(bottomLeftMm.x, bottomLeftMm.y);
    const northEast = mmToLatLng(topRightMm.x, topRightMm.y);

    return L.latLngBounds(southWest, northEast);
}

// =============================================
// カラーマップ定義 (0.0〜1.0 の正規化値 → RGBA)
// =============================================

/**
 * 複数ストップの線形補間カラーマップ
 * stops: [[position, r, g, b], ...] position: 0.0〜1.0
 */
function interpolateColormap(stops, t) {
    t = Math.max(0, Math.min(1, t));
    for (let i = 0; i < stops.length - 1; i++) {
        const [p0, r0, g0, b0] = stops[i];
        const [p1, r1, g1, b1] = stops[i + 1];
        if (t >= p0 && t <= p1) {
            const f = (t - p0) / (p1 - p0);
            return [
                Math.round(r0 + f * (r1 - r0)),
                Math.round(g0 + f * (g1 - g0)),
                Math.round(b0 + f * (b1 - b0))
            ];
        }
    }
    const last = stops[stops.length - 1];
    return [last[1], last[2], last[3]];
}

// センサータイプ別カラーマップ stops: [position, R, G, B]
// 温度: 青(低温)→シアン→緑→黄→オレンジ→赤(高温) のレインボー系で差を明確化
const sensorColormaps = {
    'temp': [
        [0.0,   8,  29, 168],   // 濃い青 (低温)
        [0.15, 37, 116, 219],   // 青
        [0.30, 18, 178, 217],   // シアン
        [0.45, 70, 199, 102],   // 緑
        [0.60, 235, 219,  50],  // 黄
        [0.75, 240, 149,  30],  // オレンジ
        [0.90, 220,  50,  30],  // 赤
        [1.0, 150,  10,  20],   // 暗赤 (高温)
    ],
    'humidity': [
        [0.0, 255, 255, 224],   // 薄い黄 (低湿)
        [0.25, 160, 230, 200],  // 薄緑
        [0.50, 80, 180, 230],   // 水色
        [0.75, 30, 120, 220],   // 青
        [1.0,  10,  40, 170],   // 濃い青 (高湿)
    ],
    'lux': [
        [0.0,  15,   5,  30],   // 暗い紫 (暗い)
        [0.25, 80,  30, 120],   // 紫
        [0.50, 180, 100,  30],  // 暗ゴールド
        [0.75, 240, 200,  50],  // ゴールド
        [1.0, 255, 255, 160],   // 明るい黄 (明るい)
    ],
    'co2': [
        [0.0,  30, 160,  70],   // 緑 (低CO2)
        [0.30, 160, 210,  80],  // 黄緑
        [0.55, 240, 200,  50],  // 黄
        [0.75, 230, 120,  40],  // オレンジ
        [1.0, 200,  30,  30],   // 赤 (高CO2)
    ]
};

// =============================================
// IDW補間 + Canvas描画ヒートマップ
// =============================================

/**
 * 凸包 (Convex Hull) を計算 (Andrew's monotone chain)
 * points: [{x, y}, ...] → 凸包頂点の配列を返す (反時計回り)
 */
function convexHull(points) {
    const pts = points.slice().sort((a, b) => a.x - b.x || a.y - b.y);
    if (pts.length <= 1) return pts;

    const cross = (O, A, B) => (A.x - O.x) * (B.y - O.y) - (A.y - O.y) * (B.x - O.x);

    // 下側ハル
    const lower = [];
    for (const p of pts) {
        while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0)
            lower.pop();
        lower.push(p);
    }
    // 上側ハル
    const upper = [];
    for (let i = pts.length - 1; i >= 0; i--) {
        const p = pts[i];
        while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0)
            upper.pop();
        upper.push(p);
    }
    lower.pop();
    upper.pop();
    return lower.concat(upper);
}

/**
 * 点が凸多角形の内部にあるか判定 (ray casting)
 * polygon: [{x,y}, ...] の頂点リスト (閉じていなくてもOK)
 */
function pointInPolygon(px, py, polygon) {
    let inside = false;
    const n = polygon.length;
    for (let i = 0, j = n - 1; i < n; j = i++) {
        const xi = polygon[i].x, yi = polygon[i].y;
        const xj = polygon[j].x, yj = polygon[j].y;
        if (((yi > py) !== (yj > py)) && (px < (xj - xi) * (py - yi) / (yj - yi) + xi)) {
            inside = !inside;
        }
    }
    return inside;
}

/**
 * 凸包をバッファ(膨張)する
 * 各辺を外側にbufferDist分オフセットし、新しい頂点を返す
 */
function bufferConvexHull(hull, bufferDist) {
    if (hull.length < 3) return hull;
    const n = hull.length;
    const buffered = [];

    for (let i = 0; i < n; i++) {
        const prev = hull[(i - 1 + n) % n];
        const curr = hull[i];
        const next = hull[(i + 1) % n];

        // 2辺の外向き法線ベクトル (CCW多角形の右法線)
        const dx1 = curr.x - prev.x, dy1 = curr.y - prev.y;
        const len1 = Math.sqrt(dx1 * dx1 + dy1 * dy1) || 1;
        const nx1 = dy1 / len1, ny1 = -dx1 / len1;

        const dx2 = next.x - curr.x, dy2 = next.y - curr.y;
        const len2 = Math.sqrt(dx2 * dx2 + dy2 * dy2) || 1;
        const nx2 = dy2 / len2, ny2 = -dx2 / len2;

        // 2法線の平均を正規化してバッファ方向とする
        let bx = nx1 + nx2, by = ny1 + ny2;
        const blen = Math.sqrt(bx * bx + by * by) || 1;
        bx /= blen;
        by /= blen;

        buffered.push({
            x: curr.x + bx * bufferDist,
            y: curr.y + by * bufferDist
        });
    }
    return buffered;
}

/**
 * IDW (Inverse Distance Weighting) で1点の補間値を計算
 */
function idwInterpolate(gx, gy, sensorData, sensorType, power) {
    let numerator = 0;
    let denominator = 0;

    for (const d of sensorData) {
        const val = d[sensorType];
        if (val === null || val === undefined || isNaN(val)) continue;

        const dx = d.x - gx;
        const dy = d.y - gy;
        const dist = Math.sqrt(dx * dx + dy * dy);

        if (dist < 1) {
            return val;
        }

        const weight = 1 / Math.pow(dist, power);
        numerator += weight * val;
        denominator += weight;
    }

    return denominator > 0 ? numerator / denominator : 0;
}

/**
 * 凸包境界付近でアルファを滑らかにフェードアウトする距離を計算
 * 凸包の内側: 1.0, 境界付近: 0〜1, 外側: 0
 */
function calcAlphaForPoint(px, py, hullBuffered, hullOuter, fadeWidth) {
    // hullOuter（フェード外縁）の外なら完全透明
    if (!pointInPolygon(px, py, hullOuter)) return 0;
    // hullBuffered（元の凸包+小バッファ）の内部なら不透明
    if (pointInPolygon(px, py, hullBuffered)) return 1.0;

    // 境界付近: hullBufferedの最近辺からの距離でフェード
    let minDist = Infinity;
    const n = hullBuffered.length;
    for (let i = 0; i < n; i++) {
        const ax = hullBuffered[i].x, ay = hullBuffered[i].y;
        const bx = hullBuffered[(i + 1) % n].x, by = hullBuffered[(i + 1) % n].y;
        const dist = distPointToSegment(px, py, ax, ay, bx, by);
        if (dist < minDist) minDist = dist;
    }
    return Math.max(0, 1 - minDist / fadeWidth);
}

/**
 * 点から線分への最短距離
 */
function distPointToSegment(px, py, ax, ay, bx, by) {
    const dx = bx - ax, dy = by - ay;
    const lenSq = dx * dx + dy * dy;
    if (lenSq === 0) return Math.sqrt((px - ax) ** 2 + (py - ay) ** 2);
    let t = ((px - ax) * dx + (py - ay) * dy) / lenSq;
    t = Math.max(0, Math.min(1, t));
    const projX = ax + t * dx, projY = ay + t * dy;
    return Math.sqrt((px - projX) ** 2 + (py - projY) ** 2);
}

/**
 * Canvas にIDW補間カラーマップを描画し、data URL を返す
 * boundary が null の場合はグリッド全面を描画する
 * boundary が指定されていればポリゴン内部のみ描画する (フェードなし)
 */
function renderHeatmapCanvas(sensorData, sensorType, xMin, xMax, yMin, yMax, boundary) {
    const gridW = 150;
    const gridH = 150;

    const canvas = document.createElement('canvas');
    canvas.width = gridW;
    canvas.height = gridH;
    const ctx = canvas.getContext('2d');
    const imgData = ctx.createImageData(gridW, gridH);
    const data = imgData.data;

    const colormap = sensorColormaps[sensorType] || sensorColormaps['temp'];
    const values = sensorData.map(d => d[sensorType]).filter(v => typeof v === 'number' && !isNaN(v));
    const minVal = Math.min(...values);
    const maxVal = Math.max(...values);
    const range = maxVal - minVal || 1;

    // データ範囲が狭い場合でも色の差がはっきり出るよう、
    // 上下に5%マージンを設け正規化範囲を若干広げる
    const margin = range * 0.05;
    const normMin = minVal - margin;
    const normRange = range + margin * 2;

    const xStep = (xMax - xMin) / gridW;
    const yStep = (yMax - yMin) / gridH;
    const power = 2;
    const baseAlpha = 170; // 基本の不透明度 (0-255)

    for (let row = 0; row < gridH; row++) {
        for (let col = 0; col < gridW; col++) {
            const gx = xMin + col * xStep;
            const gy = yMin + row * yStep;

            // ポリゴンが指定されている場合、内部のみ描画
            if (boundary && boundary.length >= 3) {
                if (!pointInPolygon(gx, gy, boundary)) continue;
            }

            const interpolated = idwInterpolate(gx, gy, sensorData, sensorType, power);
            const normalized = Math.max(0, Math.min(1, (interpolated - normMin) / normRange));

            const [r, g, b] = interpolateColormap(colormap, normalized);
            const idx = (row * gridW + col) * 4;
            data[idx]     = r;
            data[idx + 1] = g;
            data[idx + 2] = b;
            data[idx + 3] = baseAlpha;
        }
    }

    ctx.putImageData(imgData, 0, 0);
    return { dataUrl: canvas.toDataURL(), minVal, maxVal };
}

/**
 * カラーバーを描画して min/max ラベルを更新する
 */
const sensorUnits = { temp: '°C', humidity: '%', lux: 'lx', co2: 'ppm' };

function updateColorbar(sensorType, minVal, maxVal) {
    const canvas = document.getElementById('colorbar-canvas');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const w = canvas.width;
    const h = canvas.height;
    const colormap = sensorColormaps[sensorType] || sensorColormaps['temp'];

    for (let x = 0; x < w; x++) {
        const t = x / (w - 1);
        const [r, g, b] = interpolateColormap(colormap, t);
        ctx.fillStyle = `rgb(${r},${g},${b})`;
        ctx.fillRect(x, 0, 1, h);
    }

    const unit = sensorUnits[sensorType] || '';
    const minEl = document.getElementById('colorbar-min');
    const maxEl = document.getElementById('colorbar-max');
    if (minEl) minEl.textContent = minVal.toFixed(1) + unit;
    if (maxEl) maxEl.textContent = maxVal.toFixed(1) + unit;
}

// --- メインマップ ---

export function initMap(containerId) {
    map = L.map(containerId, {
        crs: L.CRS.Simple,
        minZoom: -5,
        maxZoom: 3,
        zoomSnap: 0.25,
        zoomDelta: 0.25,
        attributionControl: false
    });

    imageBounds = calculateImageBounds();

    if (FLOORPLAN_IMAGE.url) {
        imageOverlay = L.imageOverlay(FLOORPLAN_IMAGE.url, imageBounds).addTo(map);
    }

    // フロアマップのアスペクト比に合わせてコンテナの高さを調整
    adjustWrapperHeight('heatmap-wrapper', map, 0.3, 0.85);

    map.fitBounds(imageBounds);

    piMarkerGroup = L.layerGroup().addTo(map);
    personMarkerGroup = L.layerGroup().addTo(map);

    return map;
}

/**
 * フロアマップ画像のアスペクト比に基づいてマップコンテナの高さを動的に調整
 * wrapperId: ラッパー要素のID
 * mapInstance: Leafletマップインスタンス (リサイズ通知用)
 * minRatio / maxRatio: 画面高さに対する上下限比率
 */
function adjustWrapperHeight(wrapperId, mapInstance, minRatio, maxRatio) {
    const wrapper = document.getElementById(wrapperId);
    if (!wrapper) return;

    const img = FLOORPLAN_IMAGE;
    if (!img.width || !img.height) return;

    const aspectRatio = img.height / img.width;
    const wrapperWidth = wrapper.clientWidth;
    let idealHeight = wrapperWidth * aspectRatio;

    // 上下限: 画面高さに対する比率でクランプ
    const minH = window.innerHeight * minRatio;
    const maxH = window.innerHeight * maxRatio;
    idealHeight = Math.max(minH, Math.min(maxH, idealHeight));

    wrapper.style.height = idealHeight + 'px';

    // Leafletにサイズ変更を通知
    if (mapInstance) {
        mapInstance.invalidateSize();
        if (imageBounds) mapInstance.fitBounds(imageBounds);
    }
}

// ウィンドウリサイズ時にも全マップを再調整
window.addEventListener('resize', () => {
    if (map) {
        adjustWrapperHeight('heatmap-wrapper', map, 0.3, 0.85);
    }
    if (recMap) {
        adjustWrapperHeight('recommendation-map-wrapper', recMap, 0.15, 0.5);
    }
});

/**
 * ヒートマップを更新
 * IDW補間 → Canvas描画 → L.imageOverlay で地図（フロアマップ画像範囲全体）に重ねる
 */
export function updateHeatmap(sensorData, sensorType) {
    if (!map) return;

    const validData = sensorData.filter(d =>
        typeof d[sensorType] === 'number' && !isNaN(d[sensorType]) &&
        typeof d.x === 'number' && typeof d.y === 'number'
    );
    if (validData.length < 2) return;

    // フロアマップ画像の範囲を物理座標(mm)で取得
    const cal = CALIBRATION;
    const img = FLOORPLAN_IMAGE;
    let xMin, xMax, yMin, yMax;

    if (img.width && img.height && cal.scale_mm_per_px) {
        const topLeft = pxToMm(0, 0);
        const bottomRight = pxToMm(img.width, img.height);
        xMin = Math.min(topLeft.x, bottomRight.x);
        xMax = Math.max(topLeft.x, bottomRight.x);
        yMin = Math.min(topLeft.y, bottomRight.y);
        yMax = Math.max(topLeft.y, bottomRight.y);
    } else {
        // フォールバック: センサー範囲 + パディング
        const xs = validData.map(d => d.x);
        const ys = validData.map(d => d.y);
        const padding = 1500;
        xMin = Math.min(...xs) - padding;
        xMax = Math.max(...xs) + padding;
        yMin = Math.min(...ys) - padding;
        yMax = Math.max(...ys) + padding;
    }

    // FLOOR_BOUNDARYが設定されていればポリゴン内のみ描画
    // 未設定なら画像全域を描画
    let boundaryPolygon = null;
    if (FLOOR_BOUNDARY && FLOOR_BOUNDARY.length >= 3) {
        boundaryPolygon = FLOOR_BOUNDARY; // [{x, y}, ...] 物理座標mm

        // 描画範囲をポリゴンのバウンディングボックスに限定
        const bxs = boundaryPolygon.map(p => p.x);
        const bys = boundaryPolygon.map(p => p.y);
        const pad = 100;
        xMin = Math.min(...bxs) - pad;
        xMax = Math.max(...bxs) + pad;
        yMin = Math.min(...bys) - pad;
        yMax = Math.max(...bys) + pad;
    }

    // Canvas に描画して data URL 取得
    const result = renderHeatmapCanvas(validData, sensorType, xMin, xMax, yMin, yMax, boundaryPolygon);

    // カラーバー（凡例）を更新
    updateColorbar(sensorType, result.minVal, result.maxVal);

    // 物理座標 → Leaflet座標 のboundsを計算
    const heatBounds = L.latLngBounds(
        mmToLatLng(xMin, yMax),  // southWest
        mmToLatLng(xMax, yMin)   // northEast
    );

    // 前のヒートマップを削除して新しく追加
    if (heatOverlay) {
        map.removeLayer(heatOverlay);
    }
    heatOverlay = L.imageOverlay(result.dataUrl, heatBounds, {
        opacity: 0.7,
        interactive: false
    }).addTo(map);

    // ヒートマップは画像の上、マーカーの下に配置
    heatOverlay.bringToFront();
    if (imageOverlay) imageOverlay.bringToBack();
}

/**
 * ラズパイマーカーを更新
 */
export function updatePiMarkers(sensorData, sensorType, settings) {
    if (!piMarkerGroup) return;
    piMarkerGroup.clearLayers();

    sensorData.forEach(d => {
        const valueText = d[sensorType]?.toFixed(1) || '0';

        const piIcon = L.divIcon({
            className: 'pi-marker-icon',
            html: `<div style="display:flex; flex-direction:column; align-items:center;">
                     <div style="width:8px; height:8px; background:#000; border-radius:50%;"></div>
                     <div style="font-size:10px; color:white; text-align:center; white-space:nowrap; margin-top:2px; background:rgba(0,0,0,0.6); padding:1px 4px; border-radius:2px;">
                       ${d.id}<br>${valueText} ${settings.unit}
                     </div>
                   </div>`,
            iconSize: [80, 40],
            iconAnchor: [40, 4]
        });

        L.marker(mmToLatLng(d.x, d.y), { icon: piIcon, interactive: false }).addTo(piMarkerGroup);
    });
}

/**
 * 人物マーカーを更新（丸型プロフィール画像 + 名前 + 詳細ポップアップ）
 * @param {Array} beaconData - 位置データ配列
 * @param {Object} profileMap - beacon_id -> profile オブジェクトのマップ
 */
export function updatePersonMarkers(beaconData, profileMap = {}) {
    if (!personMarkerGroup) return;
    personMarkerGroup.clearLayers();

    beaconData.forEach(b => {
        const name = b.name || b.id.substring(0, 4);
        const color = deptColors[b.dept] || '#6c757d';
        const profile = profileMap[b.id] || {};
        const imgUrl = profile.profile_image || b.profile_image || null;

        // イニシャル (画像がない場合のフォールバック)
        const initial = name.charAt(0).toUpperCase();

        // ステータスランプの色
        const stColor = statusColors[b.status] || '#6c757d';
        const statusLamp = `<div style="position:absolute; bottom:0; right:0; width:12px; height:12px; border-radius:50%; background:${stColor}; border:2px solid #1a1a2e; box-shadow:0 0 4px ${stColor};"></div>`;

        // アバター部分の HTML (ステータスランプ付き)
        let avatarHtml;
        if (imgUrl) {
            avatarHtml = `<div style="position:relative; width:36px; height:36px;"><img src="${imgUrl}" style="width:36px; height:36px; border-radius:50%; border:2px solid ${color}; object-fit:cover;">${statusLamp}</div>`;
        } else {
            avatarHtml = `<div style="position:relative; width:36px; height:36px;"><div style="width:36px; height:36px; border-radius:50%; border:2px solid ${color}; background:${color}; color:#fff; display:flex; align-items:center; justify-content:center; font-size:16px; font-weight:bold;">${initial}</div>${statusLamp}</div>`;
        }

        const customIcon = L.divIcon({
            className: 'person-marker',
            html: `<div style="display:flex; flex-direction:column; align-items:center;">
                     ${avatarHtml}
                     <div style="font-size:10px; white-space:nowrap; background:rgba(0,0,0,0.75); padding:1px 6px; border-radius:3px; color:white; margin-top:2px; max-width:80px; overflow:hidden; text-overflow:ellipsis;">
                       ${name}
                     </div>
                   </div>`,
            iconSize: [90, 56],
            iconAnchor: [45, 20]
        });

        // ポップアップ内容を構築
        const stLabel = statusLabels[b.status] || b.status || '不明';
        const jobLabel = jobLabels[b.job] || b.job || '未設定';
        const deptLabel = deptLabels[b.dept] || b.dept || 'その他';

        let popupAvatarHtml;
        if (imgUrl) {
            popupAvatarHtml = `<img src="${imgUrl}" style="width:60px; height:60px; border-radius:50%; border:3px solid ${color}; object-fit:cover;">`;
        } else {
            popupAvatarHtml = `<div style="width:60px; height:60px; border-radius:50%; border:3px solid ${color}; background:${color}; color:#fff; display:flex; align-items:center; justify-content:center; font-size:28px; font-weight:bold;">${initial}</div>`;
        }

        let detailRows = '';
        if (profile.skills) {
            detailRows += `<div class="profile-popup-row"><span class="profile-popup-label">スキル</span><span>${profile.skills}</span></div>`;
        }
        if (profile.hobbies) {
            detailRows += `<div class="profile-popup-row"><span class="profile-popup-label">趣味</span><span>${profile.hobbies}</span></div>`;
        }
        if (profile.projects) {
            detailRows += `<div class="profile-popup-row"><span class="profile-popup-label">PJ経験</span><span>${profile.projects}</span></div>`;
        }
        if (profile.email) {
            detailRows += `<div class="profile-popup-row"><span class="profile-popup-label">メール</span><a href="mailto:${profile.email}" style="color:#00bcd4;">${profile.email}</a></div>`;
        }
        if (profile.phone) {
            detailRows += `<div class="profile-popup-row"><span class="profile-popup-label">電話</span><a href="tel:${profile.phone}" style="color:#00bcd4;">${profile.phone}</a></div>`;
        }

        const popupContent = `
            <div class="profile-popup">
                <div class="profile-popup-header">
                    ${popupAvatarHtml}
                    <div class="profile-popup-name">${name}</div>
                    <div class="profile-popup-meta">${deptLabel} / ${jobLabel}</div>
                    <div class="profile-popup-status" style="color:${color};">${stLabel}</div>
                </div>
                ${detailRows ? `<div class="profile-popup-details">${detailRows}</div>` : ''}
            </div>
        `;

        const marker = L.marker(mmToLatLng(b.x, b.y), { icon: customIcon, interactive: true });
        marker.bindPopup(popupContent, { className: 'profile-popup-container', maxWidth: 250 });
        marker.addTo(personMarkerGroup);
    });
}

// --- レコメンド用ミニマップ ---

export function initRecommendationMap(containerId) {
    recMap = L.map(containerId, {
        crs: L.CRS.Simple,
        minZoom: -5,
        maxZoom: 1,
        zoomControl: false,
        dragging: false,
        scrollWheelZoom: false,
        doubleClickZoom: false,
        touchZoom: false,
        attributionControl: false
    });

    if (FLOORPLAN_IMAGE.url && imageBounds) {
        recImageOverlay = L.imageOverlay(FLOORPLAN_IMAGE.url, imageBounds, {
            opacity: 0.4
        }).addTo(recMap);
        recMap.fitBounds(imageBounds);
    } else {
        const bounds = imageBounds || calculateImageBounds();
        recMap.fitBounds(bounds);
    }

    recZoneGroup = L.layerGroup().addTo(recMap);
    drawZoneBoundaries();

    // おすすめマップもフロアマップのアスペクト比に合わせて高さ調整
    adjustWrapperHeight('recommendation-map-wrapper', recMap, 0.15, 0.5);
}

function drawZoneBoundaries() {
    if (!recZoneGroup) return;

    for (const [zoneName, bounds] of Object.entries(ZONE_BOUNDARIES)) {
        // ZONE_BOUNDARIESのYは旧座標系(正)だが、物理座標系ではYは負
        // y値を負に変換して物理座標に合わせる
        const y1 = -bounds.y_min;
        const y2 = -bounds.y_max;
        const yMinPhys = Math.min(y1, y2);
        const yMaxPhys = Math.max(y1, y2);

        L.rectangle(
            [mmToLatLng(bounds.x_min, yMinPhys), mmToLatLng(bounds.x_max, yMaxPhys)],
            {
                color: 'rgba(255,255,255,0.3)',
                weight: 1,
                fillColor: 'rgba(255,255,255,0.15)',
                fillOpacity: 0.15
            }
        ).addTo(recZoneGroup);

        const centerX = (bounds.x_min + bounds.x_max) / 2;
        const centerY = (yMinPhys + yMaxPhys) / 2;
        L.marker(mmToLatLng(centerX, centerY), {
            icon: L.divIcon({
                className: 'zone-label',
                html: `<div style="color:white; font-size:12px; text-align:center; text-shadow: 0 0 4px rgba(0,0,0,0.8);">${zoneName}</div>`,
                iconSize: [80, 20],
                iconAnchor: [40, 10]
            }),
            interactive: false
        }).addTo(recZoneGroup);
    }
}

export function updateRecommendationMap(zoneBoundaries, bestZone, bestBoundaries) {
    if (!recMap || !recZoneGroup) return;

    recZoneGroup.clearLayers();
    drawZoneBoundaries();

    if (bestZone && bestBoundaries) {
        const b = bestBoundaries;
        // Y値を反転して物理座標系に合わせる
        const y1 = -b.y_min;
        const y2 = -b.y_max;
        const yMinPhys = Math.min(y1, y2);
        const yMaxPhys = Math.max(y1, y2);
        L.rectangle(
            [mmToLatLng(b.x_min, yMinPhys), mmToLatLng(b.x_max, yMaxPhys)],
            {
                color: 'red',
                weight: 3,
                fillColor: 'rgba(255,0,0,0.2)',
                fillOpacity: 0.2
            }
        ).addTo(recZoneGroup);
    }
}

export function getMap() {
    return map;
}

export function getImageBounds() {
    return imageBounds;
}

export { mmToLatLng, pxToMm, calculateImageBounds };
