## ADDED Requirements

### Requirement: Represent stereo frequency energy with fixed sphere pairs
The scene SHALL contain 28 spheres arranged as 14 left/right frequency-region pairs. Each pair SHALL use the same region and geometric response, with left-channel energy controlling the left sphere's height and right-channel energy controlling the right sphere's height. Horizontal positions SHALL remain fixed. Spheres SHALL retain a small static clearance above their floor anchors at rest, with audio-driven lift added above that baseline so low-energy trails do not collapse against the floor. Static clearance SHALL NOT imply nonzero audio energy. Threads SHALL remain faintly visible at rest, including silence, and brighten with audio energy. Reduce Motion SHALL hide threads. Bass, midrange, and treble regions SHALL retain orange, mint, and purple identities respectively. Central rings SHALL retain broad mixed-audio reactivity.

#### Scenario: Left-only tone
- **WHEN** a fresh stereo tone exists only in the left channel
- **THEN** its frequency-region left sphere rises while its right partner remains settled

#### Scenario: Centered or opposite-phase tone
- **WHEN** both channels contain equal-energy tones in the same region, including opposite phases
- **THEN** both partners rise equally rather than being silenced by channel cancellation

#### Scenario: Resting threads remain visible
- **WHEN** a sphere has zero audio energy and Reduce Motion is off
- **THEN** its thread remains faintly visible without continuous idle animation
- **AND** increasing audio energy brightens the thread without a visibility threshold

#### Scenario: Low-energy sphere clearance
- **WHEN** a sphere receives little or no energy
- **THEN** it retains its static resting height above the floor anchor, and small positive energy still increases its height without a threshold dead zone

#### Scenario: Different frequency regions
- **WHEN** left and right channels contain tones in different regions
- **THEN** the corresponding channel/region spheres react independently without sideways movement

### Requirement: Keep stereo responses smooth and truthful
Sphere response SHALL use subtle frequency-dependent rise and settling behavior, identical within each pair and independent of selected display cadence. Bass SHALL settle more slowly than mids, and mids more slowly than treble. Mono input SHALL drive both partners equally; layouts without established left/right semantics SHALL use a symmetric mixed fallback. Stale input, silence, and Reduce Motion SHALL preserve settled geometric behavior without invented motion.

#### Scenario: Frame rate changes
- **WHEN** the user switches between 30, 60, and 120 FPS
- **THEN** audio response timing remains based on elapsed audio time rather than rendered frame counts

#### Scenario: Mono or multichannel fallback
- **WHEN** input is mono or has more than two channels without established stereo layout
- **THEN** both partners receive matching region energy

#### Scenario: Silence or unavailable input
- **WHEN** input becomes silent or stale, or Reduce Motion is enabled
- **THEN** sphere displacement and decorative trails settle or disable according to the existing signal and accessibility policies

### Requirement: Keep secondary controls in the native menu
Frame-rate selection and Diagnostics SHALL be available in the native macOS Visualizer menu rather than the canvas top bar. The existing persisted frame-rate preference SHALL continue applying immediately. Diagnostics SHALL open for the focused visualizer scene and be disabled when no such scene is focused.

#### Scenario: Change frame rate from the menu
- **WHEN** the user chooses 30, 60, or 120 FPS from Visualizer → Frame Rate
- **THEN** the preference updates immediately, survives relaunch, and the canvas contains no duplicate frame-rate picker

#### Scenario: Open diagnostics
- **WHEN** the visualizer window is focused and the user chooses Visualizer → Diagnostics
- **THEN** the existing diagnostics sheet opens without starting a separate capture session

### Requirement: Diagnose the active automatic-following session
Diagnostics and audio-free export SHALL use the active automatic-following session's measured route, PCM format, and signal status rather than an unused diagnostic capture engine. Playback being reported as playing SHALL NOT alone be presented as proof of live capture. Teardown SHALL remove current route and format facts rather than leave them displayed as active.

#### Scenario: Fresh audio is visualizing
- **WHEN** the active automatic session receives fresh nonsilent audio
- **THEN** Diagnostics reports live measured audio and that session's route and format, not “Capture not started” from another engine

#### Scenario: Waiting, silence, and teardown
- **WHEN** capture is awaiting input, receives silent PCM, or is torn down
- **THEN** Diagnostics distinguishes waiting for fresh audio, captured silence, and inactive capture respectively, and inactive capture has no current route or format

#### Scenario: Export active-session diagnostics
- **WHEN** the user exports a report during automatic visualization
- **THEN** the audio-free report includes the active measured route, format, and signal label without substituting a stale legacy capture report
