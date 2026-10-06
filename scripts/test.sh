#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
export CLANG_MODULE_CACHE_PATH="$task_root/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$task_root/.build/swift-cache"
swift test --disable-sandbox --cache-path .build/cache
