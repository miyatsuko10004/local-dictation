#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_sha=f049fff95a089aa9969deb009cdd4892b3e74916
task_src="${LOCAL_DICTATION_WHISPER_SOURCE:-$task_root/.build/whisper-source}"
if [ ! -d "$task_src/.git" ]; then
  git clone --depth 1 --branch v1.9.1 https://github.com/ggml-org/whisper.cpp.git "$task_src"
fi
[ "$(git -C "$task_src" rev-parse HEAD)" = "$task_sha" ] || { echo 'Unexpected whisper.cpp revision' >&2; exit 1; }
cmake -S "$task_src" -B "$task_root/.build/whisper-engine" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DGGML_METAL_EMBED_LIBRARY=ON -DWHISPER_BUILD_TESTS=OFF
cmake --build "$task_root/.build/whisper-engine" --config Release --target whisper-cli -j 4
mkdir -p "$task_root/.local-data/bin"
cp "$task_root/.build/whisper-engine/bin/whisper-cli" "$task_root/.local-data/bin/whisper-cli"
