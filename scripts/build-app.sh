#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_NAME="二爷收着"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_DIR="$PROJECT_DIR/dist/$APP_NAME.app"

cd "$PROJECT_DIR"
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk \
CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/ModuleCache" \
swift build -c release --disable-sandbox --scratch-path .build

if [[ -d "$APP_DIR" ]]; then
    rm -rf "$APP_DIR"
fi
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/PetSorter" "$APP_DIR/Contents/MacOS/PetSorter"
cp "$PROJECT_DIR/Sources/PetSorter/Resources/guan-yu-v2.png" "$APP_DIR/Contents/Resources/guan-yu-v2.png"
cp "$PROJECT_DIR/Sources/PetSorter/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp -R "$PROJECT_DIR/Sources/PetSorter/Resources/sword-animation" "$APP_DIR/Contents/Resources/"
cp "$PROJECT_DIR/AppInfo.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
