import Foundation
import Combine

struct BudgetCategoryRow: Identifiable {
    let id: String
    let title: String
    let planned: Double
    let spent: Double
}

@MainActor
final class BudgetViewModel: ObservableObject {
    func periodKey(now: Date = .now) -> String {
        DateService.periodKey(from: now)
    }

    func summary(periodKey: String, plans: [BudgetPlan], categories: [Category], transactions: [Transaction]) -> (planned: Double, actual: Double, delta: Double, remaining: Double) {
        let planned = BudgetService.plannedTotal(for: periodKey, plans: plans, categories: categories)
        let actual = BudgetService.actualExpenseTotal(for: periodKey, transactions: transactions)
        return (planned, actual, planned - actual, max(0, planned - actual))
    }

    func categoryRows(periodKey: String, categories: [Category], plans: [BudgetPlan], transactions: [Transaction]) -> [BudgetCategoryRow] {
        categories
            .filter { $0.type == .expense }
            .map { category in
                let plan = plans.first { $0.monthPeriodKey == periodKey && $0.categoryID == category.id }?.plannedAmount ?? 0
                let spent = BudgetService.spentByCategory(for: periodKey, categoryID: category.id, transactions: transactions)
                return BudgetCategoryRow(id: category.id, title: category.name, planned: plan, spent: spent)
            }
    }

    func progressValue(for row: BudgetCategoryRow) -> Double {
        min(row.spent, max(row.planned, 1))
    }

    func progressTotal(for row: BudgetCategoryRow) -> Double {
        max(row.planned, 1)
    }
}
