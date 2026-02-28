import Foundation
import Combine
import SwiftData

@MainActor
final class ChallengesViewModel: ObservableObject {
    @Published var persistenceErrorMessage: String?

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
        do {
            try context.guardedSave(feature: "Challenges", operation: "pause")
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Kunne ikke lagre endringen."
        }
    }

    func resume(_ challenge: Challenge, context: ModelContext) {
        challenge.status = .active
        do {
            try context.guardedSave(feature: "Challenges", operation: "resume")
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Kunne ikke lagre endringen."
        }
    }

    func complete(_ challenge: Challenge, context: ModelContext) {
        challenge.status = .completed
        challenge.progress = 1
        do {
            try context.guardedSave(feature: "Challenges", operation: "complete")
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Kunne ikke lagre endringen."
        }
    }

    func recalculate(_ challenge: Challenge, transactions: [Transaction], categories: [Category], preference: UserPreference?, context: ModelContext) {
        _ = ChallengeService.recalculate(
            challenge: challenge,
            transactions: transactions,
            categories: categories,
            preference: preference
        )
        do {
            try context.guardedSave(feature: "Challenges", operation: "recalculate")
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Kunne ikke lagre endringen."
        }
    }

    func clearPersistenceError() {
        persistenceErrorMessage = nil
    }
}
