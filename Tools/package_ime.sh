#!/bin/bash
set -euo pipefail

# ==============================================================================
# HaoZhuyin (好注音) macOS Input Method Packaging & Installation Tool
#
# 安裝策略（單一目錄原則）：
#   --install  開發用，安裝至 ~/Library/Input Methods（不需管理者權限）
#   --pkg      發布用，安裝至 /Library/Input Methods（pkg 不可重新定位）
#   兩種方式互斥：任一方式安裝前都會移除另一處的複本，
#   並清除 LaunchServices 中所有其他路徑的殘留註冊（如 build/…）。
# ==============================================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

export COPYFILE_DISABLE=1

# Detect and configure developer toolchain
if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

BUILD_DIR="$PROJECT_ROOT/build"
DIST_DIR="$PROJECT_ROOT/dist"
APP_NAME="HaoZhuyin"
APP_ID="org.antigravity.inputmethod.HaoZhuyin"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
INFO_PLIST_SRC="Sources/HaoZhuyin/Resources/Info.plist"
USER_INSTALL_DIR="$HOME/Library/Input Methods"
SYSTEM_INSTALL_DIR="/Library/Input Methods"
PKG_PATH="$DIST_DIR/$APP_NAME-Installer.pkg"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
PLISTBUDDY="/usr/libexec/PlistBuddy"

APP_VERSION="$("$PLISTBUDDY" -c 'Print :CFBundleShortVersionString' "$INFO_PLIST_SRC")"
# 每次建置遞增 CFBundleVersion，迫使 LaunchServices / TIS 重新讀取 Info.plist 與圖示，
# 避免沿用舊快取（名稱、圖示不更新或設定中不出現）。
BUILD_NUMBER="$(date +%Y%m%d%H%M%S)"

DO_INSTALL=false
DO_PKG=false
DO_NOTARIZE=false
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-AC_PASSWORD}"

usage() {
    echo "用法: $0 [選項]"
    echo "  (無參數)         建置並安裝至 ~/Library/Input Methods"
    echo "  --install        建置並安裝至 ~/Library/Input Methods（開發用）"
    echo "  --pkg            產生 dist/$APP_NAME-Installer.pkg（安裝至 /Library/Input Methods）"
    echo "  --notarize       產生 pkg、簽名並提交至 Apple 公證與 Staple (需設定環境變數或參數)"
    echo "  --sign-id <id>   指定 Developer ID Application 憑證名稱或 SHA"
    echo "  --pkg-sign <id>  指定 Developer ID Installer 憑證名稱或 SHA"
    echo "  --profile <name> 指定 notarytool keychain-profile (預設: AC_PASSWORD)"
    echo "  --build-only     僅建置 build/$APP_NAME.app"
}

if [ $# -eq 0 ]; then
    DO_INSTALL=true
else
    while [ $# -gt 0 ]; do
        case "$1" in
            --install)    DO_INSTALL=true; shift ;;
            --pkg)        DO_PKG=true; shift ;;
            --notarize)   DO_PKG=true; DO_NOTARIZE=true; shift ;;
            --sign-id)    SIGN_IDENTITY="$2"; shift 2 ;;
            --pkg-sign)   INSTALLER_SIGN_IDENTITY="$2"; shift 2 ;;
            --profile)    KEYCHAIN_PROFILE="$2"; shift 2 ;;
            --build-only) shift ;;
            -h|--help)    usage; exit 0 ;;
            *)            echo "未知選項: $1"; usage; exit 1 ;;
        esac
    done
fi

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

# 列出 LaunchServices 中所有已註冊的 HaoZhuyin.app 路徑
list_registered_paths() {
    [ -x "$LSREGISTER" ] || return 0
    "$LSREGISTER" -dump 2>/dev/null \
        | sed -n 's/^path:[[:space:]]*\(.*'"$APP_NAME"'\.app\) (0x[0-9a-f]*)$/\1/p' \
        | sort -u
}

# 註銷所有「非 $1」的 HaoZhuyin.app 註冊（含已不存在的幽靈路徑）
purge_stale_registrations() {
    local keep="${1:-}"
    [ -x "$LSREGISTER" ] || return 0
    list_registered_paths | while IFS= read -r p; do
        [ -n "$p" ] || continue
        [ "$p" = "$keep" ] && continue
        echo "    註銷殘留註冊: $p"
        "$LSREGISTER" -u "$p" 2>/dev/null || true
    done
}

unregister_path() {
    [ -x "$LSREGISTER" ] && "$LSREGISTER" -u "$1" 2>/dev/null || true
}

# 刪除路徑；若因權限不足（例如被舊版 pkg 以 root 寫入）則改用 sudo
remove_path() {
    local p="$1"
    [ -e "$p" ] || return 0
    unregister_path "$p"
    if ! rm -rf "$p" 2>/dev/null || [ -e "$p" ]; then
        echo "    需要管理者權限以移除: $p"
        sudo rm -rf "$p"
    fi
}

stop_running_ime() {
    pkill -9 -x "$APP_NAME" 2>/dev/null || true
    # 等待程序完全結束，避免檔案替換期間被系統重新喚醒
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
        sleep 0.1
    done
}

refresh_input_menu() {
    killall TextInputMenuAgent 2>/dev/null || true
    killall TextInputSwitcher 2>/dev/null || true
}

echo "================================================================="
echo "  [好注音] macOS 系統輸入法自動建置與打包作業開始"
echo "  版本 $APP_VERSION (build $BUILD_NUMBER)"
echo "================================================================="

# ------------------------------------------------------------------------------
# 1. Compile release binary
# ------------------------------------------------------------------------------
echo "==> [1/4] 編譯 Release 執行檔 ($APP_NAME)..."
swift build -c release --product "$APP_NAME"

# ------------------------------------------------------------------------------
# 2. Generate icons
# ------------------------------------------------------------------------------
echo "==> [2/4] 生成選單列「好」字圖標與 AppIcon..."
mkdir -p "$BUILD_DIR/Resources"
swift Tools/generate_icons.swift "$BUILD_DIR/Resources"

# ------------------------------------------------------------------------------
# 3. Assemble App Bundle
# ------------------------------------------------------------------------------
echo "==> [3/4] 組裝 $APP_NAME.app 應用程式包..."
# 清除舊版腳本遺留的暫存目錄（其中的 .app 會被 LaunchServices 當成另一份輸入法）
remove_path "$BUILD_DIR/pkg_payload"
remove_path "$BUILD_DIR/payload"
remove_path "$BUILD_DIR/pkg_scripts"
remove_path "$APP_BUNDLE"

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/zh-Hant.lproj"
mkdir -p "$APP_BUNDLE/Contents/Resources/en.lproj"

cp ".build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$INFO_PLIST_SRC" "$APP_BUNDLE/Contents/Info.plist"
"$PLISTBUDDY" -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

cp "Sources/HaoZhuyin/Resources/zh-Hant.lproj/InfoPlist.strings" "$APP_BUNDLE/Contents/Resources/zh-Hant.lproj/"
cp "Sources/HaoZhuyin/Resources/en.lproj/InfoPlist.strings" "$APP_BUNDLE/Contents/Resources/en.lproj/"

cp "$BUILD_DIR/Resources/MenuIcon.tiff" "$APP_BUNDLE/Contents/Resources/"
cp "$BUILD_DIR/Resources/MenuIcon.png" "$APP_BUNDLE/Contents/Resources/"
cp "$BUILD_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"

if [ -d ".build/release/ZhuyinEngine_ZhuyinEngine.bundle" ]; then
    cp -R ".build/release/ZhuyinEngine_ZhuyinEngine.bundle" "$APP_BUNDLE/Contents/Resources/"
fi
if [ -f "Sources/ZhuyinEngine/Resources/lexicon.bin" ]; then
    cp "Sources/ZhuyinEngine/Resources/lexicon.bin" "$APP_BUNDLE/Contents/Resources/"
fi

# ------------------------------------------------------------------------------
# 4. Codesign
# ------------------------------------------------------------------------------
xattr -cr "$APP_BUNDLE"
if [ -n "$SIGN_IDENTITY" ]; then
    echo "==> [4/4] 執行 Developer ID 簽名與 Hardened Runtime ($SIGN_IDENTITY)..."
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
    echo "==> [4/4] 執行本機代碼簽名 (Ad-hoc codesign)..."
    codesign --force --deep --sign - "$APP_BUNDLE"
fi
codesign --verify --verbose "$APP_BUNDLE"
echo "    簽名驗證成功！"

# 建置產物不應被系統視為已安裝的輸入法
unregister_path "$APP_BUNDLE"
mkdir -p "$DIST_DIR"

# ------------------------------------------------------------------------------
# Package: .pkg
# ------------------------------------------------------------------------------
if [ "$DO_PKG" = true ]; then
    echo "==> [打包] 生成雙擊安裝套件 $PKG_PATH..."
    TEMP_PKG_DIR="$(mktemp -d -t haozhuyin_pkg_XXXXXX)"
    PKG_PAYLOAD="$TEMP_PKG_DIR/payload"
    COMPONENT_PLIST="$TEMP_PKG_DIR/component.plist"
    mkdir -p "$PKG_PAYLOAD/Library/Input Methods"

    ditto --norsrc --noextattr "$APP_BUNDLE" "$PKG_PAYLOAD/Library/Input Methods/$APP_NAME.app"
    find "$PKG_PAYLOAD" -name '._*' -delete 2>/dev/null || true

    # 關鍵修正：關閉 Bundle 重新定位（relocation）。
    pkgbuild --analyze --root "$PKG_PAYLOAD" "$COMPONENT_PLIST" >/dev/null
    COMPONENT_COUNT="$("$PLISTBUDDY" -c 'Print' "$COMPONENT_PLIST" | grep -c 'RootRelativeBundlePath' || true)"
    for ((i = 0; i < COMPONENT_COUNT; i++)); do
        "$PLISTBUDDY" -c "Set :$i:BundleIsRelocatable false" "$COMPONENT_PLIST"
        "$PLISTBUDDY" -c "Set :$i:BundleIsVersionChecked false" "$COMPONENT_PLIST"
        "$PLISTBUDDY" -c "Set :$i:BundleOverwriteAction upgrade" "$COMPONENT_PLIST"
    done

    chmod +x Tools/pkg_scripts/preinstall Tools/pkg_scripts/postinstall
    rm -f "$PKG_PATH"

    UNSIGNED_PKG="$PKG_PATH"
    if [ -n "$INSTALLER_SIGN_IDENTITY" ]; then
        UNSIGNED_PKG="$TEMP_PKG_DIR/unsigned.pkg"
    fi

    pkgbuild --root "$PKG_PAYLOAD" \
             --component-plist "$COMPONENT_PLIST" \
             --scripts "Tools/pkg_scripts" \
             --identifier "$APP_ID" \
             --version "$APP_VERSION.$BUILD_NUMBER" \
             --install-location "/" \
             "$UNSIGNED_PKG"

    # 若指定了 Developer ID Installer，執行 pkg 簽名
    if [ -n "$INSTALLER_SIGN_IDENTITY" ]; then
        echo "==> [簽名] 使用 Developer ID Installer 簽署 pkg..."
        productsign --sign "$INSTALLER_SIGN_IDENTITY" "$UNSIGNED_PKG" "$PKG_PATH"
        pkgutil --check-signature "$PKG_PATH"
    fi

    unregister_path "$PKG_PAYLOAD/Library/Input Methods/$APP_NAME.app"
    rm -rf "$TEMP_PKG_DIR"
    echo "    成功產出: $PKG_PATH"

    # --------------------------------------------------------------------------
    # Notarization & Staple
    # --------------------------------------------------------------------------
    if [ "$DO_NOTARIZE" = true ]; then
        echo "================================================================="
        echo "==> [公證] 提交 $PKG_PATH 至 Apple Notary Service..."
        echo "    使用 Keychain Profile: $KEYCHAIN_PROFILE"
        echo "================================================================="
        xcrun notarytool submit "$PKG_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait

        echo "==> [Staple] 釘裝公證票證至 pkg..."
        xcrun stapler staple "$PKG_PATH"

        echo "==> [驗證] 驗證 Gatekeeper 安裝評估..."
        spctl -a -v -t install "$PKG_PATH" || true
        echo "    🎉 公證與 Staple 完成！"
    fi
fi


# ------------------------------------------------------------------------------
# Install: ~/Library/Input Methods（開發用）
# ------------------------------------------------------------------------------
if [ "$DO_INSTALL" = true ]; then
    INSTALLED_APP="$USER_INSTALL_DIR/$APP_NAME.app"
    echo "==> [安裝] 安裝至本機使用者目錄 ($USER_INSTALL_DIR)..."

    # 1. 單一目錄原則：移除 pkg 安裝於 /Library/Input Methods 的複本。
    #    兩處同時存在時，系統會列出兩個「好注音」，且實際載入哪一份不可預期。
    if [ -e "$SYSTEM_INSTALL_DIR/$APP_NAME.app" ]; then
        echo "    檢測到全域目錄存在複本 ($SYSTEM_INSTALL_DIR/$APP_NAME.app)，將移除以確保單一目錄..."
        stop_running_ime
        if ! remove_path "$SYSTEM_INSTALL_DIR/$APP_NAME.app"; then
            echo "    ❌ 無法移除 $SYSTEM_INSTALL_DIR/$APP_NAME.app" >&2
            echo "       請手動執行: sudo rm -rf \"$SYSTEM_INSTALL_DIR/$APP_NAME.app\" 後重試。" >&2
            exit 1
        fi
        sudo pkgutil --forget "$APP_ID" >/dev/null 2>&1 || true
    fi

    # 2. 先複製到暫存位置，再以 rename 原子替換
    mkdir -p "$USER_INSTALL_DIR"
    TEMP_STAGING="$(mktemp -d -t haozhuyin_install_XXXXXX)"
    ditto "$APP_BUNDLE" "$TEMP_STAGING/$APP_NAME.app"

    stop_running_ime
    remove_path "$INSTALLED_APP"
    mv "$TEMP_STAGING/$APP_NAME.app" "$INSTALLED_APP"
    rm -rf "$TEMP_STAGING"
    xattr -dr com.apple.quarantine "$INSTALLED_APP" 2>/dev/null || true
    echo "    已安裝至: $INSTALLED_APP"

    # 3. LaunchServices：只保留安裝路徑
    echo "==> 清理 LaunchServices 殘留註冊..."
    purge_stale_registrations "$INSTALLED_APP"
    [ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$INSTALLED_APP" 2>/dev/null || true

    # 4. TIS 註冊與啟用（由 App 本身執行，冪等）
    echo "==> 向 Text Input Sources 註冊並啟用..."
    "$INSTALLED_APP/Contents/MacOS/$APP_NAME" --register || \
        echo "    ⚠️ TIS 註冊未完成，請登出後再登入，或手動於系統設定加入。"

    # 5. 刷新選單列
    echo "==> 刷新系統輸入法選單 (TextInputMenuAgent / TextInputSwitcher)..."
    refresh_input_menu

    echo "================================================================="
    echo "  🎉 [好注音] 安裝完成！"
    echo "  👉 若選單列尚未出現，請至「系統設定」>「鍵盤」>「輸入方式」>「編輯…」"
    echo "     點擊「+」，於「繁體中文」中新增「好注音」。"
    echo "  👉 仍未出現時，請登出後再登入一次。"
    echo "================================================================="
fi

# 確保建置產物不會留在 LaunchServices 中
unregister_path "$APP_BUNDLE"
