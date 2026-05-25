import SwiftUI
import Combine
import Foundation

enum AppScreen {
    case loading
    case onboarding
    case dashboard
    case recommendations
    case exploreAssets
}

class AppState: ObservableObject {
    @Published var currentScreen: AppScreen = .loading
    @Published var currentUser: BackendAPIClient.UserRecord? = nil
    @Published var riskProfile: RiskProfileInput = RiskProfileInput()
    @Published var simulationResult: SimulationResult? = nil
    @Published var selectedPair: SmartPairModel? = nil

    @Published var holdings: [HeldAsset] = []
    @Published var backendAssets: [AssetInfo] = []
    var assetIdByTicker: [String: Int] = [:]

    @Published var optionsByTicker: [String: [OptionsContract]] = [:]

    var portfolioValue: Double {
        let equity  = holdings.reduce(0.0) { $0 + $1.value }
        let options = optionsByTicker.values.flatMap { $0 }.reduce(0.0) { $0 + $1.totalValue }
        return equity + options
    }

    let apiClient = BackendAPIClient()

    // MARK: - App Initialization

    @MainActor
    func initializeApp() async {
        currentScreen = .loading
        do {
            let user = try await apiClient.fetchUser(username: "testuser")
            currentUser = user
            riskProfile.startingCapital = user.cashBalance

            async let allAssetsTask  = apiClient.fetchAllAssets()
            async let userAssetsTask = apiClient.fetchUserAssets(userId: user.userId)
            let (allAssets, userAssets) = try await (allAssetsTask, userAssetsTask)

            let assetLib      = OptimisationEngine.assetLibrary
            let assetMetadata = Dictionary(uniqueKeysWithValues: allAssets.map { ($0.assetId, $0) })
            assetIdByTicker   = Dictionary(uniqueKeysWithValues: allAssets.map { ($0.ticker, $0.assetId) })

            backendAssets = allAssets.map { ao in
                let known = assetLib[ao.ticker]
                let category: AssetCategory
                switch ao.assetType?.lowercased() {
                case "bond":                      category = .bond
                case "commodity":                 category = .commodity
                case "option":                    category = .option
                case "inverse_equity", "inverse": category = .inverseEquity
                default:                          category = known?.category ?? .equity
                }
                return AssetInfo(
                    ticker: ao.ticker,
                    name: ao.assetName ?? known?.name ?? ao.ticker,
                    annualReturn: known?.annualReturn ?? 0,
                    annualVolatility: known?.annualVolatility ?? 0.20,
                    category: category
                )
            }

            holdings = userAssets.map { ua in
                let cost = ua.avgCostBasis ?? 0
                let name = ua.assetName ?? assetMetadata[ua.assetId]?.assetName ?? ua.ticker
                let category: AssetCategory
                switch assetMetadata[ua.assetId]?.assetType?.lowercased() {
                case "bond":   category = .bond
                case "option": category = .option
                default:       category = .equity
                }
                let info = assetLib[ua.ticker] ?? AssetInfo(
                    ticker: ua.ticker,
                    name: name,
                    annualReturn: 0,
                    annualVolatility: 0.20,
                    category: category
                )
                return HeldAsset(asset: info, shares: ua.quantity, avgCost: cost, currentPrice: cost)
            }

            let isoFormatter = DateFormatter()
            isoFormatter.dateFormat = "yyyy-MM-dd"
            var newOptions: [String: [OptionsContract]] = [:]

            for ua in userAssets {
                let opts = (try? await apiClient.fetchOptions(assetId: ua.assetId, userId: user.userId)) ?? []
                let contracts: [OptionsContract] = opts.compactMap { (opt) -> OptionsContract? in
                    guard let typeStr = opt.optionType, let strike = opt.strikePrice else { return nil }
                    let optType: OptionType = typeStr.lowercased() == "call" ? .call : .put
                    let expiry = opt.expiryDate.flatMap { isoFormatter.date(from: $0) }
                        ?? Date().addingTimeInterval(90 * 86400)
                    let premium = opt.premium ?? 0
                    return OptionsContract(
                        optionId: opt.optionId,
                        underlyingTicker: ua.ticker,
                        type: optType,
                        strikePrice: strike,
                        expiryDate: expiry,
                        contracts: opt.contractSize,
                        costBasis: premium,
                        currentValue: premium
                    )
                }
                if !contracts.isEmpty { newOptions[ua.ticker] = contracts }
            }
            optionsByTicker = newOptions

            currentScreen = .dashboard
        } catch {
            currentScreen = .onboarding
        }
    }

    // MARK: - Risk Profile Sync

    @MainActor
    func saveRiskProfile(_ profile: RiskProfileInput) async {
        guard let user = currentUser else { return }
        let label: String
        switch profile.maxLossPercent {
        case 0...10:  label = "conservative"
        case 10...25: label = "moderate"
        default:      label = "aggressive"
        }
        try? await apiClient.updateUserRiskProfile(userId: user.userId, riskProfile: label)
    }

    // MARK: - Navigation

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
        case .onboarding, .loading:
            break
        }
    }
}

struct RiskProfileInput {
    var startingCapital: Double = 10000
    var timeHorizon: TimeHorizon = .oneMonth
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
