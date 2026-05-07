import Foundation

// MARK: - Simulation Output

struct SimulationResult {
    let upsidePercent: Double        // probability of profit
    let acceptablePercent: Double    // between 0% and maxLoss
    let tailRiskPercent: Double      // breaches max loss (must be ≤ 5%)
    let var95: Double                // 95th percentile worst outcome (as %)
    let expectedReturn: Double       // mean outcome (as %)
    let simulatedPaths: [[Double]]   // subset of paths for chart display
}

// MARK: - Smart Pair

enum HedgeType: String, Codable {
    case inverseETF = "Inverse ETF"
    case putOption  = "Put Option"
    case bond       = "Bond"
    case cash       = "Cash"
    case commodity  = "Commodity"
}

struct SmartPairModel: Identifiable {
    let id: UUID
    let name: String
    let description: String
    let primaryAsset: AssetInfo
    let hedgeAsset: AssetInfo
    let primaryWeight: Double
    let hedgeWeight: Double
    let expectedReturn: Double
    let simulatedVaR95: Double
    let hedgeType: HedgeType
    var ghostSimulationResult: SimulationResult? = nil

    var formattedWeights: String {
        "\((primaryWeight * 100).safeInt())% \(primaryAsset.ticker) / \((hedgeWeight * 100).safeInt())% \(hedgeAsset.ticker)"
    }
}

struct AssetInfo: Identifiable {
    let id: UUID = UUID()
    let ticker: String
    let name: String
    let annualReturn: Double     // historical mean annual return
    let annualVolatility: Double // historical annual std dev
    let category: AssetCategory
}

enum AssetCategory: String {
    case equity        = "Equity"
    case inverseEquity = "Inverse Equity"
    case bond          = "Bond"
    case commodity     = "Commodity"
    case option        = "Option"
}

// MARK: - Portfolio Sector (Pie Chart)

struct PieSlice: Identifiable {
    let label: String
    let percent: Double
    let color: PieSliceColor

    /// Stable identity for `Chart` / `ForEach` — must not use `UUID()` here: `slices`
    /// is rebuilt often; random IDs cause SwiftUI / Charts assertion failures.
    var id: String { label }
}

enum PieSliceColor {
    case upside
    case acceptable
    case tailRisk
}

// MARK: - RLHF Preference Model

struct UserPreferences {
    var avoidsPutOptions: Bool = false
    var avoidsBonds: Bool = false
    var prefersSimplePairs: Bool = true

    mutating func record(interaction: UserInteraction) {
        if interaction.hedgeType == HedgeType.putOption.rawValue {
            if interaction.actionType == "dismiss" {
                avoidsPutOptions = true
            }
        }
        if interaction.hedgeType == HedgeType.bond.rawValue {
            if interaction.actionType == "dismiss" {
                avoidsBonds = true
            }
        }
    }
}
