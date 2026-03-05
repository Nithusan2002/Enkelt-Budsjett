import Foundation
import Combine
import SwiftData

@MainActor
final class GoalEditorViewModel: ObservableObject {
    @Published var targetAmountText: String = ""
    @Published var targetDate: Date = Calendar.current.date(byAdding: .year, value: 2, to: .now) ?? .now
    @Published var persistenceErrorMessage: String?

    func onAppear(goal: Goal?) {
        if let goal, goal.targetAmount > 0 {
            targetAmountText = AppAmountInput.format(goal.targetAmount)
        } else {
            targetAmountText = ""
        }
        targetDate = goal?.targetDate ?? targetDate
    }

    var canSave: Bool {
        (parsedTargetAmount ?? 0) > 0
    }

    @discardableResult
    func save(goal: Goal?, context: ModelContext) -> Bool {
        guard let targetAmount = parsedTargetAmount, targetAmount > 0 else { return false }
        guard !PersistenceGate.isReadOnlyMode else {
            persistenceErrorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
            return false
        }
        if let goal {
            goal.targetAmount = targetAmount
            goal.targetDate = targetDate
            goal.includeAccounts = false
            goal.isActive = true
        } else {
            context.insert(Goal(targetAmount: targetAmount, targetDate: targetDate, includeAccounts: false))
        }
        do {
            try context.guardedSave(feature: "Goals", operation: "save_goal")
            persistenceErrorMessage = nil
            return true
        } catch {
            persistenceErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Kunne ikke lagre målet."
            return false
        }
    }

    func clearPersistenceError() {
        persistenceErrorMessage = nil
    }

    private var parsedTargetAmount: Double? {
        AppAmountInput.parse(targetAmountText)
    }
}
