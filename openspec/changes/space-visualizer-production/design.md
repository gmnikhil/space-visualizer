## Context

See proposal.md for motivation and the two capability specs for behavior. The current source is preserved in Git checkpoint `7c4b0b5`. The user reported successful control and subscription visualization, then scrolling/CPU regressions as the scene grew. Recent worker and view-isolation changes were reported to work, but no complete production acceptance packet exists.

The working capture route is a private Music process tap feeding a tap-only aggregate and direct device input callback. The old HAL AudioUnitRender implementation failed with -10863 and must not return as an automatic fallback. Existing code also contains dead HAL implementation, manual test UI, synchronous AppleScript polling, and incomplete automatic lifecycle integration.

## Goals / Non-Goals

**Goals:**
- One local macOS application renamed in place, with a deterministic playback-following lifecycle.
- Five-second idle discovery without persistent audio/GPU activity.
- Preserve working spatial appearance and request up to 120 Hz without main-thread FFT or unbounded job queues.
- Treat resource ownership, permissions, failure, and cancellation as production behavior, covered by deterministic tests.

**Non-Goals:**
- A second app, replacement Music player, MusicKit/catalog networking, source separation, Atmos-object reconstruction, or automatic source-quality badge claims.
- A new Metal engine in this iteration; first harden and measure the working Canvas renderer rather than silently replacing its visual grammar.
- App Store distribution, notarization, background login agents, or a claim that the entire machine's GPU can be switched off. Idle means this app schedules no continuous rendering/analysis, not that macOS's compositor stops.

## Decisions

### 1. Rename in place with an explicit rollback boundary

Rename source/modules/test targets and product to SpaceVisualizerApp/SpaceVisualizerCore and the executable to SpaceVisualizer. Build `Space Visualizer.app`; use a new stable bundle identifier `com.spacevisualizer.app`. Update signing, purpose strings, test fixtures, scripts, and documentation together. Retain historical OpenSpec/ideation artifacts rather than rewriting past evidence. Document that the new bundle identity can require fresh TCC approval; never migrate TCC records manually.

Alternative: maintain two apps or merely change the window title. Rejected because the user explicitly prefers one product and a coherent identity. Git preserves the old version.

### 2. A single lifecycle coordinator owns all asynchronous work

Use a main-actor coordinator with states onboarding, waiting, starting, visualizing, silent, suspended, recovering, permissionBlocked, failed, and terminated. Separate logical state from resource handles. One session generation tags playback queries, starts, feature snapshots, and teardown. Late results are ignored and any newly created obsolete resources destroyed.

The coordinator owns one single-shot idle timer, at most one active watchdog, notification tokens, capture session, worker, display link activation, and any metadata helper process. Invariants are enforced after every transition: waiting has no audio/analysis/display resource; visualizing has no idle timer; terminated has none. Startup and teardown serialize on a dedicated lifecycle queue rather than blocking the UI with driver work. Stop waits for in-flight work on that queue, not synchronously on the main actor.

Alternative: add more `.task` and `.onReceive` handlers to ContentView. Rejected because resource ownership becomes dependent on SwiftUI reconstruction and cancellation races are difficult to test.

### 3. Idle checks and active observation are separate modes

After onboarding, perform one initial check and then five-second idle checks. Check running-application presence before Apple Events so polling cannot launch Music. Use a monotonic injected scheduler: skip missed ticks and never queue catch-up requests.

During active visualization, cancel the idle timer. Validate local Music playback notifications on the target Mac and treat them only as hints triggering a coalesced authoritative query. Do not depend on undocumented payloads for correctness or use private APIs. Maintain a separate two-second playback watchdog as the reliable fallback. This is intentionally not "zero observation while playing": without an active observer the app cannot discover pause/stop. The five-second idle discovery loop is off while this bounded active observer runs. App termination notifications provide another prompt stop hint.

Each query has a one-second timeout and at most one in flight. Query player state independently of current track: absence of a current track must not make player-state observation fail. Read title/artist/duration in isolated best-effort branches. Model absent, stopped, paused, playing, denied, timeout, and unknown distinctly. Active unknown/timeout suspends capture conservatively and returns to waiting after cleanup; persistent capture failure enters explicit retry, not a five-second resource-creation loop.

Run the bounded AppleScript adapter outside the main process's UI thread, preferably through the local `/usr/bin/osascript` helper with fixed script arguments, bounded output, timeout termination, and no shell interpolation. Verify actual Automation attribution under the signed app bundle before accepting this approach; any helper attribution problem is an implementation blocker, not grounds to weaken consent. No web traffic is required.

### 4. Consent before automation, then automatic following

First-run setup explains exactly what automatic observation/capture will do. A user action enables observation and initiates required prompts. Persist only consent/preference intent, not a fabricated permanent TCC authorization status. Permission denial has a single settings/retry path; retries require user action. Later launches automatically follow playback once permissions remain usable.

Window focus is not visibility: switching to Music must not stop a visible visualizer. Use explicit window visibility/occlusion and app lifecycle events, not generic inactive scene state. Closing suspends all observation until reopening; hidden/minimized/fully occluded suspends expensive resources but retains at most bounded state observation. Sleep tears down; wake and visibility restoration trigger a new state check. Quit is terminal, including cancellation of helper processes and late starts.

### 5. Harden the existing audio pipeline instead of widening capture

Keep only the direct Music-only process-tap adapter. Remove dead HAL code after regression coverage. Resolve source ambiguity explicitly, never capture all processes as a fallback. Device configuration uses installed SDK definitions; handle retained CF ownership, callbacks, buffer bounds, formats, cleanup statuses, and repeated starts in one review.

Capture callbacks perform bounded copies without allocations, file I/O, FFT, UI operations, or waiting on contended locks. The serial worker owns FFT/smoothing and publishes into one overwrite-only mailbox. Read samples and their timing/format metadata atomically. Track actual sample timestamps, not merely worker completion time, to reject stale input; convert host ticks to monotonic time correctly. Overlapping windows retain the required history while skipping backlog. Generation changes invalidate both retained PCM and smoothing state before reconnection. Derive sample-rate/channel interpretation from actual tap PCM; never infer source codec or 24-bit precision from Float32.

### 6. Isolate display state and preserve low latency

Use a display-owned link requesting up to 120 Hz. Poll the latest immutable visual snapshot without enqueuing analysis or main-queue work per frame. Only the renderer subtree observes visual updates; settings/status/diagnostics publish at most four times per second, with logs only on transitions or explicit diagnostic events. Cache fixed geometry; retain the user's preferred per-segment depth shading unless a separately measured optimization proves equivalent.

Avoid delayed interpolation buffers. Make attack/release smoothing time-based so behavior does not change with sample rate, worker cadence, or display rate. In missing-input states, clear live visuals within 250 ms. Fresh silent samples are valid silence, not capture failure; geometry settles without manufacturing motion.

The scene fills the window, supports fullscreen, and has a compact overlay for waiting/permission/signal status and settings. Remove manual test-phase requirements from normal use, retaining an optional diagnostics panel/export with counters but no PCM. Preserve Reduce Motion as static geometry.

### 7. Measure acceptance, do not declare optimization by construction

Use release builds and record hardware, OS, route, display cadence, window size, and enabled effects. Baseline the checkpoint before comparing the new lifecycle. Required budgets are in the experience spec: idle mean below 2 percent of one core; active mean below 50 percent on the specified M5 Pro workload; main-thread frame work within the selected display interval; no app-caused stalls above 100 ms. These are acceptance targets, not claims already achieved.

Instrument callback/sample age, worker duration, mailbox age, main-thread frame time, outstanding tasks, live resource counts, and memory locally. Record p50/p95 latency components and compare end-to-end audio/visual alignment using a known transient fixture and user observation; target no regression versus the checkpoint and no accumulating lag over 15 minutes. Do not record protected audio or use microphone/screen capture to measure it. If targets fail, profile the stage responsible; do not silently drop the default 120 Hz request or restore lag-inducing queues.

## Risks / Trade-offs

- [Music notifications are not a reliable public playback contract] → Use only validated optional hints; the active watchdog is the authoritative fallback.
- [User wording "stop polling" conflicts with discovering pause] → Stop the idle poller, retain explicitly bounded active observation, and document the distinction.
- [App rename changes permission identity] → Explain fresh prompts, verify attribution, and leave Music untouched.
- [Query timeouts or driver operations block scrolling] → Isolate queries/lifecycle work, bound time and output, and test cancellation under rapid transitions.
- [120 Hz Canvas exceeds CPU budget] → Retain rate preference, profile release workloads, isolate notifications, and optimize measured hotspots before claiming readiness.
- [Quiet music mistaken for stopped playback] → Separate fresh silence, missing input, and authoritative player state.
- [Route-specific protected playback or AirPlay behaves differently] → Re-run per-route control/subscription acceptance; expose unsupported behavior rather than claim universal compatibility.
- [Existing code has ownership/data-race defects despite working playback] → TDD resource doubles, generation tests, sanitizers where available, and prolonged native acceptance before release.

## Migration Plan

1. Keep checkpoint `7c4b0b5` accessible; do not amend it. Work on a new branch for implementation.
2. Rename the single product and tests; run debug/release verification before lifecycle changes.
3. Add the coordinator, bounded query adapter, permission onboarding, and automated following behind tested contracts.
4. Switch to the production canvas shell and remove obsolete diagnostic-first control flow/dead capture paths.
5. Document the new bundle, commands, renewed permission flow, and optional removal of the old generated Resonant.app. Never replace a running bundle; quit first.
6. Complete performance, privacy, route, and lifecycle acceptance on the Mac. Label failures and untested routes explicitly.
7. Roll back by checking out/building the checkpoint on a separate branch/worktree; do not reset or delete unrelated user work. No Music library migration is required.
