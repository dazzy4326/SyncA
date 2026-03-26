import smbus2
import bme280
import serial
import pandas as pd
import os
import time
from datetime import datetime
import json
import requests

# .envファイルから環境変数を読み込み（存在する場合）
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass  # python-dotenv未インストールでも環境変数で動作可能

# **センサー設定**
BME280_ADDRESS = 0x76
BH1750_ADDRESS = 0x23
MHZ19C_PORT = "/dev/ttyAMA0" #このポートはモデルや接続方法によって異なる可能性があります。適宜変更してください。
MHZ19C_BAUDRATE = 9600

# **ラズパイ固有ID (環境変数から取得)**
RASPBERRY_PI_ID = os.environ.get("RASPBERRY_PI_ID", "ras_02")

# --- ▼▼▼ ★2. 接続先を環境変数から取得 ▼▼▼ ---

# **APIサーバーのURL (環境変数から取得)**
API_ENDPOINT_URL = os.environ.get("API_ENDPOINT_URL", "https://your-server.ngrok-free.dev/api/add_env_data")

# --- ▲▲▲ 修正ここまで ▲▲▲ ---

# **I2C バス設定**
bus = smbus2.SMBus(1)
bme280_params = bme280.load_calibration_params(bus, BME280_ADDRESS)

# **計測設定 (環境変数から取得)**
scan_count = int(os.environ.get("SENSOR_SCAN_COUNT", 30))
interval = int(os.environ.get("SENSOR_SCAN_INTERVAL", 1))

# **各センサーからデータを取得する関数 (エラーハンドリング追加)**
def get_bme280_data():
    try:
        data = bme280.sample(bus, BME280_ADDRESS, bme280_params)
        return data.temperature, data.humidity
    except Exception as e:
        print(f"BME280エラー: {e}")
        return None, None

def get_bh1750_data():
    try:
        CONTINUOUS_HIGH_RES_MODE = 0x10
        bus.write_byte(BH1750_ADDRESS, CONTINUOUS_HIGH_RES_MODE)
        time.sleep(0.2)
        data = bus.read_i2c_block_data(BH1750_ADDRESS, 0, 2)
        return ((data[0] << 8) | data[1]) / 1.2
    except Exception as e:
        print(f"BH1750エラー: {e}")
        return None

def get_mhz19c_data():
    try:
        command = bytes([0xFF, 0x01, 0x86, 0x00, 0x00, 0x00, 0x00, 0x00, 0x79])
        with serial.Serial(MHZ19C_PORT, MHZ19C_BAUDRATE, timeout=1) as ser:
            ser.write(command)
            time.sleep(0.1)
            response = ser.read(9)
            if len(response) == 9 and response[0] == 0xFF and response[1] == 0x86:
                return response[2] * 256 + response[3]
    except Exception as e:
        print(f"MHZ19Cエラー: {e}")
    return None

# **データ取得ループ (変更なし)**
def measure_data(scan_count, interval):
    data = []
    print(f"--- {scan_count}回 (間隔{interval}秒) のデータ計測を開始 ---")
    for scan_num in range(1, scan_count + 1):
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        bme_temp, bme_hum = get_bme280_data()
        illuminance = get_bh1750_data()
        co2 = get_mhz19c_data()
        data.append({
            "Scan Number": scan_num, "Timestamp": timestamp,
            "Temperature": bme_temp, "Humidity": bme_hum,
            "Illuminance": illuminance, "CO2": co2
        })
        print(f"  スキャン {scan_num}/{scan_count}: Temp={bme_temp}, Hum={bme_hum}, Lux={illuminance}, CO2={co2}")
        time.sleep(interval)
    print("--- 計測完了 ---")
    return pd.DataFrame(data)


# --- ▼▼▼ ★3. MySQL送信関数を「API送信関数」に置き換え★ ▼▼▼ ---

def send_summary_to_api(df, pi_id):
    """DataFrameを集計し、JSON形式でFlask APIに送信する"""
    
    if df.empty:
        print("データが空のため、APIへの送信をスキップします。")
        return

    # --- 1. データ集計 (変更なし) ---
    print("データを集計しています...")
    try:
        timestamps = pd.to_datetime(df['Timestamp'], errors='coerce').dropna()
        if not timestamps.empty:
            median_timestamp_ns = timestamps.astype(int).median()
            median_timestamp_str = pd.to_datetime(median_timestamp_ns).strftime("%Y-%m-%d %H:%M:%S")
        else:
            median_timestamp_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    except Exception as e:
        print(f"タイムスタンプの中央値計算エラー: {e}")
        median_timestamp_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    avg_temp = df['Temperature'].mean()
    avg_hum = df['Humidity'].mean()
    avg_lux = df['Illuminance'].mean()
    avg_co2 = df['CO2'].mean()

    # --- 2. 送信データ（辞書）の作成 ---
    summary_data = {
        "ras_pi_id": pi_id,
        "timestamp": median_timestamp_str,
        # (NaN (Not a Number) の場合、SQLのNULL (PythonのNone) に変換)
        "temperature": None if pd.isna(avg_temp) else avg_temp,
        "humidity": None if pd.isna(avg_hum) else avg_hum,
        "illuminance": None if pd.isna(avg_lux) else avg_lux,
        "co2": None if pd.isna(avg_co2) else avg_co2
    }
    
    data_json_string = json.dumps(summary_data, indent=2)
    print(f"--- 送信データ (集計結果) ---\n{data_json_string}\n-------------------------")

    # --- 3. APIに送信 (requestsを使用) ---
    try:
        print(f"APIサーバー ({API_ENDPOINT_URL}) に接続しています...")
        
        # タイムアウトを環境変数から取得
        api_timeout = int(os.environ.get("API_TIMEOUT", 10))
        response = requests.post(API_ENDPOINT_URL, json=summary_data, timeout=api_timeout)
        
        # 応答のステータスコードを確認
        if response.status_code == 201: # 201 = Created (成功)
            print(f"データがAPIサーバーに正常に送信されました。 (Status: {response.status_code})")
        else:
            print(f"!!! APIサーバーがエラーを返しました (Status: {response.status_code})")
            print(f"!!! 応答: {response.text}")

    except requests.exceptions.RequestException as err:
        print(f"!!! APIへの送信エラー: {err}")
        print("!!! (Flaskサーバーが起動しているか、IPアドレスとポートが正しいか確認してください)")
    except Exception as e:
        print(f"!!! 予期せぬエラー: {e}")

# **メイン処理 (変更)**
def main():
    # データ取得
    df = measure_data(scan_count, interval)
    
    # CSV保存の代わりに、集計してAPIに送信
    send_summary_to_api(df, RASPBERRY_PI_ID)

if __name__ == "__main__":
    print("--- センサー値取得ループを開始します ---")
    while True: 
        try:
            main()
        
        except KeyboardInterrupt:
            # Ctrl+C で停止できるようにする
            print("\n--- 無限ループを停止しました ---")
            break
        except Exception as e:
            # もしセンサーエラーなどでmain()が失敗しても...
            print(f"!!! メインループでエラーが発生: {e}")
            retry_delay = int(os.environ.get("RETRY_DELAY", 5))
            print(f"!!! {retry_delay}秒後に処理を再試行します...")
            time.sleep(retry_delay) # 環境変数で設定した秒数待ってから次のループに進む