#!/bin/zsh
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP="$ROOT/.build/Space Visualizer.app"
MODE="${1:-idle}"
DURATION="${2:-60}"
INTERVAL="${SAMPLE_INTERVAL_SECONDS:-1}"
ENFORCE="${ENFORCE_PERFORMANCE_TARGETS:-0}"
STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
CSV="$ROOT/.build/space-visualizer-performance-${MODE}-${STAMP}.csv"
SUMMARY="$ROOT/.build/space-visualizer-performance-${MODE}-${STAMP}.md"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This measurement must run on the target Mac." >&2
    exit 1
fi
if [[ "$MODE" != "idle" && "$MODE" != "active" ]]; then
    echo "Usage: $0 [idle|active] [duration-seconds]" >&2
    exit 2
fi
if ! [[ "$DURATION" =~ '^[0-9]+$' && "$DURATION" -gt 0 ]]; then
    echo "Duration must be a positive integer number of seconds." >&2
    exit 2
fi
if ! [[ "$INTERVAL" =~ '^[0-9]+$' && "$INTERVAL" -gt 0 ]]; then
    echo "SAMPLE_INTERVAL_SECONDS must be a positive integer." >&2
    exit 2
fi

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

cd "$ROOT"
if [[ ! -d "$APP" ]]; then
    "$ROOT/scripts/build-space-visualizer-app.sh"
fi

existing_pids=($(pgrep -x SpaceVisualizer || true))
if (( ${#existing_pids[@]} == 0 )); then
    echo "Opening Space Visualizer only; do not start or control Music from this script."
    open "$APP"
    for _ in {1..30}; do
        sleep 1
        existing_pids=($(pgrep -x SpaceVisualizer || true))
        (( ${#existing_pids[@]} > 0 )) && break
    done
fi

pids=($(pgrep -x SpaceVisualizer || true))
if (( ${#pids[@]} != 1 )); then
    echo "Expected exactly one SpaceVisualizer process, found ${#pids[@]}." >&2
    exit 1
fi
PID="${pids[1]}"

if [[ "$MODE" == "idle" ]]; then
    echo "Idle measurement: quit diagnostics, leave Music absent or paused, and do not interact for ${DURATION}s."
    TARGET="2"
else
    echo "Active measurement: start Music playback manually, enable following, close diagnostics, then wait ${DURATION}s."
    TARGET="50"
fi
read -r "answer?Continue with PID $PID? [y/N] "
print
[[ "$answer" == [yY] ]] || { echo "Cancelled."; exit 0; }

print 'timestamp,cpu_percent,resident_memory_kb,threads,open_files' > "$CSV"
for ((elapsed = 0; elapsed < DURATION; elapsed += INTERVAL)); do
    if ! kill -0 "$PID" 2>/dev/null; then
        echo "Space Visualizer exited during measurement." >&2
        exit 1
    fi
    cpu="$(ps -p "$PID" -o %cpu= | awk '{print $1}')"
    rss="$(ps -p "$PID" -o rss= | awk '{print $1}')"
    threads="$(ps -p "$PID" -o thcount= | awk '{print $1}')"
    files="$(lsof -n -p "$PID" 2>/dev/null | awk 'NR > 1 { count++ } END { print count + 0 }')"
    print "$(date -u '+%Y-%m-%dT%H:%M:%SZ'),${cpu:-0},${rss:-0},${threads:-0},${files:-0}" >> "$CSV"
    if (( elapsed + INTERVAL < DURATION )); then sleep "$INTERVAL"; fi
done

metrics="$(awk -F, '
NR > 1 {
    cpu = $2 + 0
    rss = $3 + 0
    threads = $4 + 0
    files = $5 + 0
    cpuSum += cpu
    count += 1
    if (cpu > cpuMax) cpuMax = cpu
    if (NR == 2) firstRSS = rss
    lastRSS = rss
    if (NR == 2) firstThreads = threads
    lastThreads = threads
    if (NR == 2) firstFiles = files
    lastFiles = files
}
END {
    if (count == 0) exit 1
    printf "mean_cpu=%.2f\nmax_cpu=%.2f\nfirst_rss_kb=%d\nlast_rss_kb=%d\nrss_delta_kb=%d\nfirst_threads=%d\nlast_threads=%d\nfirst_files=%d\nlast_files=%d\nsamples=%d\n", cpuSum / count, cpuMax, firstRSS, lastRSS, lastRSS - firstRSS, firstThreads, lastThreads, firstFiles, lastFiles, count
}' "$CSV")"
eval "$metrics"

cat > "$SUMMARY" <<EOF
# Space Visualizer ${MODE} performance measurement

- Date (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')
- macOS: $(sw_vers -productVersion)
- Hardware: $(sysctl -n hw.model)
- Process: SpaceVisualizer (PID ${PID})
- Duration: ${DURATION}s sampled every ${INTERVAL}s
- CSV: ${CSV:t}
- Music control: not performed by this script

## Measured

- Mean process CPU: ${mean_cpu}% of one core
- Maximum sampled CPU: ${max_cpu}%
- Resident memory: ${first_rss_kb} KiB → ${last_rss_kb} KiB (delta ${rss_delta_kb} KiB)
- Threads: ${first_threads} → ${last_threads}
- Open files: ${first_files} → ${last_files}

## Gate

- Target for ${MODE}: below ${TARGET}% mean process CPU
- Result: $(awk -v mean="$mean_cpu" -v target="$TARGET" 'BEGIN { print (mean < target ? "PASS" : "FAIL — investigate before claiming readiness") }')

Record display cadence and p50/p95 display tick timing from the optional in-app Diagnostics panel separately. This summary contains no PCM, artwork, track data, or screen capture.
EOF

gate="$(awk -v mean="$mean_cpu" -v target="$TARGET" 'BEGIN { print (mean < target ? "yes" : "no") }')"
if [[ "$ENFORCE" == "1" && "$gate" != "yes" ]]; then
    echo "Performance CPU gate failed; see $SUMMARY" >&2
    exit 1
fi

printf '\nWrote CSV: %s\nWrote summary: %s\n' "$CSV" "$SUMMARY"
