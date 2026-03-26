-- ============================================================
--  tohata_web_app データベース初期化スクリプト
--
--  使い方:
--    mysql -u root -p < scripts/init_db.sql
--
--  ※ このスクリプトは何度実行しても安全です。
-- ============================================================

-- データベースの作成
CREATE DATABASE IF NOT EXISTS sensor_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

-- ユーザーの作成（既に存在する場合はスキップ）
CREATE USER IF NOT EXISTS 'flask_reader'@'localhost'
  IDENTIFIED BY 'your-password-here';

-- 権限の付与
GRANT ALL PRIVILEGES ON sensor_db.* TO 'flask_reader'@'localhost';
FLUSH PRIVILEGES;

-- テーブル作成
USE sensor_db;

-- 環境センサーデータ
CREATE TABLE IF NOT EXISTS env_data (
    id          BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    ras_pi_id   VARCHAR(10)  NOT NULL,
    timestamp   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    temperature DECIMAL(5,2),
    humidity    DECIMAL(5,2),
    illuminance DECIMAL(7,2),
    co2         DECIMAL(7,2),
    INDEX idx_env_ras_pi_id (ras_pi_id),
    INDEX idx_env_timestamp (timestamp)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ビーコン生距離データ
CREATE TABLE IF NOT EXISTS location_data (
    id              BIGINT        NOT NULL AUTO_INCREMENT PRIMARY KEY,
    ras_pi_id       VARCHAR(10)   NOT NULL,
    beacon_id       VARCHAR(50)   NOT NULL,
    timestamp       TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    distance        DECIMAL(7,3),
    actual_distance DECIMAL(7,3),
    INDEX idx_loc_ras_pi_id (ras_pi_id),
    INDEX idx_loc_beacon_id (beacon_id),
    INDEX idx_loc_timestamp (timestamp)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 推定位置データ
CREATE TABLE IF NOT EXISTS estimated_positions (
    id           BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    timestamp    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    beacon_id    VARCHAR(50),
    user_name    VARCHAR(50),
    job_title    VARCHAR(50),
    department   VARCHAR(50),
    status       VARCHAR(20),
    obs_x        DECIMAL(10,3),
    obs_y        DECIMAL(10,3),
    kf_x         DECIMAL(10,3),
    kf_y         DECIMAL(10,3),
    est_x        DECIMAL(10,3),
    est_y        DECIMAL(10,3),
    pi_ids_used  VARCHAR(255),
    actual_x     DECIMAL(10,3),
    actual_y     DECIMAL(10,3),
    calc_method  VARCHAR(50),
    is_moving    TINYINT      DEFAULT 0,
    INDEX idx_pos_beacon_id (beacon_id),
    INDEX idx_pos_timestamp (timestamp)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ユーザープロフィールデータ
CREATE TABLE IF NOT EXISTS user_profiles (
    beacon_id     VARCHAR(50)  NOT NULL PRIMARY KEY,
    user_name     VARCHAR(50),
    job_title     VARCHAR(50),
    department    VARCHAR(50),
    skills        TEXT,
    hobbies       TEXT,
    projects      TEXT,
    email         VARCHAR(100),
    phone         VARCHAR(30),
    profile_image VARCHAR(255),
    created_at    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SELECT 'データベース sensor_db の初期化が完了しました。' AS result;
