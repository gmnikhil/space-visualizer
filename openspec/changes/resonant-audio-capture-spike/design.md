## Context

See `proposal.md` for the motivation and approved scope. This repository currently contains the HTML design review and planning notes, but no native macOS project or capture implementation.

The feasibility spike targets the user's M5 Pro and two initial output routes: built-in speakers and AirPlay. Apple Music remains the playback owner. The central design constraint is that metadata and audio are independent inputs: a valid track title does not prove that analyzable PCM is available, and a valid audio signal does not require metadata to be present.

Apple documents macOS system-audio process taps and an audio-capture purpose string, but public documentation does not establish that every protected Apple Music stream or route will yield usable samples. The spike must therefore collect evidence from a known control and from the user's actual subscription playback rather than encode a presumed DRM result.

## Goals / Non-Goals

**Goals:**

- Produce a small, executable, local macOS diagnostic that can be run while Apple Music continues playing normally.
- Exercise the two independent paths: current-track metadata through the public/scriptable Music interface, and permitted outgoing audio through the supported audio-capture path.
- Show a minimal visual proof driven by one analysis snapshot: a readable 2D band/level view plus a lightweight projected 3D wireframe/shape view. This validates the combined 2D/3D direction without becoming the production scene engine.
- Compare an unprotected local control with streamed and downloaded Apple Music playback on built-in speakers and AirPlay, recording route and format context for every attempt.
- Make permission, source, route, silence, format, freshness, and protected-playback uncertainty visible as separate states.
- Keep transient PCM bounded and local, release audio resources safely, and leave Music playback unchanged.
- Produce a user-initiated, audio-free diagnostic report that is sufficient to decide whether a production visualizer should proceed.

**Non-Goals:**

- A production Resonant shell, scene library, Metal renderer, polished animation system, or 60-fps performance tuning.
- Playing, searching, authorizing, or managing Apple Music inside the spike; no Apple ID sign-in, MusicKit playback, lyrics, queue, or library replacement.
- Bypassing DRM, extracting protected files, using private now-playing APIs, or adding a virtual audio driver.
- Microphone capture, screen-image capture, audio recording, cloud processing, analytics, or automatic upload.
- A guaranteed compatibility claim for Apple Music subscription playback, AirPlay, Bluetooth, Lossless, or Spatial Audio.
- App Store distribution or a final signing/notarization decision.

## Decisions

### 1. Use a native SwiftUI diagnostic window, not a browser or command-line-only probe

The question depends on macOS permissions, the installed Music scripting dictionary, Core Audio device behavior, and output routes. A native window can request permissions in context, show actionable recovery states, enumerate the current route, and let the user start/stop each test without leaving Music. A command-line tool is useful for low-level logging but is insufficient as the primary user-facing diagnostic; a browser cannot access the required macOS APIs.

The native project should remain deliberately small: one app target, no third-party dependencies, and no network capability. Use a debug/local build first. Keep the capture and analysis services separable so a later production app can replace only the UI and scene layer.

### 2. Implement two isolated input adapters

**Metadata adapter:** use Music's supported scriptable interface through Apple Events/ScriptingBridge after inspecting the Music dictionary available on the target Mac. Poll or subscribe at a bounded low rate from a non-audio execution context. Normalize the result into an optional track snapshot containing identity, playback state, position, duration, and artwork availability. Missing properties remain unknown. Automation permission errors are reported independently from audio errors.

This is preferred over using MusicKit as a global now-playing bridge because the user wants to keep playing in the existing Music app. MusicKit may be considered in a later product phase for catalog enrichment, but it is not a dependency for this spike and is not treated as a decoded-PCM source.

**Audio adapter:** request system-audio access only after the user starts a capture test. Resolve the intended Music output source and attempt a private, nonmuting process tap feeding a temporary aggregate device. The tap/device lifecycle owns creation, start, route/format observation, stop, and destruction. It must never default to mixing all system applications or muting playback. If source resolution is ambiguous, the UI must ask the user to choose/retry rather than silently capture unrelated audio.

ScreenCaptureKit is not the primary adapter: although it can deliver audio, it introduces a different permission model and is not a protected-content workaround. A microphone is explicitly excluded because it is inaccurate with headphones, unsuitable for AirPlay, and less private.

### 3. Keep the real-time path bounded and timestamped

The audio callback performs only the minimum bounded copy into a preallocated single-producer/single-consumer ring buffer and records the source format plus host-time information. It does not allocate, lock on an unbounded mutex, touch SwiftUI, write files, or run FFT work.

A dedicated analysis worker drains the ring buffer and creates immutable feature snapshots. The starting diagnostic configuration is:

- 48 kHz where the route supplies it, while accepting and displaying the actual route sample rate.
- Stereo-aware RMS/peak measurements with an explicit channel-count report.
- A Hann-windowed 2,048-sample FFT with a 512-sample hop when the format permits it.
- Log-spaced band energy plus coarse bass (20–250 Hz), mids (250 Hz–4 kHz), and highs (4–16 kHz), bounded by the actual Nyquist frequency.
- A measured noise floor and attack/release smoothing for display only; sustained near-zero input must remain silence.
- Host-time freshness, format generation, sample discontinuity, and route identifiers on each snapshot.

The UI and visual proof consume the newest snapshot without blocking the audio path. Old snapshots are dropped rather than replayed. Audio buffers are cleared when the route, format, source, permission, or test generation changes.

### 4. Treat the diagnostic as a state machine, not a single “connected” flag

Track metadata health and audio health are separate. The capture state should make at least these externally visible states possible: idle, permission required, connecting, control signal verified, Apple Music test running, no usable signal, paused/silent, route changed/reconnecting, metadata unavailable, failed, and stopped.

The report classifier uses evidence in this order:

1. Verify the unprotected control on the selected route.
2. Verify fresh, nonzero samples and expected band behavior.
3. Test streamed Apple Music playback.
4. Test downloaded Apple Music playback.
5. Repeat on AirPlay if the route is available and explicitly selected.

Only correlated audible playback plus fresh samples can produce a **pass**. A broken control path produces **inconclusive**, not a conclusion about Apple Music. Audible subscription playback with no usable samples produces **fail or inconclusive**, with permission/source/route/silence evidence and a statement that protected-content behavior remains unproven. The spike never emits a “DRM detected” assertion from silence alone.

### 5. Use one snapshot to drive both a 2D and a 3D proof view

The diagnostic window should contain:

- A 2D signal panel: current state, RMS/freshness, sample rate/channel count, and bass/mids/highs bars or a compact spectrum.
- A lightweight 3D-coordinate projection rendered in a native canvas-style view: combined orbital curves/rings plus a deforming polygon or wireframe. Bass controls scale, mids deform, and highs add bounded edge detail. When the signal is silent or invalid, geometry settles and the state label explains why.
- A metadata panel showing optional title/artist/state and an explicit “metadata unavailable” treatment.
- Permission/source/route controls, start/stop actions, test phase, and a human-readable event log.
- A “Save diagnostic report” action that exports only sanitized measurements and user-selected test labels; it never exports PCM or artwork by default.

This is a proof of the data contract and the requested combination of shapes with 2D/3D motion, not the production Metal design from the HTML proposal. A later approved product phase can replace the proof view with the Orbital Bloom, Spectral Terrain, and Prism Drift Metal scenes without changing the capture contract.

### 6. Make cleanup and privacy ownership explicit

A session object owns every temporary capture resource and has one idempotent shutdown path. Stop it on user stop, app termination, permission revocation, route/format failure, and sleep/wake recovery. Destroy temporary aggregate devices and taps even when a test throws an error. Do not pause, seek, mute, or reroute Music as part of setup or teardown.

Use purpose strings that explain system audio is analyzed in memory to drive a visualizer and is not recorded or uploaded. Do not request microphone or screen-recording permission. Keep the report local and user-initiated. A bounded recent-event log may be retained in the current session; PCM and raw buffers are discarded on stop.

### 7. Build a repeatable evidence packet

Every test attempt records: test label, timestamp, macOS/app build identifier, selected route, format, channel count, permission states, metadata state, signal freshness, expected control frequency/band, measured band response, and result classification. It must also record whether the user could hear playback, because audibility cannot be inferred from samples alone.

Use a supplied or documented unprotected fixture with distinct low, middle, high, and silence intervals. Keep the Apple Music comparison manual and explicit: the app must not scrape or store protected content. The final spike output is a report and recommendation for the next OpenSpec change, not an automatic approval of the full visualizer.

## Risks / Trade-offs

- **[Protected Apple Music playback may expose no usable PCM]** → Run the unprotected control first, then test streamed/downloaded subscription tracks; report evidence honestly and stop before production implementation if the requirement is unsupported.
- **[A process tap may not map cleanly to the visible Music process or every output route]** → Resolve and display the source/route, never capture all applications silently, test speakers before AirPlay, and classify source/route failures separately.
- **[AirPlay and route changes can introduce latency, format changes, or inaccessible paths]** → Treat AirPlay as an explicit second test, show actual format/route, use host timestamps, flush stale data, and do not promise synchronization until measured.
- **[Music's scriptable dictionary or artwork fields may differ by OS version]** → Inspect the installed dictionary at runtime/build time, make all metadata optional, and keep audio validity independent.
- **[Permission wording may make users think the app records them]** → Explain the purpose before the OS prompt, request only system audio and Apple Events, show settings guidance after denial, and never request the microphone.
- **[Realtime callback bugs could drop audio or disrupt playback]** → Keep callback work bounded, use preallocated buffers, isolate analysis from UI, stress with route/format changes, and verify Music remains audible throughout.
- **[A small 2D/3D proof could be mistaken for production visual quality]** → Label it “feasibility preview,” keep the HTML proposal as the visual reference, and defer Metal materials, scene polish, and performance claims.
- **[The user's M5 Pro may use a newer OS/SDK than the documented sample baseline]** → Verify deployment availability on the actual SDK and record OS/build information in the report; do not infer compatibility from processor branding alone.
- **[Direct distribution, signing, and Mac App Store rules may diverge]** → Use local development signing for the spike and defer distribution choice until capture and entitlement behavior are known.

## Migration Plan

There is no production migration because this change adds a disposable feasibility target, not a released product. Run it as a local/debug app on the user's Mac. On stop, quit, or failure, destroy the temporary tap and aggregate device and discard transient buffers; uninstalling the spike requires no library or playback migration.

If the result passes and the user separately approves a production change, carry forward the normalized metadata/audio feature contract and the measured route constraints. Replace the proof renderer with the approved Metal scene engine only in that later change. If the result fails or remains inconclusive, preserve the audio-free report for decision-making and do not ship a visualizer that claims to react to subscription audio.

## Open Questions

These do not block the spike or change its behavioral contract:

- Which exact visual grammar wins for the production phase after the 2D/3D proof: Orbital Bloom, Terrain, Prism, or a composed scene?
- Which report format is most convenient for the user's later review (plain text, JSON, or both)?
- Which additional routes, codecs, Bluetooth devices, Lossless settings, or Spatial Audio modes should be tested after the speaker/AirPlay baseline?
