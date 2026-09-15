import SwiftUI
import SpaceVisualizerCore

// Own the live models without forwarding their frequent updates to the scene.
// ContentView observes them directly; background polling must not invalidate menus.
private final class AppModels: ObservableObject {
    let engine = DiagnosticEngine.live()
    let automaticFollowing = AutomaticFollowingViewModel.live()
}

@main
struct SpaceVisualizerApp: App {
    @StateObject private var models = AppModels()

    var body: some Scene {
        Window("Space Visualizer", id: "main") {
            ContentView(engine: models.engine, automaticFollowing: models.automaticFollowing)
                .frame(minWidth: 1_040, minHeight: 760)
        }
        .commands { VisualizerCommands() }
    }
}
