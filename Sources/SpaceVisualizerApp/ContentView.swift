import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SpaceVisualizerCore

private func presentImageExportError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "Image export failed"
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
}

struct ContentView: View {
    @ObservedObject var engine: DiagnosticEngine
    @ObservedObject var automaticFollowing: AutomaticFollowingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingDiagnostics = false
    @State private var displayTelemetry = DisplayFrameTelemetry()

    private static let exportImageSize = CGSize(width: 3_840, height: 2_160)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.028, green: 0.025, blue: 0.05)
                .ignoresSafeArea()
            RadialGradient(
                colors: [Color.purple.opacity(0.20), Color.black.opacity(0.88)],
                center: .center,
                startRadius: 20,
                endRadius: 900
            )
            .ignoresSafeArea()

            SpatialCanvasView(
                featuresSource: automaticFollowing.visualFeatures,
                // Reduce Motion keeps the canvas static; status remains live.
                active: canvasIsActive && !reduceMotion,
                reduceMotion: reduceMotion,
                telemetry: displayTelemetry
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                topBar
                Spacer()
                statusOverlay
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            automaticFollowing.openWindow()
        }
        .onDisappear {
            engine.stop()
            automaticFollowing.closeWindow()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                engine.stop()
                automaticFollowing.sleep()
            } else if phase == .active {
                automaticFollowing.wake()
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            engine.stop()
            automaticFollowing.sleep()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            automaticFollowing.wake()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            engine.stop()
            automaticFollowing.quit()
        }
        .background {
            WindowVisibilityObserver { visible in
                guard automaticFollowing.presentation.isWindowVisible != visible else { return }
                automaticFollowing.setWindowVisible(visible)
            }
            .frame(width: 1, height: 1)
            .opacity(0.001)
            .accessibilityHidden(true)
        }
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsPanel(
                engine: engine,
                automaticFollowing: automaticFollowing,
                displayTelemetry: displayTelemetry
            )
            .frame(minWidth: 620, minHeight: 460)
        }
    }

    private var canvasIsActive: Bool {
        switch automaticFollowing.presentation.state {
        case .visualizing, .silent:
            return true
        default:
            return false
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("SPACE VISUALIZER")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(.purple.opacity(0.95))
                Text("A quiet space for Music")
                    .font(.system(size: 30, weight: .medium, design: .serif))
                Text("Apple Music remains in charge · local · nonmuting")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    showingDiagnostics = true
                } label: {
                    Label("Diagnostics", systemImage: "waveform.path.ecg")
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Opens optional audio-free diagnostics and export")

                Button {
                    exportCurrentImage()
                } label: {
                    Label("Export image", systemImage: "photo")
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Exports the current spatial scene as a 4K PNG image")
            }
        }
    }

    private var statusOverlay: some View {
        let presentation = automaticFollowing.presentation
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Circle()
                        .fill(statusColor(for: presentation.state))
                        .frame(width: 8, height: 8)
                    Text(stateLabel(for: presentation.state))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(statusColor(for: presentation.state))
                }
                Text(presentation.message)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                if let playback = presentation.playback,
                   let track = playback.track,
                   playback.isPlaying {
                    trackDetails(for: track, playback: playback)
                }
            }
            Spacer()
            permissionAction(for: presentation)
        }
        .padding(16)
        .frame(maxWidth: 780)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(statusColor(for: presentation.state).opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func permissionAction(for presentation: LifecyclePresentation) -> some View {
        if !presentation.consentIntent {
            Button("Enable automatic following") {
                automaticFollowing.enableAutomaticFollowing()
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        } else if presentation.state == .permissionBlocked || presentation.state == .failed {
            HStack(spacing: 8) {
                Button("Retry") { automaticFollowing.retry() }
                    .buttonStyle(.borderedProminent)
                Button("Settings") { openPrivacySettings() }
                    .buttonStyle(.bordered)
            }
        } else if presentation.state == .waiting {
            Text("Checks every 5 seconds while waiting")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func stateLabel(for state: SpaceVisualizerLifecycleState) -> String {
        switch state {
        case .onboarding: return "READY TO ENABLE"
        case .waiting: return "WAITING FOR MUSIC"
        case .starting: return "STARTING"
        case .visualizing: return "LIVE"
        case .silent: return "QUIET"
        case .suspended: return "SUSPENDED"
        case .recovering: return "RECOVERING"
        case .permissionBlocked: return "PERMISSION REQUIRED"
        case .failed: return "RETRY REQUIRED"
        case .terminated: return "TERMINATED"
        }
    }

    private func statusColor(for state: SpaceVisualizerLifecycleState) -> Color {
        switch state {
        case .visualizing: return .green
        case .silent: return .yellow
        case .starting, .recovering, .permissionBlocked: return .orange
        case .failed: return .red
        case .terminated: return .secondary
        case .onboarding, .waiting, .suspended: return .purple
        }
    }

    @ViewBuilder
    private func trackDetails(for track: TrackSnapshot, playback: PlaybackObservation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let title = nonEmpty(track.title) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
            }
            if let artist = nonEmpty(track.artist) {
                Text(artist)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if let album = nonEmpty(track.album) {
                Text("Album · \(album)")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            // Align ticks to playback seconds instead of an unrelated UI timer.
            TimelineView(.periodic(from: playbackSecondAnchor(playback), by: 1)) { context in
                if let position = formattedTime(
                    displayedSeconds(
                        track.position,
                        duration: track.duration,
                        playback: playback,
                        now: context.date
                    )
                ) {
                    let duration = formattedTime(track.duration) ?? "—"
                    Text("Position · \(position) / \(duration)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func formattedTime(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        let totalSeconds = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func displayedSeconds(
        _ position: Double?,
        duration: Double?,
        playback: PlaybackObservation,
        now: Date
    ) -> Double? {
        guard let position, position.isFinite, position >= 0 else { return nil }
        var displayed = position
        if playback.isPlaying, let observedAt = playback.positionObservedAt {
            let elapsed = now.timeIntervalSince(observedAt)
            if elapsed.isFinite, elapsed > 0 { displayed += elapsed }
        }
        if let duration, duration.isFinite, duration >= 0 {
            displayed = min(displayed, duration)
        }
        return displayed
    }

    private func playbackSecondAnchor(_ playback: PlaybackObservation) -> Date {
        guard let observedAt = playback.positionObservedAt,
              let position = playback.track?.position,
              position.isFinite, position >= 0 else { return Date() }
        // A tiny margin avoids floating-point rounding back into the prior second.
        return observedAt.addingTimeInterval(-position.truncatingRemainder(dividingBy: 1) + 0.002)
    }

    private func exportCurrentImage() {
        let size = Self.exportImageSize
        let artwork = VisualizerExportView(
            features: automaticFollowing.visualFeatures.snapshot(),
            reduceMotion: reduceMotion,
            playback: automaticFollowing.presentation.playback,
            status: stateLabel(for: automaticFollowing.presentation.state),
            message: automaticFollowing.presentation.message,
            statusColor: statusColor(for: automaticFollowing.presentation.state)
        )
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: artwork)
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        renderer.scale = 1

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            presentImageExportError("The 4K scene could not be rendered.")
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "space-visualizer-3840x2160.png"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try png.write(to: url, options: .atomic)
            } catch {
                presentImageExportError(error.localizedDescription)
            }
        }
    }

    private func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct SpatialCanvasView: View {
    let featuresSource: LatestAudioFeatures
    let active: Bool
    let reduceMotion: Bool
    let telemetry: DisplayFrameTelemetry
    @State private var features: AudioFeatures = .settled

    var body: some View {
        SpatialArtworkView(features: features, reduceMotion: reduceMotion)
            .overlay(alignment: .topLeading) {
                DisplayRefreshDriver(active: active, telemetry: telemetry) {
                    let next = featuresSource.snapshot()
                    if features != next { features = next }
                }
                .frame(width: 1, height: 1)
                .opacity(0.001)
                .accessibilityHidden(true)
            }
            .onChange(of: active) { _, isActive in
                if !isActive { features = .settled }
            }
            .accessibilityLabel("Space Visualizer spatial scene driven by fresh Apple Music audio")
    }
}

/// Static artwork shared by the live Canvas and the 4K export. It has no
/// display link, mailbox, or status bindings, so exporting cannot start a
/// second high-frequency update path.
private struct SpatialArtworkView: View {
    let features: AudioFeatures
    let reduceMotion: Bool
    private let spatialScale: CGFloat = 0.75

    var body: some View {
        Canvas { context, size in
            SpatialStage.draw(context: context, size: size, features: features, reduceMotion: reduceMotion)
            drawRings(context: &context, size: size)
        }
        // Apply the same centered scale in both windowed and fullscreen modes.
        .scaleEffect(spatialScale, anchor: .center)
    }

    private func drawRings(context: inout GraphicsContext, size: CGSize) {
        let parameters = VisualParameters(features: features)
        let rings = ShapeGeometry.projectedRings(features: features, reduceMotion: reduceMotion)
        // Keep the full high-energy projection inside the Canvas before the
        // centered 75% presentation scale is applied.
        let center = CGPoint(x: size.width / 2, y: size.height * 0.50)
        let base = min(size.width, size.height) * 0.28
        for ringIndex in rings.indices {
            let color: Color = ringIndex % 3 == 0 ? .orange : (ringIndex % 3 == 1 ? .purple : .mint)
            var previous: CGPoint?
            for projected in rings[ringIndex] {
                let point = CGPoint(
                    x: center.x + CGFloat(projected.x) * base,
                    y: center.y + CGFloat(projected.y) * base
                )
                if let previous {
                    var segment = Path()
                    segment.move(to: previous)
                    segment.addLine(to: point)
                    let front = min(1.0, max(0.0, (projected.depth + 1.6) / 3.2))
                    let detail = reduceMotion ? 0 : Double(parameters.edgeDetail)
                    context.stroke(
                        segment,
                        with: .color(color.opacity(min(1, 0.10 + front * 0.56 + detail * 0.22))),
                        lineWidth: 0.7 + front * 1.5 + detail * 0.8
                    )
                }
                previous = point
            }
        }
    }
}

private struct VisualizerExportView: View {
    let features: AudioFeatures
    let reduceMotion: Bool
    let playback: PlaybackObservation?
    let status: String
    let message: String
    let statusColor: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.028, green: 0.025, blue: 0.05)
            RadialGradient(
                colors: [Color.purple.opacity(0.20), Color.black.opacity(0.88)],
                center: .center,
                startRadius: 20,
                endRadius: 900
            )
            SpatialArtworkView(features: features, reduceMotion: reduceMotion)
            VStack(alignment: .leading, spacing: 14) {
                Text("SPACE VISUALIZER")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(.purple.opacity(0.95))
                Text("A quiet space for Music")
                    .font(.system(size: 60, weight: .medium, design: .serif))
                    .foregroundStyle(.white)
                Text("Apple Music remains in charge · local · nonmuting")
                    .font(.system(size: 20, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.68))
                Spacer()
                HStack(spacing: 18) {
                    Circle().fill(statusColor).frame(width: 16, height: 16)
                    Text(status)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(statusColor)
                }
                Text(message)
                    .font(.system(size: 24, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                if let playback, let track = playback.track {
                    songDetails(for: track, playback: playback)
                }
            }
            .padding(90)
            .frame(maxWidth: 1_800, maxHeight: .infinity, alignment: .leading)
            .shadow(color: .black.opacity(0.8), radius: 16, y: 4)
        }
    }

    @ViewBuilder
    private func songDetails(for track: TrackSnapshot, playback: PlaybackObservation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = nonEmpty(track.title) {
                Text(title)
                    .font(.system(size: 48, weight: .medium, design: .serif))
                    .foregroundStyle(.white)
            }
            if let artist = nonEmpty(track.artist) {
                Text(artist)
                    .font(.system(size: 28, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
            }
            if let album = nonEmpty(track.album) {
                Text("Album · \(album)")
                    .font(.system(size: 22, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
            }
            if let position = formattedTime(
                displayedSeconds(
                    track.position,
                    duration: track.duration,
                    playback: playback,
                    now: Date()
                )
            ) {
                let duration = formattedTime(track.duration) ?? "—"
                Text("Position · \(position) / \(duration)")
                    .font(.system(size: 20, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func formattedTime(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        let totalSeconds = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func displayedSeconds(
        _ position: Double?,
        duration: Double?,
        playback: PlaybackObservation,
        now: Date
    ) -> Double? {
        guard let position, position.isFinite, position >= 0 else { return nil }
        var displayed = position
        if playback.isPlaying, let observedAt = playback.positionObservedAt {
            let elapsed = now.timeIntervalSince(observedAt)
            if elapsed.isFinite, elapsed > 0 { displayed += elapsed }
        }
        if let duration, duration.isFinite, duration >= 0 {
            displayed = min(displayed, duration)
        }
        return displayed
    }
}

private struct DiagnosticsPanel: View {
    @ObservedObject var engine: DiagnosticEngine
    @ObservedObject var automaticFollowing: AutomaticFollowingViewModel
    let displayTelemetry: DisplayFrameTelemetry
    @Environment(\.dismiss) private var dismiss
    @State private var exportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Diagnostics")
                        .font(.system(size: 26, weight: .medium, design: .serif))
                    Text("Optional, local, audio-free evidence")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 10) {
                GridRow { Text("Following"); Text(automaticFollowing.presentation.state.rawValue) }
                GridRow { Text("Playback"); Text(automaticFollowing.presentation.playback?.state.rawValue ?? "unknown") }
                GridRow { Text("Route"); Text(engine.state.route?.name ?? "unknown") }
                GridRow { Text("Format"); Text(formatLabel) }
                GridRow { Text("Signal"); Text(engine.viewModel.audioLabel) }
                GridRow { Text("Display tick p50/p95"); Text(displayTimingLabel) }
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)

            Text(engine.captureDiagnostics)
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Text("Source quality: unknown · PCM format does not prove Lossless, Hi-Res, or Atmos")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Export audio-free report…") { exportReport() }
                    .buttonStyle(.bordered)
            }

            if let exportError {
                Text(exportError)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(24)
        .background(Color(red: 0.055, green: 0.05, blue: 0.08))
    }

    private var formatLabel: String {
        guard let format = engine.state.format else { return "unknown" }
        return "\(Int(format.sampleRate)) Hz · \(format.channelCount) ch · \(format.sampleFormat.rawValue)"
    }

    private var displayTimingLabel: String {
        let summary = displayTelemetry.snapshot().frameWork
        let p50 = summary.p50Nanoseconds.map(String.init) ?? "—"
        let p95 = summary.p95Nanoseconds.map(String.init) ?? "—"
        return "\(p50)/\(p95) ns"
    }

    private func exportReport() {
        let export = SpaceVisualizerDiagnosticsExport(
            appBuild: engine.buildContext,
            presentation: automaticFollowing.presentation,
            legacyReport: engine.lastReport,
            display: displayTelemetry.snapshot()
        )
        do {
            let data = try export.encodedJSON()
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "space-visualizer-diagnostic-report.json"
            panel.allowedContentTypes = [.json]
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    exportError = error.localizedDescription
                }
            }
        } catch {
            exportError = error.localizedDescription
        }
    }
}
