# ============================================================
#  SyncA バックエンド Makefile
#  よく使うコマンドをショートカットとしてまとめたファイル
#
#  ※ backend/ ディレクトリで実行してください
#
#  使い方:
#    make setup     … 初回セットアップ（仮想環境 + パッケージ + .env）
#    make run       … 開発サーバー起動
#    make run-prod  … 本番サーバー起動 (Gunicorn)
#    make db-init   … データベース初期化
#    make clean     … 仮想環境・キャッシュを削除
# ============================================================

SHELL      := /bin/bash
VENV_DIR   := .venv
PYTHON     := $(VENV_DIR)/bin/python
PIP        := $(VENV_DIR)/bin/pip
FLASK      := $(VENV_DIR)/bin/flask
GUNICORN   := $(VENV_DIR)/bin/gunicorn

HOST       := 0.0.0.0
PORT       := 5001

.PHONY: help setup venv install env run run-prod db-init clean check

# ---------- デフォルト: ヘルプ ----------
help: ## このヘルプを表示
	@echo ""
	@echo "使い方: make <target>"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@echo ""

# ---------- 一括セットアップ ----------
setup: venv install env ## 初回セットアップ（仮想環境 + パッケージ + .env）
	@echo ""
	@echo "✅ セットアップ完了！"
	@echo "   次のステップ:"
	@echo "     1. .env を確認・編集: nano .env"
	@echo "     2. DB 初期化:        make db-init"
	@echo "     3. サーバー起動:     make run"

# ---------- 仮想環境 ----------
venv: ## Python 仮想環境を作成
	@if [ ! -d "$(VENV_DIR)" ]; then \
		echo "仮想環境を作成しています..."; \
		python3 -m venv $(VENV_DIR); \
		echo "✓ 仮想環境を作成しました"; \
	else \
		echo "✓ 仮想環境は既に存在します"; \
	fi

# ---------- パッケージインストール ----------
install: venv ## 依存パッケージをインストール
	$(PIP) install --upgrade pip --quiet
	$(PIP) install -r requirements.txt --quiet
	@echo "✓ パッケージをインストールしました"

# ---------- .env ----------
env: ## .env ファイルを作成（なければ .env.example からコピー）
	@if [ ! -f ".env" ]; then \
		cp .env.example .env; \
		echo "✓ .env.example → .env をコピーしました"; \
		echo "⚠️  .env を編集してください: nano .env"; \
	else \
		echo "✓ .env は既に存在します"; \
	fi

# ---------- 開発サーバー ----------
run: ## 開発サーバーを起動 (Flask)
	$(FLASK) --app src.app:create_app run --host $(HOST) --port $(PORT) --debug

# ---------- 本番サーバー ----------
run-prod: ## 本番サーバーを起動 (Gunicorn)
	$(GUNICORN) -w 4 'src.app:create_app()' -b '$(HOST):$(PORT)'

# ---------- DB 初期化 ----------
db-init: ## MySQL データベースを初期化
	@echo "MySQL root パスワードを入力してください:"
	@mysql -u root -p < scripts/init_db.sql
	@echo "✓ データベースを初期化しました"

# ---------- 環境チェック ----------
check: ## Python・MySQL の動作確認
	@echo "=== 環境チェック ==="
	@echo -n "Python:  "; python3 --version
	@echo -n "pip:     "; $(PIP) --version 2>/dev/null || echo "未インストール (make setup を実行)"
	@echo -n "MySQL:   "; mysql --version 2>/dev/null || echo "未検出"
	@echo -n ".env:    "; test -f .env && echo "あり ✓" || echo "なし ⚠️ (make env を実行)"
	@echo -n "venv:    "; test -d $(VENV_DIR) && echo "あり ✓" || echo "なし ⚠️ (make setup を実行)"

# ---------- クリーン ----------
clean: ## 仮想環境・キャッシュを削除
	rm -rf $(VENV_DIR)
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true
	@echo "✓ クリーンアップ完了"
