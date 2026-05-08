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
