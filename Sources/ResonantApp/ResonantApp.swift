import SwiftUI
import ResonantCore

@main
struct ResonantApp: App {
    @StateObject private var engine = DiagnosticEngine.live()

    var body: some Scene {
        WindowGroup("Resonant Feasibility Spike") {
            ContentView(engine: engine)
                .frame(minWidth: 1_040, minHeight: 760)
        }
    }
}
