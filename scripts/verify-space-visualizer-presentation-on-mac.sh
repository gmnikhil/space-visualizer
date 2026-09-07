#!/bin/zsh
set -e
set -o pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LOG="$ROOT/.build/space-visualizer-presentation.log"
mkdir -p "$ROOT/.build"
cd "$ROOT"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

{
    echo "Space Visualizer presentation verification"
    echo "Started: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "Repository: $ROOT"
    echo
    echo "=== Environment ==="
    uname -a
    sw_vers
    xcode-select -p
    swift --version
    echo
    echo "=== Debug tests ==="
    swift test --parallel
    echo
    echo "=== Release tests ==="
    swift test -c release --parallel
    echo
    echo "=== Presentation contracts ==="
    CONTENT="$ROOT/Sources/SpaceVisualizerApp/ContentView.swift"
    OBSERVER="$ROOT/Sources/SpaceVisualizerApp/WindowVisibilityObserver.swift"
    rg -n 'SpatialCanvasView|DiagnosticsPanel|Export image|ImageRenderer|VisualizerExportView|TimelineView|positionObservedAt|Export audio-free report|SpaceVisualizerDiagnosticsExport|Source quality: unknown' "$CONTENT"
    rg -n 'didMiniaturizeNotification|didChangeOcclusionStateNotification|willCloseNotification|didHideNotification|didUnhideNotification|forceHidden' "$OBSERVER"
    if rg -n '\.disabled\(engine\.lastReport == nil\)' "$CONTENT"; then
        echo "Automatic diagnostics export is incorrectly disabled without a legacy report."
        exit 1
    fi
    if rg -n 'Start capture|TEST PHASE|Record current attempt|Picker\("Test phase"|toggleFullScreen|Fullscreen' "$CONTENT"; then
        echo "Obsolete manual/fullscreen controls remain in the default presentation."
        exit 1
    fi
    rg -n 'preferred: requested|DisplayRefreshDriver|viewDidMoveToWindow|stopLink\(\)' "$ROOT/Sources/SpaceVisualizerApp/DisplayRefreshDriver.swift" "$CONTENT"
    rg -n 'DisplayCadencePolicy|DiagnosticUpdateLimiter|LatestAudioFeatures' "$ROOT/Sources/SpaceVisualizerCore"
    echo
    echo "Completed: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} 2>&1 | tee "$LOG"

exit $pipestatus[1]
