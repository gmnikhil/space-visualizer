## Purpose

Provide the Space Visualizer product identity and immersive audio-driven spatial scene while keeping signal truthfulness, smooth interaction, and idle efficiency observable and testable.

## ADDED Requirements

### Requirement: Evolve the existing application in place

The application SHALL be named Space Visualizer in its window, menus, app bundle, and launch documentation. It SHALL replace the existing product rather than introduce a second application. Git checkpoint 7c4b0b5 SHALL remain the documented rollback point.

#### Scenario: Build the renamed product
- **WHEN** the documented release build completes
- **THEN** the user can open Space Visualizer.app with consistent product identity and the verification scripts test the renamed targets without depending on an old Resonant executable

### Requirement: Prioritize the spatial canvas

The primary experience SHALL use the available window canvas for the existing audio-driven rings, spheres, depth cues, and trails, with fullscreen support and compact controls. Test-phase forms and verbose diagnostic logs SHALL NOT occupy the default scene. Diagnostics SHALL be available on demand and remain audio-free.

#### Scenario: Automatic visualization begins
- **WHEN** the app receives usable audio from playing Music
- **THEN** the full-canvas scene responds without requiring phase selection, evidence recording, or a Start capture button

#### Scenario: Waiting for Music
- **WHEN** Music is not playing
- **THEN** a static waiting presentation explains that the app will check every five seconds, without continuous idle animation

### Requirement: Preserve truthful signal and source-quality status

Visual movement SHALL derive from fresh measured audio, not track time or invented beats. Status SHALL distinguish waiting, starting, live, silence, unavailable input, and permission errors. Measured capture format SHALL remain distinct from source codec or quality; the app SHALL NOT infer Lossless, Hi-Res Lossless, 24-bit source precision, or Dolby Atmos from PCM format alone.

#### Scenario: Captured PCM is 192 kHz Float32
- **WHEN** the audio tap exposes that format but Music does not expose the active source-quality badge
- **THEN** diagnostics display the measured PCM rate and format and leave source quality unknown rather than claiming Hi-Res Lossless or Atmos

#### Scenario: Audio stops arriving
- **WHEN** a previously live stream ceases delivering fresh input
- **THEN** audio-driven visual movement settles within 250 ms of the last usable input, rather than continuing to display stale motion as live

### Requirement: Render at the available display cadence without queueing history

The app SHALL request display-synchronized rendering up to 120 Hz by default on supported displays, respecting the system-selected cadence. Analysis SHALL operate independently from rendering and supply the newest available result without an accumulating playback-history queue. High-rate audio and window changes SHALL preserve sample-rate-aware analysis and overlapping windows.

#### Scenario: Display supports only 60 Hz
- **WHEN** the window is on a 60 Hz display
- **THEN** rendering follows that display rather than scheduling 120 timer-driven redraws or changing Music playback

#### Scenario: UI work falls behind
- **WHEN** rendering or interaction temporarily stalls
- **THEN** the next visual update consumes the newest valid measurement instead of replaying queued old frames

#### Scenario: Higher-rate PCM arrives
- **WHEN** supported 96 or 192 kHz PCM is analyzed
- **THEN** known control tones still map to the expected frequency bands, and unsupported formats are reported explicitly instead of misinterpreted

### Requirement: Respect accessibility and idle power

Reduce Motion SHALL disable audio-driven geometric displacement and decorative trails while keeping meaningful signal status. In idle, closed, and stopped states the app SHALL perform no continuous visual rendering or FFT analysis. The app SHALL remain responsive during playback without increasing memory, observer, timer, or task counts over time.

#### Scenario: Reduce Motion is enabled
- **WHEN** the system preference is enabled during playback
- **THEN** geometry becomes static and accessible status continues to report the measured signal

#### Scenario: Long-running acceptance test
- **WHEN** the release app runs the documented target-Mac test for 15 minutes and cycles through play/pause 20 times
- **THEN** resource counts return to the idle baseline after each teardown, memory does not grow monotonically, and idle CPU averages below 2 percent of one core over a 60-second window with diagnostics closed

#### Scenario: Interactive performance acceptance
- **WHEN** the release app visualizes 48 kHz stereo on the target M5 Pro at the recorded window size and selected display cadence
- **THEN** a five-minute run meets a mean process CPU target below 50 percent of one core, p95 main-thread frame work below one display interval, and no app-caused interaction stalls above 100 ms; failures block production-readiness claims and require measured follow-up
