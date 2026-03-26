import { PI_LOCATIONS } from './config.js'; 

// ダークモード用の色設定
const chartOptions = {
    responsive: true,
    maintainAspectRatio: true,
    plugins: { legend: { labels: { color: '#e0e0e0' } } },
    scales: {
        x: {
            ticks: { color: '#e0e0e0' },
            grid: { color: 'rgba(224, 224, 224, 0.1)' }
        },
        y: {
            ticks: { color: '#e0e0e0' },
            grid: { color: 'rgba(224, 224, 224, 0.1)' }
        }
    }
};

// 3つのグラフを初期化する関数
export function initCharts() {

    const lineCtx = document.getElementById('lineChart').getContext('2d');
    const barCtx = document.getElementById('barChart').getContext('2d');
    const gaugeCtx = document.getElementById('gaugeChart').getContext('2d');

    // 折れ線グラフ (Line Chart) の作成 ---
    const lineChart = new Chart(lineCtx, {
        type: 'line',
        data: {
            labels: [], 
            datasets: PI_LOCATIONS.map((pi, index) => ({
                label: pi.id, 
                data: [],     
                borderColor: `hsl(${index * 40}, 70%, 60%)`, 
                tension: 0.3,
                borderWidth: 2,
                pointRadius: 0 
            }))
        },
        options: {
            ...chartOptions
        }
    });

    // 棒グラフ (Bar Chart) の作成
    const barChart = new Chart(barCtx, {
        type: 'bar',
        data: {
            labels: PI_LOCATIONS.map(pi => pi.id),
            datasets: [{
                label: '...',
                data: [],
                backgroundColor: '#00bcd4',
            }]
        },
        options: {
            ...chartOptions,
            indexAxis: 'x'
        }
    });

    // ゲージグラフ (Gauge Chart) の作成
    const gaugeChart = new Chart(gaugeCtx, {
        type: 'doughnut', 
        data: {
            labels: ['現在値', '残り'],
            datasets: [{
                data: [0, 1000], 
                backgroundColor: ['#00bcd4', '#40407a'], 
                borderWidth: 0
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: true,
            circumference: 180,
            rotation: -90,
            cutout: '70%',
            plugins: {
                legend: { display: false },
                tooltip: { enabled: false }
            }
        }
    });

    // 3つのインスタンスをオブジェクトとして返す (main.js で使うため)
    return { lineChart, barChart, gaugeChart };
}