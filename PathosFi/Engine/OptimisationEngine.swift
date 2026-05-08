import Foundation

/// Constrained optimisation engine that finds Smart Pair weight ratios
/// satisfying the 95% VaR constraint.
///
/// Algorithm:
/// 1. Start at 100% primary / 0% hedge.
/// 2. Run Monte Carlo simulation.
/// 3. If 95% VaR breaches the user's max loss → increment hedge weight by `step`.
/// 4. Terminate when VaR ≤ maxLossLimit, or when hedge weight reaches ceiling.
struct OptimisationEngine {

    // MARK: - Asset Library

    /// Static asset library with historical return/volatility data.
    /// In production this would be hydrated from the Python backend.
    static let assetLibrary: [String: AssetInfo] = [
        "QQQ": AssetInfo(ticker: "QQQ", name: "Invesco QQQ Trust",
                         annualReturn: 0.18, annualVolatility: 0.22,
                         category: .equity),
        "SPY": AssetInfo(ticker: "SPY", name: "SPDR S&P 500 ETF",
                         annualReturn: 0.12, annualVolatility: 0.17,
                         category: .equity),
        "AAPL": AssetInfo(ticker: "AAPL", name: "Apple Inc.",
                          annualReturn: 0.22, annualVolatility: 0.28,
                          category: .equity),
        "SQQQ": AssetInfo(ticker: "SQQQ", name: "ProShares UltraPro Short QQQ",
                          annualReturn: -0.45, annualVolatility: 0.65,
                          category: .inverseEquity),
        "SH": AssetInfo(ticker: "SH", name: "ProShares Short S&P500",
                        annualReturn: -0.12, annualVolatility: 0.17,
                        category: .inverseEquity),
        "TLT": AssetInfo(ticker: "TLT", name: "iShares 20+ Year Treasury Bond ETF",
                         annualReturn: 0.04, annualVolatility: 0.14,
                         category: .bond),
        "GLD": AssetInfo(ticker: "GLD", name: "SPDR Gold Shares",
                         annualReturn: 0.07, annualVolatility: 0.15,
                         category: .commodity),
        "PUT_QQQ": AssetInfo(ticker: "PUT_QQQ", name: "QQQ Protective Put (ATM)",
                             annualReturn: -0.08, annualVolatility: 0.20,
                             category: .option),
        "MSFT": AssetInfo(ticker: "MSFT", name: "Microsoft Corporation",
                          annualReturn: 0.20, annualVolatility: 0.24,
                          category: .equity),
        "NVDA": AssetInfo(ticker: "NVDA", name: "NVIDIA Corporation",
                          annualReturn: 0.42, annualVolatility: 0.55,
                          category: .equity),
        "AMZN": AssetInfo(ticker: "AMZN", name: "Amazon.com Inc.",
                          annualReturn: 0.19, annualVolatility: 0.30,
                          category: .equity),
        "TSLA": AssetInfo(ticker: "TSLA", name: "Tesla Inc.",
                          annualReturn: 0.30, annualVolatility: 0.60,
                          category: .equity),
        "AGG": AssetInfo(ticker: "AGG", name: "iShares Core US Aggregate Bond ETF",
                         annualReturn: 0.03, annualVolatility: 0.06,
                         category: .bond),
        "IEF": AssetInfo(ticker: "IEF", name: "iShares 7-10 Year Treasury Bond ETF",
                         annualReturn: 0.025, annualVolatility: 0.08,
                         category: .bond),
        "SLV": AssetInfo(ticker: "SLV", name: "iShares Silver Trust",
                         annualReturn: 0.05, annualVolatility: 0.28,
                         category: .commodity),
        "USO": AssetInfo(ticker: "USO", name: "United States Oil Fund",
                         annualReturn: 0.06, annualVolatility: 0.35,
                         category: .commodity),
        "SPXU": AssetInfo(ticker: "SPXU", name: "ProShares UltraPro Short S&P500",
                          annualReturn: -0.38, annualVolatility: 0.52,
                          category: .inverseEquity),
    ]

    /// Known correlations between asset pairs (ρ).
    static let correlationMatrix: [String: [String: Double]] = [
        "QQQ":  ["SQQQ": -0.99, "TLT": -0.25, "GLD": 0.05, "SPY": 0.93],
        "SPY":  ["SH": -0.99,   "TLT": -0.20, "GLD": 0.08, "QQQ": 0.93],
        "AAPL": ["PUT_QQQ": -0.85, "TLT": -0.15, "GLD": 0.02],
    ]

    // MARK: - Candidate Pair Definitions

    struct PairDefinition {
        let name: String
        let description: String
        let primaryTicker: String
        let hedgeTicker: String
        let hedgeType: HedgeType
    }

    static let candidatePairs: [PairDefinition] = [
        PairDefinition(name: "The Tech Growth Hedge",
                       description: "Capture QQQ upside while inverse ETF absorbs drawdowns",
                       primaryTicker: "QQQ", hedgeTicker: "SQQQ",
                       hedgeType: .inverseETF),
        PairDefinition(name: "The Broad Market Shield",
                       description: "S&P 500 exposure with a direct inverse hedge",
                       primaryTicker: "SPY", hedgeTicker: "SH",
                       hedgeType: .inverseETF),
        PairDefinition(name: "The Flight-to-Safety Pair",
                       description: "QQQ growth buffered by long-duration Treasuries",
                       primaryTicker: "QQQ", hedgeTicker: "TLT",
                       hedgeType: .bond),
        PairDefinition(name: "The Apple Put Collar",
                       description: "AAPL directional exposure, hedged with protective puts",
                       primaryTicker: "AAPL", hedgeTicker: "PUT_QQQ",
                       hedgeType: .putOption),
        PairDefinition(name: "The Gold Diversifier",
                       description: "QQQ + gold allocation for crisis diversification",
                       primaryTicker: "QQQ", hedgeTicker: "GLD",
                       hedgeType: .commodity),
    ]

    // MARK: - Optimisation

    /// Run the full optimisation loop for all candidate pairs.
    /// Returns pairs sorted by expected return (descending).
    static func optimise(
        profile: RiskProfileInput,
        preferences: UserPreferences,
        predictedVolatilityMultiplier: Double = 1.0
    ) async -> [SmartPairModel] {

        let maxLoss = profile.maxLossPercent / 100.0
        let horizon = profile.timeHorizon.annualFraction

        var results: [SmartPairModel] = []

        for definition in candidatePairs {
            // Respect RLHF preferences — skip disfavoured hedge types
            if preferences.avoidsPutOptions && definition.hedgeType == .putOption { continue }
            if preferences.avoidsBonds && definition.hedgeType == .bond { continue }

            guard let primary = assetLibrary[definition.primaryTicker],
                  let hedge   = assetLibrary[definition.hedgeTicker] else { continue }

            // Constrained weight search: step from 0% to 50% hedge in 5% increments
            let step = 0.05
            var bestPair: SmartPairModel? = nil

            for hedgeStep in 0 ... 10 {
                let wH = Double(hedgeStep) * step
                let wA = 1.0 - wH

                let result = MonteCarloEngine.simulate(
                    primaryWeight: wA,
                    hedgeWeight: wH,
                    primary: primary,
                    hedge: hedge,
                    horizon: horizon,
                    maxLossLimit: maxLoss,
                    predictedVolatilityMultiplier: predictedVolatilityMultiplier
                )

                // VaR constraint satisfied: tail risk ≤ 5%
                if result.tailRiskPercent <= 5.0 {
                    bestPair = SmartPairModel(
                        id: UUID(),
                        name: definition.name,
                        description: definition.description,
                        primaryAsset: primary,
                        hedgeAsset: hedge,
                        primaryWeight: wA,
                        hedgeWeight: wH,
                        expectedReturn: result.expectedReturn,
                        simulatedVaR95: result.var95,
                        hedgeType: definition.hedgeType
                    )
                    break  // Take the minimum hedge that satisfies the constraint
                }
            }

            if let pair = bestPair {
                results.append(pair)
            }
        }

        // Sort by expected return — maximise return subject to VaR constraint
        return results.sorted { $0.expectedReturn > $1.expectedReturn }
    }
}
