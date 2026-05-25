import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        Group {
            switch appState.currentScreen {
            case .loading:
                ZStack {
                    AuraBackground()
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.teal)
                        Text("Connecting to PathosFi...")
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            case .onboarding:
                RiskAssessmentView(profile: appState.riskProfile)
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
        .task {
            await appState.initializeApp()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [UserRiskProfile.self, SmartPair.self, UserInteraction.self], inMemory: true)
}
