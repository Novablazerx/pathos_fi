import SwiftData
import Foundation

@Model
final class UserRiskProfile {
    var id: UUID
    var startingCapital: Double
    var maxLossPercent: Double
    var timeHorizonMonths: Int
    var createdAt: Date
    var updatedAt: Date

    init(startingCapital: Double, maxLossPercent: Double, timeHorizonMonths: Int) {
        self.id = UUID()
        self.startingCapital = startingCapital
        self.maxLossPercent = maxLossPercent
        self.timeHorizonMonths = timeHorizonMonths
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class SmartPair {
    var id: UUID
    var name: String
    var primaryAssetTicker: String
    var hedgeAssetTicker: String
    var primaryWeight: Double
    var hedgeWeight: Double
    var expectedReturn: Double
    var simulatedVaR95: Double
    var hedgeType: String
    var createdAt: Date

    init(
        name: String,
        primaryAssetTicker: String,
        hedgeAssetTicker: String,
        primaryWeight: Double,
        hedgeWeight: Double,
        expectedReturn: Double,
        simulatedVaR95: Double,
        hedgeType: String
    ) {
        self.id = UUID()
        self.name = name
        self.primaryAssetTicker = primaryAssetTicker
        self.hedgeAssetTicker = hedgeAssetTicker
        self.primaryWeight = primaryWeight
        self.hedgeWeight = hedgeWeight
        self.expectedReturn = expectedReturn
        self.simulatedVaR95 = simulatedVaR95
        self.hedgeType = hedgeType
        self.createdAt = Date()
    }
}

@Model
final class UserInteraction {
    var id: UUID
    var pairId: UUID
    var actionType: String // "simulate" | "execute" | "dismiss"
    var hedgeType: String
    var timestamp: Date

    init(pairId: UUID, actionType: String, hedgeType: String) {
        self.id = UUID()
        self.pairId = pairId
        self.actionType = actionType
        self.hedgeType = hedgeType
        self.timestamp = Date()
    }
}
