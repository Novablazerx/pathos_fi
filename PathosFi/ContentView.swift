import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        Group {
            switch appState.currentScreen {
            case .onboarding:
                RiskAssessmentView()
                    .environmentObject(appState)
            case .dashboard:
                DashboardView()
                    .environmentObject(appState)
            case .recommendations:
                ActionableView()
                    .environmentObject(appState)
            case .exploreAssets:
                ExploreAssetsView()
                    .environmentObject(appState)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: appState.currentScreen)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [UserRiskProfile.self, SmartPair.self, UserInteraction.self], inMemory: true)
}
