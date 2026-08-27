#!/bin/zsh
# 构建标准 macOS App，并生成可拖入“应用程序”目录安装的压缩 DMG。
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_NAME="云长卫"
DIST_DIR="$PROJECT_DIR/dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_DIR/AppInfo.plist")
ARCHITECTURE="$(uname -m)"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION-$ARCHITECTURE.dmg"

mkdir -p "$DIST_DIR"
STAGING_DIR="$(mktemp -d "$DIST_DIR/.dmg-staging.XXXXXX")"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT INT TERM

echo "[1/3] 正在构建 $APP_NAME.app…"
"$PROJECT_DIR/scripts/build-app.sh" >/dev/null

echo "[2/3] 正在准备安装盘内容…"
/usr/bin/ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "[3/3] 正在生成 DMG…"
rm -f "$DMG_PATH"
/usr/bin/hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

echo
echo "打包完成：$DMG_PATH"
echo "安装方式：打开 DMG，将“$APP_NAME”拖入“Applications”。"
