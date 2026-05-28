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
    @Published var rlRationale: String? = nil
    @Published var rlStatus: BackendAPIClient.RLStatus? = nil

    private let rlhfEngine = RLHFEngine()
    private let apiClient = BackendAPIClient()

    // MARK: - Load Recommendations

    func loadRecommendations(profile: RiskProfileInput, userId: Int?, portfolioValue: Double) async {
        isOptimising = true
        defer { isOptimising = false }

        // Try RL recommendation endpoint first
        if let userId = userId {
            let riskMargin = max(portfolioValue * (1.0 - profile.maxLossPercent / 100.0), 0)
            if let response = try? await apiClient.fetchRLRecommendation(
                userId: userId,
                riskMargin: riskMargin,
                horizonDays: 30
            ) {
                rlRationale = response.rationale
                rlStatus = response.status

                if response.status == .approved {
                    let pairs = convertRLResponse(response)
                    if !pairs.isEmpty {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            smartPairs = pairs
                        }
                        return
                    }
                }
            }
        }

        // Fallback: local constrained optimisation
        let allTickers = OptimisationEngine.candidatePairs.flatMap {
            [$0.primaryTicker, $0.hedgeTicker]
        }
        let volResponse = await apiClient.fetchPredictedVolatility(
            tickers: Array(Set(allTickers)),
            horizon: profile.timeHorizon
        )
        let pairs = await OptimisationEngine.optimise(
            profile: profile,
            preferences: rlhfEngine.preferences,
            predictedVolatilityMultiplier: volResponse.multiplier
        )
        withAnimation(.easeInOut(duration: 0.4)) {
            smartPairs = pairs
        }
    }

    // MARK: - RL Response → SmartPairModel

    private func convertRLResponse(_ response: BackendAPIClient.RLRecommendResponse) -> [SmartPairModel] {
        var pairs: [SmartPairModel] = []
        let currentValue = response.currentValue
        let stressVaR = response.stressTest.crashPct * 100  // 20.0 for a 20% crash

        let cashAsset = AssetInfo(
            ticker: "CASH",
            name: "Cash",
            annualReturn: 0.04,
            annualVolatility: 0.0,
            category: .equity
        )

        // Equity trades (skip hold)
        for trade in response.trades where trade.side != .hold {
            let equity = OptimisationEngine.assetLibrary[trade.ticker] ?? AssetInfo(
                ticker: trade.ticker,
                name: trade.ticker,
                annualReturn: 0,
                annualVolatility: 0.20,
                category: .equity
            )
            let fraction = currentValue > 0 ? min(trade.notionalUsd / currentValue, 0.95) : 0.10
            let primaryWeight = max(fraction, 0.05)
            let annualReturn = equity.annualReturn
            let thirtyDayReturn: Double
            switch trade.side {
            case .buy:  thirtyDayReturn = annualReturn * (30.0 / 365.0) * 100
            case .sell: thirtyDayReturn = 0.04 * (30.0 / 365.0) * 100  // cash yield
            case .hold: thirtyDayReturn = 0
            }

            let execution: TradeExecutionInfo = trade.side == .buy
                ? TradeExecutionInfo(ticker: trade.ticker,
                                     action: .buyEquity(shares: trade.shares, notionalUsd: trade.notionalUsd))
                : TradeExecutionInfo(ticker: trade.ticker,
                                     action: .sellEquity(shares: trade.shares, notionalUsd: trade.notionalUsd))

            pairs.append(SmartPairModel(
                id: UUID(),
                name: "\(trade.side.rawValue.capitalized) \(trade.ticker)",
                description: "\(trade.shares) shares · $\(Int(trade.notionalUsd))",
                primaryAsset: equity,
                hedgeAsset: cashAsset,
                primaryWeight: primaryWeight,
                hedgeWeight: 1.0 - primaryWeight,
                expectedReturn: thirtyDayReturn,
                simulatedVaR95: stressVaR,
                hedgeType: .cash,
                tradeExecution: execution
            ))
        }

        // Options hedges
        for hedge in response.hedges {
            let underlying = OptimisationEngine.assetLibrary[hedge.ticker] ?? AssetInfo(
                ticker: hedge.ticker,
                name: hedge.ticker,
                annualReturn: 0,
                annualVolatility: 0.20,
                category: .equity
            )
            let optionAsset = AssetInfo(
                ticker: "\(hedge.contractType.rawValue.uppercased()) $\(Int(hedge.strike))",
                name: "\(hedge.ticker) \(hedge.contractType.rawValue.capitalized) @ $\(Int(hedge.strike))",
                annualReturn: 0,
                annualVolatility: 0.50,
                category: .option
            )
            let hedgeFraction = currentValue > 0 ? min(hedge.totalPremium / currentValue, 0.50) : 0.05
            let hedgeWeight = max(hedgeFraction, 0.03)
            let hedgeType: HedgeType = hedge.contractType == .put ? .putOption : .callOption
            let costReturn = -(hedge.totalPremium / max(currentValue, 1)) * 100
            let optionExecution = TradeExecutionInfo(
                ticker: hedge.ticker,
                action: .buyOption(
                    isCall: hedge.contractType == .call,
                    contracts: hedge.contracts,
                    strike: hedge.strike,
                    expiry: hedge.expiry,
                    premiumPerContract: hedge.premiumPerContract,
                    totalPremium: hedge.totalPremium
                )
            )

            pairs.append(SmartPairModel(
                id: UUID(),
                name: "\(hedge.contractType.rawValue.capitalized) \(hedge.ticker) @ $\(Int(hedge.strike))",
                description: "\(hedge.contracts) contracts · $\(Int(hedge.totalPremium)) premium",
                primaryAsset: underlying,
                hedgeAsset: optionAsset,
                primaryWeight: 1.0 - hedgeWeight,
                hedgeWeight: hedgeWeight,
                expectedReturn: costReturn,
                simulatedVaR95: stressVaR,
                hedgeType: hedgeType,
                tradeExecution: optionExecution
            ))
        }

        return pairs
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
