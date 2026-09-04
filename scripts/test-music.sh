#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
mkdir -p .build
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
  swiftc -swift-version 5 -module-cache-path .build/ModuleCache \
  Sources/PetSorter/MusicHistoryStore.swift Tests/PetSorterTests/MusicHistoryTests.swift \
  -o .build/music-history-tests
.build/music-history-tests
node browser-extension/music-observer.test.cjs
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
  swiftc -swift-version 5 -module-cache-path .build/ModuleCache \
  Sources/PetSorter/MusicHistoryStore.swift Sources/PetSorter/NeteasePlaybackReader.swift \
  Tests/PetSorterTests/NeteasePlaybackTests.swift -o .build/netease-playback-tests
.build/netease-playback-tests
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
  swiftc -swift-version 5 -module-cache-path .build/ModuleCache \
  Sources/PetSorter/ListeningAnimationVariant.swift Tests/PetSorterTests/ListeningPlaybackTests.swift \
  -o .build/listening-playback-tests
.build/listening-playback-tests
