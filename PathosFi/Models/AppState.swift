import SwiftUI
import Combine

enum AppScreen {
    case onboarding
    case dashboard
    case recommendations
}

class AppState: ObservableObject {
    @Published var currentScreen: AppScreen = .onboarding
    @Published var riskProfile: RiskProfileInput = RiskProfileInput()
    @Published var simulationResult: SimulationResult? = nil
    @Published var selectedPair: SmartPairModel? = nil

    func navigateToDashboard() {
        currentScreen = .dashboard
    }

    func navigateToRecommendations() {
        currentScreen = .recommendations
    }

    func navigateBack() {
        switch currentScreen {
        case .recommendations:
            currentScreen = .dashboard
        case .dashboard:
            currentScreen = .onboarding
        case .onboarding:
            break
        }
    }
}

struct RiskProfileInput {
    var startingCapital: Double = 10000
    var timeHorizon: TimeHorizon = .sixMonths
    var maxLossPercent: Double = 15.0
}

enum TimeHorizon: String, CaseIterable, Identifiable {
    case oneMonth   = "1 Month"
    case sixMonths  = "6 Months"
    case oneYear    = "1 Year"
    case fiveYears  = "5 Years"

    var id: String { rawValue }

    var months: Int {
        switch self {
        case .oneMonth:   return 1
        case .sixMonths:  return 6
        case .oneYear:    return 12
        case .fiveYears:  return 60
        }
    }

    var annualFraction: Double {
        Double(months) / 12.0
    }
}
