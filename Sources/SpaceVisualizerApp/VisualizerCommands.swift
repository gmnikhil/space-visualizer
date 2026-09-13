import SwiftUI
import SpaceVisualizerCore

private struct ShowVisualizerDiagnosticsKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var showVisualizerDiagnostics: (() -> Void)? {
        get { self[ShowVisualizerDiagnosticsKey.self] }
        set { self[ShowVisualizerDiagnosticsKey.self] = newValue }
    }
}

struct VisualizerCommands: Commands {
    @AppStorage("visualizerFramesPerSecond") private var framesPerSecond = DisplayCadencePolicy.defaultFramesPerSecond
    @FocusedValue(\.showVisualizerDiagnostics) private var showDiagnostics

    var body: some Commands {
        CommandMenu("Visualizer") {
            Picker("Frame Rate", selection: Binding(
                get: { DisplayCadencePolicy.validatedFramesPerSecond(framesPerSecond) },
                set: { framesPerSecond = $0 }
            )) {
                ForEach(DisplayCadencePolicy.supportedFramesPerSecond, id: \.self) { rate in
                    Text("\(rate) FPS").tag(rate)
                }
            }
            Divider()
            Button("Diagnostics…") { showDiagnostics?() }
                .disabled(showDiagnostics == nil)
        }
    }
}
