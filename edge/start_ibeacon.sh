#!/bin/bash

# 設定セクション
# ----------------------------------------
# 1. iOSアプリ側で設定したUUID (ハイフン無しで)
UUID="DD05B849BB424AB8B8F3798B42440C4E"

# 2. このビーコンの Major ID (これはアプリで設定したものと一致させる)
MAJOR="0001"

# 3. このビーコンの Minor ID (ラズパイごとに割り当てるもの)
MINOR="0001"

# 4. 送信強度 (TX Power)
# iPhone側で距離を推定するために使われます。
# 一般的に -59dBm (C5) が使われます。
TX_POWER="C5"
# ----------------------------------------


# Bluetoothデバイス (通常は hci0)
HCI_DEVICE="hci0"

# 1. Bluetoothデバイスをリセットし、起動（sleepで安定化）
hciconfig $HCI_DEVICE down
sleep 1
hciconfig $HCI_DEVICE up
sleep 1

# 2. 発信間隔を100ms (0.1秒) に設定
# A0 00 = 160 * 0.625ms = 100ms
# cmd 0x08 0x0006 (LE Set Advertising Parameters)
echo "発信間隔を100msに設定中..."
hcitool -i $HCI_DEVICE cmd 0x08 0x0006 A0 00 A0 00 03 00 00 00 00 00 00 00 00 07 00

# 3. iBeaconのフォーマットに従ったアドバタイズパケットを構築
# フラグバイト 06 = LE General Discoverable + BR/EDR Not Supported（BLE専用の標準フラグ）
IBEACON_PREFIX="1E 02 01 06 1A FF 4C 00 02 15"

# UUIDをスペース区切りの16進数に変換
UUID_HEX=$(echo $UUID | sed 's/\(..\)/\1 /g')

# Major, Minorをスペース区切りの16進数に変換
MAJOR_HEX=$(echo $MAJOR | sed 's/\(..\)/\1 /g')
MINOR_HEX=$(echo $MINOR | sed 's/\(..\)/\1 /g')

# 4. アドバタイズパケットを設定 (hcitool を使用)
echo "iBeaconパケットを設定中..."
hcitool -i $HCI_DEVICE cmd 0x08 0x0008 \
$IBEACON_PREFIX \
$UUID_HEX \
$MAJOR_HEX \
$MINOR_HEX \
$TX_POWER

# 5. アドバタイズ（発信）を開始
# hciconfig leadv ではなく直接HCIコマンドで開始（パラメータを上書きしない）
# cmd 0x08 0x000a (LE Set Advertise Enable)
echo "アドバタイズを開始します (UUID: $UUID, Major: $MAJOR, Minor: $MINOR)"
hcitool -i $HCI_DEVICE cmd 0x08 0x000a 01

echo "--- iBeaconとして動作中 ---"
echo "(停止するには 'hcitool -i $HCI_DEVICE cmd 0x08 0x000a 00' を実行してください)"
