# SyncA

**スマートオフィス環境モニタリング＆ソーシャルプラットフォーム**

オフィスの各所に設置した Raspberry Pi（環境センサー＋iBeacon）と iPhone アプリを連携させ、
**室内環境のリアルタイム可視化** と **人の位置に基づくソーシャル機能** を提供するシステムです。

---

## このプロジェクトで何ができるか

| 機能 | 説明 |
|---|---|
| **環境モニタリング** | 温度・湿度・照度・CO2 をリアルタイムでダッシュボードに表示 |
| **屋内測位** | iBeacon × iPhone BLE スキャンで人の位置を三点測位 |
| **3D フロアマップ** | SceneKit による 3D ヒートマップで環境と人の位置を可視化 |
| **おすすめエリア** | ユーザーの好み（涼しい・静か・明るい等）に合うゾーンを自動提案 |
| **ソーシャル** | スキル検索、近くの人マッチ、コラボ掲示板、ランチマッチ、交流分析 |
| **管理者設定** | フロアプラン画像の差し替え、ビーコン配置、オブジェクト編集 |

---

## デモ

### iOS アプリ

[![SyncA iOS デモ](https://img.youtube.com/vi/YrQHP6wvBY4/maxresdefault.jpg)](https://www.youtube.com/watch?v=YrQHP6wvBY4/)

> 画像クリックで YouTube のデモ動画（約 4 分）が再生されます。

---

## システム構成

```
  Raspberry Pi (edge/)             Flask Server (backend/)           クライアント
 ┌────────────────────┐           ┌────────────────────┐
 │ BME280  → 温度/湿度 │──── API ──▶│                    │◀── ブラウザ (frontend/web/)
 │ BH1750  → 照度      │           │  REST API          │
 │ MH-Z19C → CO2       │           │  測位計算 (Shapely) │◀── iPhone  (frontend/ios/)
 │ iBeacon → BLE発信   │           │  MySQL             │
 └────────────────────┘           └────────────────────┘
        × 9 台                          1 台
```

**データの流れ:**
1. 各 Raspberry Pi がセンサー値を計測し、Flask サーバーに POST 送信
2. iPhone アプリが各 Pi の iBeacon 電波を受信して距離を測定し、サーバーに送信
3. サーバーが三点測位で位置を推定し、環境データと合わせて DB に保存
4. Web ブラウザまたは iPhone アプリがダッシュボードとしてデータを表示

---

## 前提条件

セットアップを始める前に、以下がインストールされている必要があります。

### バックエンド（必須）

| ソフトウェア | バージョン | インストール方法 |
|---|---|---|
| **Python** | 3.9 以上（推奨 3.11） | [python.org](https://www.python.org/downloads/) または `brew install python` |
| **MySQL** | 8.0 以上 | [dev.mysql.com](https://dev.mysql.com/downloads/) または `brew install mysql` |
| **Git** | 任意 | `brew install git`（macOS）/ `apt install git`（Ubuntu） |

### iOS アプリ（iPhone で使う場合）

| ソフトウェア | バージョン | 備考 |
|---|---|---|
| **Xcode** | 15 以上 | Mac App Store からインストール |
| **iPhone 実機** | iOS 16 以上 | BLE スキャンにはシミュレーターは使用不可 |

### エッジデバイス（Raspberry Pi）

| ハードウェア | 備考 |
|---|---|
| **Raspberry Pi** | Bluetooth 対応モデル（3B+ / 4 / Zero 2W 等） |
| **BME280** | 温度・湿度センサー（I2C 接続） |
| **BH1750** | 照度センサー（I2C 接続） |
| **MH-Z19C** | CO2 センサー（UART 接続） |

---

## セットアップ手順

### Step 1: リポジトリのクローン

```bash
git clone https://github.com/your-username/synca.git
cd synca
```

### Step 2: バックエンドサーバーの起動

```bash
cd backend
```

#### 方法 A: ワンコマンドセットアップ（推奨）

```bash
chmod +x setup.sh
./setup.sh
```

対話形式で以下を自動実行します:
- Python 仮想環境の作成
- 依存パッケージのインストール
- `.env` ファイルの生成
- データベースの初期化（任意）

#### 方法 B: 手動セットアップ

```bash
# 1. Python 仮想環境を作成・有効化
python3 -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate

# 2. 依存パッケージをインストール
pip install -r requirements.txt

# 3. 環境変数ファイルを作成
cp .env.example .env

# 4. .env を編集（DB のパスワード等を自分の環境に合わせる）
nano .env                        # または任意のエディタ
```

#### データベースの準備

```bash
# MySQL にログインして初期化スクリプトを実行
mysql -u root -p < scripts/init_db.sql
```

これにより以下が作成されます:
- データベース `sensor_db`
- ユーザー `flask_reader`（アプリ用の接続ユーザー）
- テーブル 4 つ（`env_data`, `location_data`, `estimated_positions`, `user_profiles`）

#### サーバーの起動

```bash
# 開発サーバー（デバッグモード）
make run

# 本番サーバー（Gunicorn, ワーカー 4 プロセス）
make run-prod
```

起動後、ブラウザで **http://localhost:5001/** を開くと Web ダッシュボードが表示されます。

### Step 3: iOS アプリのビルド（任意）

1. `frontend/ios/Synca.xcodeproj` を Xcode で開く
2. iPhone 実機を Mac に接続
3. Xcode の Signing & Capabilities で自分の Apple ID を設定
4. ビルド＆実行（`Cmd + R`）
5. アプリ起動後、**管理者タブ**でサーバーの接続先を設定:
   - 同じ WiFi 内なら `http://<Mac の IP>:5001`
   - 外部公開なら ngrok の URL

### Step 4: エッジデバイスのセットアップ（任意）

Raspberry Pi 上で実行します:

```bash
cd edge

# セットアップ（root 権限が必要）
sudo chmod +x setup.sh
sudo ./setup.sh

# .env を編集（ラズパイごとに異なる ID を設定）
nano .env
```

`.env` の設定項目:

```env
RASPBERRY_PI_ID=ras_01                           # このラズパイの ID（ras_01 〜 ras_09）
API_ENDPOINT_URL=http://server-ip:5001/api/add_env_data  # Flask サーバーの URL
```

iBeacon の Minor ID を設定（ラズパイごとに異なる値）:

```bash
nano start_ibeacon.sh
# MINOR="0001"  ← ras_01 なら 0001, ras_02 なら 0002, ...
```

サービスを有効化して自動起動:

```bash
sudo systemctl enable --now env_sensing.service   # センサー値送信
sudo systemctl enable --now ibeacon.service        # iBeacon 発信
```

動作確認:

```bash
sudo systemctl status env_sensing.service
journalctl -u env_sensing.service -f              # ログをリアルタイム表示
```

---

## 環境変数リファレンス

### バックエンド（`backend/.env`）

| 変数名 | 説明 | デフォルト値 |
|---|---|---|
| `FLASK_DEBUG` | デバッグモード（True/False） | `True` |
| `FLASK_SECRET_KEY` | Flask のシークレットキー | `your-secret-key-change-in-production` |
| `DB_USER` | MySQL 接続ユーザー名 | `flask_reader` |
| `DB_PASSWORD` | MySQL 接続パスワード | ※ 必ず変更してください |
| `DB_HOST` | MySQL ホスト | `localhost` |
| `DB_NAME` | データベース名 | `sensor_db` |

### エッジデバイス（`edge/.env`）

| 変数名 | 説明 | デフォルト値 |
|---|---|---|
| `RASPBERRY_PI_ID` | このラズパイの識別 ID | `ras_01` |
| `API_ENDPOINT_URL` | サーバーのデータ送信先 URL | ※ 必ず変更してください |
| `SENSOR_SCAN_COUNT` | 1 回あたりのセンサースキャン回数 | `30` |
| `SENSOR_SCAN_INTERVAL` | スキャン間隔（秒） | `1` |
| `API_TIMEOUT` | API リクエストタイムアウト（秒） | `10` |
| `RETRY_DELAY` | エラー時の再試行間隔（秒） | `5` |

---

## Make コマンド一覧

`backend/` ディレクトリで使用できます。

```bash
make help       # コマンド一覧を表示
make setup      # 初回セットアップ（仮想環境 + パッケージ + .env）
make run        # 開発サーバーを起動（Flask, ポート 5001）
make run-prod   # 本番サーバーを起動（Gunicorn, ワーカー 4）
make db-init    # MySQL データベースを初期化
make check      # 環境チェック（Python・MySQL・.env の有無）
make clean      # 仮想環境・キャッシュを削除
```

---

## ディレクトリ構成

```
synca/
├── backend/                     # サーバーサイド
│   ├── src/                     #   Flask アプリケーション
│   │   ├── app.py               #     アプリケーションファクトリ
│   │   ├── routes.py            #     ページルーティング
│   │   └── api/                 #     REST API
│   │       ├── routes.py        #       エンドポイント定義
│   │       ├── data_provider.py #       DB 操作・測位計算
│   │       ├── analysis.py      #       密度推定・ゾーン分析・レコメンド
│   │       ├── social.py        #       ソーシャル機能
│   │       └── config_loader.py #       設定ファイル読み込み
│   ├── data/                    #   設定 JSON・座標データ
│   ├── scripts/                 #   DB 初期化 SQL
│   ├── requirements.txt
│   ├── Makefile
│   ├── setup.sh
│   └── .env.example
│
├── frontend/                    # フロントサイド
│   ├── web/                     #   Web ダッシュボード
│   │   ├── templates/           #     Jinja2 テンプレート
│   │   └── static/              #     CSS / JS / 画像
│   └── ios/                     #   iOS アプリ (SwiftUI)
│       ├── Synca.xcodeproj/
│       └── tohata_ios_02/       #     Swift ソースコード
│
├── edge/                        # エッジデバイス (Raspberry Pi)
│   ├── env_get_api.py           #   センサー値取得＆API 送信
│   ├── start_ibeacon.sh         #   iBeacon 発信
│   ├── setup.sh                 #   セットアップスクリプト
│   ├── requirements.txt
│   └── .env.example
│
├── sample/                      # サンプルデータ
├── .gitignore
├── LICENSE
└── README.md
```

---

## API エンドポイント一覧

### データ取得

| メソッド | パス | 説明 |
|---|---|---|
| GET | `/api/sensor-data` | 全拠点の最新センサーデータ |
| GET | `/api/floorplan-data` | フロアプラン座標データ |
| GET | `/api/app_config` | アプリケーション設定（拠点座標・閾値等） |
| GET | `/api/get_iphone_positions` | 全ユーザーの最新推定位置 |
| GET | `/api/recommendations?temp=cool&occupancy=quiet&light=bright` | おすすめエリア提案 |

### データ登録

| メソッド | パス | 説明 |
|---|---|---|
| POST | `/api/add_env_data` | 環境データ登録（Raspberry Pi → サーバー） |
| POST | `/api/add_raw_data_batch` | BLE 距離データ一括登録（iPhone → サーバー） |
| POST | `/api/calculate_from_iphone` | サーバーサイド測位計算 |

### ソーシャル機能

| メソッド | パス | 説明 |
|---|---|---|
| GET | `/api/search_users?q=Python` | ユーザー検索（名前・スキル・部署） |
| GET | `/api/skill_search?skill=React` | スキルベース検索 |
| GET | `/api/nearby_matches?beacon_id=xxx` | 近くのマッチングユーザー |
| GET/POST | `/api/collab_posts` | コラボレーション掲示板 |
| POST | `/api/lunch_match/generate` | ランチマッチ自動生成 |
| GET | `/api/interaction_stats` | 部署間交流の統計 |

### 管理者

| メソッド | パス | 説明 |
|---|---|---|
| POST | `/api/verify_admin_password` | 管理者認証 |
| POST | `/api/upload_floorplan` | フロアプラン画像アップロード |
| POST | `/api/update_beacon_config` | ビーコン配置設定の更新 |
| POST | `/api/update_floor_boundary` | フロア外枠の更新 |
| POST | `/api/update_floor_objects` | フロアオブジェクトの更新 |

---

## 技術スタック

### バックエンド
- **Flask** + Flask-CORS + Flask-SQLAlchemy
- **MySQL 8.0** (PyMySQL)
- **Gunicorn**（本番 WSGI サーバー）
- **Shapely**（幾何学計算 / 測位補正）
- **SciPy**（カーネル密度推定）
- **NumPy / Pandas**（データ処理）

### Web フロントエンド
- **Leaflet.js**（2D マップ）
- **Three.js**（3D フロアマップ）
- **Chart.js**（時系列グラフ・棒グラフ）

### iOS アプリ
- **SwiftUI** + **Combine**
- **CoreLocation**（iBeacon スキャン）
- **CoreMotion**（加速度センサー / カルマンフィルター）
- **SceneKit**（3D フロアマップ）
- **Swift Charts**（ネイティブグラフ）

### エッジデバイス
- **Raspberry Pi** + Bluetooth
- **BME280 / BH1750 / MH-Z19C** センサー
- **smbus2 / pyserial**（I2C・UART 通信）
- **systemd**（デーモン管理・自動起動）

---

## トラブルシューティング

### サーバーが起動しない

```bash
# 環境チェック
cd backend
make check

# よくある原因
# 1. 仮想環境が有効化されていない
source .venv/bin/activate

# 2. MySQL が起動していない（macOS）
brew services start mysql

# 3. .env の DB_PASSWORD が間違っている
cat .env | grep DB_
```

### MySQL に接続できない

```bash
# MySQL が動作しているか確認
mysql -u root -p -e "SHOW DATABASES;"

# DB 初期化を再実行
mysql -u root -p < scripts/init_db.sql

# 接続テスト（.env の値で接続できるか確認）
mysql -u flask_reader -p sensor_db -e "SHOW TABLES;"
```

### iOS アプリがサーバーに接続できない

1. iPhone と Mac が**同じ WiFi** に接続されているか確認
2. Mac の IP アドレスを確認: `ifconfig en0 | grep inet`
3. アプリの管理者設定で `http://<Mac の IP>:5001` を入力
4. Mac のファイアウォールがポート 5001 をブロックしていないか確認

### Raspberry Pi のセンサーが動かない

```bash
# I2C デバイスが認識されているか確認
i2cdetect -y 1
# 0x76 (BME280) と 0x23 (BH1750) が表示されれば OK

# シリアルポートの確認（MH-Z19C）
ls /dev/ttyAMA0

# ログの確認
journalctl -u env_sensing.service -f
```

---

## ライセンス

**Source Available License** - ソースコードは公開されていますが、利用には制限があります。

- 著作権者および所属組織内での利用・改変・再配布は **自由** です
- 外部の第三者はソースコードの **閲覧のみ** 許可されています
- 外部利用には著作権者の書面による許可が必要です

詳細は [LICENSE](LICENSE) を参照してください。
