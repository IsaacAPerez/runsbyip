#!/usr/bin/env bash
# Build and launch RunsByIP on iPhone 17 Pro Max, iOS 26.0 simulator runtime (override via IOS_SIMULATOR_RUNTIME).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

DEVICE_NAME="${IOS_SIMULATOR_DEVICE_NAME:-iPhone 17 Pro Max}"
# Match simctl runtime id suffix, e.g. com.apple.CoreSimulator.SimRuntime.iOS-26-0
RUNTIME_SUFFIX="${IOS_SIMULATOR_RUNTIME:-iOS-26-0}"
BUNDLE_ID="com.isaacperez.runsbyip"
DERIVED="${ROOT}/DerivedDataCLI"

udid_for_device() {
  python3 -c "
import json, subprocess, sys
name = '''${DEVICE_NAME}'''
suffix = '''${RUNTIME_SUFFIX}'''
data = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))
for runtime, devs in data.get('devices', {}).items():
    if not runtime.endswith(suffix):
        continue
    for d in devs:
        if d.get('name') == name and d.get('isAvailable'):
            print(d['udid'])
            sys.exit(0)
sys.exit(
    'No available %r on runtime *.%s — install that simulator in Xcode > Settings > Platforms, '
    'or set IOS_SIMULATOR_RUNTIME (e.g. iOS-26-1).' % (name, suffix)
)
"
}

UDID="$(udid_for_device)"

open -a Simulator
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b &>/dev/null || true

xcodebuild -project RunsByIP.xcodeproj -scheme RunsByIP \
  -destination "id=$UDID" \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  build

xcrun simctl install "$UDID" "$DERIVED/Build/Products/Debug-iphonesimulator/RunsByIP.app"
xcrun simctl launch "$UDID" "$BUNDLE_ID"
