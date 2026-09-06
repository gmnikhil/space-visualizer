import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import ResonantCore

struct ContentView: View {
    @ObservedObject var engine: DiagnosticEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedRouteID = ""
    @State private var expectedBand = "bass"
    @State private var measuredBand = "bass"
    @State private var playbackAudible = false
    @State private var controlVerified = false
    @State private var showReportError = false
    @State private var reportErrorMessage = ""
    @State private var displayMode: DiagnosticDisplayMode = .threeD

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.05, blue: 0.08)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    connectionCard
                    signalCard
                    evidenceCard
                    eventCard
                    footer
                }
                .padding(28)
                .frame(maxWidth: 1_420, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            engine.refreshRoutes()
        }
        .onDisappear {
            // WindowGroup does not terminate the process when its last window
            // closes, so explicitly release any active tap/device here.
            engine.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { engine.stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            engine.stop()
        }
        .background {
            DisplayRefreshDriver(active: engine.isCapturing) { engine.pollFeatures() }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .task(id: engine.isMetadataObservationEnabled) {
            guard engine.isMetadataObservationEnabled else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                catch { return }
                guard !Task.isCancelled, engine.isMetadataObservationEnabled else { return }
                _ = engine.refreshMetadata()
            }
        }
        .onChange(of: engine.routes) { _, routes in
            guard selectedRouteID.isEmpty else { return }
            selectedRouteID = routes.first(where: \.isActive)?.id ?? routes.first?.id ?? ""
        }
        .alert("Report export failed", isPresented: $showReportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reportErrorMessage)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("RESONANT")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(.purple.opacity(0.9))
                Text("Native audio feasibility")
                    .font(.system(size: 32, weight: .medium, design: .serif))
                Text("Apple Music remains the player. This spike tests whether permitted audio can drive a real visualizer.")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                StatusBadge(text: engine.state.captureState.rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).uppercased(), color: captureColor)
                Text("FEASIBILITY PREVIEW")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var connectionCard: some View {
        Panel(title: "Connection", subtitle: "Two independent paths · no Apple ID required") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    PathStatus(
                        icon: "music.note",
                        title: "Music metadata",
                        value: engine.viewModel.metadataLabel,
                        detail: metadataDetail,
                        color: metadataColor
                    )
                    PathStatus(
                        icon: "waveform",
                        title: "Audio samples",
                        value: engine.viewModel.audioLabel,
                        detail: engine.state.message,
                        color: audioColor
                    )
                }
                Divider().overlay(Color.white.opacity(0.1))
                if engine.state.metadataHealth == .permissionRequired {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.open")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(engine.viewModel.metadataPermissionExplanation)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(engine.viewModel.metadataRecoveryLabel)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.orange.opacity(0.9))
                        }
                        Spacer()
                        Button("Retry Music access") { engine.beginMetadataObservation() }
                            .buttonStyle(.bordered)
                        Button("Open Automation Settings") { openAutomationSettings() }
                            .buttonStyle(.bordered)
                    }
                }
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("TEST PHASE")
                            .captionLabel()
                        Picker("Test phase", selection: Binding(
                            get: { engine.phase },
                            set: { engine.setPhase($0) }
                        )) {
                            Text("Unprotected control").tag(TestPhase.unprotectedControl)
                            Text("Streamed subscription").tag(TestPhase.streamedSubscription)
                            Text("Downloaded subscription").tag(TestPhase.downloadedSubscription)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 220, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text("OUTPUT ROUTE")
                            .captionLabel()
                        Picker("Output route", selection: $selectedRouteID) {
                            Text(engine.routes.isEmpty ? "No routes found" : "Choose a route").tag("")
                            ForEach(engine.routes) { route in
                                Text("\(route.name)\(route.isActive ? " · active" : "")")
                                    .tag(route.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 280, alignment: .leading)
                    }
                    Spacer()
                    if !engine.isMetadataObservationEnabled {
                        Button("Connect to Music") { engine.beginMetadataObservation() }
                            .buttonStyle(.bordered)
                    }
                    Button(engine.isCapturing ? "Stop capture" : "Start capture") {
                        if engine.isCapturing { engine.stop() }
                        else { engine.start(routeID: selectedRouteID.isEmpty ? nil : selectedRouteID) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(engine.isCapturing ? .red.opacity(0.85) : .purple)
                    Button("Refresh") {
                        engine.refreshRoutes()
                        engine.beginMetadataObservation()
                    }
                    .buttonStyle(.bordered)
                }
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.mint)
                    Text("Local only: no microphone, recording, upload, or cloud analysis. The system prompt may call this system-audio recording access.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if engine.permission.status == .denied {
                        Button("Privacy Settings") { openPrivacySettings() }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var signalCard: some View {
        let features = engine.lastFeatures
        return Panel(title: "Signal proof", subtitle: "One feature snapshot feeds both views") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Source quality: unknown · Lossless / Hi-Res / Dolby Atmos not exposed by the PCM tap")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(engine.captureDiagnostics)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                HStack {
                    Picker("Display", selection: $displayMode) {
                        ForEach(DiagnosticDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Spacer()
                    Text(engine.viewModel.liveLabel)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(engine.viewModel.isLive ? .green : .secondary)
                        .accessibilityLabel("Signal status: \(engine.viewModel.liveLabel)")
                    Text("RMS \(percent(features.rms)) · peak \(percent(features.peak))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                LiveProofViews(store: engine.visualFeatures, displayMode: displayMode, reduceMotion: reduceMotion)
                HStack(spacing: 14) {
                    MetricTile(title: "BASS", value: percent(features.bass), tint: .orange)
                    MetricTile(title: "MIDS", value: percent(features.mids), tint: .mint)
                    MetricTile(title: "HIGHS", value: percent(features.highs), tint: .purple)
                    MetricTile(title: "FRESH", value: features.isFresh ? "YES" : "NO", tint: features.isFresh ? .green : .red)
                    MetricTile(title: "SAMPLES", value: features.isSilent ? "QUIET" : "PRESENT", tint: features.isSilent ? .yellow : .green)
                }
                HStack(spacing: 18) {
                    Fact(label: "Route", value: engine.state.route?.name ?? "Unknown")
                    Fact(label: "Format", value: formatLabel)
                    Fact(label: "Generation", value: String(features.generation))
                    Fact(label: "Callback", value: engine.hasReceivedAudioCallback ? "RECEIVED" : "NO DATA")
                    Fact(label: "Timestamp", value: features.timestamp == 0 ? "—" : String(features.timestamp))
                }
            }
        }
    }

    private var evidenceCard: some View {
        Panel(title: "Record evidence", subtitle: "The result is a measurement, not a DRM diagnosis") {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 20) {
                    Toggle("I can hear playback", isOn: $playbackAudible)
                    if engine.phase == .unprotectedControl {
                        Toggle("Control signal verified", isOn: $controlVerified)
                    } else {
                        Label(
                            engine.hasVerifiedControl ? "Control path verified" : "Run the control first",
                            systemImage: engine.hasVerifiedControl ? "checkmark.circle" : "exclamationmark.triangle"
                        )
                        .foregroundStyle(engine.hasVerifiedControl ? .green : .orange)
                        .accessibilityLabel(engine.hasVerifiedControl ? "Control path verified" : "Control path has not been verified")
                    }
                    Spacer()
                }
                HStack(spacing: 14) {
                    Picker("Expected band", selection: $expectedBand) {
                        Text("Bass").tag("bass")
                        Text("Mids").tag("mids")
                        Text("Highs").tag("highs")
                    }
                    .pickerStyle(.menu)
                    Picker("Measured band", selection: $measuredBand) {
                        Text("Bass").tag("bass")
                        Text("Mids").tag("mids")
                        Text("Highs").tag("highs")
                        Text("None").tag("")
                    }
                    .pickerStyle(.menu)
                    Spacer()
                    Button("Record current attempt") {
                        engine.recordAttempt(
                            playbackAudible: playbackAudible,
                            expectedBand: expectedBand,
                            measuredBand: measuredBand.isEmpty ? nil : measuredBand,
                            controlVerified: controlVerified
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange.opacity(0.9))
                    Button("Save report…") { saveReport() }
                        .buttonStyle(.bordered)
                        .disabled(engine.lastReport == nil)
                }
                if let report = engine.lastReport {
                    Text("\(report.tests.count) attempt(s) recorded · latest: \(report.tests.last?.result.rawValue.uppercased() ?? "—")")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.orange)
                } else {
                    Text("Run the control first. A failed control makes subscription results inconclusive.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var eventCard: some View {
        Panel(title: "Session log", subtitle: "Bounded, local, and intentionally boring") {
            if engine.events.isEmpty {
                Text("No events yet.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(engine.events.suffix(12).reversed()), id: \.self) { event in
                        Text(event)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Resonant · feasibility spike · Apple Music remains in charge")
            Spacer()
            Text("Full production visualizer is not approved")
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.secondary)
    }

    private var captureColor: Color {
        switch engine.state.captureState {
        case .active: return .green
        case .connecting, .reconnecting, .permissionRequired: return .orange
        case .failed: return .red
        case .stopped: return .secondary
        case .idle: return .purple
        }
    }

    private var metadataColor: Color {
        switch engine.state.metadataHealth {
        case .available: return .green
        case .permissionRequired: return .orange
        case .unavailable: return .red
        case .unknown: return .secondary
        }
    }

    private var audioColor: Color {
        switch engine.state.audioHealth {
        case .live: return .green
        case .silent: return .yellow
        case .permissionRequired, .connecting, .reconnecting: return .orange
        case .failed, .unavailable: return .red
        case .stopped, .unknown: return .secondary
        }
    }

    private var metadataDetail: String {
        "Title: \(engine.viewModel.metadataTitleLabel) · Artist: \(engine.viewModel.metadataArtistLabel)\nState: \(engine.viewModel.metadataPlaybackStateLabel) · Position: \(engine.viewModel.metadataPositionLabel) / \(engine.viewModel.metadataDurationLabel)"
    }

    private var formatLabel: String {
        guard let format = engine.state.format else { return "Unknown" }
        return "\(Int(format.sampleRate)) Hz · \(format.channelCount) ch · \(format.sampleFormat.rawValue)"
    }

    private func percent(_ value: Float) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }

    private func saveReport() {
        guard let report = engine.lastReport else { return }
        do {
            let data = try report.encodedJSON()
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "resonant-diagnostic-report.json"
            panel.allowedContentTypes = [.json]
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                do { try data.write(to: url, options: .atomic) }
                catch {
                    reportErrorMessage = error.localizedDescription
                    showReportError = true
                }
            }
        } catch {
            reportErrorMessage = error.localizedDescription
            showReportError = true
        }
    }
}

private struct Panel<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 21, weight: .medium, design: .serif))
                Text(subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            content()
        }
        .padding(20)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

private struct StatusBadge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.16), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 1))
            .foregroundStyle(color)
    }
}

private struct PathStatus: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let color: Color
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct Fact: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SignalBandsView: View, Equatable {
    let features: AudioFeatures
    private var colors: [Color] { [.orange, .mint, .purple] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RELATIVE ENERGY · NOT CALIBRATED LOUDNESS")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colors[index % colors.count].opacity(0.7))
                            .frame(height: max(2, geometry.size.height * CGFloat(value)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .padding(14)
            .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Text("20 Hz")
                Spacer()
                Text("250 Hz")
                Spacer()
                Text("4 kHz")
                Spacer()
                Text("16 kHz")
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }

    private var values: [Float] {
        if features.bands.isEmpty {
            return [features.bass, features.bass, features.mids, features.mids, features.highs, features.highs]
        }
        return features.bands
    }
}

/// Only this subtree observes high-frequency audio updates, not the scrolling shell.
private struct LiveProofViews: View {
    @ObservedObject var store: VisualFeatureStore
    let displayMode: DiagnosticDisplayMode
    let reduceMotion: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            if displayMode != .threeD {
                SignalBandsView(features: store.features)
                    .equatable()
                    .frame(minWidth: 320, maxWidth: .infinity, minHeight: 230)
            }
            if displayMode != .twoD {
                ShapeProofView(features: store.features, reduceMotion: reduceMotion)
                    .equatable()
                    .frame(minWidth: 320, maxWidth: .infinity, minHeight: displayMode == .threeD ? 560 : 380)
            }
        }
    }
}

private struct ShapeProofView: View, Equatable {
    let features: AudioFeatures
    let reduceMotion: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SPATIAL PLAYGROUND · AUDIO-DRIVEN FEASIBILITY PREVIEW")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            Canvas { context, size in
                SpatialStage.draw(context: context, size: size, features: features, reduceMotion: reduceMotion)
                let parameters = VisualParameters(features: features)
                let rings = ShapeGeometry.projectedRings(features: features, reduceMotion: reduceMotion)
                let center = CGPoint(x: size.width / 2, y: size.height * 0.36)
                let base = min(size.width, size.height) * 0.28
                for ring in rings.indices {
                    let color: Color = ring % 3 == 0 ? .orange : (ring % 3 == 1 ? .purple : .mint)
                    var previous: CGPoint?
                    for projected in rings[ring] {
                        let point = CGPoint(x: center.x + CGFloat(projected.x) * base,
                                            y: center.y + CGFloat(projected.y) * base)
                        if let previous {
                            var segment = Path()
                            segment.move(to: previous)
                            segment.addLine(to: point)
                            let front = min(1.0, max(0.0, (projected.depth + 1.6) / 3.2))
                            let detail = reduceMotion ? 0 : Double(parameters.edgeDetail)
                            context.stroke(segment,
                                with: .color(color.opacity(min(1, 0.12 + front * 0.55 + detail * 0.25))),
                                lineWidth: 0.6 + front * 1.3 + detail * 0.8)
                        }
                        previous = point
                    }
                }
                let dotRadius: CGFloat = reduceMotion ? 3 : 3 + CGFloat(parameters.expansion) * 8
                context.fill(Path(ellipseIn: CGRect(x: center.x - dotRadius, y: center.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)), with: .color(.white.opacity(0.75)))
            }
            .clipped()
            .accessibilityLabel("Spatial audio preview with perspective rings and frequency-driven spheres")
            .background(
                RadialGradient(colors: [Color.purple.opacity(0.22), Color.black.opacity(0.8)], center: .center, startRadius: 4, endRadius: 480),
                in: RoundedRectangle(cornerRadius: 8)
            )
            Text("Bass → bounce · mids → sway · highs → sparks. Select 3D shape for the full-width stage.")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

private extension Text {
    func captionLabel() -> some View {
        self.font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
    }
}
