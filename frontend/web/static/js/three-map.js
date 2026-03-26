// three-map.js -- Three.jsによる3Dフロアマップモジュール
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { FLOORPLAN_IMAGE, CALIBRATION, FLOOR_BOUNDARY } from './config.js';

// --- 定数 ---
const SCALE = 0.001;          // mm → m
const WALL_HEIGHT = 2800;     // 壁の高さ (mm)
const WALL_THICKNESS = 120;   // 壁の厚み (mm)
const HEATMAP_GRID = 150;     // ヒートマップ解像度

// 部署色
const deptColors3D = {
    'dev_team': 0x007bff,
    'sales_team': 0xdc3545,
    'hr_team': 0x28a745,
    'other': 0x6c757d
};

// ステータス色
const statusColors3D = {
    'available': 0x28a745,
    'busy': 0xdc3545,
    'meeting': 0xfd7e14,
    'break': 0x17a2b8
};

// カラーマップ (2Dと同一)
const sensorColormaps = {
    'temp': [
        [0.0, 8, 29, 168], [0.15, 37, 116, 219], [0.30, 18, 178, 217],
        [0.45, 70, 199, 102], [0.60, 235, 219, 50], [0.75, 240, 149, 30],
        [0.90, 220, 50, 30], [1.0, 150, 10, 20],
    ],
    'humidity': [
        [0.0, 255, 255, 224], [0.25, 160, 230, 200], [0.50, 80, 180, 230],
        [0.75, 30, 120, 220], [1.0, 10, 40, 170],
    ],
    'lux': [
        [0.0, 15, 5, 30], [0.25, 80, 30, 120], [0.50, 180, 100, 30],
        [0.75, 240, 200, 50], [1.0, 255, 255, 160],
    ],
    'co2': [
        [0.0, 30, 160, 70], [0.30, 160, 210, 80], [0.55, 240, 200, 50],
        [0.75, 230, 120, 40], [1.0, 200, 30, 30],
    ]
};

// --- モジュールレベルの状態 ---
let scene, camera, renderer, controls;
let floorMesh, heatmapMesh;
let wallGroup, sensorGroup, personGroup, labelGroup;
let container;
let animationId;
let isInitialized = false;

// --- 座標変換 ---

function pxToMm(px_x, px_y) {
    const cal = CALIBRATION;
    return {
        x: (px_x - cal.origin_px.x) * cal.scale_mm_per_px,
        y: -(px_y - cal.origin_px.y) * cal.scale_mm_per_px
    };
}

// 物理座標(mm) → Three.js座標 (X=X, Y=高さ, Z=-physY)
function toWorld(x_mm, y_mm, h_mm = 0) {
    return new THREE.Vector3(x_mm * SCALE, h_mm * SCALE, -y_mm * SCALE);
}

// --- カラーマップ補間 ---

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

// --- IDW補間 ---

function idwInterpolate(gx, gy, sensorData, sensorType, power) {
    let numerator = 0, denominator = 0;
    for (const d of sensorData) {
        const val = d[sensorType];
        if (val === null || val === undefined || isNaN(val)) continue;
        const dx = d.x - gx, dy = d.y - gy;
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist < 1) return val;
        const weight = 1 / Math.pow(dist, power);
        numerator += weight * val;
        denominator += weight;
    }
    return denominator > 0 ? numerator / denominator : 0;
}

// ポリゴン内判定 (ray casting)
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

// --- 初期化 ---

export function init3DMap(containerId) {
    container = document.getElementById(containerId);
    if (!container) return;

    // シーン
    scene = new THREE.Scene();
    scene.background = new THREE.Color(0x1a1a2e);
    scene.fog = new THREE.FogExp2(0x1a1a2e, 0.08);

    // カメラ
    const aspect = container.clientWidth / container.clientHeight;
    camera = new THREE.PerspectiveCamera(50, aspect, 0.01, 100);

    // レンダラー
    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setSize(container.clientWidth, container.clientHeight);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.2;
    container.appendChild(renderer.domElement);

    // コントロール
    controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.dampingFactor = 0.08;
    controls.maxPolarAngle = Math.PI / 2.1;
    controls.minDistance = 1;
    controls.maxDistance = 25;

    // ライティング
    const ambient = new THREE.AmbientLight(0xffffff, 0.6);
    scene.add(ambient);

    const dirLight = new THREE.DirectionalLight(0xffffff, 0.8);
    dirLight.position.set(5, 10, 5);
    dirLight.castShadow = true;
    dirLight.shadow.mapSize.set(2048, 2048);
    dirLight.shadow.camera.left = -15;
    dirLight.shadow.camera.right = 15;
    dirLight.shadow.camera.top = 15;
    dirLight.shadow.camera.bottom = -15;
    scene.add(dirLight);

    const fillLight = new THREE.DirectionalLight(0x4488ff, 0.3);
    fillLight.position.set(-5, 5, -5);
    scene.add(fillLight);

    // グループ
    wallGroup = new THREE.Group();
    sensorGroup = new THREE.Group();
    personGroup = new THREE.Group();
    labelGroup = new THREE.Group();
    scene.add(wallGroup);
    scene.add(sensorGroup);
    scene.add(personGroup);
    scene.add(labelGroup);

    // フロア画像
    createFloorPlane();

    // 壁
    createWalls();

    // カメラ位置の初期設定
    positionCamera();

    // リサイズ対応
    window.addEventListener('resize', onResize);

    // アニメーション開始
    animate();
    isInitialized = true;
}

// --- フロア平面 (図面画像テクスチャ) ---

function createFloorPlane() {
    const img = FLOORPLAN_IMAGE;
    const cal = CALIBRATION;
    if (!img.url || !img.width || !img.height) return;

    const topLeft = pxToMm(0, 0);
    const bottomRight = pxToMm(img.width, img.height);

    const xMin = Math.min(topLeft.x, bottomRight.x);
    const xMax = Math.max(topLeft.x, bottomRight.x);
    const yMin = Math.min(topLeft.y, bottomRight.y);
    const yMax = Math.max(topLeft.y, bottomRight.y);

    const w = (xMax - xMin) * SCALE;
    const h = (yMax - yMin) * SCALE;

    const geometry = new THREE.PlaneGeometry(w, h);
    const texture = new THREE.TextureLoader().load(img.url);
    texture.colorSpace = THREE.SRGBColorSpace;

    const material = new THREE.MeshStandardMaterial({
        map: texture,
        side: THREE.DoubleSide,
        roughness: 0.8,
        metalness: 0.0
    });

    floorMesh = new THREE.Mesh(geometry, material);
    floorMesh.rotation.x = -Math.PI / 2;
    // 中心位置
    const cx = (xMin + xMax) / 2 * SCALE;
    const cz = -(yMin + yMax) / 2 * SCALE;
    floorMesh.position.set(cx, 0, cz);
    floorMesh.receiveShadow = true;
    scene.add(floorMesh);
}

// --- 壁 ---

function createWalls() {
    if (!FLOOR_BOUNDARY || FLOOR_BOUNDARY.length < 3) return;

    const boundary = FLOOR_BOUNDARY;
    const h = WALL_HEIGHT * SCALE;
    const thick = WALL_THICKNESS * SCALE;

    const wallMaterial = new THREE.MeshStandardMaterial({
        color: 0x3a3a5e,
        roughness: 0.6,
        metalness: 0.1,
        side: THREE.DoubleSide
    });

    // 壁上部のアクセントライン
    const edgeMaterial = new THREE.MeshStandardMaterial({
        color: 0x00bcd4,
        emissive: 0x00bcd4,
        emissiveIntensity: 0.5,
        roughness: 0.3
    });

    for (let i = 0; i < boundary.length; i++) {
        const p1 = boundary[i];
        const p2 = boundary[(i + 1) % boundary.length];

        const dx = (p2.x - p1.x) * SCALE;
        const dz = -(p2.y - p1.y) * SCALE;
        const length = Math.sqrt(dx * dx + dz * dz);
        if (length < 0.001) continue;

        // 壁パネル
        const wallGeom = new THREE.BoxGeometry(length, h, thick);
        const wall = new THREE.Mesh(wallGeom, wallMaterial);

        const mx = (p1.x + p2.x) / 2 * SCALE;
        const mz = -(p1.y + p2.y) / 2 * SCALE;
        wall.position.set(mx, h / 2, mz);
        wall.rotation.y = Math.atan2(dz, dx);
        wall.castShadow = true;
        wall.receiveShadow = true;
        wallGroup.add(wall);

        // 壁上部のアクセントライン
        const edgeGeom = new THREE.BoxGeometry(length, 0.03, thick + 0.01);
        const edge = new THREE.Mesh(edgeGeom, edgeMaterial);
        edge.position.set(mx, h + 0.015, mz);
        edge.rotation.y = Math.atan2(dz, dx);
        wallGroup.add(edge);
    }
}

// --- カメラ初期位置 ---

function positionCamera() {
    if (!FLOOR_BOUNDARY || FLOOR_BOUNDARY.length < 3) {
        camera.position.set(4, 8, 10);
        controls.target.set(4, 0, 4);
    } else {
        const xs = FLOOR_BOUNDARY.map(p => p.x);
        const ys = FLOOR_BOUNDARY.map(p => p.y);
        const cx = (Math.min(...xs) + Math.max(...xs)) / 2 * SCALE;
        const cz = -(Math.min(...ys) + Math.max(...ys)) / 2 * SCALE;
        const rangeX = (Math.max(...xs) - Math.min(...xs)) * SCALE;
        const rangeZ = (Math.max(...ys) - Math.min(...ys)) * SCALE;
        const dist = Math.max(rangeX, rangeZ) * 0.9;

        camera.position.set(cx + dist * 0.5, dist * 0.7, cz + dist * 0.8);
        controls.target.set(cx, 0, cz);
    }
    controls.update();
}

// --- ヒートマップ更新 ---

export function update3DHeatmap(sensorData, sensorType) {
    if (!isInitialized) return;

    const validData = sensorData.filter(d =>
        typeof d[sensorType] === 'number' && !isNaN(d[sensorType]) &&
        typeof d.x === 'number' && typeof d.y === 'number'
    );
    if (validData.length < 2) return;

    // 描画範囲
    let xMin, xMax, yMin, yMax;
    let boundaryPolygon = null;

    if (FLOOR_BOUNDARY && FLOOR_BOUNDARY.length >= 3) {
        boundaryPolygon = FLOOR_BOUNDARY;
        const bxs = boundaryPolygon.map(p => p.x);
        const bys = boundaryPolygon.map(p => p.y);
        xMin = Math.min(...bxs) - 100;
        xMax = Math.max(...bxs) + 100;
        yMin = Math.min(...bys) - 100;
        yMax = Math.max(...bys) + 100;
    } else {
        const cal = CALIBRATION;
        const img = FLOORPLAN_IMAGE;
        const topLeft = pxToMm(0, 0);
        const bottomRight = pxToMm(img.width, img.height);
        xMin = Math.min(topLeft.x, bottomRight.x);
        xMax = Math.max(topLeft.x, bottomRight.x);
        yMin = Math.min(topLeft.y, bottomRight.y);
        yMax = Math.max(topLeft.y, bottomRight.y);
    }

    // Canvas描画
    const canvas = document.createElement('canvas');
    canvas.width = HEATMAP_GRID;
    canvas.height = HEATMAP_GRID;
    const ctx = canvas.getContext('2d');
    const imgData = ctx.createImageData(HEATMAP_GRID, HEATMAP_GRID);
    const data = imgData.data;

    const colormap = sensorColormaps[sensorType] || sensorColormaps['temp'];
    const values = validData.map(d => d[sensorType]).filter(v => typeof v === 'number');
    const minVal = Math.min(...values);
    const maxVal = Math.max(...values);
    const range = maxVal - minVal || 1;
    const margin = range * 0.05;
    const normMin = minVal - margin;
    const normRange = range + margin * 2;

    const xStep = (xMax - xMin) / HEATMAP_GRID;
    const yStep = (yMax - yMin) / HEATMAP_GRID;

    for (let row = 0; row < HEATMAP_GRID; row++) {
        for (let col = 0; col < HEATMAP_GRID; col++) {
            const gx = xMin + col * xStep;
            const gy = yMin + row * yStep;
            if (boundaryPolygon && !pointInPolygon(gx, gy, boundaryPolygon)) continue;

            const interpolated = idwInterpolate(gx, gy, validData, sensorType, 2);
            const normalized = Math.max(0, Math.min(1, (interpolated - normMin) / normRange));
            const [r, g, b] = interpolateColormap(colormap, normalized);
            const idx = (row * HEATMAP_GRID + col) * 4;
            data[idx] = r;
            data[idx + 1] = g;
            data[idx + 2] = b;
            data[idx + 3] = 180;
        }
    }
    ctx.putImageData(imgData, 0, 0);

    // ヒートマップメッシュの更新
    const texture = new THREE.CanvasTexture(canvas);
    texture.needsUpdate = true;

    const w = (xMax - xMin) * SCALE;
    const h = (yMax - yMin) * SCALE;

    if (heatmapMesh) {
        heatmapMesh.material.map.dispose();
        heatmapMesh.material.map = texture;
        heatmapMesh.material.needsUpdate = true;
    } else {
        const geom = new THREE.PlaneGeometry(w, h);
        const mat = new THREE.MeshBasicMaterial({
            map: texture,
            transparent: true,
            opacity: 0.75,
            side: THREE.DoubleSide,
            depthWrite: false
        });
        heatmapMesh = new THREE.Mesh(geom, mat);
        heatmapMesh.rotation.x = -Math.PI / 2;
        const cx = (xMin + xMax) / 2 * SCALE;
        const cz = -(yMin + yMax) / 2 * SCALE;
        heatmapMesh.position.set(cx, 0.005, cz);
        scene.add(heatmapMesh);
    }

    return { minVal, maxVal };
}

// --- センサーマーカー更新 ---

export function update3DSensorMarkers(sensorData, sensorType, settings) {
    if (!isInitialized) return;

    // 既存マーカーを削除
    sensorGroup.clear();
    labelGroup.children = labelGroup.children.filter(c => {
        if (c.userData.isSensorLabel) {
            scene.remove(c);
            return false;
        }
        return true;
    });

    const colormap = sensorColormaps[sensorType] || sensorColormaps['temp'];
    const values = sensorData.map(d => d[sensorType]).filter(v => typeof v === 'number');
    const minVal = Math.min(...values);
    const maxVal = Math.max(...values);
    const range = maxVal - minVal || 1;

    sensorData.forEach(d => {
        const val = d[sensorType];
        if (val === null || val === undefined) return;

        const normalized = Math.max(0, Math.min(1, (val - minVal) / range));
        const [r, g, b] = interpolateColormap(colormap, normalized);
        const color = new THREE.Color(r / 255, g / 255, b / 255);

        // ポール
        const poleGeom = new THREE.CylinderGeometry(0.03, 0.03, 0.8, 8);
        const poleMat = new THREE.MeshStandardMaterial({ color: 0x444466, roughness: 0.5 });
        const pole = new THREE.Mesh(poleGeom, poleMat);
        const pos = toWorld(d.x, d.y, 400);
        pole.position.copy(pos);
        pole.castShadow = true;
        sensorGroup.add(pole);

        // センサー球
        const sphereGeom = new THREE.SphereGeometry(0.12, 16, 16);
        const sphereMat = new THREE.MeshStandardMaterial({
            color: color,
            emissive: color,
            emissiveIntensity: 0.4,
            roughness: 0.3,
            metalness: 0.2
        });
        const sphere = new THREE.Mesh(sphereGeom, sphereMat);
        sphere.position.copy(toWorld(d.x, d.y, 850));
        sphere.castShadow = true;
        sensorGroup.add(sphere);

        // ラベル (スプライト)
        const label = createTextSprite(
            `${d.id}\n${val.toFixed(1)}${settings.unit}`,
            { fontSize: 48, color: '#ffffff', bgColor: 'rgba(0,0,0,0.7)' }
        );
        label.position.copy(toWorld(d.x, d.y, 1150));
        label.scale.set(0.6, 0.3, 1);
        label.userData.isSensorLabel = true;
        labelGroup.add(label);
    });
}

// --- 人物マーカー更新 ---

export function update3DPersonMarkers(beaconData) {
    if (!isInitialized) return;

    personGroup.clear();
    labelGroup.children = labelGroup.children.filter(c => {
        if (c.userData.isPersonLabel) {
            scene.remove(c);
            return false;
        }
        return true;
    });

    beaconData.forEach(b => {
        const name = b.name || b.id?.substring(0, 4) || '?';
        const deptColor = deptColors3D[b.dept] || 0x6c757d;
        const stColor = statusColors3D[b.status] || 0x6c757d;

        // 人型: 胴体 (カプセル状のシリンダー)
        const bodyGeom = new THREE.CylinderGeometry(0.12, 0.10, 0.5, 12);
        const bodyMat = new THREE.MeshStandardMaterial({
            color: deptColor,
            roughness: 0.4,
            metalness: 0.1
        });
        const body = new THREE.Mesh(bodyGeom, bodyMat);
        body.position.copy(toWorld(b.x, b.y, 250));
        body.castShadow = true;
        personGroup.add(body);

        // 頭
        const headGeom = new THREE.SphereGeometry(0.10, 16, 16);
        const headMat = new THREE.MeshStandardMaterial({
            color: 0xf5d0a9,
            roughness: 0.6
        });
        const head = new THREE.Mesh(headGeom, headMat);
        head.position.copy(toWorld(b.x, b.y, 580));
        head.castShadow = true;
        personGroup.add(head);

        // ステータスリング (頭上)
        const ringGeom = new THREE.TorusGeometry(0.14, 0.025, 8, 24);
        const ringMat = new THREE.MeshStandardMaterial({
            color: stColor,
            emissive: stColor,
            emissiveIntensity: 0.6,
            roughness: 0.3
        });
        const ring = new THREE.Mesh(ringGeom, ringMat);
        ring.position.copy(toWorld(b.x, b.y, 720));
        ring.rotation.x = -Math.PI / 2;
        personGroup.add(ring);

        // 名前ラベル
        const label = createTextSprite(name, {
            fontSize: 44,
            color: '#ffffff',
            bgColor: `rgba(${(deptColor >> 16) & 0xff},${(deptColor >> 8) & 0xff},${deptColor & 0xff},0.85)`
        });
        label.position.copy(toWorld(b.x, b.y, 950));
        label.scale.set(0.5, 0.2, 1);
        label.userData.isPersonLabel = true;
        labelGroup.add(label);
    });
}

// --- テキストスプライト生成 ---

function createTextSprite(text, { fontSize = 48, color = '#fff', bgColor = 'rgba(0,0,0,0.7)' } = {}) {
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    canvas.width = 512;
    canvas.height = 256;

    // 背景
    ctx.fillStyle = bgColor;
    const radius = 20;
    roundRect(ctx, 10, 10, canvas.width - 20, canvas.height - 20, radius);
    ctx.fill();

    // テキスト
    ctx.fillStyle = color;
    ctx.font = `bold ${fontSize}px sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

    const lines = text.split('\n');
    const lineHeight = fontSize * 1.3;
    const startY = canvas.height / 2 - (lines.length - 1) * lineHeight / 2;
    lines.forEach((line, i) => {
        ctx.fillText(line, canvas.width / 2, startY + i * lineHeight);
    });

    const texture = new THREE.CanvasTexture(canvas);
    const material = new THREE.SpriteMaterial({
        map: texture,
        transparent: true,
        depthWrite: false
    });
    return new THREE.Sprite(material);
}

function roundRect(ctx, x, y, w, h, r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.lineTo(x + w - r, y);
    ctx.quadraticCurveTo(x + w, y, x + w, y + r);
    ctx.lineTo(x + w, y + h - r);
    ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
    ctx.lineTo(x + r, y + h);
    ctx.quadraticCurveTo(x, y + h, x, y + h - r);
    ctx.lineTo(x, y + r);
    ctx.quadraticCurveTo(x, y, x + r, y);
    ctx.closePath();
}

// --- アニメーションループ ---

function animate() {
    animationId = requestAnimationFrame(animate);
    controls.update();
    renderer.render(scene, camera);
}

// --- リサイズ ---

function onResize() {
    if (!container || !renderer) return;
    const w = container.clientWidth;
    const h = container.clientHeight;
    if (w === 0 || h === 0) return;
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    renderer.setSize(w, h);
}

// --- 破棄 ---

export function dispose3DMap() {
    if (animationId) {
        cancelAnimationFrame(animationId);
        animationId = null;
    }
    window.removeEventListener('resize', onResize);

    if (renderer) {
        renderer.dispose();
        if (renderer.domElement && renderer.domElement.parentNode) {
            renderer.domElement.parentNode.removeChild(renderer.domElement);
        }
    }
    if (controls) controls.dispose();

    scene = null;
    camera = null;
    renderer = null;
    controls = null;
    floorMesh = null;
    heatmapMesh = null;
    wallGroup = null;
    sensorGroup = null;
    personGroup = null;
    labelGroup = null;
    isInitialized = false;
}

export function is3DInitialized() {
    return isInitialized;
}
