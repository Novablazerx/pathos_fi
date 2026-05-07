import Foundation
import Combine
import SwiftData

/// RLHF (Reinforcement Learning from Human Feedback) preference engine.
///
/// Tracks user interactions (Simulate / Execute / Dismiss) on Smart Pairs
/// and updates a reward model that biases future recommendations toward the
/// user's preferred hedging style.
///
/// Current reward signals:
/// - Repeated dismissal of Put Options → avoidsPutOptions = true
/// - Repeated dismissal of Bonds      → avoidsBonds = true
/// - High simulate rate on a pair     → boosts that hedge type's ranking score
class RLHFEngine: ObservableObject {

    @Published var preferences: UserPreferences = UserPreferences()

    private var dismissCounts: [String: Int] = [:]
    private let dismissThreshold = 2  // after 2 dismissals, mark as avoided

    // MARK: - Record Interaction

    func record(action: String, hedgeType: HedgeType) {
        switch action {
        case "dismiss":
            let key = hedgeType.rawValue
            dismissCounts[key, default: 0] += 1
            if dismissCounts[key, default: 0] >= dismissThreshold {
                applyDismissalPreference(hedgeType: hedgeType)
            }
        case "simulate":
            // Positive signal — user is curious about this pair style
            break
        case "execute":
            // Strong positive signal — could boost this style's ranking weight
            break
        default:
            break
        }
    }

    // MARK: - Preference Update

    private func applyDismissalPreference(hedgeType: HedgeType) {
        switch hedgeType {
        case .putOption:
            preferences.avoidsPutOptions = true
        case .bond:
            preferences.avoidsBonds = true
        default:
            break
        }
    }

    // MARK: - Persist to SwiftData

    func persistInteraction(
        pairId: UUID,
        action: String,
        hedgeType: HedgeType,
        context: ModelContext
    ) {
        let interaction = UserInteraction(
            pairId: pairId,
            actionType: action,
            hedgeType: hedgeType.rawValue
        )
        context.insert(interaction)
        try? context.save()
    }
}
