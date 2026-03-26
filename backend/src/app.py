from flask import Flask
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
import os
import logging

logger = logging.getLogger(__name__)

# .envファイルがあれば読み込む (python-dotenv)
try:
    from dotenv import load_dotenv
    # プロジェクトルートの .env を探す (src/app.py → ../.env)
    _env_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '.env')
    _loaded = load_dotenv(_env_path, override=True)
    if not _loaded:
        # フォールバック: find_dotenv() で自動探索
        from dotenv import find_dotenv
        load_dotenv(find_dotenv(), override=True)
except ImportError:
    pass  # python-dotenv がインストールされていない場合はスキップ

# インスタンスを "外" で作成 (他のファイルからインポートされる)
db = SQLAlchemy()

# プロジェクトルート (backend/ の親ディレクトリ) を基準にパスを解決
_BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_PROJECT_ROOT = os.path.dirname(_BACKEND_DIR)

# Flaskアプリケーションのインスタンスを作成する処理を関数にまとめる
def create_app():
    app = Flask(
        __name__,
        template_folder=os.path.join(_PROJECT_ROOT, 'frontend', 'web', 'templates'),
        static_folder=os.path.join(_PROJECT_ROOT, 'frontend', 'web', 'static'),
    )

    app.debug = os.environ.get('FLASK_DEBUG', 'False').lower() in ('true', '1', 'yes')

    CORS(app) # CORSを先に設定

    # --- データベース設定 (環境変数から取得) ---
    _default_password = 'changeme'
    db_user = os.environ.get('DB_USER', 'flask_reader')
    db_password = os.environ.get('DB_PASSWORD', _default_password)
    db_host = os.environ.get('DB_HOST', 'localhost')
    db_name = os.environ.get('DB_NAME', 'sensor_db')

    if db_password == _default_password:
        logger.warning(
            "DB_PASSWORD が環境変数で設定されていません。デフォルトのパスワードを使用しています。"
            ".env ファイルで DB_PASSWORD を設定してください。"
        )

    app.config['SQLALCHEMY_DATABASE_URI'] = \
        f'mysql+pymysql://{db_user}:{db_password}@{db_host}/{db_name}'
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

    # 接続プール設定 (高負荷時の接続枯渇を防ぐ)
    app.config['SQLALCHEMY_ENGINE_OPTIONS'] = {
        'pool_size': 10,
        'pool_recycle': 300,   # 5分でコネクションを再利用
        'pool_pre_ping': True, # 切断されたコネクションを自動検出
        'max_overflow': 5,
    }

    # 'init_app' を使ってアプリと 'db' を関連付ける
    db.init_app(app)

    # --- Blueprintの登録 ---
    # src/api/routes.py から api_bp をインポート
    try:
        from .api.routes import api_bp
        app.register_blueprint(api_bp)

        from .routes import routes_bp
        app.register_blueprint(routes_bp)
    except ImportError as e:
        logger.error(f"Blueprint のインポートに失敗しました: {e}")

    return app

# このファイル (app.py) を直接実行したときにサーバーが起動するようにします
if __name__ == '__main__':
    app = create_app()
    # Gunicornから実行されることを想定し、app.runは直接使わない
    # 開発用に実行する場合は、以下のコメントを解除
    # app.run(debug=True, host='0.0.0.0', port=5001)
    pass # 何も実行しない