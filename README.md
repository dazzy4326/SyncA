# SyncA

**スマートオフィス環境モニタリング＆ソーシャルプラットフォーム**

オフィスの各所に設置した Raspberry Pi（環境センサー＋iBeacon）と iPhone アプリを連携させ、
**室内環境のリアルタイム可視化** と **人の位置に基づくソーシャル機能** を提供するシステムです。

---

## 目次

1. [このプロジェクトで何ができるか](#このプロジェクトで何ができるか)
2. [デモ](#デモ)
3. [システム構成](#システム構成)
4. [前提条件](#前提条件)
5. [セットアップ手順](#セットアップ手順)
6. [iOS アプリ詳細](#ios-アプリ詳細)
7. [環境変数リファレンス](#環境変数リファレンス)
8. [Make コマンド一覧](#make-コマンド一覧)
9. [ディレクトリ構成](#ディレクトリ構成)
10. [API エンドポイント一覧](#api-エンドポイント一覧)
11. [技術スタック](#技術スタック)
12. [測位の仕組み](#測位の仕組み)
13. [トラブルシューティング](#トラブルシューティング)
14. [ライセンス](#ライセンス)

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
| **macOS** | Ventura 13.0 以上 | — |
| **Xcode** | 15 以上（Swift 5.0） | Mac App Store からインストール |
| **iPhone 実機** | iOS 15.6 以上 | BLE/iBeacon はシミュレータ非対応 |
| **Apple Developer アカウント** | — | 実機ビルドに署名が必要（無料アカウント可、7日ごと再署名） |
| **BLE ビーコン** | iBeacon 対応 9台 | UUID: `DD05B849-BB42-4AB8-B8F3-798B42440C4E`、Minor値 1〜9 |
| **ネットワーク** | — | iPhone とサーバーが通信可能（同一LAN or ngrok） |

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

#### 方法 A: セットアップスクリプト（推奨）

```bash
cd frontend/ios/tohata_ios_02

# セットアップ（サーバーURL と Apple Developer Team ID を対話入力）
./setup.sh

# Xcode で開く
open Synca.xcodeproj
```

> `setup.sh` は `AppConfig.swift` のサーバーURLと、`project.pbxproj` の `DEVELOPMENT_TEAM` を書き換えます。

#### 方法 B: 手動設定

```bash
cd frontend/ios
open Synca.xcodeproj
```

以下を **手動** で変更してください：

**手順 1: 署名設定（必須）**

1. Xcode の **Settings → Accounts** で Apple ID にサインイン
2. プロジェクトナビゲータで **Synca** を選択
3. ターゲット **tohata_ios_02** → **Signing & Capabilities** タブ
4. **Team** を自分の Apple Developer アカウントに変更
5. 必要に応じて **Bundle Identifier** を変更（現在: `com.tohata.synca`）

**手順 2: サーバーURL変更（必須）**

`tohata_ios_02/AppConfig.swift` を開き、以下を変更：

```swift
// AppConfig.swift 14行目
static let localURL = "https://ungnarled-bemazed-argelia.ngrok-free.dev"
//                      ↑ ここを自分のサーバーURLに変更
```

ローカルLAN接続の場合:
```swift
static let localURL = "http://192.168.x.x:5001"
```

ngrok経由の場合:
```swift
static let localURL = "https://xxxxx.ngrok-free.dev"
```

> このURLはアプリ内の管理画面からも動的に変更可能です（UserDefaultsに保存）。

**手順 3: ビルド＆実行**

1. 実機 iPhone を USB 接続（シミュレータ不可）
2. ビルドターゲットに実機を選択 → **Run**（`Cmd + R`）
3. 初回起動時に **Bluetooth** と **位置情報** を **「常に許可」**

> **外部ライブラリ（CocoaPods / SPM）は一切不要です。** クローン後そのままビルドできます。

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

## iOS アプリ詳細

### 画面構成（5タブ）

カスタムタブバーによる5画面構成です。

#### タブ 1: ダッシュボード

| セクション | 内容 |
|---|---|
| **ユーザー検索** | 名前・スキル・部署で検索。アイコンタップで位置ハイライト（位置あり）またはプロフィール表示（位置なし） |
| **センサー概要カード** | 各拠点の温度・湿度・照度・CO2 を数値表示 |
| **リアルタイムヒートマップ** | SceneKit 3Dフロアマップ上に環境データをヒートマップ重畳。タブで温度/湿度/照度/CO2切替 |
| **お好み選択** | 温度・混雑度・明るさ・湿度・CO2 の好みを設定 → おすすめエリア表示 |
| **時系列チャート** | Charts フレームワークで環境データの時間推移をグラフ表示 |
| **拠点別比較** | 各拠点の環境データを棒グラフで比較 |

**3Dフロアマップの特徴:**

- **フロアオブジェクト**: 壁・机・柱・棚・植物・椅子・モニター・窓の8種をサーバー設定から読み込み
- **人体モデル（6パーツ）**: 胴体 + 頭 + 両腕 + 両脚
  - 移動中（立位）: 脚は垂直、腕はやや開く
  - 静止中（座位）: 太ももは水平前方、すねは垂直、腕は前方（机に向かう姿勢）
- **空中パルスハイライト**: ユーザーアイコンタップ時にY=1.5mの空中でパルスリング＋垂直ガイドライン表示。タップで解除可能
- **動静ラベル**: 「移動中」「静止中」を3D空間内にオフセット配置

#### タブ 2: ソーシャル

| セクション | 内容 |
|---|---|
| **スキルマッチング** | スキルキーワードで検索。位置あり→ハイライト、位置なし→プロフィール |
| **近くのマッチ** | 半径3m以内でスキル・趣味が合うユーザーを表示 |
| **コラボレーションボード** | ヘルプ募集・ディスカッション・告知の投稿と応答 |
| **ランチマッチング** | 趣味・プロジェクトの共通点でマッチした相手を表示 |
| **交流分析** | 他ユーザーとの交流頻度・履歴を可視化 |

#### タブ 3: プロフィール

ユーザー名・部署・職種・スキル・趣味・プロジェクト・連絡先の編集。プロフィール画像のアップロード。

#### タブ 4: 測位

ビーコンの受信状況（RSSI・距離）、測位計算結果、カルマンフィルタの状態をリアルタイム表示。デバッグ・検証用。

#### タブ 5: 管理

パスワード認証後にサーバー設定を編集：
- サーバー接続URL（ローカル / ngrok 切替）
- フロアプラン画像アップロード
- キャリブレーション（原点・縮尺）
- ビーコン配置座標
- フロア外枠（境界ポリゴン）
- フロアオブジェクト（壁・机など）

### iOS アプリ設定値

すべて **`frontend/ios/tohata_ios_02/AppConfig.swift`** に一元管理されています。

#### サーバー設定（ServerConfig）

| 項目 | デフォルト | 説明 |
|---|---|---|
| `localURL` | ngrok URL | **必ず変更** — サーバーのURL |
| `requestTimeoutInterval` | 3.0秒 | 通信タイムアウト |

> ngrok ヘッダー（`ngrok-skip-browser-warning`）が自動付与されます。アプリ内管理画面からURLを動的に切替可能です。

#### ビーコン設定（BeaconConfig）

| 項目 | デフォルト | 説明 |
|---|---|---|
| `targetUUID` | `DD05B849-BB42-4AB8-B8F3-798B42440C4E` | ビーコンのUUID |
| `coordinates` | 9台の(x,y)座標（mm） | ビーコン設置位置 |
| `requiredBeaconCount` | 9 | 測位に必要なビーコン台数 |
| `sampleCount` | 30 | フォアグラウンドのRSSIサンプル数 |
| `backgroundSampleCount` | 5 | バックグラウンドのRSSIサンプル数 |
| `maxValidDistanceMeters` | 50.0 | 有効最大距離(m) |

#### 動静検知設定（SensorConfig）

| 項目 | デフォルト | 説明 |
|---|---|---|
| `motionDetectionInterval` | 0.02秒(50Hz) | 動静検知ループ間隔 |
| `motionThreshold` | 0.1G | 動き判定の閾値 |

#### ユーザーデフォルト・選択肢

- **UserDefaultsConfig**: 初期ユーザー名「ゲスト」、初期部署「other」など。`@AppStorage` に保存され端末に永続化
- **PickerOptions**: 職種（エンジニア/マネージャー/営業/事務）、部署（開発部/営業部/総務部/その他）、ステータス（取込可/取込中/会議中/休憩中）

### iOS アプリの必要な権限

| 権限 | 用途 |
|---|---|
| **Bluetooth（常に許可）** | BLE ビーコンの検出 |
| **位置情報（常に許可）** | iBeacon レンジング（バックグラウンド含む） |
| **HTTP通信** | ATS無効化でローカルサーバーへHTTP通信を許可 |

> 本番/App Store公開時は HTTPS に切り替えてください。

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
│       ├── Synca.xcodeproj/     #     ← Xcode で開くファイル
│       ├── setup.sh             #     初期セットアップスクリプト
│       ├── tohata-ios-02-Info.plist  # バックグラウンドモード・ATS設定
│       └── tohata_ios_02/       #     Swift ソースコード
│           ├── tohata_ios_02App.swift   # @main エントリーポイント（29行）
│           ├── AppConfig.swift          # 全設定値の一元管理（162行）
│           ├── ContentView.swift        # 5タブ構成・テーマ色定義（1111行）
│           ├── Models.swift             # 全APIレスポンスの構造体（390行）
│           ├── APIService.swift         # サーバー通信・データ公開（688行）
│           ├── BeaconManager.swift      # ビーコン検出・測位計算・KF補正（805行）
│           ├── NativeDashboardView.swift # ダッシュボード・ヒートマップ（1153行）
│           ├── FloorMap3DView.swift      # SceneKit 3Dフロアマップ（1615行）
│           ├── SocialView.swift          # スキル検索・コラボ・交流分析（2079行）
│           ├── DashboardWebView.swift    # WKWebView 表示（77行）
│           ├── AdminView.swift           # 管理者設定（2415行）
│           └── Assets.xcassets/          # アプリアイコン・フロアプラン画像
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

**iOS アプリ合計: 約10,500行の Swift コード**

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

すべて iOS 標準フレームワーク。**外部ライブラリは不要**。

| フレームワーク | 用途 |
|---|---|
| **SwiftUI** | 全UI構築 |
| **SceneKit** | 3Dフロアマップ・人体モデル・パルスアニメーション |
| **CoreLocation** | iBeacon レンジング |
| **CoreMotion** | 加速度センサー（動静検知） |
| **Charts** | 時系列・棒グラフ描画 |
| **WebKit** | WKWebView でサーバーダッシュボード表示 |
| **Network** | ネットワーク状態監視 |
| **Combine** | リアクティブデータバインディング |
| **PhotosUI** | プロフィール画像選択 |
| **UserNotifications** | 通知権限 |

### エッジデバイス
- **Raspberry Pi** + Bluetooth
- **BME280 / BH1750 / MH-Z19C** センサー
- **smbus2 / pyserial**（I2C・UART 通信）
- **systemd**（デーモン管理・自動起動）

---

## 測位の仕組み

```
[BLE ビーコン x9]
       │ RSSI信号
       ▼
[CoreLocation iBeacon レンジング]
       │ accuracy(m) → mm に変換
       ▼
[サンプリング] ── 各ビーコン30回収集 → 中央値
       │ 9台分揃ったら
       ▼
[動静検知] ── CoreMotion 加速度 > 0.1G → 移動中/静止中をUI反映
       │
       ▼
[三点測位] ── POST /api/calculate_from_iphone
       │     サーバー側で距離が近い3台を選択
       │     Shapely で3円の交差 → 重心を計算
       ▼
[境界クランプ] ── フロア外枠ポリゴンの外に出た場合、
       │        最近傍の境界上の点に補正
       ▼
[サーバー送信] ── POST /api/add_location
       │ x, y を受信・DB保存
       ▼
[3Dフロアマップ更新] ── 人体モデルの位置・姿勢を反映
```

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

### iOS ビルド時のエラー

| 症状 | 原因と対処 |
|---|---|
| `Signing requires a development team` | Signing & Capabilities で Team を設定。または `./setup.sh` を実行 |
| `Provisioning profile` エラー | Xcode → Settings → Accounts で Apple ID にサインインし直す |
| シミュレータでクラッシュ | **実機でのみ動作**。BLE/iBeacon はシミュレータ非対応 |
| `tohata_ios_02.xcodeproj` が開けない | **`Synca.xcodeproj`** を使ってください。旧プロジェクトファイルは廃止 |

### iOS 実行時のエラー

| 症状 | 原因と対処 |
|---|---|
| 「位置情報の許可がありません」 | 設定 → プライバシー → 位置情報 → 本アプリ → **「常に許可」** |
| ビーコンが検出されない | (1) Bluetooth ON確認 (2) ビーコン電源確認 (3) UUID/Minor値の一致確認 |
| 「位置を計算中...」が続く | 9台全ビーコンの30回サンプリング完了を待つ（数十秒かかる） |
| 「移動中」が出続ける | `SensorConfig.motionThreshold` を大きくして感度調整 |
| ハイライトが消えない | ハイライトリング付近をタップして解除 |

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
