# SyncA

**スマートオフィス環境モニタリング＆ソーシャルプラットフォーム**

オフィスや研究室に設置した **9台の Raspberry Pi**（環境センサー＋iBeacon）と **iPhone アプリ** を連携させ、
**室内環境のリアルタイム可視化** と **人の位置に基づくソーシャル機能** を提供するシステムです。

---

## 目次

1. [概要 — このシステムで何ができるか](#概要--このシステムで何ができるか)
2. [デモ動画](#デモ動画)
3. [システム全体像](#システム全体像)
4. [3つのコンポーネントの役割](#3つのコンポーネントの役割)
5. [データの流れ — 各処理の詳細](#データの流れ--各処理の詳細)
6. [データベース設計](#データベース設計)
7. [設定ファイル（config_lab.json）](#設定ファイルconfig_labjson)
8. [前提条件](#前提条件)
9. [セットアップ手順](#セットアップ手順)
10. [iOS アプリ詳細](#ios-アプリ詳細)
11. [環境変数リファレンス](#環境変数リファレンス)
12. [Make コマンド一覧](#make-コマンド一覧)
13. [ディレクトリ構成](#ディレクトリ構成)
14. [API エンドポイント一覧](#api-エンドポイント一覧)
15. [技術スタック](#技術スタック)
16. [測位の仕組み](#測位の仕組み)
17. [トラブルシューティング](#トラブルシューティング)
18. [ライセンス](#ライセンス)

---

## 概要 — このシステムで何ができるか

| 機能カテゴリ | 機能 | 説明 |
|---|---|---|
| **環境モニタリング** | センサーデータ収集 | 9台の Raspberry Pi が温度・湿度・照度・CO2 を定期的に計測し、サーバーに送信 |
| | リアルタイム表示 | Web ダッシュボード・iOS アプリでセンサーデータを数値・グラフ・ヒートマップで表示 |
| | 時系列分析 | 環境データの時間推移をグラフで確認。拠点別の比較も可能 |
| **屋内測位** | BLE 三点測位 | 各 Raspberry Pi が発信する iBeacon 電波を iPhone で受信し、距離が近い3台のビーコンから位置を推定 |
| | 動静検知 | iPhone の加速度センサーでユーザーが移動中か静止中かを判定し、3Dマップ上の人体モデルの姿勢に反映 |
| | 境界クランプ | 測位結果がフロア外枠ポリゴンの外に出た場合、最近傍の境界上の点に自動補正 |
| **3D 可視化** | 3D フロアマップ | SceneKit で壁・机・棚・窓などを立体表示。人の位置と環境ヒートマップを重畳 |
| | 人体モデル | 胴体・頭・両腕・両脚の6パーツで人を表現。移動中は立位、静止中は座位の姿勢 |
| **おすすめエリア** | エリアレコメンド | 温度・混雑度・明るさなどの好みに基づき、最適な座席エリアを自動提案 |
| **ソーシャル** | スキル検索 | 名前・スキル・部署でユーザーを検索。位置がわかる場合は3Dマップ上でハイライト |
| | 近くのマッチ | 半径3m以内でスキル・趣味が合うユーザーを自動検出 |
| | コラボ掲示板 | ヘルプ募集・ディスカッション・告知の投稿と応答 |
| | ランチマッチ | 趣味・プロジェクトの共通点でマッチした相手を表示 |
| | 交流分析 | ユーザー間・部署間の交流頻度を可視化 |
| **管理者設定** | フロア設定 | フロアプラン画像・ビーコン配置・フロア外枠・フロアオブジェクトをアプリ内から編集 |

---

## デモ動画

### iOS アプリ

[![SyncA iOS デモ](https://img.youtube.com/vi/YrQHP6wvBY4/maxresdefault.jpg)](https://www.youtube.com/watch?v=YrQHP6wvBY4/)

> 画像クリックで YouTube のデモ動画（約 4 分）が再生されます。

---

## システム全体像

本システムは **エッジデバイス（Raspberry Pi）**、**バックエンドサーバー（Flask）**、**クライアント（iPhone / Web ブラウザ）** の3層で構成されています。

```
                              ┌──────────────────────────────────────────┐
                              │         Flask サーバー (backend/)         │
                              │                                          │
  Raspberry Pi × 9台          │  ┌──────────────────────────────────┐    │
 ┌──────────────────────┐     │  │  REST API (routes.py)            │    │     クライアント
 │                      │     │  │  ・環境データ受信・保存           │    │
 │  BME280  → 温度/湿度  │─────┼──│  ・三点測位計算 (Shapely)        │────┼──▶ iPhone (frontend/ios/)
 │  BH1750  → 照度       │ API │  │  ・境界クランプ補正              │    │    ・BLE ビーコン受信
 │  MH-Z19C → CO2        │     │  │  ・ソーシャル機能                │    │    ・3D フロアマップ
 │                      │     │  │  ・おすすめエリア計算             │    │    ・ソーシャル機能
 │  iBeacon → BLE発信    │     │  └──────────────────────────────────┘    │
 │  (Minor ID 1〜9)      │     │                                          │
 └──────────────────────┘     │  ┌──────────────────────────────────┐    │
                              │  │  MySQL (sensor_db)                │────┼──▶ Web ブラウザ (frontend/web/)
                              │  │  ・env_data (環境データ)          │    │    ・2D/3D マップ
                              │  │  ・location_data (BLE生距離)      │    │    ・ダッシュボード
                              │  │  ・estimated_positions (推定位置)  │    │
                              │  │  ・user_profiles (ユーザー情報)    │    │
                              │  └──────────────────────────────────┘    │
                              │                                          │
                              │  設定: data/config_lab.json              │
                              │  (ビーコン座標・ゾーン・フロア外枠 etc.)   │
                              └──────────────────────────────────────────┘
```

---

## 3つのコンポーネントの役割

### 1. エッジデバイス — Raspberry Pi（`edge/`）

各 Raspberry Pi は **2つの役割** を同時に担います。

| 役割 | 詳細 |
|---|---|
| **環境センサー** | BME280（温度・湿度）、BH1750（照度）、MH-Z19C（CO2）の3種のセンサーから値を読み取り、定期的に Flask サーバーの `/api/add_env_data` に POST 送信。`env_get_api.py` が担当 |
| **iBeacon 発信** | Bluetooth で iBeacon 信号を常時発信。UUID は全台共通（`DD05B849-BB42-4AB8-B8F3-798B42440C4E`）、Minor ID（1〜9）で個体を識別。`start_ibeacon.sh` が担当 |

- どちらも `systemd` サービスとして登録し、OS 起動時に自動開始
- 9台のラズパイはフロア内にグリッド状に配置。配置座標は `config_lab.json` の `PI_LOCATIONS` / `BEACON_POSITIONS` で管理

### 2. バックエンドサーバー — Flask（`backend/`）

システムの中核。以下の処理を担当します。

| 処理 | 説明 | 主要ファイル |
|---|---|---|
| **環境データの受信・保存** | ラズパイからのセンサー値を `env_data` テーブルに保存 | `api/routes.py` |
| **三点測位計算** | iPhone から受け取ったBLE距離データを元に、Shapely で3円の交差から位置を推定 | `api/data_provider.py` → `calculate_position_with_shapely()` |
| **境界クランプ** | 測位結果がフロア外枠（`FLOOR_BOUNDARY`）の外に出た場合、最近傍の境界点に補正 | `api/data_provider.py` → `_clamp_to_floor_boundary()` |
| **推定位置の保存・配信** | 測位結果を `estimated_positions` テーブルに保存し、Web/iOS に最新位置を返す | `api/data_provider.py` |
| **おすすめエリア計算** | ユーザーの好みとゾーン別の環境データからおすすめ席を算出 | `api/analysis.py` |
| **ソーシャル機能** | スキル検索・コラボ掲示板・ランチマッチ・交流分析などのAPI | `api/social.py` |
| **設定管理** | `config_lab.json` の読み書き（ビーコン配置・フロア外枠・オブジェクト等） | `api/config_loader.py` |
| **Web ダッシュボード配信** | Jinja2 テンプレート + 静的ファイル（JS/CSS）を配信 | `routes.py`, `frontend/web/` |

### 3. クライアント

#### iOS アプリ（`frontend/ios/`）

SwiftUI で構築された iPhone アプリ。外部ライブラリ不要（iOS 標準フレームワークのみ）。

| 処理 | 説明 | 主要ファイル |
|---|---|---|
| **BLE ビーコン受信** | CoreLocation で9台の iBeacon 電波を受信し、各ビーコンとの距離を測定。30回サンプリングして中央値を算出 | `BeaconManager.swift` |
| **動静検知** | CoreMotion の加速度センサーで移動中/静止中を50Hz で判定。3Dマップの人体モデルの姿勢（立位/座位）に反映 | `BeaconManager.swift` |
| **サーバー測位リクエスト** | 中央値データをサーバーに送信し、三点測位結果を受け取る。サーバー通信失敗時はiPhone内で三点測位のフォールバック計算 | `BeaconManager.swift` |
| **3D フロアマップ** | SceneKit でフロアオブジェクト（壁・机等）と人体モデルを3D描画。環境ヒートマップを重畳表示 | `FloorMap3DView.swift` |
| **ダッシュボード** | センサーデータの数値・グラフ・ヒートマップ・レコメンドを表示 | `NativeDashboardView.swift` |
| **ソーシャル** | スキル検索・コラボ掲示板・ランチマッチ・交流分析 | `SocialView.swift` |
| **管理者設定** | フロアプラン・ビーコン配置・フロア外枠・オブジェクトの編集 | `AdminView.swift` |

#### Web ダッシュボード（`frontend/web/`）

Flask が配信する HTML/JS/CSS。Leaflet.js（2Dマップ）、Three.js（3Dマップ）、Chart.js（グラフ）で環境データと位置を可視化します。

---

## データの流れ — 各処理の詳細

### 処理 A: 環境データ収集（ラズパイ → サーバー → DB）

```
Raspberry Pi                Flask サーバー                 MySQL
┌──────────┐     POST       ┌──────────────┐              ┌──────────┐
│ センサー   │──────────────▶│ /api/add_    │─── INSERT ──▶│ env_data │
│ 読み取り   │ /api/add_    │  env_data    │              │ テーブル  │
│ (30回平均) │  env_data    └──────────────┘              └──────────┘
└──────────┘
```

1. `env_get_api.py` がセンサーから値を30回読み取り、平均値を算出
2. JSON（`ras_pi_id`, `timestamp`, `temperature`, `humidity`, `illuminance`, `co2`）をサーバーに POST
3. サーバーが `env_data` テーブルに保存

### 処理 B: 屋内測位（iPhone → サーバー → DB → iPhone）

```
iPhone                         Flask サーバー               MySQL
┌────────────────┐             ┌─────────────────┐
│ 1. BLE受信      │   POST     │ 3. Shapely      │
│ 2. 30回サンプル  │──────────▶│    三点測位       │
│    → 中央値     │ /api/      │ 4. 境界クランプ   │
│                │ calculate_ │ 5. 座標をレスポンス│
│                │ from_      │                  │
│                │ iphone     │                  │
│                │◀──────────│                  │
│                │  {x, y}   │                  │
│                │            └─────────────────┘
│ 6. 座標を受信   │   POST     ┌─────────────────┐     ┌──────────────┐
│ 7. 位置をサーバー│──────────▶│ 8. DB保存        │────▶│ estimated_   │
│    に送信       │ /api/      │ 9. 座標をレスポンス│     │ positions    │
│                │ add_       │                  │     └──────────────┘
│ 10. UI更新      │ location   │                  │
│    (3Dマップ)   │◀──────────│                  │
└────────────────┘  {x, y}   └─────────────────┘
```

**各ステップの詳細:**

1. **BLE受信**: CoreLocation の iBeacon レンジングで9台のビーコンから RSSI を受信し、`accuracy`（メートル単位）をミリメートルに変換
2. **サンプリング**: 各ビーコンから30回分の距離を収集し、中央値を算出（外れ値の影響を低減）
3. **三点測位**: サーバーが距離が近い3台のビーコンを選択し、Shapely で3つの円（中心=ビーコン座標、半径=距離）の交差領域の重心を計算。交差がない場合は円を段階的に拡大して再試行（最大10回）
4. **境界クランプ**: 測位結果がフロア外枠ポリゴン（`FLOOR_BOUNDARY`）の外にある場合、Shapely の `nearest_points` で最近傍の境界上の点に補正
5. **レスポンス**: クランプ後の座標を iPhone に返す
6. **座標受信 → 位置送信**: iPhone がサーバーから受け取った座標を `/api/add_location` に送信（ユーザー名・部署・動静状態を付与）
7. **DB保存**: `estimated_positions` テーブルに保存
8. **UI更新**: 3D フロアマップ上の人体モデルの位置を更新

**フォールバック**: サーバー通信に失敗した場合、iPhone 内で距離が近い3台を選び、連立方程式による三点測位を実行（`calculateTrilateration` 関数）

### 処理 C: 動静検知（iPhone 内で完結）

```
CoreMotion                BeaconManager              3D フロアマップ
┌──────────────┐          ┌───────────────┐          ┌───────────────┐
│ 加速度センサー  │── 50Hz ─▶│ √(ax²+ay²+az²)│── bool ─▶│ 人体モデル姿勢  │
│ (x, y, z)     │          │ > 0.1G ?      │          │ 立位 or 座位   │
└──────────────┘          └───────────────┘          └───────────────┘
```

- 加速度の大きさが閾値（0.1G）を超えると「移動中」、それ以下は「静止中」
- 結果は `isUserMoving` として3Dマップの人体モデルの姿勢と「移動中/静止中」ラベルに反映
- 移動状態はサーバーにも送信され、`is_moving` カラムに保存

---

## データベース設計

MySQL データベース `sensor_db` に4つのテーブルがあります。

### env_data — 環境センサーデータ

各ラズパイから定期的に送信される温度・湿度・照度・CO2の計測値。

| カラム | 型 | 説明 |
|---|---|---|
| `id` | BIGINT (PK) | 自動採番 |
| `ras_pi_id` | VARCHAR(10) | 送信元ラズパイのID（`ras_01` 〜 `ras_09`） |
| `timestamp` | TIMESTAMP | 計測日時 |
| `temperature` | DECIMAL(5,2) | 温度（℃） |
| `humidity` | DECIMAL(5,2) | 湿度（%） |
| `illuminance` | DECIMAL(7,2) | 照度（lux） |
| `co2` | DECIMAL(7,2) | CO2濃度（ppm） |

### location_data — BLE 生距離データ

iPhone が三点測位計算のためにサーバーに送信した、各ビーコンとの中央値距離。

| カラム | 型 | 説明 |
|---|---|---|
| `id` | BIGINT (PK) | 自動採番 |
| `ras_pi_id` | VARCHAR(10) | ビーコンのラズパイID |
| `beacon_id` | VARCHAR(50) | iPhoneのデバイスID |
| `timestamp` | TIMESTAMP | 受信日時 |
| `distance` | DECIMAL(7,3) | 中央値距離（mm） |
| `actual_distance` | DECIMAL(7,3) | 実測距離（検証用、NULLの場合あり） |

### estimated_positions — 推定位置データ

三点測位で推定されたユーザーの位置情報。

| カラム | 型 | 説明 |
|---|---|---|
| `id` | BIGINT (PK) | 自動採番 |
| `timestamp` | TIMESTAMP | 推定日時 |
| `beacon_id` | VARCHAR(50) | iPhoneのデバイスID |
| `user_name` | VARCHAR(50) | ユーザー名 |
| `job_title` | VARCHAR(50) | 職種 |
| `department` | VARCHAR(50) | 部署 |
| `status` | VARCHAR(20) | ステータス（available/busy/meeting/break） |
| `x` | DECIMAL(10,3) | 推定X座標（mm） |
| `y` | DECIMAL(10,3) | 推定Y座標（mm） |
| `pi_ids_used` | VARCHAR(255) | 測位に使用したビーコンのMinor IDリスト |
| `actual_x` | DECIMAL(10,3) | 正解X座標（検証用） |
| `actual_y` | DECIMAL(10,3) | 正解Y座標（検証用） |
| `calc_method` | VARCHAR(50) | 測位手法（`SHAPELY` / `TRILAT_FALLBACK`） |
| `is_moving` | TINYINT | 移動中フラグ（0=静止中、1=移動中） |

### user_profiles — ユーザープロフィール

ソーシャル機能で使用するユーザー情報。`beacon_id`（iPhoneのデバイスID）が主キー。

| カラム | 型 | 説明 |
|---|---|---|
| `beacon_id` | VARCHAR(50) (PK) | iPhoneのデバイスID |
| `user_name` | VARCHAR(50) | ユーザー名 |
| `job_title` | VARCHAR(50) | 職種 |
| `department` | VARCHAR(50) | 部署 |
| `skills` | TEXT | スキル（カンマ区切り） |
| `hobbies` | TEXT | 趣味（カンマ区切り） |
| `projects` | TEXT | プロジェクト（カンマ区切り） |
| `email` | VARCHAR(100) | メールアドレス |
| `phone` | VARCHAR(30) | 電話番号 |
| `profile_image` | VARCHAR(255) | プロフィール画像パス |

---

## 設定ファイル（config_lab.json）

`backend/data/config_lab.json` がシステム全体の設定を一元管理します。サーバー起動時に `config_loader.py` が読み込み、管理者画面から編集すると上書き保存されます。

| キー | 型 | 説明 |
|---|---|---|
| `PI_LOCATIONS` | 配列（9要素） | 各ラズパイの配置座標。`ras_pi_id`, `x`(mm), `y`(mm), `ip` |
| `BEACON_POSITIONS` | オブジェクト | ラズパイIDをキー、`[x, y]` を値としたビーコン座標マップ。`PI_LOCATIONS` から自動派生 |
| `MINOR_ID_TO_PI_NAME_MAP` | オブジェクト | Minor ID（文字列 "1"〜"9"）→ ラズパイ名（"ras_01"〜"ras_09"）のマッピング |
| `ZONE_MAPPING` | オブジェクト | ゾーン名（"Aエリア"等）→ 所属ラズパイIDの配列 |
| `ZONE_BOUNDARIES` | オブジェクト | 各ゾーンの矩形境界（`x_min`, `x_max`, `y_min`, `y_max`） |
| `FLOOR_BOUNDARY` | 配列（9頂点） | フロア外枠ポリゴンの頂点座標。測位結果がこの外に出ると境界クランプで補正 |
| `FLOOR_OBJECTS` | 配列（60要素） | フロア上のオブジェクト（壁・机・柱・棚・椅子・植物・モニター・窓）。3Dマップ描画に使用 |
| `FLOORPLAN_IMAGE` | オブジェクト | フロアプラン画像の`url`, `width`, `height` |
| `CALIBRATION` | オブジェクト | フロアプラン画像の原点ピクセル座標（`origin_px`）とスケール（`scale_mm_per_px`） |
| `SHAPELY_SETTINGS` | オブジェクト | 三点測位の設定（使用ビーコン数、円拡大率など） |
| `POSITION_STALENESS_MINUTES` | 数値 | 位置データの有効期限（分）。これを超えると「オフライン」扱い |
| `ADMIN_PASSWORD` | 文字列 | 管理者画面のパスワード |
| `BEACON_GROUND_TRUTH` | オブジェクト | 検証用の正解座標（デバイスID → `[x, y]`） |
| `BEACON_ACTUAL_DISTANCES` | オブジェクト | 検証用の実測距離データ |

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
// AppConfig.swift 13行目
static let ngrokURL = "https://ungnarled-bemazed-argelia.ngrok-free.dev"
//                      ↑ ここを自分のサーバーURLに変更
```

ローカルLAN接続の場合:
```swift
static let ngrokURL = "http://192.168.x.x:5001"
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

#### タブ 1: ダッシュボード（NativeDashboardView.swift）

| セクション | 内容 |
|---|---|
| **ユーザー検索** | 名前・スキル・部署で検索。アイコンタップで位置ハイライト（位置あり）またはプロフィール表示（位置なし） |
| **センサー概要カード** | 各拠点の温度・湿度・照度・CO2 を数値表示 |
| **リアルタイムヒートマップ** | SceneKit 3Dフロアマップ上に環境データをヒートマップ重畳。タブで温度/湿度/照度/CO2切替 |
| **お好み選択** | 温度・混雑度・明るさ・湿度・CO2 の好みを設定 → おすすめエリア表示 |
| **時系列チャート** | Charts フレームワークで環境データの時間推移をグラフ表示 |
| **拠点別比較** | 各拠点の環境データを棒グラフで比較 |

**3Dフロアマップの特徴（FloorMap3DView.swift）:**

- **フロアオブジェクト**: 壁・机・柱・棚・植物・椅子・モニター・窓の8種をサーバー設定から読み込み
- **人体モデル（6パーツ）**: 胴体 + 頭 + 両腕 + 両脚
  - 移動中（立位）: 脚は垂直、腕はやや開く
  - 静止中（座位）: 太ももは水平前方、すねは垂直、腕は前方（机に向かう姿勢）
- **空中パルスハイライト**: ユーザーアイコンタップ時にY=1.5mの空中でパルスリング＋垂直ガイドライン表示。タップで解除可能
- **動静ラベル**: 「移動中」「静止中」を3D空間内にオフセット配置

#### タブ 2: ソーシャル（SocialView.swift）

| セクション | 内容 |
|---|---|
| **スキルマッチング** | スキルキーワードで検索。位置あり→ハイライト、位置なし→プロフィール |
| **近くのマッチ** | 半径3m以内でスキル・趣味が合うユーザーを表示 |
| **コラボレーションボード** | ヘルプ募集・ディスカッション・告知の投稿と応答 |
| **ランチマッチング** | 趣味・プロジェクトの共通点でマッチした相手を表示 |
| **交流分析** | 他ユーザーとの交流頻度・履歴を可視化 |

#### タブ 3: プロフィール

ユーザー名・部署・職種・スキル・趣味・プロジェクト・連絡先の編集。プロフィール画像のアップロード。

#### タブ 4: 測位（デバッグ用）

ビーコンの受信状況（RSSI・距離）、サンプリング進捗、測位計算結果をリアルタイム表示。開発・検証時に使用。

#### タブ 5: 管理（AdminView.swift）

パスワード認証後にサーバー設定を編集：
- サーバー接続URL（ローカル / ngrok 切替。LAN自動検出機能あり）
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
| `ngrokURL` | ngrok URL | **必ず変更** — サーバーのデフォルトURL |
| `requestTimeoutInterval` | 3.0秒 | 通信タイムアウト |
| `baseURL` | UserDefaults or ngrokURL | 管理画面で切り替え可能な現在の接続先 |

> ngrok ヘッダー（`ngrok-skip-browser-warning`）が自動付与されます。アプリ内管理画面からURLを動的に切替可能です。

#### ビーコン設定（BeaconConfig）

| 項目 | デフォルト | 説明 |
|---|---|---|
| `targetUUID` | `DD05B849-BB42-4AB8-B8F3-798B42440C4E` | ビーコンのUUID（全9台共通） |
| `coordinates` | 9台の(x,y)座標（mm） | iPhone側に保持するビーコン設置位置。フォールバック計算に使用 |
| `requiredBeaconCount` | 9 | 測位に必要なビーコン台数（全台の中央値が揃ってから計算開始） |
| `sampleCount` | 30 | フォアグラウンドのRSSIサンプル数 |
| `backgroundSampleCount` | 5 | バックグラウンドのサンプル数（実行時間が限られるため少なく） |
| `maxValidDistanceMeters` | 50.0 | この距離を超える測定値は無効として除外 |

#### 動静検知設定（SensorConfig）

| 項目 | デフォルト | 説明 |
|---|---|---|
| `motionDetectionInterval` | 0.02秒(50Hz) | 動静検知ループの更新間隔 |
| `motionThreshold` | 0.1G | この加速度を超えると「移動中」と判定 |

#### ユーザーデフォルト・選択肢

- **UserDefaultsConfig**: 初期ユーザー名「ゲスト」、初期部署「other」など。`@AppStorage` に保存され端末に永続化
- **PickerOptions**: 職種（エンジニア/マネージャー/営業/事務）、部署（開発部/営業部/総務部/その他）、ステータス（取込可/取込中/会議中/休憩中）

### iOS アプリの必要な権限

| 権限 | 用途 | 設定箇所 |
|---|---|---|
| **Bluetooth（常に許可）** | BLE ビーコンの検出 | Info.plist の `NSBluetoothAlwaysUsageDescription` |
| **位置情報（常に許可）** | iBeacon レンジング（バックグラウンド含む） | Info.plist の `NSLocationAlwaysAndWhenInUseUsageDescription` |
| **HTTP通信** | ATS無効化でローカルサーバーへHTTP通信を許可 | Info.plist の `NSAppTransportSecurity` |
| **バックグラウンドモード** | BLE受信とサーバー通信をバックグラウンドで継続 | Signing & Capabilities |

> 本番/App Store公開時は HTTPS に切り替え、ATS を有効化してください。

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
│   │   ├── app.py               #     アプリケーションファクトリ（DB初期化・CORS設定）
│   │   ├── routes.py            #     Web ページルーティング（テンプレート配信）
│   │   └── api/                 #     REST API
│   │       ├── routes.py        #       全APIエンドポイント定義
│   │       ├── data_provider.py #       DB操作・三点測位計算・境界クランプ
│   │       ├── analysis.py      #       密度推定・ゾーン分析・レコメンド
│   │       ├── social.py        #       ソーシャル機能（スキル検索・コラボ等）
│   │       └── config_loader.py #       config_lab.json の読み込み・グローバル変数管理
│   ├── data/                    #   設定ファイル
│   │   ├── config_lab.json      #     ビーコン座標・ゾーン・フロア境界等（主設定）
│   │   └── lab_coord.json       #     フロアプラン座標データ
│   ├── scripts/                 #   DB初期化
│   │   └── init_db.sql          #     テーブル定義・ユーザー作成
│   ├── requirements.txt
│   ├── Makefile
│   ├── setup.sh
│   └── .env.example
│
├── frontend/                    # フロントサイド
│   ├── web/                     #   Web ダッシュボード
│   │   ├── templates/           #     Jinja2 テンプレート（HTML）
│   │   └── static/              #     CSS / JS / 画像
│   └── ios/                     #   iOS アプリ (SwiftUI)
│       ├── Synca.xcodeproj/     #     ← Xcode で開くファイル
│       ├── setup.sh             #     初期セットアップスクリプト
│       ├── tohata-ios-02-Info.plist  # バックグラウンドモード・ATS設定
│       └── tohata_ios_02/       #     Swift ソースコード
│           ├── tohata_ios_02App.swift   # @main エントリーポイント
│           ├── AppConfig.swift          # 全設定値の一元管理
│           ├── ContentView.swift        # 5タブ構成・テーマ色定義
│           ├── Models.swift             # 全APIレスポンスの構造体
│           ├── APIService.swift         # サーバー通信・データ購読（Combine）
│           ├── BeaconManager.swift      # BLE受信・測位・動静検知
│           ├── NativeDashboardView.swift # ダッシュボード・ヒートマップ
│           ├── FloorMap3DView.swift      # SceneKit 3Dフロアマップ・人体モデル
│           ├── SocialView.swift          # スキル検索・コラボ・交流分析
│           ├── DashboardWebView.swift    # WKWebView でWebダッシュボード表示
│           ├── AdminView.swift           # 管理者設定画面
│           └── Assets.xcassets/          # アプリアイコン・フロアプラン画像
│
├── edge/                        # エッジデバイス (Raspberry Pi)
│   ├── env_get_api.py           #   センサー値取得＆API送信（30回平均→POST）
│   ├── start_ibeacon.sh         #   iBeacon 発信（hcitool で BLE アドバタイズ）
│   ├── setup.sh                 #   セットアップスクリプト（依存・systemd登録）
│   ├── requirements.txt
│   └── .env.example
│
├── sample/                      # サンプルデータ（過去の測位結果CSV等）
├── .gitignore
├── LICENSE
└── README.md
```

---

## API エンドポイント一覧

### 環境データ

| メソッド | パス | 説明 | 呼び出し元 |
|---|---|---|---|
| POST | `/api/add_env_data` | 環境データ登録 | Raspberry Pi |
| GET | `/api/sensor-data` | 全拠点の最新センサーデータ取得 | Web / iOS |

### 測位

| メソッド | パス | 説明 | 呼び出し元 |
|---|---|---|---|
| POST | `/api/calculate_from_iphone` | BLE距離データを受け取り三点測位を実行して座標を返す | iOS |
| POST | `/api/add_location` | 測位結果をDBに保存 | iOS |
| POST | `/api/add_raw_data_batch` | BLE生距離データを一括保存（検証用） | iOS |
| GET | `/api/get_iphone_positions` | 全ユーザーの最新推定位置を取得 | Web / iOS |

### フロアプラン・設定

| メソッド | パス | 説明 | 呼び出し元 |
|---|---|---|---|
| GET | `/api/floorplan-data` | フロアプラン座標データ | Web / iOS |
| GET | `/api/app_config` | アプリケーション設定一式 | Web / iOS |
| GET | `/api/recommendations` | おすすめエリア提案（`?temp=cool&occupancy=quiet&light=bright`） | iOS |

### ソーシャル

| メソッド | パス | 説明 | 呼び出し元 |
|---|---|---|---|
| GET | `/api/search_users?q=Python` | ユーザー検索（名前・スキル・部署） | iOS |
| GET | `/api/skill_search?skill=React` | スキルベース検索 | iOS |
| GET | `/api/nearby_matches?beacon_id=xxx` | 近くのマッチングユーザー | iOS |
| GET/POST | `/api/collab_posts` | コラボレーション掲示板の取得・投稿 | iOS |
| POST | `/api/lunch_match/generate` | ランチマッチ自動生成 | iOS |
| GET | `/api/interaction_stats` | 部署間交流の統計 | iOS |

### 管理者

| メソッド | パス | 説明 | 呼び出し元 |
|---|---|---|---|
| POST | `/api/verify_admin_password` | 管理者認証 | iOS / Web |
| POST | `/api/upload_floorplan` | フロアプラン画像アップロード | iOS / Web |
| POST | `/api/update_beacon_config` | ビーコン配置設定の更新 | iOS / Web |
| POST | `/api/update_floor_boundary` | フロア外枠ポリゴンの更新 | iOS / Web |
| POST | `/api/update_floor_objects` | フロアオブジェクト（壁・机等）の更新 | iOS / Web |

---

## 技術スタック

### バックエンド

| ライブラリ | 用途 |
|---|---|
| **Flask** + Flask-CORS + Flask-SQLAlchemy | Web フレームワーク・CORS対応・ORM |
| **MySQL 8.0** (PyMySQL) | データベース |
| **Gunicorn** | 本番 WSGI サーバー |
| **Shapely** | 幾何学計算（三点測位の円交差・境界クランプ） |
| **SciPy** | カーネル密度推定（ゾーン分析） |
| **NumPy / Pandas** | データ処理 |

### Web フロントエンド

| ライブラリ | 用途 |
|---|---|
| **Leaflet.js** | 2D マップ表示 |
| **Three.js** | 3D フロアマップ表示 |
| **Chart.js** | 時系列グラフ・棒グラフ描画 |

### iOS アプリ

すべて iOS 標準フレームワーク。**外部ライブラリは不要**。

| フレームワーク | 用途 |
|---|---|
| **SwiftUI** | 全UI構築 |
| **SceneKit** | 3Dフロアマップ・人体モデル・パルスアニメーション |
| **CoreLocation** | iBeacon レンジング（距離測定） |
| **CoreMotion** | 加速度センサー（動静検知） |
| **Charts** | 時系列・棒グラフ描画 |
| **WebKit** | WKWebView でWebダッシュボード表示 |
| **Network** | ネットワーク状態監視（Wi-Fi/オフライン検出） |
| **Combine** | リアクティブデータバインディング（APIデータ購読） |
| **PhotosUI** | プロフィール画像選択 |
| **UserNotifications** | 近くのマッチ通知 |

### エッジデバイス

| ライブラリ/ツール | 用途 |
|---|---|
| **smbus2** | I2C 通信（BME280・BH1750） |
| **pyserial** | UART 通信（MH-Z19C） |
| **hcitool** | BLE iBeacon アドバタイズ発信 |
| **systemd** | デーモン管理・自動起動 |

---

## 測位の仕組み

### フロー図

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

### 三点測位の詳細（Shapely）

1. iPhone から9台分の中央値距離データを受信
2. 距離が短い順にソートし、**近い3台** を選択
3. 各ビーコンの座標を中心、距離を半径とする **3つの円** を Shapely で生成
4. 3つの円の **交差領域** を計算
5. 交差領域が空（3つの円が重ならない）場合、円を **10% ずつ拡大** して再試行（最大10回）
6. 交差領域の **重心（centroid）** を推定位置とする

### 境界クランプの詳細

- フロアの外枠は `config_lab.json` の `FLOOR_BOUNDARY` に9頂点のポリゴンとして定義
- Shapely の `Polygon.contains()` で測位結果がポリゴン内か判定
- ポリゴン外の場合、`nearest_points()` でポリゴン外周上の最近傍点に補正
- これにより、BLE信号の不安定さで測位結果がフロア外に飛んでも、常にフロア内の座標が返される

### フォールバック（サーバー通信失敗時）

サーバーとの通信に失敗した場合、iPhone 内で以下のフォールバック計算を実行：
1. 距離が近い3台のビーコンを選択
2. 連立方程式による三点測位を実行（`calculateTrilateration` 関数）
3. 計算結果を `TRILAT_FALLBACK` メソッドとしてサーバーに送信

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
5. ngrok 使用時は `ngrok http 5001` でトンネルを起動し、表示された URL をアプリに設定

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

# サービスのログ確認
journalctl -u env_sensing.service -f
journalctl -u ibeacon.service -f
```

---

## ライセンス

**Source Available License** - ソースコードは公開されていますが、利用には制限があります。

- 著作権者および所属組織内での利用・改変・再配布は **自由** です
- 外部の第三者はソースコードの **閲覧のみ** 許可されています
- 外部利用には著作権者の書面による許可が必要です

詳細は [LICENSE](LICENSE) を参照してください。
