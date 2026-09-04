#!/bin/zsh
# 遇到错误、未定义变量或管道失败时立即退出，防止生成半成品 App。
set -euo pipefail

# 解析项目根目录并集中声明构建产物路径。
PROJECT_DIR="${0:A:h:h}"
APP_NAME="云长卫"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_DIR="$PROJECT_DIR/dist/$APP_NAME.app"
LEGACY_APP_DIR="$PROJECT_DIR/dist/二爷收着.app"

# 使用与当前命令行工具匹配的 SDK 构建 release 可执行文件。
cd "$PROJECT_DIR"
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/ModuleCache" \
swift build -c release --disable-sandbox --scratch-path .build

# 重新创建标准 macOS App Bundle 目录结构。
if [[ -d "$APP_DIR" ]]; then
    rm -rf "$APP_DIR"
fi
# 产品更名后清理旧名称的生成包，避免用户误开过期版本。
if [[ -d "$LEGACY_APP_DIR" ]]; then
    rm -rf "$LEGACY_APP_DIR"
fi
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
# 复制可执行文件、应用图标、四态桌宠立绘和兼容保留的逐帧动画资源。
cp "$BUILD_DIR/PetSorter" "$APP_DIR/Contents/MacOS/PetSorter"
cp "$PROJECT_DIR/Sources/PetSorter/Resources/guan-yu-v2.png" "$APP_DIR/Contents/Resources/guan-yu-v2.png"
for variant in "" "-nod" "-beat" "-dance" "-zen"; do
    cp "$PROJECT_DIR/Sources/PetSorter/Resources/guan-yu-listening$variant.png" "$APP_DIR/Contents/Resources/guan-yu-listening$variant.png"
done
cp "$PROJECT_DIR/Sources/PetSorter/Resources/guan-yu-idle.png" "$APP_DIR/Contents/Resources/guan-yu-idle.png"
cp "$PROJECT_DIR/Sources/PetSorter/Resources/guan-yu-receiving.png" "$APP_DIR/Contents/Resources/guan-yu-receiving.png"
cp "$PROJECT_DIR/Sources/PetSorter/Resources/guan-yu-failure.png" "$APP_DIR/Contents/Resources/guan-yu-failure.png"
cp "$PROJECT_DIR/Sources/PetSorter/Resources/guan-yu-complete.png" "$APP_DIR/Contents/Resources/guan-yu-complete.png"
cp "$PROJECT_DIR/Sources/PetSorter/Resources/guan-yu-skin-crimson.png" "$APP_DIR/Contents/Resources/guan-yu-skin-crimson.png"
cp "$PROJECT_DIR/Sources/PetSorter/Resources/guan-yu-skin-midnight.png" "$APP_DIR/Contents/Resources/guan-yu-skin-midnight.png"
cp "$PROJECT_DIR/Sources/PetSorter/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp -R "$PROJECT_DIR/Sources/PetSorter/Resources/sword-animation" "$APP_DIR/Contents/Resources/"
# 写入 Info.plist，并进行本机临时签名以便直接运行和验证。
cp "$PROJECT_DIR/AppInfo.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - "$APP_DIR"

# 向调用者输出最终应用绝对路径。
echo "$APP_DIR"
