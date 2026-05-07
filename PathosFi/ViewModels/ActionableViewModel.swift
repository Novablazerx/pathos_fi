import SwiftUI
import SwiftData
import Combine

@MainActor
class ActionableViewModel: ObservableObject {
    @Published var smartPairs: [SmartPairModel] = []
    @Published var isOptimising: Bool = false
    @Published var simulatingPairId: UUID? = nil
    @Published var ghostSimulationResult: SimulationResult? = nil
    @Published var selectedPairForExecution: SmartPairModel? = nil

    private let rlhfEngine = RLHFEngine()
    private let apiClient = BackendAPIClient()

    // MARK: - Load Recommendations

    func loadRecommendations(profile: RiskProfileInput) async {
        isOptimising = true
        defer { isOptimising = false }

        // Fetch AI-predicted volatility multiplier
        let allTickers = OptimisationEngine.candidatePairs.flatMap {
            [$0.primaryTicker, $0.hedgeTicker]
        }
        let volResponse = await apiClient.fetchPredictedVolatility(
            tickers: Array(Set(allTickers)),
            horizon: profile.timeHorizon
        )

        // Run constrained optimisation loop
        let pairs = await OptimisationEngine.optimise(
            profile: profile,
            preferences: rlhfEngine.preferences,
            predictedVolatilityMultiplier: volResponse.multiplier
        )

        withAnimation(.easeInOut(duration: 0.4)) {
            smartPairs = pairs
        }
    }

    // MARK: - Simulate a Pair (Ghost Chart)

    func simulatePair(_ pair: SmartPairModel, profile: RiskProfileInput) async {
        simulatingPairId = pair.id
        defer { simulatingPairId = nil }

        guard let primary = OptimisationEngine.assetLibrary[pair.primaryAsset.ticker],
              let hedge   = OptimisationEngine.assetLibrary[pair.hedgeAsset.ticker] else { return }

        let result = MonteCarloEngine.simulate(
            primaryWeight: pair.primaryWeight,
            hedgeWeight: pair.hedgeWeight,
            primary: primary,
            hedge: hedge,
            horizon: profile.timeHorizon.annualFraction,
            maxLossLimit: profile.maxLossPercent / 100.0
        )

        withAnimation(.spring(response: 0.4)) {
            ghostSimulationResult = result
        }

        // Auto-dismiss ghost after 8 seconds
        try? await Task.sleep(for: .seconds(8))
        withAnimation { ghostSimulationResult = nil }
    }

    // MARK: - RLHF Interaction Recording

    func recordInteraction(
        pairId: UUID,
        action: String,
        hedgeType: HedgeType,
        context: ModelContext
    ) {
        rlhfEngine.record(action: action, hedgeType: hedgeType)
        rlhfEngine.persistInteraction(
            pairId: pairId,
            action: action,
            hedgeType: hedgeType,
            context: context
        )
    }

    // MARK: - Dismiss Pair

    func dismiss(pair: SmartPairModel) {
        withAnimation(.easeInOut(duration: 0.3)) {
            smartPairs.removeAll { $0.id == pair.id }
        }
    }
}
