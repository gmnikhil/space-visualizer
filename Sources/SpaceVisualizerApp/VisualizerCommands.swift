import SwiftUI
import SpaceVisualizerCore

// A stable, window-owned command target rather than new closures on every
// playback update. ContentView observes requests; the scene does not.
final class VisualizerMenuActions: ObservableObject {
    @Published var isPresented = false
    @Published private(set) var imageExportRequest = 0

    func show() { isPresented = true }
    func exportImage() { imageExportRequest += 1 }
}

private struct VisualizerMenuActionsKey: FocusedValueKey {
    typealias Value = VisualizerMenuActions
}

extension FocusedValues {
    var visualizerMenuActions: VisualizerMenuActions? {
        get { self[VisualizerMenuActionsKey.self] }
        set { self[VisualizerMenuActionsKey.self] = newValue }
    }
}

struct VisualizerCommands: Commands {
    @AppStorage("visualizerFramesPerSecond") private var framesPerSecond = DisplayCadencePolicy.defaultFramesPerSecond
    @FocusedValue(\.visualizerMenuActions) private var menuActions

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
            Button("Export Image…") { menuActions?.exportImage() }
                .disabled(menuActions == nil)
                .accessibilityHint("Exports the current spatial scene as a 4K PNG image")
            Button("Diagnostics…") { menuActions?.show() }
                .disabled(menuActions == nil)
        }
    }
}
