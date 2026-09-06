#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$ROOT/.build"
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
OUT="$ROOT/.build/coreaudio-sdk.txt"
{
    SDK="$(xcrun --sdk macosx --show-sdk-path)"
    printf 'SDK: %s\n' "$SDK"
    for FRAMEWORK in CoreAudio AudioToolbox AudioUnit; do
        HEADERS="$SDK/System/Library/Frameworks/$FRAMEWORK.framework/Headers"
        if [ -d "$HEADERS" ]; then
            grep -n -B 15 -A 25 -E 'AudioDeviceCreateIOProcID|AudioDeviceIOProc\)|AudioDeviceStart\(|AudioDeviceStop\(|AudioDeviceDestroyIOProcID|kAudioAggregateDeviceTap|kAudioSubTap|CannotDoInCurrentContext|SetInputCallback|kAudioTapPropertyFormat' "$HEADERS"/*.h || true
        fi
    done
} > "$OUT" 2>&1
printf 'Saved local SDK declarations to %s\n' "$OUT"
