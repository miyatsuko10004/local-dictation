#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
with_ai=false
launch=true
for arg in "$@"; do
  case "$arg" in
    --with-ai) with_ai=true ;;
    --no-open) launch=false ;;
    *) printf 'Usage: %s [--with-ai] [--no-open]\n' "$0" >&2; exit 2 ;;
  esac
done
./scripts/build.sh
LOCAL_DICTATION_DATA="$PWD/.local-data" ./.build/release/dictation-check prepare
if "$with_ai"; then
  command -v ollama >/dev/null || { printf 'Install and start Ollama before using --with-ai.\n' >&2; exit 1; }
  ollama pull qwen3:4b-instruct-2507-q4_K_M
fi
if "$launch"; then
  open "$PWD/build/Local Dictation.app"
fi
