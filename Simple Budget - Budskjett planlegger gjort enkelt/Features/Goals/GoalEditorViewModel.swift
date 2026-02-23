import Foundation
import Combine
import SwiftData

@MainActor
final class GoalEditorViewModel: ObservableObject {
    @Published var targetAmount: Double = 0
    @Published var targetDate: Date = Calendar.current.date(byAdding: .year, value: 2, to: .now) ?? .now
    @Published var includeAccounts = true

    func onAppear(goal: Goal?) {
        targetAmount = goal?.targetAmount ?? 450000
        targetDate = goal?.targetDate ?? targetDate
        includeAccounts = goal?.includeAccounts ?? true
    }

    func save(goal: Goal?, context: ModelContext) {
        if let goal {
            goal.targetAmount = targetAmount
            goal.targetDate = targetDate
            goal.includeAccounts = includeAccounts
            goal.isActive = true
        } else {
            context.insert(Goal(targetAmount: targetAmount, targetDate: targetDate, includeAccounts: includeAccounts))
        }
        try? context.save()
    }
}
