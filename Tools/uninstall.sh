#!/usr/bin/env bash
set -uo pipefail

# ==============================================================================
# 好注音 (HaoZhuyin) 完整移除工具
# 移除所有安裝位置的複本、TIS 啟用狀態、LaunchServices 殘留註冊與 pkg 收據。
# ==============================================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="HaoZhuyin"
APP_ID="org.antigravity.inputmethod.HaoZhuyin"
USER_APP="$HOME/Library/Input Methods/$APP_NAME.app"
SYSTEM_APP="/Library/Input Methods/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

echo "================================================================="
echo "  [好注音] 正在徹底移除輸入法並清理 macOS 殘留註冊..."
echo "================================================================="

# 1. 在 TIS 中停用所有輸入來源（必須在刪除檔案前，由 App 本身執行）
echo "[1/6] 停用 Text Input Sources 中的所有好注音來源..."
REGISTRAR=""
for candidate in "$USER_APP" "$SYSTEM_APP" "$PROJECT_ROOT/build/$APP_NAME.app"; do
    if [ -x "$candidate/Contents/MacOS/$APP_NAME" ]; then
        REGISTRAR="$candidate/Contents/MacOS/$APP_NAME"
        break
    fi
done
if [ -n "$REGISTRAR" ]; then
    "$REGISTRAR" --unregister || true
else
    echo "    找不到可執行的 App，略過（刪除檔案後系統會自動移除來源）。"
fi

# 2. 關閉運行中的程序
echo "[2/6] 關閉背景程序..."
pkill -9 -x "$APP_NAME" 2>/dev/null || true

# 3. 卸載可能掛載中的安裝磁碟
echo "[3/6] 檢查並卸載掛載中的安裝磁碟..."
for vol in /Volumes/好注音*; do
    if [ -d "$vol" ]; then
        echo "    卸載磁碟區: $vol"
        hdiutil detach "$vol" -force >/dev/null 2>&1 || true
    fi
done

# 4. 從 LaunchServices 註銷所有 HaoZhuyin.app 路徑（含已不存在的幽靈路徑）
echo "[4/6] 從 LaunchServices 註銷所有殘留路徑..."
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -dump 2>/dev/null \
        | sed -n 's/^path:[[:space:]]*\(.*'"$APP_NAME"'\.app\) (0x[0-9a-f]*)$/\1/p' \
        | sort -u \
        | while IFS= read -r p; do
            [ -n "$p" ] || continue
            echo "    註銷: $p"
            "$LSREGISTER" -u "$p" 2>/dev/null || true
        done
fi

# 5. 移除檔案與 pkg 安裝收據
echo "[5/6] 移除安裝檔案..."
rm -rf "$USER_APP"
if [ -e "$SYSTEM_APP" ]; then
    rm -rf "$SYSTEM_APP" 2>/dev/null || true
    if [ -e "$SYSTEM_APP" ]; then
        echo "    使用 sudo 移除 $SYSTEM_APP（可能需要密碼）..."
        sudo rm -rf "$SYSTEM_APP" || echo "    ⚠️ 無法移除 $SYSTEM_APP"
    fi
fi
if pkgutil --pkg-info "$APP_ID" >/dev/null 2>&1; then
    echo "    移除 pkg 安裝收據 ($APP_ID)..."
    sudo pkgutil --forget "$APP_ID" >/dev/null 2>&1 || true
fi

# 專案 build 目錄中的 .app 與舊版暫存目錄（可能被舊版 pkg 以 root 寫入）
for p in "$PROJECT_ROOT/build/$APP_NAME.app" "$PROJECT_ROOT/build/pkg_payload" \
         "$PROJECT_ROOT/build/payload" "$PROJECT_ROOT/build/dmg_root" "$PROJECT_ROOT/build/pkg_scripts"; do
    [ -e "$p" ] || continue
    rm -rf "$p" 2>/dev/null || sudo rm -rf "$p" || true
done

# 6. 刷新輸入法選單
echo "[6/6] 刷新系統輸入法選單 (TextInputMenuAgent / TextInputSwitcher)..."
killall TextInputMenuAgent 2>/dev/null || true
killall TextInputSwitcher 2>/dev/null || true

echo ""
echo "================================================================="
echo "  🎉 清理完成！"
echo "  可前往「系統設定」>「鍵盤」>「輸入方式」確認清單已恢復乾淨。"
echo "================================================================="
