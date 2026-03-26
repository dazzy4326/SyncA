// settings-modal.js -- 設定モーダルのロジック (旧admin.js機能を統合)
import { FLOORPLAN_IMAGE, CALIBRATION, FLOOR_BOUNDARY, loadAppConfig } from './config.js';

// --- 状態変数 ---
let settingsMap = null;
let settingsImageOverlay = null;
let settingsImageBounds = null;
let state = 'idle';
let originPx = { x: 0, y: 0 };
let scaleMmPerPx = 1.0;
let scalePoint1 = null;

// 設定データ
let newBeaconPositions = {};
let newMinorIdMap = {};
let boundaryPoints = [];       // フロア外枠のピクセル座標
let boundaryPolygonLayer = null; // 外枠ポリゴンのLeafletレイヤー

// オブジェクト管理
let floorObjects = [];            // サーバーから取得した全オブジェクト
let selectedObjType = 'wall';     // 選択中のオブジェクトタイプ
let objDrawMode = false;          // 配置モードON/OFF
let objFirstPoint = null;         // 2点配置の1点目 (物理座標mm)
const singlePointTypes = new Set(['plant', 'monitor']);
const PLANT_RADIUS = 250;
const MONITOR_SIZE = 300;

// マーカー管理
let settingsMarkers = L.layerGroup ? L.layerGroup() : null;
let currentLineLayer = null;
let originMarker = null;

// 現在アクティブなタブ用のマップコンテナID
let activeMapContainer = null;

// --- 認証状態 ---
let isAuthenticated = false;

/**
 * 設定モーダルを初期化
 */
export function initSettingsModal() {
    const modal = document.getElementById('settings-modal');
    const openBtn = document.getElementById('settings-btn');
    const closeBtn = document.getElementById('modal-close-btn');
    const passwordDialog = document.getElementById('password-dialog');
    const passwordInput = document.getElementById('settings-password');
    const passwordError = document.getElementById('password-error');
    const passwordSubmitBtn = document.getElementById('password-submit-btn');
    const passwordCancelBtn = document.getElementById('password-cancel-btn');

    if (!openBtn || !modal) return;

    // 既存のキャリブレーションデータを読み込む
    if (CALIBRATION.origin_px) {
        originPx = { ...CALIBRATION.origin_px };
    }
    if (CALIBRATION.scale_mm_per_px) {
        scaleMmPerPx = CALIBRATION.scale_mm_per_px;
    }

    // 歯車ボタン → パスワードダイアログまたは直接モーダル
    openBtn.addEventListener('click', () => {
        if (isAuthenticated) {
            openSettingsModal();
        } else {
            passwordDialog.style.display = 'flex';
            passwordInput.value = '';
            passwordError.textContent = '';
            setTimeout(() => passwordInput.focus(), 100);
        }
    });

    // パスワード認証
    passwordSubmitBtn.addEventListener('click', () => verifyPassword());
    passwordInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') verifyPassword();
    });

    async function verifyPassword() {
        const password = passwordInput.value;
        if (!password) {
            passwordError.textContent = 'パスワードを入力してください';
            return;
        }

        try {
            const response = await fetch('/api/verify_admin_password', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ password })
            });

            if (response.ok) {
                isAuthenticated = true;
                passwordDialog.style.display = 'none';
                openSettingsModal();
            } else {
                const result = await response.json();
                passwordError.textContent = result.message || '認証に失敗しました';
                passwordInput.value = '';
                passwordInput.focus();
            }
        } catch (error) {
            passwordError.textContent = '通信エラーが発生しました';
        }
    }

    // パスワードダイアログのキャンセル
    passwordCancelBtn.addEventListener('click', () => {
        passwordDialog.style.display = 'none';
    });

    passwordDialog.addEventListener('click', (e) => {
        if (e.target === passwordDialog) {
            passwordDialog.style.display = 'none';
        }
    });

    function openSettingsModal() {
        modal.style.display = 'flex';
        updateCalibrationDisplay();
        setTimeout(() => {
            initOrRefreshSettingsMap('calibration-map-container');
        }, 150);
    }

    closeBtn.addEventListener('click', () => {
        modal.style.display = 'none';
        state = 'idle';
        clearActiveButtons();
    });

    modal.addEventListener('click', (e) => {
        if (e.target === modal) {
            modal.style.display = 'none';
            state = 'idle';
            clearActiveButtons();
        }
    });

    // タブ切り替え
    document.querySelectorAll('.settings-tab').forEach(tab => {
        tab.addEventListener('click', function () {
            document.querySelector('.settings-tab.active').classList.remove('active');
            this.classList.add('active');
            document.querySelectorAll('.settings-panel').forEach(p => p.classList.remove('active'));
            const panelId = `panel-${this.dataset.tab}`;
            document.getElementById(panelId).classList.add('active');

            state = 'idle';
            clearActiveButtons();

            // タブに応じたマップコンテナを初期化
            const containerMap = {
                'calibration': 'calibration-map-container',
                'beacons': 'beacon-map-container',
                'boundary': 'boundary-map-container',
                'objects': 'objects-map-container'
            };
            const containerId = containerMap[this.dataset.tab];
            if (containerId) {
                setTimeout(() => initOrRefreshSettingsMap(containerId), 100);
            }

            // ユーザー管理タブが選択されたらユーザー一覧を読み込む
            if (this.dataset.tab === 'users') {
                loadUserList();
            }

            // オブジェクトタブが選択されたらオブジェクト一覧を読み込む
            if (this.dataset.tab === 'objects') {
                loadFloorObjects();
            }

            // 設定情報タブが選択されたら設定情報を表示
            if (this.dataset.tab === 'configinfo') {
                loadConfigInfo();
            }
        });
    });

    // ハンドラー設定
    setupUploadHandler();
    setupCalibrationHandlers();
    setupBeaconHandlers();
    setupBoundaryHandlers();
    setupUserHandlers();
    setupObjectHandlers();
    setupConfigInfoHandlers();
    setupSaveHandler();

    // フロアプラン画像名を表示
    if (FLOORPLAN_IMAGE.url) {
        const nameEl = document.getElementById('current-floorplan-name');
        if (nameEl) nameEl.textContent = FLOORPLAN_IMAGE.url.split('/').pop();
    }
}

/**
 * 設定用Leafletマップを初期化/リフレッシュ
 */
function initOrRefreshSettingsMap(containerId) {
    const container = document.getElementById(containerId);
    if (!container) return;

    // マップが既に別のコンテナにある場合、移動
    if (settingsMap) {
        if (activeMapContainer === containerId) {
            settingsMap.invalidateSize();
            return;
        }
        // 既存のマップを破棄
        settingsMap.remove();
        settingsMap = null;
        settingsMarkers = null;
    }

    activeMapContainer = containerId;

    settingsMap = L.map(container, {
        crs: L.CRS.Simple,
        minZoom: -5,
        maxZoom: 5,
        attributionControl: false
    });

    settingsMarkers = L.layerGroup().addTo(settingsMap);

    if (FLOORPLAN_IMAGE.url && FLOORPLAN_IMAGE.width && FLOORPLAN_IMAGE.height) {
        // 画像をピクセル座標系で表示 (キャリブレーション用)
        const bounds = [[0, 0], [FLOORPLAN_IMAGE.height, FLOORPLAN_IMAGE.width]];
        settingsImageBounds = L.latLngBounds(bounds);
        settingsImageOverlay = L.imageOverlay(FLOORPLAN_IMAGE.url, settingsImageBounds).addTo(settingsMap);
        settingsMap.fitBounds(settingsImageBounds);
    } else if (FLOORPLAN_IMAGE.url) {
        // widthが不明な場合、画像を読み込んでサイズを取得
        const img = new Image();
        img.onload = function () {
            const bounds = [[0, 0], [img.naturalHeight, img.naturalWidth]];
            settingsImageBounds = L.latLngBounds(bounds);
            settingsImageOverlay = L.imageOverlay(FLOORPLAN_IMAGE.url, settingsImageBounds).addTo(settingsMap);
            settingsMap.fitBounds(settingsImageBounds);
            // config更新
            FLOORPLAN_IMAGE.width = img.naturalWidth;
            FLOORPLAN_IMAGE.height = img.naturalHeight;
        };
        img.src = FLOORPLAN_IMAGE.url;
    } else {
        // 画像なし
        settingsMap.setView([250, 250], 0);
    }

    // マップクリックイベント
    settingsMap.on('click', onSettingsMapClick);

    // 既存のマーカーを再描画
    redrawSettingsMarkers();
}

/**
 * 設定マップのクリックハンドラー
 */
function onSettingsMapClick(e) {
    // Leaflet CRS.Simple座標: lat=y(ピクセル), lng=x(ピクセル)
    const px_x = e.latlng.lng;
    const px_y = e.latlng.lat;

    const toPhysicalCoords = (pxX, pxY) => {
        const physicalX = (pxX - originPx.x) * scaleMmPerPx;
        const physicalY = -((pxY - originPx.y) * scaleMmPerPx);
        return { x: Math.floor(physicalX), y: Math.floor(physicalY) };
    };

    switch (state) {
        case 'set_origin':
            originPx = { x: px_x, y: px_y };
            updateCalibrationDisplay();
            // 原点マーカーを描画
            if (originMarker) settingsMarkers.removeLayer(originMarker);
            originMarker = L.circleMarker([px_y, px_x], {
                radius: 8, color: '#00ff00', fillColor: '#00ff00', fillOpacity: 0.8
            }).addTo(settingsMarkers);
            originMarker.bindTooltip('原点(0,0)', { permanent: true, direction: 'top', offset: [0, -10] });
            alert(`原点を (${px_x.toFixed(0)}px, ${px_y.toFixed(0)}px) に設定しました。`);
            state = 'idle';
            clearActiveButtons();
            break;

        case 'set_scale_1':
            scalePoint1 = { x: px_x, y: px_y };
            L.circleMarker([px_y, px_x], {
                radius: 5, color: '#ffff00', fillColor: '#ffff00', fillOpacity: 0.8
            }).addTo(settingsMarkers);
            alert('縮尺の1点目を設定しました。2点目をクリックしてください。');
            state = 'set_scale_2';
            break;

        case 'set_scale_2': {
            const p1 = scalePoint1;
            const p2 = { x: px_x, y: px_y };
            const distPx = Math.sqrt(Math.pow(p2.x - p1.x, 2) + Math.pow(p2.y - p1.y, 2));

            L.circleMarker([px_y, px_x], {
                radius: 5, color: '#ffff00', fillColor: '#ffff00', fillOpacity: 0.8
            }).addTo(settingsMarkers);

            // 2点間に線を描画
            L.polyline([[p1.y, p1.x], [px_y, px_x]], { color: '#ffff00', weight: 2, dashArray: '5,5' }).addTo(settingsMarkers);

            const distMm = prompt(`2点間のピクセル距離は ${distPx.toFixed(1)}px です。\n実際の距離 (mm) を入力してください:`, "10000");

            if (distMm && distPx > 0) {
                scaleMmPerPx = parseFloat(distMm) / distPx;
                updateCalibrationDisplay();
                alert(`縮尺を設定しました: ${scaleMmPerPx.toFixed(2)} mm/px`);
            }
            state = 'idle';
            clearActiveButtons();
            break;
        }

        case 'add_beacon': {
            const rasPiId = prompt("この場所の「ラズパイID」(例: ras_01) を入力:");
            if (!rasPiId) { state = 'idle'; clearActiveButtons(); return; }
            const minorId = prompt(`「${rasPiId}」に対応する「Minor ID」(例: 1) を入力:`);
            if (!minorId) { state = 'idle'; clearActiveButtons(); return; }

            const physicalPos = toPhysicalCoords(px_x, px_y);
            newBeaconPositions[rasPiId] = [physicalPos.x, physicalPos.y];
            newMinorIdMap[minorId] = rasPiId;

            alert(`ビーコン追加: ${rasPiId} (Minor ${minorId}) @ (${physicalPos.x}mm, ${physicalPos.y}mm)`);
            updateConfigOutput();
            redrawSettingsMarkers();
            state = 'idle';
            clearActiveButtons();
            break;
        }

        case 'draw_object_1': {
            const phys = toPhysicalCoords(px_x, px_y);
            if (singlePointTypes.has(selectedObjType)) {
                // 1点配置タイプ（植物・モニター）
                let obj;
                if (selectedObjType === 'plant') {
                    obj = { type: 'plant', x1: phys.x - PLANT_RADIUS, y1: phys.y - PLANT_RADIUS, x2: phys.x + PLANT_RADIUS, y2: phys.y + PLANT_RADIUS };
                } else {
                    obj = { type: 'monitor', x1: phys.x - MONITOR_SIZE / 2, y1: phys.y, x2: phys.x + MONITOR_SIZE / 2, y2: phys.y };
                }
                floorObjects.push(obj);
                renderFloorObjectsList();
                redrawObjectMarkers();
                updateObjectDrawStatus(`${typeLabel(selectedObjType)} を追加しました (${phys.x}, ${phys.y})`);
            } else {
                // 2点配置の1点目
                objFirstPoint = phys;
                L.circleMarker([px_y, px_x], { radius: 5, color: '#ff6600', fillColor: '#ff6600', fillOpacity: 0.9 }).addTo(settingsMarkers);
                updateObjectDrawStatus('終点をクリックしてください');
                state = 'draw_object_2';
            }
            break;
        }

        case 'draw_object_2': {
            const phys2 = toPhysicalCoords(px_x, px_y);
            const obj2 = {
                type: selectedObjType,
                x1: objFirstPoint.x, y1: objFirstPoint.y,
                x2: phys2.x, y2: phys2.y
            };
            floorObjects.push(obj2);
            objFirstPoint = null;
            state = 'draw_object_1'; // 続けて配置可能
            renderFloorObjectsList();
            redrawObjectMarkers();
            updateObjectDrawStatus(`${typeLabel(selectedObjType)} を追加しました。次の始点をクリック`);
            break;
        }

        case 'add_boundary_point': {
            boundaryPoints.push({ px_x, px_y });

            // 頂点マーカー
            L.circleMarker([px_y, px_x], {
                radius: 4, color: '#ff6600', fillColor: '#ff6600', fillOpacity: 0.9
            }).addTo(settingsMarkers);

            // 前の点と線を描画
            if (boundaryPoints.length > 1) {
                const prev = boundaryPoints[boundaryPoints.length - 2];
                L.polyline([[prev.px_y, prev.px_x], [px_y, px_x]], {
                    color: '#ff6600', weight: 2
                }).addTo(settingsMarkers);
            }

            const countEl = document.getElementById('boundary-point-count');
            if (countEl) countEl.textContent = boundaryPoints.length;
            break;
        }
    }
}

/**
 * 設定マーカーを再描画
 */
function redrawSettingsMarkers() {
    if (!settingsMarkers || !settingsMap) return;

    // ビーコンマーカー
    for (const [id, coords] of Object.entries(newBeaconPositions)) {
        const pxX = coords[0] / scaleMmPerPx + originPx.x;
        const pxY = -(coords[1] / scaleMmPerPx) + originPx.y;

        const marker = L.circleMarker([pxY, pxX], {
            radius: 6, color: '#dc3545', fillColor: '#dc3545', fillOpacity: 0.8
        }).addTo(settingsMarkers);
        marker.bindTooltip(id, { permanent: true, direction: 'top', offset: [0, -8], className: 'beacon-tooltip' });
    }

    // フロア外枠ポリゴン
    if (boundaryPoints.length >= 3) {
        const latlngs = boundaryPoints.map(p => [p.px_y, p.px_x]);
        boundaryPolygonLayer = L.polygon(latlngs, {
            color: '#ff6600',
            weight: 2,
            fillColor: 'rgba(255,102,0,0.15)',
            fillOpacity: 0.15
        }).addTo(settingsMarkers);
    }
}

/**
 * キャリブレーション表示を更新
 */
function updateCalibrationDisplay() {
    const originDisplay = document.getElementById('origin-display');
    const scaleDisplay = document.getElementById('scale-display');
    if (originDisplay) originDisplay.textContent = `(${originPx.x.toFixed(0)}, ${originPx.y.toFixed(0)}) px`;
    if (scaleDisplay) scaleDisplay.textContent = scaleMmPerPx.toFixed(2);
}

/**
 * アクティブボタンスタイルをクリア
 */
function clearActiveButtons() {
    document.querySelectorAll('.btn-secondary.active-mode').forEach(btn => {
        btn.classList.remove('active-mode');
    });
}

/**
 * ボタンをアクティブにする
 */
function setActiveButton(btn) {
    clearActiveButtons();
    btn.classList.add('active-mode');
}

// --- ハンドラー設定 ---

function setupUploadHandler() {
    const uploadBtn = document.getElementById('btn-upload-floorplan');
    if (!uploadBtn) return;

    uploadBtn.addEventListener('click', async () => {
        const fileInput = document.getElementById('floorplan-upload');
        const file = fileInput.files[0];
        if (!file) {
            alert('ファイルを選択してください');
            return;
        }

        const formData = new FormData();
        formData.append('floorplan', file);

        const statusEl = document.getElementById('upload-status');
        statusEl.textContent = 'アップロード中...';

        try {
            const response = await fetch('/api/upload_floorplan', {
                method: 'POST',
                body: formData
            });
            const result = await response.json();

            if (result.status === 'success') {
                statusEl.textContent = 'アップロード成功';
                statusEl.style.color = '#28a745';
                document.getElementById('current-floorplan-name').textContent = result.filename;

                // configをリロード
                await loadAppConfig();

                // 設定マップをリフレッシュ
                if (settingsMap) {
                    settingsMap.remove();
                    settingsMap = null;
                    settingsMarkers = null;
                    activeMapContainer = null;
                }
                setTimeout(() => initOrRefreshSettingsMap('calibration-map-container'), 100);
            } else {
                statusEl.textContent = 'エラー: ' + result.message;
                statusEl.style.color = '#f43f5e';
            }
        } catch (error) {
            statusEl.textContent = 'エラー: ' + error.message;
            statusEl.style.color = '#f43f5e';
        }
    });
}

function setupCalibrationHandlers() {
    const btnOrigin = document.getElementById('btn-set-origin');
    const btnScale = document.getElementById('btn-set-scale');
    const btnSaveCalibration = document.getElementById('btn-save-calibration');

    if (btnOrigin) {
        btnOrigin.addEventListener('click', function () {
            state = 'set_origin';
            setActiveButton(this);
        });
    }

    if (btnScale) {
        btnScale.addEventListener('click', function () {
            state = 'set_scale_1';
            setActiveButton(this);
        });
    }

    if (btnSaveCalibration) {
        btnSaveCalibration.addEventListener('click', async () => {
            const calibrationData = {
                origin_px: originPx,
                scale_mm_per_px: scaleMmPerPx
            };

            try {
                const response = await fetch('/api/update_calibration', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(calibrationData)
                });
                const result = await response.json();
                if (result.status === 'success') {
                    alert('キャリブレーションデータを保存しました。');
                    await loadAppConfig();
                } else {
                    alert('エラー: ' + result.message);
                }
            } catch (error) {
                alert('保存に失敗: ' + error.message);
            }
        });
    }
}

function setupBeaconHandlers() {
    const btnBeacon = document.getElementById('btn-add-beacon');
    if (btnBeacon) {
        btnBeacon.addEventListener('click', function () {
            state = 'add_beacon';
            setActiveButton(this);
            alert('マップをクリックしてビーコンを配置します。');
        });
    }
}

function setupBoundaryHandlers() {
    const btnStart = document.getElementById('btn-start-boundary');
    const btnFinish = document.getElementById('btn-finish-boundary');
    const btnClear = document.getElementById('btn-clear-boundary');
    const btnSave = document.getElementById('btn-save-boundary');

    // 既存のFLOOR_BOUNDARYがあれば読み込む
    if (FLOOR_BOUNDARY && FLOOR_BOUNDARY.length >= 3) {
        // 物理座標→ピクセル座標に戻してboundaryPointsにセット
        boundaryPoints = FLOOR_BOUNDARY.map(p => {
            const px_x = p.x / scaleMmPerPx + originPx.x;
            const px_y = -(p.y / scaleMmPerPx) + originPx.y;
            return { px_x, px_y };
        });
        const countEl = document.getElementById('boundary-point-count');
        if (countEl) countEl.textContent = boundaryPoints.length;
    }

    if (btnStart) {
        btnStart.addEventListener('click', function () {
            boundaryPoints = [];
            if (boundaryPolygonLayer && settingsMarkers) {
                settingsMarkers.removeLayer(boundaryPolygonLayer);
                boundaryPolygonLayer = null;
            }
            state = 'add_boundary_point';
            setActiveButton(this);
            const countEl = document.getElementById('boundary-point-count');
            if (countEl) countEl.textContent = '0';
            alert('図面の外枠をクリックして囲んでください。\n頂点を順にクリックし、最後に「外枠を確定」を押します。');
        });
    }

    if (btnFinish) {
        btnFinish.addEventListener('click', () => {
            if (boundaryPoints.length < 3) {
                alert('3点以上クリックしてください。');
                return;
            }
            // ポリゴンを閉じて描画
            const latlngs = boundaryPoints.map(p => [p.px_y, p.px_x]);
            if (boundaryPolygonLayer && settingsMarkers) {
                settingsMarkers.removeLayer(boundaryPolygonLayer);
            }
            boundaryPolygonLayer = L.polygon(latlngs, {
                color: '#ff6600',
                weight: 2,
                fillColor: 'rgba(255,102,0,0.15)',
                fillOpacity: 0.15
            }).addTo(settingsMarkers);

            alert(`外枠を ${boundaryPoints.length} 頂点で確定しました。\n「外枠を保存」でサーバーに保存してください。`);
            state = 'idle';
            clearActiveButtons();
        });
    }

    if (btnClear) {
        btnClear.addEventListener('click', () => {
            boundaryPoints = [];
            if (boundaryPolygonLayer && settingsMarkers) {
                settingsMarkers.removeLayer(boundaryPolygonLayer);
                boundaryPolygonLayer = null;
            }
            // settingsMarkersから外枠関連のマーカーも再描画でクリアされる
            if (settingsMarkers) settingsMarkers.clearLayers();
            redrawSettingsMarkers();
            const countEl = document.getElementById('boundary-point-count');
            if (countEl) countEl.textContent = '0';
            state = 'idle';
            clearActiveButtons();
        });
    }

    if (btnSave) {
        btnSave.addEventListener('click', async () => {
            if (boundaryPoints.length < 3) {
                alert('外枠が設定されていません。3点以上で描画してください。');
                return;
            }
            // ピクセル座標→物理座標(mm)に変換
            const physicalBoundary = boundaryPoints.map(p => ({
                x: Math.round((p.px_x - originPx.x) * scaleMmPerPx),
                y: Math.round(-((p.px_y - originPx.y) * scaleMmPerPx))
            }));

            try {
                const response = await fetch('/api/update_floor_boundary', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ FLOOR_BOUNDARY: physicalBoundary })
                });
                const result = await response.json();
                if (result.status === 'success') {
                    alert('フロア外枠を保存しました。');
                    await loadAppConfig();
                } else {
                    alert('エラー: ' + result.message);
                }
            } catch (error) {
                alert('保存に失敗: ' + error.message);
            }
        });
    }
}

function setupSaveHandler() {
    const btnSave = document.getElementById('btn-save-config');
    if (!btnSave) return;

    btnSave.addEventListener('click', async () => {
        const configData = {
            "BEACON_POSITIONS": newBeaconPositions,
            "MINOR_ID_TO_PI_NAME_MAP": newMinorIdMap
        };

        if (Object.keys(newBeaconPositions).length === 0) {
            if (!confirm("ビーコンが追加されていません。保存しますか？")) {
                return;
            }
        }

        if (!confirm("この設定をサーバーの config.json に保存しますか？\n（サーバーの再起動が必要です）")) {
            return;
        }

        try {
            const response = await fetch('/api/update_beacon_config', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(configData)
            });

            if (!response.ok) {
                const err = await response.json();
                throw new Error(err.message || `HTTP ${response.status}`);
            }

            const result = await response.json();
            alert(`成功: ${result.message}`);

        } catch (error) {
            console.error("設定の保存に失敗:", error);
            alert(`エラー: 設定の保存に失敗しました。\n${error.message}`);
        }
    });
}

/**
 * 設定JSONプレビューを更新
 */
function updateConfigOutput() {
    const configOutput = document.getElementById('config-output');
    if (!configOutput) return;

    const configData = {
        "BEACON_POSITIONS": newBeaconPositions,
        "MINOR_ID_TO_PI_NAME_MAP": newMinorIdMap,
        "CALIBRATION": {
            "origin_px": originPx,
            "scale_mm_per_px": scaleMmPerPx
        }
    };
    configOutput.textContent = JSON.stringify(configData, null, 2);
}


// ==========================================================
//  ユーザー管理
// ==========================================================

let currentEditBeaconId = null;

async function loadUserList() {
    const listEl = document.getElementById('user-list');
    const formEl = document.getElementById('user-edit-form');
    if (!listEl) return;

    formEl.style.display = 'none';

    try {
        const res = await fetch('/api/user_profiles');
        if (!res.ok) throw new Error('Failed to load profiles');
        const profiles = await res.json();

        if (profiles.length === 0) {
            listEl.innerHTML = '<p style="color:#9ca3af; font-size:0.9em;">登録済みユーザーがいません。iOSアプリから位置データを送信すると自動で一覧に表示されます。</p>';
            return;
        }

        listEl.innerHTML = profiles.map(p => {
            const name = p.user_name || p.beacon_id.substring(0, 8);
            const initial = name.charAt(0).toUpperCase();
            const avatarHtml = p.profile_image
                ? `<img class="user-list-item-avatar" src="${p.profile_image}" alt="${name}">`
                : `<div class="user-list-item-avatar-placeholder">${initial}</div>`;

            return `<div class="user-list-item" data-beacon-id="${p.beacon_id}">
                ${avatarHtml}
                <div class="user-list-item-info">
                    <div class="user-list-item-name">${name}</div>
                    <div class="user-list-item-sub">${p.department || ''} / ${p.job_title || ''}</div>
                </div>
            </div>`;
        }).join('');

        // クリックで編集フォームを表示
        listEl.querySelectorAll('.user-list-item').forEach(item => {
            item.addEventListener('click', () => {
                const bid = item.dataset.beaconId;
                const profile = profiles.find(p => p.beacon_id === bid);
                if (profile) openUserEditForm(profile);
            });
        });

    } catch (e) {
        console.error('ユーザー一覧の取得に失敗:', e);
        listEl.innerHTML = '<p style="color:#f43f5e;">ユーザー一覧の読み込みに失敗しました。</p>';
    }
}

function openUserEditForm(profile) {
    const formEl = document.getElementById('user-edit-form');
    formEl.style.display = 'block';

    currentEditBeaconId = profile.beacon_id;
    document.getElementById('user-edit-title').textContent = `プロフィール編集: ${profile.user_name || profile.beacon_id.substring(0, 8)}`;
    document.getElementById('user-beacon-id').value = profile.beacon_id;
    document.getElementById('user-name-input').value = profile.user_name || '';
    document.getElementById('user-job-input').value = profile.job_title || '';
    document.getElementById('user-dept-input').value = profile.department || '';
    document.getElementById('user-skills-input').value = profile.skills || '';
    document.getElementById('user-hobbies-input').value = profile.hobbies || '';
    document.getElementById('user-projects-input').value = profile.projects || '';
    document.getElementById('user-email-input').value = profile.email || '';
    document.getElementById('user-phone-input').value = profile.phone || '';

    const previewEl = document.getElementById('user-avatar-preview');
    if (profile.profile_image) {
        previewEl.innerHTML = `<img src="${profile.profile_image}">`;
    } else {
        const initial = (profile.user_name || '?').charAt(0).toUpperCase();
        previewEl.innerHTML = `<span style="color:#e0e0e0; font-size:20px; font-weight:bold;">${initial}</span>`;
    }

    document.getElementById('user-save-status').textContent = '';
}

function setupUserHandlers() {
    const cancelBtn = document.getElementById('btn-cancel-user-edit');
    const saveBtn = document.getElementById('btn-save-user-profile');
    const chooseAvatarBtn = document.getElementById('btn-choose-avatar');
    const avatarInput = document.getElementById('user-avatar-input');

    if (!cancelBtn) return;

    cancelBtn.addEventListener('click', () => {
        document.getElementById('user-edit-form').style.display = 'none';
        currentEditBeaconId = null;
    });

    chooseAvatarBtn.addEventListener('click', () => {
        avatarInput.click();
    });

    avatarInput.addEventListener('change', async () => {
        const file = avatarInput.files[0];
        if (!file || !currentEditBeaconId) return;

        const formData = new FormData();
        formData.append('beacon_id', currentEditBeaconId);
        formData.append('image', file);

        try {
            const res = await fetch('/api/upload_profile_image', {
                method: 'POST',
                body: formData
            });
            const data = await res.json();
            if (res.ok && data.image_url) {
                const previewEl = document.getElementById('user-avatar-preview');
                previewEl.innerHTML = `<img src="${data.image_url}?t=${Date.now()}">`;
                document.getElementById('user-save-status').textContent = '画像をアップロードしました';
            }
        } catch (e) {
            console.error('画像アップロードエラー:', e);
        }

        avatarInput.value = '';
    });

    saveBtn.addEventListener('click', async () => {
        if (!currentEditBeaconId) return;

        const payload = {
            beacon_id: currentEditBeaconId,
            user_name: document.getElementById('user-name-input').value,
            job_title: document.getElementById('user-job-input').value,
            department: document.getElementById('user-dept-input').value,
            skills: document.getElementById('user-skills-input').value,
            hobbies: document.getElementById('user-hobbies-input').value,
            projects: document.getElementById('user-projects-input').value,
            email: document.getElementById('user-email-input').value,
            phone: document.getElementById('user-phone-input').value,
        };

        try {
            const res = await fetch('/api/update_user_profile', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });

            if (res.ok) {
                document.getElementById('user-save-status').textContent = '保存しました';
                document.getElementById('user-save-status').style.color = '#28a745';
                // 一覧を再読み込み
                loadUserList();
            } else {
                const data = await res.json();
                document.getElementById('user-save-status').textContent = data.message || '保存に失敗しました';
                document.getElementById('user-save-status').style.color = '#f43f5e';
            }
        } catch (e) {
            document.getElementById('user-save-status').textContent = '通信エラー';
            document.getElementById('user-save-status').style.color = '#f43f5e';
        }
    });
}


// ==========================================================
//  フロアオブジェクト管理
// ==========================================================

/** オブジェクトタイプの日本語ラベル */
function typeLabel(t) {
    const map = { wall: '壁', desk: '机', pillar: '柱', shelf: '棚', plant: '植物', chair: '椅子', monitor: 'モニター', window: '窓' };
    return map[t] || t;
}

/** オブジェクト描画ステータス更新 */
function updateObjectDrawStatus(msg) {
    const el = document.getElementById('object-draw-status');
    if (el) el.textContent = msg;
}

/** サーバーからオブジェクト一覧を読み込む */
async function loadFloorObjects() {
    try {
        const res = await fetch('/api/app_config');
        if (!res.ok) throw new Error('Failed');
        const config = await res.json();
        floorObjects = config.FLOOR_OBJECTS || [];
        renderFloorObjectsList();
        redrawObjectMarkers();
    } catch (e) {
        console.error('フロアオブジェクト取得エラー:', e);
        const el = document.getElementById('floor-objects-list');
        if (el) el.innerHTML = '<p style="color:#f43f5e;">読み込みに失敗しました</p>';
    }
}

/** オブジェクト一覧をHTMLに描画 */
function renderFloorObjectsList() {
    const listEl = document.getElementById('floor-objects-list');
    if (!listEl) return;

    if (floorObjects.length === 0) {
        listEl.innerHTML = '<p style="color:#9ca3af; font-size:0.9em;">オブジェクトがありません</p>';
        return;
    }

    listEl.innerHTML = floorObjects.map((obj, i) => {
        const badge = typeLabel(obj.type);
        const coords = `(${obj.x1}, ${obj.y1}) → (${obj.x2}, ${obj.y2})`;
        const extra = [];
        if (obj.height) extra.push(`H:${obj.height}`);
        if (obj.label) extra.push(obj.label);
        if (obj.color) extra.push(obj.color);
        if (obj.count && obj.count > 1) extra.push(`×${obj.count}`);
        const extraStr = extra.length ? ` [${extra.join(', ')}]` : '';

        return `<div class="floor-obj-item" data-index="${i}">
            <div class="floor-obj-item-info">
                <span class="floor-obj-type-badge">${badge}</span>
                <span class="floor-obj-coords">${coords}${extraStr}</span>
            </div>
            <button class="floor-obj-delete" data-index="${i}">削除</button>
        </div>`;
    }).join('');

    // 削除ボタン
    listEl.querySelectorAll('.floor-obj-delete').forEach(btn => {
        btn.addEventListener('click', (e) => {
            const idx = parseInt(e.target.dataset.index);
            floorObjects.splice(idx, 1);
            renderFloorObjectsList();
            redrawObjectMarkers();
        });
    });
}

/** マップ上にオブジェクトマーカーを描画 */
function redrawObjectMarkers() {
    if (!settingsMarkers || !settingsMap) return;
    // 既存のオブジェクトマーカーをクリアして再描画
    // (settingsMarkersは共有なので、全クリア→全再描画)
    settingsMarkers.clearLayers();
    redrawSettingsMarkers(); // 他のタブのマーカーも再描画

    // オブジェクトを描画
    floorObjects.forEach((obj, i) => {
        const px1x = obj.x1 / scaleMmPerPx + originPx.x;
        const px1y = -(obj.y1 / scaleMmPerPx) + originPx.y;
        const px2x = obj.x2 / scaleMmPerPx + originPx.x;
        const px2y = -(obj.y2 / scaleMmPerPx) + originPx.y;

        const colorMap = {
            wall: '#888888', desk: '#8B4513', pillar: '#666666', shelf: '#A0522D',
            plant: '#28a745', chair: '#00bcd4', monitor: '#9c27b0', window: '#03a9f4'
        };
        const color = obj.color || colorMap[obj.type] || '#ff6600';

        if (obj.type === 'plant') {
            const cx = (px1x + px2x) / 2;
            const cy = (px1y + px2y) / 2;
            L.circleMarker([cy, cx], { radius: 6, color, fillColor: color, fillOpacity: 0.5 }).addTo(settingsMarkers)
                .bindTooltip(`🌿 ${obj.label || '植物'}`, { direction: 'top', offset: [0, -8] });
        } else {
            L.polyline([[px1y, px1x], [px2y, px2x]], { color, weight: 3, opacity: 0.8 }).addTo(settingsMarkers)
                .bindTooltip(`${typeLabel(obj.type)} ${obj.label || ''}`.trim(), { direction: 'top' });
        }
    });
}

function setupObjectHandlers() {
    // タイプ選択ボタン
    document.querySelectorAll('.obj-type-btn').forEach(btn => {
        btn.addEventListener('click', function() {
            document.querySelector('.obj-type-btn.active')?.classList.remove('active');
            this.classList.add('active');
            selectedObjType = this.dataset.objtype;
            // 配置モード中なら1点目をリセット
            objFirstPoint = null;
            if (objDrawMode) {
                state = 'draw_object_1';
                updateObjectDrawStatus(`${typeLabel(selectedObjType)} の始点をクリック`);
            }
        });
    });

    // 配置モード開始/終了
    const drawBtn = document.getElementById('btn-draw-object');
    if (drawBtn) {
        drawBtn.addEventListener('click', function() {
            objDrawMode = !objDrawMode;
            objFirstPoint = null;
            if (objDrawMode) {
                state = 'draw_object_1';
                this.textContent = '配置モード終了';
                this.classList.add('active-mode');
                updateObjectDrawStatus(`${typeLabel(selectedObjType)} の${singlePointTypes.has(selectedObjType) ? '位置' : '始点'}をクリック`);
            } else {
                state = 'idle';
                this.textContent = '配置モード開始';
                this.classList.remove('active-mode');
                updateObjectDrawStatus('');
            }
        });
    }

    // 手動追加
    const addManualBtn = document.getElementById('btn-add-object-manual');
    if (addManualBtn) {
        addManualBtn.addEventListener('click', () => {
            const obj = {
                type: document.getElementById('obj-type-select').value,
                x1: parseFloat(document.getElementById('obj-x1').value) || 0,
                y1: parseFloat(document.getElementById('obj-y1').value) || 0,
                x2: parseFloat(document.getElementById('obj-x2').value) || 0,
                y2: parseFloat(document.getElementById('obj-y2').value) || 0,
            };
            const h = document.getElementById('obj-height').value;
            if (h) obj.height = parseFloat(h);
            const hs = document.getElementById('obj-height-start').value;
            if (hs) obj.height_start = parseFloat(hs);
            const lbl = document.getElementById('obj-label').value.trim();
            if (lbl) obj.label = lbl;
            const clr = document.getElementById('obj-color').value.trim();
            if (clr) obj.color = clr;
            const cnt = document.getElementById('obj-count').value;
            if (cnt && parseInt(cnt) > 1) obj.count = parseInt(cnt);
            const rot = document.getElementById('obj-rotation').value;
            if (rot && parseFloat(rot) !== 0) obj.rotation = parseFloat(rot);

            floorObjects.push(obj);
            renderFloorObjectsList();
            redrawObjectMarkers();
        });
    }

    // 保存
    const saveBtn = document.getElementById('btn-save-floor-objects');
    if (saveBtn) {
        saveBtn.addEventListener('click', async () => {
            const statusEl = document.getElementById('objects-save-status');
            statusEl.textContent = '保存中...';
            statusEl.style.color = '#ffc107';

            try {
                const res = await fetch('/api/update_floor_objects', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ FLOOR_OBJECTS: floorObjects })
                });
                const data = await res.json();
                if (res.ok && data.status === 'success') {
                    statusEl.textContent = '保存しました';
                    statusEl.style.color = '#28a745';
                    await loadAppConfig();
                } else {
                    statusEl.textContent = data.message || '保存に失敗しました';
                    statusEl.style.color = '#f43f5e';
                }
            } catch (e) {
                statusEl.textContent = '通信エラー: ' + e.message;
                statusEl.style.color = '#f43f5e';
            }
        });
    }
}


// ==========================================================
//  設定情報表示
// ==========================================================

async function loadConfigInfo() {
    const contentEl = document.getElementById('config-info-content');
    if (!contentEl) return;

    contentEl.innerHTML = '<p style="color:#9ca3af;">読み込み中...</p>';

    try {
        const res = await fetch('/api/app_config');
        if (!res.ok) throw new Error('Failed');
        const config = await res.json();

        let html = '';

        // Pi配置
        const piLocs = config.PI_LOCATIONS || [];
        if (piLocs.length > 0) {
            html += `<div class="config-info-card"><h4>Pi配置 (${piLocs.length}台)</h4>`;
            piLocs.forEach(pi => {
                html += `<div class="config-info-row"><span class="label">${pi.id}</span><span class="value">x=${Math.round(pi.x)}, y=${Math.round(pi.y)}</span></div>`;
            });
            html += '</div>';
        }

        // サーバー設定データサマリー
        html += '<div class="config-info-card"><h4>サーバー設定データ</h4>';

        const beaconPos = config.BEACON_POSITIONS || {};
        html += configInfoRow('BEACON_POSITIONS', `${Object.keys(beaconPos).length}件`);

        const minorMap = config.MINOR_ID_TO_PI_NAME_MAP || {};
        html += configInfoRow('MINOR_ID_MAP', `${Object.keys(minorMap).length}件`);

        const boundary = config.FLOOR_BOUNDARY || [];
        html += configInfoRow('FLOOR_BOUNDARY', `${boundary.length}点`);

        const objs = config.FLOOR_OBJECTS || [];
        if (objs.length > 0) {
            const grouped = {};
            objs.forEach(o => { grouped[o.type] = (grouped[o.type] || 0) + 1; });
            const summary = Object.entries(grouped).sort((a, b) => a[0].localeCompare(b[0])).map(([k, v]) => `${typeLabel(k)}:${v}`).join(' ');
            html += configInfoRow('FLOOR_OBJECTS', `${objs.length}件 (${summary})`);
        } else {
            html += configInfoRow('FLOOR_OBJECTS', '0件');
        }

        const zones = config.ZONE_BOUNDARIES || {};
        const zoneNames = Object.keys(zones).sort().join(', ');
        html += configInfoRow('ZONE_BOUNDARIES', `${Object.keys(zones).length}ゾーン${zoneNames ? ' (' + zoneNames + ')' : ''}`);


        const cal = config.CALIBRATION || {};
        html += configInfoRow('CALIBRATION', cal.scale_mm_per_px ? `設定済み (${cal.scale_mm_per_px.toFixed(2)} mm/px)` : '未設定');

        const fp = config.FLOORPLAN_IMAGE || {};
        html += configInfoRow('FLOORPLAN', fp.url ? fp.url.split('/').pop() : '未設定');

        const dashboard = config.DASHBOARD_SETTINGS || {};
        if (dashboard.update_interval_ms) {
            html += configInfoRow('更新間隔', `${dashboard.update_interval_ms}ms`);
        }

        const alerts = config.ALERT_THRESHOLDS || {};
        if (alerts.temp_low !== undefined) {
            html += configInfoRow('アラート閾値', `温度:${alerts.temp_low}-${alerts.temp_high}°C, 湿度:${alerts.humidity_low}-${alerts.humidity_high}%, CO2:${alerts.co2_high}ppm`);
        }

        html += '</div>';

        // ビーコン配置詳細
        if (Object.keys(beaconPos).length > 0) {
            html += '<div class="config-info-card"><h4>ビーコン配置</h4>';
            for (const [id, coords] of Object.entries(beaconPos)) {
                html += `<div class="config-info-row"><span class="label">${id}</span><span class="value">[${coords.join(', ')}]</span></div>`;
            }
            html += '</div>';
        }

        // Minor IDマッピング
        if (Object.keys(minorMap).length > 0) {
            html += '<div class="config-info-card"><h4>Minor ID → Pi名 マッピング</h4>';
            for (const [minor, piName] of Object.entries(minorMap)) {
                html += `<div class="config-info-row"><span class="label">Minor ${minor}</span><span class="value">${piName}</span></div>`;
            }
            html += '</div>';
        }

        contentEl.innerHTML = html;

    } catch (e) {
        console.error('設定情報の取得エラー:', e);
        contentEl.innerHTML = '<p style="color:#f43f5e;">設定情報の読み込みに失敗しました</p>';
    }
}

function configInfoRow(label, value) {
    return `<div class="config-info-row"><span class="label">${label}</span><span class="value">${value}</span></div>`;
}

function setupConfigInfoHandlers() {
    const reloadBtn = document.getElementById('btn-reload-config');
    if (reloadBtn) {
        reloadBtn.addEventListener('click', async () => {
            await loadAppConfig();
            await loadConfigInfo();
        });
    }
}
