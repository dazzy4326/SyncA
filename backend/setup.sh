#!/usr/bin/env bash
# ============================================================
#  SyncA バックエンド セットアップスクリプト
#  どの PC でも同じ手順で環境を構築できるようにするワンコマンドスクリプト
#
#  ※ backend/ ディレクトリで実行してください
#
#  使い方:
#    cd backend
#    chmod +x setup.sh
#    ./setup.sh
# ============================================================
set -euo pipefail

# ---------- 色付き出力 ----------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ---------- 事前チェック ----------
info "=== tohata_web_app 環境セットアップを開始します ==="
echo

# Python のバージョン確認
REQUIRED_PYTHON_MAJOR=3
REQUIRED_PYTHON_MINOR=9

if ! command -v python3 &>/dev/null; then
    error "python3 が見つかりません。Python ${REQUIRED_PYTHON_MAJOR}.${REQUIRED_PYTHON_MINOR}+ をインストールしてください。"
    exit 1
fi

PY_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PY_MAJOR=$(echo "$PY_VERSION" | cut -d. -f1)
PY_MINOR=$(echo "$PY_VERSION" | cut -d. -f2)

if [[ "$PY_MAJOR" -lt "$REQUIRED_PYTHON_MAJOR" ]] || \
   { [[ "$PY_MAJOR" -eq "$REQUIRED_PYTHON_MAJOR" ]] && [[ "$PY_MINOR" -lt "$REQUIRED_PYTHON_MINOR" ]]; }; then
    error "Python ${REQUIRED_PYTHON_MAJOR}.${REQUIRED_PYTHON_MINOR}+ が必要です (現在: ${PY_VERSION})"
    exit 1
fi
info "Python ${PY_VERSION} を検出しました ✓"

# MySQL の確認
if command -v mysql &>/dev/null; then
    info "MySQL クライアントを検出しました ✓"
else
    warn "mysql コマンドが見つかりません。データベースの自動セットアップはスキップされます。"
fi

# ---------- 1. 仮想環境の作成 ----------
VENV_DIR=".venv"

if [[ -d "$VENV_DIR" ]]; then
    info "仮想環境 ($VENV_DIR) は既に存在します。スキップします。"
else
    info "仮想環境を作成しています..."
    python3 -m venv "$VENV_DIR"
    info "仮想環境を作成しました ✓"
fi

# 仮想環境をアクティベート
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
info "仮想環境をアクティベートしました ($(which python))"

# ---------- 2. pip のアップグレード ----------
info "pip をアップグレードしています..."
pip install --upgrade pip --quiet

# ---------- 3. 依存パッケージのインストール ----------
info "依存パッケージをインストールしています..."
pip install -r requirements.txt --quiet
info "依存パッケージをインストールしました ✓"

# ---------- 4. .env ファイルの生成 ----------
if [[ -f ".env" ]]; then
    info ".env ファイルは既に存在します。スキップします。"
else
    if [[ -f ".env.example" ]]; then
        cp .env.example .env
        info ".env.example → .env をコピーしました"
        warn "⚠️  .env を開いて、DB 接続情報などを環境に合わせて編集してください。"
    else
        error ".env.example が見つかりません。手動で .env を作成してください。"
    fi
fi

# ---------- 5. データベースの初期化（オプション） ----------
echo
read -rp "データベースを自動セットアップしますか？ (y/N): " SETUP_DB
if [[ "${SETUP_DB,,}" == "y" ]]; then
    if ! command -v mysql &>/dev/null; then
        error "mysql コマンドが見つからないため、DB セットアップをスキップします。"
    else
        # .env から DB 情報を読み込み
        DB_USER=$(grep '^DB_USER=' .env 2>/dev/null | cut -d= -f2 || echo "flask_reader")
        DB_PASSWORD=$(grep '^DB_PASSWORD=' .env 2>/dev/null | cut -d= -f2 || echo "changeme")
        DB_HOST=$(grep '^DB_HOST=' .env 2>/dev/null | cut -d= -f2 || echo "localhost")
        DB_NAME=$(grep '^DB_NAME=' .env 2>/dev/null | cut -d= -f2 || echo "sensor_db")

        read -rsp "MySQL root パスワードを入力してください: " MYSQL_ROOT_PW
        echo

        info "データベースを初期化しています..."
        if mysql -u root -p"${MYSQL_ROOT_PW}" -h "${DB_HOST}" < scripts/init_db.sql 2>/dev/null; then
            info "データベースを初期化しました ✓"
        else
            error "データベースの初期化に失敗しました。手動で scripts/init_db.sql を実行してください。"
        fi
    fi
else
    info "DB セットアップをスキップしました。後で手動セットアップする場合は:"
    info "  mysql -u root -p < scripts/init_db.sql"
fi

# ---------- 6. 完了メッセージ ----------
echo
info "============================================"
info "  セットアップが完了しました！ 🎉"
info "============================================"
echo
info "次のステップ:"
echo "  1. .env ファイルを確認・編集:"
echo "       nano .env"
echo
echo "  2. 仮想環境をアクティベート (新しいターミナルで):"
echo "       source ${VENV_DIR}/bin/activate"
echo
echo "  3. 開発サーバーを起動:"
echo "       flask --app src.app:create_app run --host 0.0.0.0 --port 5001 --debug"
echo
echo "  4. または本番サーバーを起動:"
echo "       gunicorn -w 4 'src.app:create_app()' -b '0.0.0.0:5001'"
echo
echo "  ブラウザで http://localhost:5001/ を開いてください。"
echo
