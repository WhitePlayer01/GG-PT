#!/bin/zsh
# 渲染原生设置页截图；不启动桌宠及音乐或收纳服务。
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
sources=(Sources/PetSorter/*.swift)
sources=(${sources:#Sources/PetSorter/PetSorterApp.swift})
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
[[ -d "$SDK_PATH" ]] || SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDKROOT="${SDKROOT:-$SDK_PATH}" \
  swiftc -swift-version 5 -target arm64-apple-macos13.0 -module-cache-path .build/ModuleCache \
  $sources scripts/render-appearance-preview.swift -o .build/appearance-preview
.build/appearance-preview
