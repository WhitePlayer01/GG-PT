#!/bin/zsh
# 使用临时目录验证文件整理扩展，不启动桌宠或后台巡查。
set -euo pipefail
cd "${0:A:h:h}"
sources=(Sources/PetSorter/*.swift)
sources=(${sources:#Sources/PetSorter/PetSorterApp.swift})
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
[[ -d "$SDK_PATH" ]] || SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDKROOT="${SDKROOT:-$SDK_PATH}" swiftc -swift-version 5 -target arm64-apple-macos13.0 -module-cache-path .build/ModuleCache \
  $sources Tests/Support/OrganizationTestDefaults.swift Tests/PetSorterTests/OrganizationTests.swift -o .build/organization-tests
.build/organization-tests
