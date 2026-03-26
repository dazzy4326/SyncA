// --- モジュールのインポート ---
import { sensorSettings, PI_LOCATIONS, MAP_SETTINGS, ZONE_BOUNDARIES, ALERT_THRESHOLDS, DASHBOARD_SETTINGS, loadAppConfig } from './config.js';
import { initCharts } from './charts.js';
import { initMap, updateHeatmap, updatePersonMarkers, updatePiMarkers, initRecommendationMap, updateRecommendationMap } from './leaflet-map.js';
import { init3DMap, update3DHeatmap, update3DSensorMarkers, update3DPersonMarkers, dispose3DMap, is3DInitialized } from './three-map.js';
import { initSettingsModal } from './settings-modal.js';

// --- グローバルな変数 ---
let currentSensor = 'temp';      // ヒートマップ + ゲージ用
let currentLineSensor = 'temp';   // 折れ線グラフ用
let currentBarSensor = 'temp';    // 棒グラフ用
let lineChart, barChart, gaugeChart;
let is3DMode = false;             // 2D/3D表示切り替え

// センサータイプごとの色定義 (棒/ゲージグラフ用)
const colorMap = {
    'temp': '#dc3545',
    'humidity': '#17a2b8',
    'lux': '#ffc107',
    'co2': '#28a745'
};

// 最新のセンサーデータを保持
let latestSensorData = null;

// プロフィールデータのキャッシュ (beacon_id -> profile)
let profileMap = {};

document.addEventListener('DOMContentLoaded', function () {

    // --- 初期化処理 ---

    // Chart.jsグラフの初期化
    const charts = initCharts();
    lineChart = charts.lineChart;
    barChart = charts.barChart;
    gaugeChart = charts.gaugeChart;

    // --- 時計の更新 ---
    const clockElement = document.getElementById('clock');
    function updateClock() {
        const now = new Date();
        clockElement.textContent = now.toLocaleString('ja-JP');
    }
    setInterval(updateClock, 1000);
    updateClock();

    // 好み入力UIの要素を取得
    const prefTemp = document.getElementById('pref-temp');
    const prefOccupancy = document.getElementById('pref-occupancy');
    const prefLight = document.getElementById('pref-light');
    const prefHumidity = document.getElementById('pref-humidity');
    const prefCo2 = document.getElementById('pref-co2');
    const recommendationMessageEl = document.getElementById('recommendation-message');
    const staticRecommendationMessageEl = document.getElementById('static-recommendation-message');

    // ★ おすすめ更新関数
    async function updateRecommendations() {
        const temp = prefTemp.value;
        const occupancy = prefOccupancy.value;
        const light = prefLight.value;
        const humidity = prefHumidity.value;
        const co2 = prefCo2.value;

        try {
            const response = await fetch(`/api/recommendations?temp=${temp}&occupancy=${occupancy}&light=${light}&humidity=${humidity}&co2=${co2}`);
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);

            const data = await response.json();

            if (data.custom_message) {
                recommendationMessageEl.innerHTML = data.custom_message;
            }
            if (data.static_message) {
                staticRecommendationMessageEl.innerHTML = data.static_message;
            }

            console.log("ゾーン分析データ:", data.debug_analytics);

            // Leafletミニマップを更新
            updateRecommendationMap(ZONE_BOUNDARIES, data.best_zone, data.boundaries);

        } catch (error) {
            console.error("おすすめ情報の取得に失敗:", error);
            recommendationMessageEl.textContent = "情報の取得に失敗しました。";
        }
    }

    // --- 折れ線グラフを更新 ---
    function updateLineChart(sensorData) {
        const settings = sensorSettings[currentLineSensor];
        const now = new Date();
        const timeLabel = `${now.getHours()}:${String(now.getMinutes()).padStart(2, '0')}:${String(now.getSeconds()).padStart(2, '0')}`;

        lineChart.data.labels.push(timeLabel);
        if (lineChart.data.labels.length > DASHBOARD_SETTINGS.max_line_chart_points) { lineChart.data.labels.shift(); }

        sensorData.forEach((d, index) => {
            if (lineChart.data.datasets[index]) {
                lineChart.data.datasets[index].data.push(d[currentLineSensor]);
                if (lineChart.data.datasets[index].data.length > DASHBOARD_SETTINGS.max_line_chart_points) {
                    lineChart.data.datasets[index].data.shift();
                }
            }
        });

        lineChart.options.plugins.title = { display: true, text: `時系列トレンド (${settings.label})`, color: '#e0e0e0' };
        lineChart.update();
    }

    // --- 棒グラフを更新 ---
    function updateBarChart(sensorData) {
        const settings = sensorSettings[currentBarSensor];
        const mainColor = colorMap[currentBarSensor] || '#00bcd4';

        barChart.data.datasets[0].label = `${settings.label} (${settings.unit})`;
        barChart.data.datasets[0].data = sensorData.map(d => d[currentBarSensor]);
        barChart.data.datasets[0].backgroundColor = mainColor;
        barChart.data.datasets[0].borderColor = mainColor;
        barChart.update();
    }

    // --- ゲージグラフを更新 ---
    function updateGaugeChart(sensorData) {
        const settings = sensorSettings[currentSensor];
        const mainColor = colorMap[currentSensor] || '#00bcd4';

        const avgValue = sensorData.reduce((sum, d) => sum + (d[currentSensor] || 0), 0) / sensorData.length;
        const gaugeMax = settings.gaugeMax;

        gaugeChart.data.datasets[0].data[0] = avgValue;
        gaugeChart.data.datasets[0].data[1] = Math.max(0, gaugeMax - avgValue);
        gaugeChart.data.datasets[0].backgroundColor[0] = mainColor;

        gaugeChart.update();
        document.getElementById('gauge-label').textContent = `${avgValue.toFixed(1)} ${settings.unit}`;
    }

    // --- アラート更新 ---
    function updateAlerts(sensorData) {
        const avg_temp = sensorData.reduce((sum, d) => sum + (d.temp || 0), 0) / sensorData.length;
        const avg_humidity = sensorData.reduce((sum, d) => sum + (d.humidity || 0), 0) / sensorData.length;
        const avg_lux = sensorData.reduce((sum, d) => sum + (d.lux || 0), 0) / sensorData.length;
        const avg_co2 = sensorData.reduce((sum, d) => sum + (d.co2 || 0), 0) / sensorData.length;

        const alerts = [];

        if (avg_temp <= ALERT_THRESHOLDS.temp_low) {
            alerts.push("部屋を温めてください！");
        } else if (avg_temp >= ALERT_THRESHOLDS.temp_high) {
            alerts.push("部屋を冷やしてください！");
        }

        if (avg_humidity <= ALERT_THRESHOLDS.humidity_low) {
            alerts.push("加湿してください！");
        } else if (avg_humidity >= ALERT_THRESHOLDS.humidity_high) {
            alerts.push("除湿してください！");
        }

        if (avg_lux <= ALERT_THRESHOLDS.lux_low) {
            alerts.push("照明を強めてください！");
        } else if (avg_lux >= ALERT_THRESHOLDS.lux_high) {
            alerts.push("照明を弱めてください！");
        }

        if (avg_co2 >= ALERT_THRESHOLDS.co2_high) {
            alerts.push("換気をしましょう！");
        }

        const alertBox = document.getElementById('average-alerts');
        if (alerts.length === 0) {
            alertBox.innerHTML = '<span class="alert-good">\u2705 現在の環境は快適です</span>';
        } else {
            alertBox.innerHTML = alerts.map(msg => `<span class="alert-warning">\u26A0\uFE0F ${msg}</span>`).join('<br>');
        }
    }

    // --- リアルタイムデータ更新処理 (メインの関数) ---
    async function updateDashboard() {
        const settings = sensorSettings[currentSensor];

        // サーバーからセンサーデータを取得
        let sensorData;
        try {
            const response = await fetch('/api/sensor-data');
            if (!response.ok) { throw new Error(`HTTP error! status: ${response.status}`); }
            sensorData = await response.json();
        } catch (error) {
            console.error("センサーデータの取得に失敗しました:", error);
            return;
        }

        // 最新データを保持
        latestSensorData = sensorData;

        // ビーコン位置取得
        let beaconData;
        try {
            const response = await fetch('/api/get_iphone_positions');
            if (!response.ok) { throw new Error(`HTTP error! status: ${response.status}`); }
            beaconData = await response.json();
        } catch (error) {
            console.error("ビーコン位置の取得に失敗:", error);
            beaconData = [];
        }

        // プロフィールデータ取得 (5回に1回更新、初回は必ず)
        if (!profileMap._loaded || (profileMap._counter || 0) % 5 === 0) {
            try {
                const res = await fetch('/api/user_profiles');
                if (res.ok) {
                    const profiles = await res.json();
                    profileMap = { _loaded: true, _counter: 0 };
                    profiles.forEach(p => { profileMap[p.beacon_id] = p; });
                }
            } catch (e) {
                console.error("プロフィール取得エラー:", e);
            }
        }
        profileMap._counter = ((profileMap._counter || 0) + 1);

        // マップの更新 (2D/3D切り替え)
        if (is3DMode && is3DInitialized()) {
            update3DHeatmap(sensorData, currentSensor);
            update3DSensorMarkers(sensorData, currentSensor, settings);
            update3DPersonMarkers(beaconData);
        } else {
            updateHeatmap(sensorData, currentSensor);
            updatePiMarkers(sensorData, currentSensor, settings);
            updatePersonMarkers(beaconData, profileMap);
        }

        // 各グラフを更新
        updateLineChart(sensorData);
        updateBarChart(sensorData);
        updateGaugeChart(sensorData);
        updateAlerts(sensorData);
    }

    // 2D/3D表示切り替えボタン
    const viewToggleBtn = document.getElementById('view-toggle-btn');
    if (viewToggleBtn) {
        viewToggleBtn.addEventListener('click', function () {
            is3DMode = !is3DMode;
            const leafletEl = document.getElementById('leaflet-map');
            const threeEl = document.getElementById('three-map');

            if (is3DMode) {
                this.textContent = '2D';
                this.classList.add('active-3d');
                leafletEl.style.display = 'none';
                threeEl.style.display = 'block';
                if (!is3DInitialized()) {
                    init3DMap('three-map');
                }
                updateDashboard();
            } else {
                this.textContent = '3D';
                this.classList.remove('active-3d');
                threeEl.style.display = 'none';
                leafletEl.style.display = 'block';
                dispose3DMap();
                updateDashboard();
            }
        });
    }

    // ヒートマップ用タブ切り替え（.heatmap-container内のタブ）
    document.querySelectorAll('.heatmap-container .tab-btn').forEach(btn => {
        btn.addEventListener('click', function () {
            document.querySelector('.heatmap-container .tab-btn.active').classList.remove('active');
            this.classList.add('active');
            currentSensor = this.dataset.sensor;

            updateDashboard();
        });
    });

    // チャート用タブ切り替え
    document.querySelectorAll('.chart-tabs').forEach(tabGroup => {
        const chartType = tabGroup.dataset.chart; // 'line' or 'bar'

        tabGroup.querySelectorAll('.chart-tab-btn').forEach(btn => {
            btn.addEventListener('click', function () {
                // 同じグループ内のアクティブを解除
                tabGroup.querySelector('.chart-tab-btn.active').classList.remove('active');
                this.classList.add('active');

                const sensor = this.dataset.sensor;

                if (chartType === 'line') {
                    currentLineSensor = sensor;
                    // 折れ線グラフのデータをリセット
                    lineChart.data.labels = [];
                    lineChart.data.datasets.forEach(dataset => { dataset.data = []; });
                    if (latestSensorData) {
                        updateLineChart(latestSensorData);
                    }
                } else if (chartType === 'bar') {
                    currentBarSensor = sensor;
                    if (latestSensorData) {
                        updateBarChart(latestSensorData);
                    }
                }
            });
        });
    });

    // 好み入力UIが変更されたら、すぐにおすすめを更新
    [prefTemp, prefOccupancy, prefLight, prefHumidity, prefCo2].forEach(select => {
        select.addEventListener('change', updateRecommendations);
    });

    // --- ユーザー検索 ---
    setupUserSearch();

    // 定期実行と初回実行
    setInterval(() => {
        updateDashboard();
        updateRecommendations();
    }, DASHBOARD_SETTINGS.update_interval_ms);

    // ページ読み込み完了時に、まず1回目を実行
    (async () => {
        await loadAppConfig();

        // 設定モーダル初期化 (loadAppConfig後に実行)
        initSettingsModal();

        // Leafletマップ初期化
        initMap('leaflet-map');
        initRecommendationMap('recommendation-map');

        // 初回データ取得＆描画
        updateDashboard();
        updateRecommendations();
    })();

    // --- ユーザー検索のセットアップ ---
    function setupUserSearch() {
        const searchInput = document.getElementById('user-search-input');
        const searchResults = document.getElementById('user-search-results');
        const clearBtn = document.getElementById('user-search-clear');
        const filterDept = document.getElementById('search-filter-dept');
        const filterJob = document.getElementById('search-filter-job');
        const sortSelect = document.getElementById('search-sort');
        if (!searchInput || !searchResults) return;

        let debounceTimer = null;
        let expandedBeaconId = null;
        let lastResults = [];
        let lastQuery = '';

        // フィルタ選択肢を動的に取得して構築
        populateFilterOptions();

        async function populateFilterOptions() {
            try {
                const res = await fetch('/api/user_profiles');
                if (!res.ok) return;
                const profiles = await res.json();

                const depts = [...new Set(profiles.map(p => p.department).filter(Boolean))].sort();
                const jobs = [...new Set(profiles.map(p => p.job_title).filter(Boolean))].sort();

                depts.forEach(d => {
                    const opt = document.createElement('option');
                    opt.value = d;
                    opt.textContent = d;
                    filterDept.appendChild(opt);
                });
                jobs.forEach(j => {
                    const opt = document.createElement('option');
                    opt.value = j;
                    opt.textContent = j;
                    filterJob.appendChild(opt);
                });
            } catch (e) {
                console.error('フィルタ選択肢の取得エラー:', e);
            }
        }

        function triggerSearch() {
            const q = searchInput.value.trim();
            const dept = filterDept.value;
            const job = filterJob.value;

            clearBtn.style.display = q ? 'block' : 'none';

            if (debounceTimer) clearTimeout(debounceTimer);

            if (!q && !dept && !job) {
                searchResults.style.display = 'none';
                expandedBeaconId = null;
                lastResults = [];
                lastQuery = '';
                return;
            }

            debounceTimer = setTimeout(() => performSearch(q, dept, job), 300);
        }

        searchInput.addEventListener('input', triggerSearch);
        filterDept.addEventListener('change', triggerSearch);
        filterJob.addEventListener('change', triggerSearch);
        sortSelect.addEventListener('change', triggerSearch);

        clearBtn.addEventListener('click', () => {
            searchInput.value = '';
            filterDept.value = '';
            filterJob.value = '';
            sortSelect.value = 'name';
            clearBtn.style.display = 'none';
            searchResults.style.display = 'none';
            expandedBeaconId = null;
            lastResults = [];
            lastQuery = '';
        });

        // 外部クリックで結果を閉じる
        document.addEventListener('click', (e) => {
            if (!e.target.closest('#user-search-section')) {
                searchResults.style.display = 'none';
                expandedBeaconId = null;
            }
        });

        async function performSearch(query, dept, job) {
            try {
                const params = new URLSearchParams();
                if (query) params.set('q', query);
                if (dept) params.set('department', dept);
                if (job) params.set('job_title', job);
                params.set('sort', sortSelect.value);

                const res = await fetch(`/api/search_users?${params.toString()}`);
                if (!res.ok) return;
                const results = await res.json();
                lastResults = results;
                lastQuery = query;
                renderSearchResults(results, query);
            } catch (e) {
                console.error('検索エラー:', e);
            }
        }

        function highlightMatch(text, query) {
            if (!text || !query) return text || '';
            const escaped = query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
            return text.replace(new RegExp(`(${escaped})`, 'gi'), '<mark style="background:#00bcd4; color:#1a1a2e; border-radius:2px; padding:0 1px;">$1</mark>');
        }

        function renderSearchResults(results, query) {
            if (results.length === 0) {
                searchResults.innerHTML = '<div class="user-search-no-results">該当するユーザーが見つかりませんでした</div>';
                searchResults.style.display = 'block';
                return;
            }

            let html = `<div class="search-results-header">${results.length}件のユーザーが見つかりました</div>`;
            results.forEach(p => {
                const name = p.user_name || p.beacon_id.substring(0, 8);
                const initial = name.charAt(0).toUpperCase();
                const avatarHtml = p.profile_image
                    ? `<img class="search-result-avatar" src="${p.profile_image}" alt="${name}">`
                    : `<div class="search-result-avatar-placeholder">${initial}</div>`;

                const meta = [p.department, p.job_title].filter(Boolean).join(' / ');

                // マッチしたフィールドをタグとして表示
                let tags = '';
                if (query) {
                    const tagFields = [
                        { key: 'skills', label: 'スキル' },
                        { key: 'projects', label: 'PJ経験' },
                        { key: 'job_title', label: '職種' },
                        { key: 'department', label: '部署' }
                    ];
                    tagFields.forEach(f => {
                        if (p[f.key] && p[f.key].toLowerCase().includes(query.toLowerCase())) {
                            const vals = p[f.key].split(',').map(s => s.trim()).filter(s =>
                                s.toLowerCase().includes(query.toLowerCase())
                            );
                            vals.forEach(v => {
                                tags += `<span class="search-result-tag">${f.label}: ${highlightMatch(v, query)}</span>`;
                            });
                        }
                    });
                }

                html += `<div class="user-search-result-item" data-beacon-id="${p.beacon_id}">
                    ${avatarHtml}
                    <div class="search-result-info">
                        <div class="search-result-name">${highlightMatch(name, query)}</div>
                        <div class="search-result-meta">${meta}</div>
                        ${tags ? `<div class="search-result-tags">${tags}</div>` : ''}
                    </div>
                </div>`;

                // 展開中の詳細パネル
                if (expandedBeaconId === p.beacon_id) {
                    html += renderDetailPanel(p);
                }
            });

            searchResults.innerHTML = html;
            searchResults.style.display = 'block';

            // クリックで詳細パネルを展開/折りたたみ
            searchResults.querySelectorAll('.user-search-result-item').forEach(item => {
                item.addEventListener('click', () => {
                    const bid = item.dataset.beaconId;
                    expandedBeaconId = (expandedBeaconId === bid) ? null : bid;
                    renderSearchResults(lastResults, lastQuery);
                });
            });
        }

        function renderDetailPanel(p) {
            const name = p.user_name || p.beacon_id.substring(0, 8);
            const initial = name.charAt(0).toUpperCase();
            const color = '#00bcd4';

            const avatarHtml = p.profile_image
                ? `<img class="search-detail-avatar" src="${p.profile_image}" style="border: 2px solid ${color};">`
                : `<div class="search-detail-avatar-placeholder" style="border: 2px solid ${color};">${initial}</div>`;

            let rows = '';
            const fields = [
                { key: 'job_title', label: '職種' },
                { key: 'department', label: '部署' },
                { key: 'skills', label: 'スキル' },
                { key: 'projects', label: 'PJ経験' },
                { key: 'hobbies', label: '趣味' },
            ];
            fields.forEach(f => {
                if (p[f.key]) {
                    rows += `<div class="search-detail-label">${f.label}</div><div class="search-detail-value">${p[f.key]}</div>`;
                }
            });
            if (p.email) {
                rows += `<div class="search-detail-label">メール</div><div class="search-detail-value"><a href="mailto:${p.email}">${p.email}</a></div>`;
            }
            if (p.phone) {
                rows += `<div class="search-detail-label">電話</div><div class="search-detail-value"><a href="tel:${p.phone}">${p.phone}</a></div>`;
            }

            return `<div class="search-detail-panel">
                <div class="search-detail-header">
                    ${avatarHtml}
                    <div>
                        <div class="search-detail-name">${name}</div>
                        <div class="search-detail-meta">${[p.department, p.job_title].filter(Boolean).join(' / ')}</div>
                    </div>
                </div>
                ${rows ? `<div class="search-detail-grid">${rows}</div>` : ''}
            </div>`;
        }
    }

});
