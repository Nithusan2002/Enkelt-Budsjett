import Foundation
import Combine
import SwiftData

@MainActor
final class ChallengesViewModel: ObservableObject {
    func title(for type: ChallengeType) -> String {
        switch type {
        case .noCoffeeWeek: return "No-coffee-week"
        case .save1000In30Days: return "1 000 kr på 30 dager"
        case .roundUpManual: return "Rund opp kjøp (manuelt)"
        case .foodBudgetWeek: return "Matbudsjett-uke"
        }
    }

    func pause(_ challenge: Challenge, context: ModelContext) {
        challenge.status = .paused
        try? context.save()
    }

    func resume(_ challenge: Challenge, context: ModelContext) {
        challenge.status = .active
        try? context.save()
    }

    func complete(_ challenge: Challenge, context: ModelContext) {
        challenge.status = .completed
        challenge.progress = 1
        try? context.save()
    }

    func recalculate(_ challenge: Challenge, transactions: [Transaction], categories: [Category], preference: UserPreference?, context: ModelContext) {
        _ = ChallengeService.recalculate(
            challenge: challenge,
            transactions: transactions,
            categories: categories,
            preference: preference
        )
        try? context.save()
    }
}
