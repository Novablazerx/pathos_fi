import SwiftUI
import Combine
import Foundation

enum AppScreen {
    case onboarding
    case dashboard
    case recommendations
    case exploreAssets
}

class AppState: ObservableObject {
    @Published var currentScreen: AppScreen = .onboarding
    @Published var riskProfile: RiskProfileInput = RiskProfileInput()
    @Published var simulationResult: SimulationResult? = nil
    @Published var selectedPair: SmartPairModel? = nil

    @Published var holdings: [HeldAsset] = {
        let lib = OptimisationEngine.assetLibrary
        return [
            HeldAsset(asset: lib["SPY"]!, shares: 5,  avgCost: 420, currentPrice: 456),
            HeldAsset(asset: lib["QQQ"]!, shares: 3,  avgCost: 340, currentPrice: 382),
            HeldAsset(asset: lib["GLD"]!, shares: 10, avgCost: 185, currentPrice: 192),
        ]
    }()

    @Published var optionsByTicker: [String: [OptionsContract]] = {
        let cal = Calendar.current; let now = Date()
        func expiry(_ m: Int) -> Date { cal.date(byAdding: .month, value: m, to: now) ?? now }
        return [
            "SPY": [
                OptionsContract(underlyingTicker: "SPY", type: .put,  strikePrice: 440, expiryDate: expiry(3), contracts: 1, costBasis: 8.50, currentValue: 11.20),
                OptionsContract(underlyingTicker: "SPY", type: .call, strikePrice: 475, expiryDate: expiry(6), contracts: 2, costBasis: 6.30, currentValue: 4.80),
            ],
            "QQQ": [
                OptionsContract(underlyingTicker: "QQQ", type: .put,  strikePrice: 360, expiryDate: expiry(2), contracts: 1, costBasis: 7.20, currentValue: 9.40),
            ],
        ]
    }()

    var portfolioValue: Double { holdings.reduce(0) { $0 + $1.value } }

    func navigateToDashboard() {
        currentScreen = .dashboard
    }

    func navigateToRecommendations() {
        currentScreen = .recommendations
    }

    func navigateToExploreAssets() {
        currentScreen = .exploreAssets
    }

    func navigateBack() {
        switch currentScreen {
        case .recommendations, .exploreAssets:
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
