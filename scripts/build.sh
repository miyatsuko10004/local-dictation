#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
export CLANG_MODULE_CACHE_PATH="$task_root/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$task_root/.build/swift-cache"
if [ ! -x "$task_root/.local-data/bin/whisper-cli" ]; then "$task_root/scripts/build-engine.sh"; fi
swift build -c release --disable-sandbox --cache-path .build/cache
app="$task_root/build/Local Dictation.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/LocalDictation "$app/Contents/MacOS/LocalDictation"
cp .local-data/bin/whisper-cli "$app/Contents/Resources/whisper-cli"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
codesign --force --sign "${LOCAL_DICTATION_SIGN_IDENTITY:--}" "$app/Contents/Resources/whisper-cli"
python3 - "$app" "$task_root" <<'PYINFO'
import plistlib,sys
from pathlib import Path
app,root=sys.argv[1:]
info={'CFBundleIdentifier':'local.manyo.LocalDictation','CFBundleName':'Local Dictation',
'CFBundleDisplayName':'Local Dictation','CFBundleExecutable':'LocalDictation','CFBundlePackageType':'APPL',
'CFBundleShortVersionString':'0.1.0','CFBundleVersion':'1','LSMinimumSystemVersion':'14.0',
'NSMicrophoneUsageDescription':'あなたの声をこのMacの中だけで文字にします。',
'LocalDictationDataDirectory':str(Path(root)/'.local-data'),'NSHighResolutionCapable':True}
Path(app+'/Contents/Info.plist').write_bytes(plistlib.dumps(info))
PYINFO
codesign --force --sign "${LOCAL_DICTATION_SIGN_IDENTITY:--}" --identifier local.manyo.LocalDictation "$app"
printf '%s\n' "$app"
