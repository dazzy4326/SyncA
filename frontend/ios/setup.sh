#!/bin/bash
# ============================================================
#  tohata_ios_02 — 初期セットアップスクリプト
#  
#  他の PC でクローン後に実行してください。
#  サーバー IP と開発チーム ID を対話的に設定します。
#
#  使い方:
#    chmod +x setup.sh
#    ./setup.sh
# ============================================================

set -e

# --- 色定義 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_CONFIG="${SCRIPT_DIR}/tohata_ios_02/AppConfig.swift"
PBXPROJ="${SCRIPT_DIR}/tohata_ios_02.xcodeproj/project.pbxproj"

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  tohata_ios_02 初期セットアップ${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# ---- 1. AppConfig.swift の存在確認 ----
if [ ! -f "$APP_CONFIG" ]; then
    echo -e "${RED}エラー: AppConfig.swift が見つかりません。${NC}"
    echo "  パス: $APP_CONFIG"
    exit 1
fi

if [ ! -f "$PBXPROJ" ]; then
    echo -e "${RED}エラー: project.pbxproj が見つかりません。${NC}"
    echo "  パス: $PBXPROJ"
    exit 1
fi

# ---- 2. サーバー IP アドレスの設定 ----
echo -e "${YELLOW}【1/2】 サーバー IP アドレスの設定${NC}"
echo ""

# 現在のサーバー URL を取得
CURRENT_URL=$(grep 'static let baseURL' "$APP_CONFIG" | sed 's/.*"\(.*\)".*/\1/')
echo -e "  現在の設定: ${CYAN}${CURRENT_URL}${NC}"
echo ""
read -p "  新しいサーバー URL を入力してください (例: http://192.168.1.100:5001)
  [Enter でスキップ]: " NEW_URL

if [ -n "$NEW_URL" ]; then
    # URL の簡易バリデーション
    if [[ ! "$NEW_URL" =~ ^https?:// ]]; then
        echo -e "${RED}  エラー: URL は http:// または https:// で始まる必要があります。${NC}"
        exit 1
    fi
    
    # エスケープ処理 (sed 用)
    ESCAPED_CURRENT=$(echo "$CURRENT_URL" | sed 's/[&/\]/\\&/g')
    ESCAPED_NEW=$(echo "$NEW_URL" | sed 's/[&/\]/\\&/g')
    
    sed -i '' "s|${ESCAPED_CURRENT}|${ESCAPED_NEW}|g" "$APP_CONFIG"
    echo -e "  ${GREEN}✅ サーバー URL を変更しました: ${NEW_URL}${NC}"
else
    echo -e "  ⏭️  スキップしました (変更なし)"
fi
echo ""

# ---- 3. Development Team の設定 ----
echo -e "${YELLOW}【2/2】 Apple Development Team ID の設定${NC}"
echo ""
echo "  Xcode → Settings → Accounts → Apple ID で確認できます。"
echo "  (例: ABCDE12345)"
echo ""

# 現在の値を取得
CURRENT_TEAM=$(grep -m1 'DEVELOPMENT_TEAM' "$PBXPROJ" | sed 's/.*= *"\?\([^";]*\)"\?;.*/\1/')
if [ -n "$CURRENT_TEAM" ] && [ "$CURRENT_TEAM" != '""' ] && [ "$CURRENT_TEAM" != "" ]; then
    echo -e "  現在の設定: ${CYAN}${CURRENT_TEAM}${NC}"
else
    echo -e "  現在の設定: ${RED}(未設定)${NC}"
fi
echo ""
read -p "  Development Team ID を入力してください
  [Enter でスキップ (Xcode で後から設定可能)]: " NEW_TEAM

if [ -n "$NEW_TEAM" ]; then
    sed -i '' "s/DEVELOPMENT_TEAM = \"[^\"]*\";/DEVELOPMENT_TEAM = \"${NEW_TEAM}\";/g" "$PBXPROJ"
    # 引用符なしパターンにも対応
    sed -i '' "s/DEVELOPMENT_TEAM = [^;\"]*;/DEVELOPMENT_TEAM = \"${NEW_TEAM}\";/g" "$PBXPROJ"
    echo -e "  ${GREEN}✅ Development Team を設定しました: ${NEW_TEAM}${NC}"
else
    echo -e "  ⏭️  スキップしました (Xcode の Signing & Capabilities で設定してください)"
fi

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${GREEN}  セットアップ完了！${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""
echo "  次のステップ:"
echo "    1. Xcode でプロジェクトを開く:"
echo "       open tohata_ios_02.xcodeproj"
echo ""
echo "    2. Signing & Capabilities で Team が設定されているか確認"
echo ""
echo "    3. 実機 iPhone を接続してビルド & 実行"
echo ""
echo "  設定ファイル:"
echo "    - サーバー URL / ビーコン設定 → tohata_ios_02/AppConfig.swift"
echo "    - Xcode プロジェクト設定      → Xcode の GUI で操作"
echo ""
