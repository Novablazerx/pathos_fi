import SwiftUI
import Combine

@MainActor
class RiskAssessmentViewModel: ObservableObject {
    @Published var capitalInput: String
    @Published var capitalRaw: Double
    var selectedHorizon: TimeHorizon
    @Published var maxLossPercent: Double

    init(profile: RiskProfileInput = RiskProfileInput()) {
        capitalRaw    = profile.startingCapital
        capitalInput  = String(Int(profile.startingCapital))
        selectedHorizon = profile.timeHorizon
        maxLossPercent  = profile.maxLossPercent
    }

    var formattedCapital: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: capitalRaw)) ?? "$\(capitalRaw.safeInt())"
    }

    var lossColor: Color {
        switch maxLossPercent {
        case 0...10:  return Color("AccentGreen")
        case 10...25: return .orange
        default:      return .red
        }
    }

    var lossDescription: String {
        switch maxLossPercent {
        case 0...5:   return "Ultra-conservative — almost zero risk tolerance"
        case 5...10:  return "Conservative — suitable for capital preservation"
        case 10...20: return "Moderate — balanced risk/return trade-off"
        case 20...35: return "Aggressive — seeking higher returns"
        default:      return "Very aggressive — high-risk, high-reward"
        }
    }
}
