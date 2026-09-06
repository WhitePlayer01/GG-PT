#!/bin/zsh
# 使用内存设置与临时素材，验证时不启动应用或操作用户文件。
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
mkdir -p .build
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
[[ -d "$SDK_PATH" ]] || SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDKROOT="${SDKROOT:-$SDK_PATH}" \
  swiftc -swift-version 5 -target arm64-apple-macos13.0 -module-cache-path .build/ModuleCache \
  Sources/PetSorter/CharacterSystem.swift Sources/PetSorter/ListeningAnimationVariant.swift \
  Sources/PetSorter/AppearanceProfile.swift Sources/PetSorter/VideoArtwork.swift Sources/PetSorter/CustomArtworkView.swift \
  Sources/PetSorter/SettingsStore.swift Tests/PetSorterTests/AppearanceTests.swift \
  -o .build/appearance-tests
.build/appearance-tests
