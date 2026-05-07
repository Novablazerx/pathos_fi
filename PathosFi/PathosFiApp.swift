import SwiftUI
import SwiftData

@main
struct PathosFiApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([UserRiskProfile.self, SmartPair.self, UserInteraction.self])
        let diskConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [diskConfig])
        } catch {
            let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [memoryConfig])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
