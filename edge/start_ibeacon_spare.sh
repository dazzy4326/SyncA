#!/bin/bash

# 1. リセット
hciconfig hci0 down
sleep 1
hciconfig hci0 up
sleep 1

# 2. 【重要】発信間隔を 100ms (0.1秒) に設定
# A0 00 = 160 * 0.625ms = 100ms
# cmd 0x08 0x0006 (LE Set Advertising Parameters)
hcitool cmd 0x08 0x0006 A0 00 A0 00 03 00 00 00 00 00 00 00 00 07 00

# 3. iBeaconデータをセット (以前と同じ内容)
# ※ 下の行は各ラズパイごとのMinorIDになっているものを使ってください
# (例: ... 00 01 00 01 C5)
hcitool cmd 0x08 0x0008 1E 02 01 06 1A FF 4C 00 02 15 DD 05 B8 49 BB 42 4A B8 B8 F3 79 8B 42 44 0C 4E 00 01 00 02 C5

# 4. 発信開始 (hciconfig leadv 3 の代わり)
# cmd 0x08 0x000a (LE Set Advertise Enable)
hcitool cmd 0x08 0x000a 01