#!/bin/zsh
# 以临时示例数据渲染设置界面，输出用于验收和推广素材。
set -euo pipefail
cd "${0:A:h:h}"
sources=(Sources/PetSorter/*.swift)
sources=(${sources:#Sources/PetSorter/PetSorterApp.swift})
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
[[ -d "$SDK_PATH" ]] || SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDKROOT="${SDKROOT:-$SDK_PATH}" swiftc -swift-version 5 -target arm64-apple-macos13.0 -module-cache-path .build/ModuleCache \
  $sources Tests/Support/OrganizationTestDefaults.swift scripts/render-organization-preview.swift -o .build/organization-preview
.build/organization-preview
