import SwiftUI
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var simulationResult: SimulationResult? = nil
    @Published var isSimulating: Bool = false

    private let apiClient = BackendAPIClient()

    func runSimulation(profile: RiskProfileInput) async {
        isSimulating = true
        defer { isSimulating = false }

//        let horizonDays: Int = {
//            switch profile.timeHorizon {
//            case .oneMonth:  return 21
//            case .sixMonths: return 126
//            case .oneYear:   return 252
//            case .fiveYears: return 252   // clamped to API max
//            }
//        }()
        
        let horizonDays: Int = {
            switch profile.timeHorizon {
            case .oneMonth:  return 30
            case .sixMonths: return 126
            case .oneYear:   return 252
            case .fiveYears: return 252   // clamped to API max
            }
        }()

        // Approximate QQQ share count for the given starting capital (~$380/share).
        let shares = max(1.0, (profile.startingCapital / 380.0).rounded())

        let simRequest = BackendAPIClient.PortfolioSimRequest(
            portfolioId: UUID().uuidString,
            horizonDays: horizonDays,
            assets: [
                BackendAPIClient.AssetPosition(
                    ticker: "QQQ", type: "equity", shares: shares,
                    contract: nil, strike: nil, expiry: nil, quantity: nil
                )
            ]
        )

        guard let response = try? await apiClient.fetchPortfolioSimulation(request: simRequest) else {
            return
        }

        // Derive probability buckets from the response histogram.
        // Histogram bins are absolute portfolio dollar values.
        let maxLossThreshold = response.currentValue * (1.0 - profile.maxLossPercent / 100.0)
        var upsideProb   = 0.0
        var tailRiskProb = 0.0
        for (bin, prob) in zip(response.distributionHistogram.bins,
                               response.distributionHistogram.probabilities) {
            if bin > response.currentValue {
                upsideProb   += prob
            } else if bin < maxLossThreshold {
                tailRiskProb += prob
            }
        }
        let acceptableProb = max(0.0, 1.0 - upsideProb - tailRiskProb)

        let var95 = response.currentValue > 0
            ? (response.valueAtRisk95 / response.currentValue) * 100.0
            : 0.0
        let expectedReturn = response.currentValue > 0
            ? ((response.expectedMeanValueT30 - response.currentValue) / response.currentValue) * 100.0
            : 0.0

        let result = SimulationResult(
            upsidePercent:     (upsideProb   * 100.0).isFinite ? upsideProb   * 100.0 : 0.0,
            acceptablePercent: (acceptableProb * 100.0).isFinite ? acceptableProb * 100.0 : 0.0,
            tailRiskPercent:   (tailRiskProb  * 100.0).isFinite ? tailRiskProb  * 100.0 : 0.0,
            var95:             var95.isFinite          ? var95          : 0.0,
            expectedReturn:    expectedReturn.isFinite ? expectedReturn : 0.0,
            simulatedPaths:    []
        )

        withAnimation(.easeInOut(duration: 0.5)) {
            simulationResult = result
        }
    }
}
