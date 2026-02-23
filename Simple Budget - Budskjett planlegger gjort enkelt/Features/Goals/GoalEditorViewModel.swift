import Foundation
import Combine
import SwiftData

@MainActor
final class GoalEditorViewModel: ObservableObject {
    @Published var targetAmountText: String = ""
    @Published var targetDate: Date = Calendar.current.date(byAdding: .year, value: 2, to: .now) ?? .now
    @Published var includeAccounts = true

    func onAppear(goal: Goal?) {
        if let goal, goal.targetAmount > 0 {
            targetAmountText = formatInputAmount(goal.targetAmount)
        } else {
            targetAmountText = ""
        }
        targetDate = goal?.targetDate ?? targetDate
        includeAccounts = goal?.includeAccounts ?? true
    }

    var canSave: Bool {
        (parsedTargetAmount ?? 0) > 0
    }

    func save(goal: Goal?, context: ModelContext) {
        guard let targetAmount = parsedTargetAmount, targetAmount > 0 else { return }
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

    private var parsedTargetAmount: Double? {
        parseInputAmount(targetAmountText)
    }

    private func parseInputAmount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func formatInputAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }
}
