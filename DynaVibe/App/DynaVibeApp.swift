import SwiftUI
import SwiftData

@main
struct DynaVibeApp: App {
    private var modelContainer = try! ModelContainer(for: Project.self, Measurement.self)
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
