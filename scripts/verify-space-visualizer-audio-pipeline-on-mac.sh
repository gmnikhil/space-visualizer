#!/bin/zsh
set -e
set -o pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LOG="$ROOT/.build/space-visualizer-audio-pipeline.log"
mkdir -p "$ROOT/.build"
cd "$ROOT"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

{
    echo "Space Visualizer audio-pipeline verification"
    echo "Started: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "Repository: $ROOT"
    echo
    echo "=== Environment ==="
    uname -a
    sw_vers
    xcode-select -p
    swift --version
    echo
    echo "=== Package description ==="
    swift package describe
    echo
    echo "=== Debug tests ==="
    swift test --parallel
    echo
    echo "=== Release tests ==="
    swift test -c release --parallel
    echo
    echo "=== Thread sanitizer ==="
    if [[ "${RUN_THREAD_SANITIZER:-0}" == "1" ]]; then
        swift test --sanitize=thread --parallel
    else
        echo "Skipped. Re-run with RUN_THREAD_SANITIZER=1 for the available race check."
    fi
    echo
    echo "=== Static capture invariants ==="
    if rg -n 'AudioUnitRender|kAudioUnitSubType_HALOutput|createInputUnit|screen capture|AVCaptureDevice' Sources/SpaceVisualizerCore; then
        echo "Forbidden legacy or unrelated capture path found."
        exit 1
    fi
    rg -n 'AudioDeviceCreateIOProcID|kAudioAggregateDeviceTapListKey|AudioHardwareCreateProcessTap|maximumSampleAgeNanoseconds|isDiscontinuous' Sources/SpaceVisualizerCore
    echo
    echo "Completed: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} 2>&1 | tee "$LOG"

exit $pipestatus[1]
