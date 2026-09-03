#!/bin/zsh
# 构建标准 macOS App，并生成可拖入“应用程序”目录安装的压缩 DMG。
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_NAME="云长卫"
DIST_DIR="$PROJECT_DIR/dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
ICON_PATH="$PROJECT_DIR/Sources/PetSorter/Resources/AppIcon.icns"
PLIST_PATH="$PROJECT_DIR/AppInfo.plist"
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST_PATH")
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST_PATH")
VERSION_PARTS=("${(@s:.:)CURRENT_VERSION}")
if [[ ${#VERSION_PARTS[@]} -ne 3 ]] || [[ "$CURRENT_VERSION" != <->.<->.<-> ]] || [[ "$CURRENT_BUILD" != <-> ]]; then
    echo "无法自动递增版本：当前版本必须为 x.y.z，构建号必须为整数。" >&2
    exit 1
fi
VERSION="${VERSION_PARTS[1]}.${VERSION_PARTS[2]}.$((VERSION_PARTS[3] + 1))"
BUILD_NUMBER="$((CURRENT_BUILD + 1))"
ARCHITECTURE="$(uname -m)"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION-$ARCHITECTURE.dmg"
RW_DMG_PATH="$DIST_DIR/.$APP_NAME-$VERSION-$ARCHITECTURE.rw.dmg"

mkdir -p "$DIST_DIR"
STAGING_DIR="$(mktemp -d "$DIST_DIR/.dmg-staging.XXXXXX")"
MOUNT_DIR="$(mktemp -d "/tmp/yunchangwei-dmg.XXXXXX")"
PLIST_BACKUP="$(mktemp "/tmp/yunchangwei-info.XXXXXX")"
cp "$PLIST_PATH" "$PLIST_BACKUP"
IS_MOUNTED=0
PACKAGING_SUCCEEDED=0

cleanup() {
    if [[ $IS_MOUNTED -eq 1 ]]; then
        /usr/bin/hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
    fi
    rm -rf "$STAGING_DIR"
    rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
    rm -f "$RW_DMG_PATH"
    if [[ $PACKAGING_SUCCEEDED -ne 1 ]]; then
        cp "$PLIST_BACKUP" "$PLIST_PATH"
    fi
    rm -f "$PLIST_BACKUP"
}
trap cleanup EXIT INT TERM

echo "版本自动更新：$CURRENT_VERSION（构建 $CURRENT_BUILD）→ $VERSION（构建 $BUILD_NUMBER）"
/usr/bin/sed -i '' \
    -e "/<key>CFBundleShortVersionString<\\/key>/{n;s#<string>[^<]*</string>#<string>$VERSION</string>#;}" \
    -e "/<key>CFBundleVersion<\\/key>/{n;s#<string>[^<]*</string>#<string>$BUILD_NUMBER</string>#;}" \
    "$PLIST_PATH"

echo "[1/4] 正在构建 $APP_NAME.app…"
"$PROJECT_DIR/scripts/build-app.sh" >/dev/null

echo "[2/4] 正在准备安装盘内容…"
/usr/bin/ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
# 将应用图标写入安装盘，并隐藏 Finder 识别用的图标文件。
cp "$ICON_PATH" "$STAGING_DIR/.VolumeIcon.icns"
xcrun SetFile -a V "$STAGING_DIR/.VolumeIcon.icns"

echo "[3/4] 正在设置安装盘图标…"
rm -f "$RW_DMG_PATH" "$DMG_PATH"
/usr/bin/hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDRW \
    "$RW_DMG_PATH" >/dev/null
/usr/bin/hdiutil attach \
    "$RW_DMG_PATH" \
    -nobrowse \
    -noverify \
    -mountpoint "$MOUNT_DIR" >/dev/null
IS_MOUNTED=1
xcrun SetFile -a C "$MOUNT_DIR"
/usr/bin/hdiutil detach "$MOUNT_DIR" >/dev/null
IS_MOUNTED=0

echo "[4/4] 正在压缩 DMG…"
/usr/bin/hdiutil convert \
    "$RW_DMG_PATH" \
    -ov \
    -format UDZO \
    -o "$DMG_PATH" >/dev/null
rm -f "$RW_DMG_PATH"

# 让本机 Finder 中的 DMG 文件也显示应用图标。
(
    cd "$PROJECT_DIR/scripts"
    xcrun Rez dmg-icon.r -append -o "$DMG_PATH"
)
xcrun SetFile -a C "$DMG_PATH"
PACKAGING_SUCCEEDED=1

echo
echo "打包完成：$DMG_PATH"
echo "安装包图标：已使用 $APP_NAME 的 AppIcon.icns"
echo "安装方式：打开 DMG，将“$APP_NAME”拖入“Applications”。"
