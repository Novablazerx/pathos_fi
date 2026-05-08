import SwiftUI
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var simulationResult: SimulationResult? = nil
    @Published var isSimulating: Bool = false

    let heldAssets: [HeldAsset] = {
        let lib = OptimisationEngine.assetLibrary
        return [
            HeldAsset(asset: lib["SPY"]!,  shares: 5,  avgCost: 420, currentPrice: 456),
            HeldAsset(asset: lib["QQQ"]!,  shares: 3,  avgCost: 340, currentPrice: 382),
            HeldAsset(asset: lib["GLD"]!,  shares: 10, avgCost: 185, currentPrice: 192),
        ]
    }()

    let optionsByTicker: [String: [OptionsContract]] = {
        let cal = Calendar.current
        let now = Date()
        func expiry(months: Int) -> Date { cal.date(byAdding: .month, value: months, to: now) ?? now }
        return [
            "SPY": [
                OptionsContract(underlyingTicker: "SPY", type: .put,  strikePrice: 440, expiryDate: expiry(months: 3),  contracts: 1, costBasis: 8.50,  currentValue: 11.20),
                OptionsContract(underlyingTicker: "SPY", type: .call, strikePrice: 475, expiryDate: expiry(months: 6),  contracts: 2, costBasis: 6.30,  currentValue: 4.80),
            ],
            "QQQ": [
                OptionsContract(underlyingTicker: "QQQ", type: .put,  strikePrice: 360, expiryDate: expiry(months: 2),  contracts: 1, costBasis: 7.20,  currentValue: 9.40),
            ],
        ]
    }()

    private let apiClient = BackendAPIClient()

    func runSimulation(profile: RiskProfileInput) async {
        isSimulating = true
        defer { isSimulating = false }

        // Fetch AI-predicted volatility from backend (falls back gracefully)
        let volResponse = await apiClient.fetchPredictedVolatility(
            tickers: ["QQQ", "SPY"],
            horizon: profile.timeHorizon
        )

        // Run on-device Monte Carlo (10,000 paths via Accelerate)
        // Use a simple 100% QQQ unhedged baseline for the dashboard view
        guard let primaryAsset = OptimisationEngine.assetLibrary["QQQ"],
              let hedgeAsset = OptimisationEngine.assetLibrary["TLT"] else {
            return
        }

        let result = MonteCarloEngine.simulate(
            primaryWeight: 1.0,
            hedgeWeight: 0.0,
            primary: primaryAsset,
            hedge: hedgeAsset,
            horizon: profile.timeHorizon.annualFraction,
            maxLossLimit: profile.maxLossPercent / 100.0,
            predictedVolatilityMultiplier: volResponse.multiplier
        )

        withAnimation(.easeInOut(duration: 0.5)) {
            simulationResult = result
        }
    }
}
