#!/bin/bash
# エッジデバイス（Raspberry Pi）セットアップスクリプト
# 使い方: chmod +x setup.sh && sudo ./setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CURRENT_USER=${SUDO_USER:-$USER}
VENV_DIR="${SCRIPT_DIR}/venv"

echo "===== エッジデバイス セットアップ開始 ====="
echo "  ディレクトリ: ${SCRIPT_DIR}"
echo "  ユーザー: ${CURRENT_USER}"

# --- 1. I2C・シリアル有効化チェック ---
echo ""
echo "[1/6] I2C・シリアル通信の確認..."
if [ ! -e /dev/i2c-1 ]; then
    echo "  警告: I2Cが無効です。raspi-config で有効化してください："
    echo "    sudo raspi-config → Interface Options → I2C → Enable"
else
    echo "  OK: I2C有効"
fi

if [ ! -e /dev/ttyAMA0 ]; then
    echo "  警告: シリアルポートが無効です。raspi-config で有効化してください："
    echo "    sudo raspi-config → Interface Options → Serial Port"
    echo "    → Login shell: No → Serial hardware: Yes"
else
    echo "  OK: シリアルポート有効"
fi

# --- 2. ユーザーをi2c・dialoutグループに追加 ---
echo ""
echo "[2/6] ユーザー権限の設定..."
for grp in i2c dialout bluetooth; do
    if id -nG "$CURRENT_USER" | grep -qw "$grp"; then
        echo "  OK: $CURRENT_USER は $grp グループに所属済み"
    else
        usermod -aG "$grp" "$CURRENT_USER"
        echo "  追加: $CURRENT_USER を $grp グループに追加しました"
    fi
done

# --- 3. python3-venv のインストール確認 ---
echo ""
echo "[3/6] python3-venv の確認..."
if ! dpkg -l python3-venv >/dev/null 2>&1; then
    echo "  python3-venv をインストール中..."
    apt-get update -qq && apt-get install -y -qq python3-venv python3-full
else
    echo "  OK: python3-venv インストール済み"
fi

# --- 4. 仮想環境の作成と依存パッケージのインストール ---
echo ""
echo "[4/6] Python仮想環境のセットアップ..."
if [ ! -d "$VENV_DIR" ]; then
    echo "  仮想環境を作成中: ${VENV_DIR}"
    sudo -u "$CURRENT_USER" python3 -m venv "$VENV_DIR"
else
    echo "  OK: 仮想環境が存在します"
fi

echo "  依存パッケージをインストール中..."
sudo -u "$CURRENT_USER" "${VENV_DIR}/bin/pip" install --upgrade pip -q
sudo -u "$CURRENT_USER" "${VENV_DIR}/bin/pip" install -r "$SCRIPT_DIR/requirements.txt" -q
echo "  OK: パッケージインストール完了"

# --- 5. .envファイルの準備 ---
echo ""
echo "[5/6] 環境設定ファイルの確認..."
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    chown "$CURRENT_USER":"$CURRENT_USER" "$SCRIPT_DIR/.env"
    echo "  .env.example を .env にコピーしました"
    echo "  ※ .env を編集して RASPBERRY_PI_ID と API_ENDPOINT_URL を設定してください"
else
    echo "  OK: .env ファイルが存在します"
fi

# --- 6. 既存サービスの停止・無効化 → 新サービスの登録 ---
echo ""
echo "[6/6] systemdサービスの登録..."

# 既存の同名サービスが動作中なら停止・無効化してから上書き
for SVC in env_sensing ibeacon; do
    if systemctl is-active --quiet "${SVC}.service" 2>/dev/null; then
        echo "  既存の ${SVC}.service を停止中..."
        systemctl stop "${SVC}.service"
    fi
    if systemctl is-enabled --quiet "${SVC}.service" 2>/dev/null; then
        echo "  既存の ${SVC}.service を無効化中..."
        systemctl disable "${SVC}.service"
    fi
done

# env_sensing.service（venv内のpythonを使用）
ENV_SERVICE="/etc/systemd/system/env_sensing.service"
cat > "$ENV_SERVICE" << EOF
[Unit]
Description=Environment Sensing Python Script
After=network.target

[Service]
ExecStart=${VENV_DIR}/bin/python ${SCRIPT_DIR}/env_get_api.py
WorkingDirectory=${SCRIPT_DIR}
StandardOutput=inherit
StandardError=inherit
Restart=always
RestartSec=10s
User=${CURRENT_USER}
EnvironmentFile=${SCRIPT_DIR}/.env

[Install]
WantedBy=multi-user.target
EOF
echo "  env_sensing.service を登録しました"

# ibeacon.service
IBEACON_SERVICE="/etc/systemd/system/ibeacon.service"
cat > "$IBEACON_SERVICE" << EOF
[Unit]
Description=iBeacon Broadcast Service
After=bluetooth.service network.target
Requires=bluetooth.service

[Service]
Type=oneshot
ExecStart=${SCRIPT_DIR}/start_ibeacon.sh
RemainAfterExit=yes
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
echo "  ibeacon.service を登録しました"

# iBeaconスクリプトに実行権限付与
chmod +x "$SCRIPT_DIR/start_ibeacon.sh"
chmod +x "$SCRIPT_DIR/start_ibeacon_spare.sh"

systemctl daemon-reload
echo "  systemctl daemon-reload 完了"

echo ""
echo "===== セットアップ完了 ====="
echo ""
echo "次のステップ:"
echo "  1. .env を編集: nano ${SCRIPT_DIR}/.env"
echo "  2. start_ibeacon.sh のMinor IDを編集（ラズパイごとに異なる値）"
echo "  3. サービス有効化:"
echo "     sudo systemctl enable --now env_sensing.service"
echo "     sudo systemctl enable --now ibeacon.service"
echo "  4. 動作確認:"
echo "     sudo systemctl status env_sensing.service"
echo "     journalctl -u env_sensing.service -f"
echo ""
echo "  Python仮想環境: ${VENV_DIR}"
echo "  手動実行: ${VENV_DIR}/bin/python ${SCRIPT_DIR}/env_get_api.py"
