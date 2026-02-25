import Foundation
import Combine
import SwiftData

enum BudgetCategoryFilter: String, CaseIterable {
    case all = "Alle"
    case overBudget = "Over budsjett"
}

struct BudgetSummaryData {
    let planned: Double
    let actual: Double
    let income: Double
    let net: Double
    let deviation: Double
    let remaining: Double
}

struct BudgetCategoryRow: Identifiable {
    let id: String
    let title: String
    let planned: Double
    let spent: Double
    let isOverBudget: Bool
}

struct BudgetInsight {
    let title: String
    let detail: String
}

struct BudgetTrendPoint: Identifiable {
    let id = UUID()
    let day: Int
    let cumulative: Double
}

struct BudgetEditorTarget: Identifiable {
    let id: String
    let categoryName: String
    let categoryID: String
}

@MainActor
final class BudgetViewModel: ObservableObject {
    @Published var selectedMonthDate: Date = .now
    @Published var selectedFilter: BudgetCategoryFilter = .all
    @Published var showAddTransaction = false
    @Published var editorTarget: BudgetEditorTarget?

    func periodKey() -> String {
        DateService.periodKey(from: selectedMonthDate)
    }

    func monthDateText() -> String {
        let key = periodKey()
        return formatPeriodKeyAsDate(key)
    }

    func changeMonth(by offset: Int) {
        selectedMonthDate = Calendar.current.date(byAdding: .month, value: offset, to: selectedMonthDate) ?? selectedMonthDate
    }

    func ensureMonthExists(
        context: ModelContext,
        months: [BudgetMonth],
        plans: [BudgetPlan]
    ) {
        let currentKey = periodKey()
        let hasMonth = months.contains { $0.periodKey == currentKey }

        if !hasMonth {
            let bounds = DateService.monthBounds(for: selectedMonthDate)
            context.insert(
                BudgetMonth(
                    periodKey: currentKey,
                    year: Calendar.current.component(.year, from: selectedMonthDate),
                    month: Calendar.current.component(.month, from: selectedMonthDate),
                    startDate: bounds.start,
                    endDate: bounds.end
                )
            )
        }

        let bounds = DateService.monthBounds(for: selectedMonthDate)
        try? FixedItemsService.generateForMonth(
            context: context,
            periodKey: currentKey,
            monthStart: bounds.start,
            monthEnd: bounds.end
        )

        let hasPlans = plans.contains { $0.monthPeriodKey == currentKey }
        if !hasPlans, let previousKey = DateService.offsetPeriodKey(currentKey, months: -1) {
            let previousPlans = plans.filter { $0.monthPeriodKey == previousKey }
            for previousPlan in previousPlans {
                let newKey = "\(currentKey)|\(previousPlan.categoryID)"
                let exists = plans.contains { $0.uniqueKey == newKey }
                if !exists {
                    context.insert(
                        BudgetPlan(
                            monthPeriodKey: currentKey,
                            categoryID: previousPlan.categoryID,
                            plannedAmount: previousPlan.plannedAmount
                        )
                    )
                }
            }
        }

        try? context.save()
    }

    func summary(periodKey: String, plans: [BudgetPlan], categories: [Category], transactions: [Transaction]) -> BudgetSummaryData {
        let planned = BudgetService.plannedTotal(for: periodKey, plans: plans, categories: categories)
        let actual = BudgetService.actualExpenseTotal(for: periodKey, transactions: transactions)
        let income = BudgetService.actualIncomeTotal(for: periodKey, transactions: transactions)
        let net = income - actual
        let deviation = actual - planned
        let remaining = planned > 0 ? (planned - actual) : net
        return BudgetSummaryData(
            planned: planned,
            actual: actual,
            income: income,
            net: net,
            deviation: deviation,
            remaining: remaining
        )
    }

    func previousMonthActual(periodKey: String, transactions: [Transaction]) -> Double {
        guard let previous = DateService.offsetPeriodKey(periodKey, months: -1) else { return 0 }
        return BudgetService.actualExpenseTotal(for: previous, transactions: transactions)
    }

    func categoryRows(periodKey: String, categories: [Category], plans: [BudgetPlan], transactions: [Transaction]) -> [BudgetCategoryRow] {
        let rows = categories
            .filter { $0.type == .expense && $0.isActive }
            .map { category in
                let planned = plans.first { $0.monthPeriodKey == periodKey && $0.categoryID == category.id }?.plannedAmount ?? 0
                let spent = BudgetService.spentByCategory(for: periodKey, categoryID: category.id, transactions: transactions)
                let overBudget = (planned > 0 && spent > planned) || (planned == 0 && spent > 0)
                return BudgetCategoryRow(
                    id: category.id,
                    title: category.name,
                    planned: planned,
                    spent: spent,
                    isOverBudget: overBudget
                )
            }

        let sorted = rows.sorted { lhs, rhs in
            if lhs.isOverBudget != rhs.isOverBudget { return lhs.isOverBudget && !rhs.isOverBudget }
            if lhs.spent != rhs.spent { return lhs.spent > rhs.spent }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        switch selectedFilter {
        case .all:
            return sorted
        case .overBudget:
            return sorted.filter(\.isOverBudget)
        }
    }

    func transactionsForMonth(periodKey: String, transactions: [Transaction]) -> [Transaction] {
        transactions
            .filter { DateService.periodKey(from: $0.date) == periodKey }
            .sorted { $0.date > $1.date }
    }

    func topCategoryRows(periodKey: String, categories: [Category], plans: [BudgetPlan], transactions: [Transaction], limit: Int = 3) -> [BudgetCategoryRow] {
        Array(categoryRows(periodKey: periodKey, categories: categories, plans: plans, transactions: transactions).prefix(limit))
    }

    func progressValue(for row: BudgetCategoryRow) -> Double {
        if row.planned <= 0 { return max(row.spent, 0) }
        return max(row.spent, 0)
    }

    func progressTotal(for row: BudgetCategoryRow) -> Double {
        if row.planned <= 0 { return max(row.spent, 1) }
        return max(row.planned, 1)
    }

    func insight(summary: BudgetSummaryData, rows: [BudgetCategoryRow]) -> BudgetInsight {
        if rows.isEmpty {
            return BudgetInsight(
                title: "Klar for første registrering",
                detail: "Legg til en utgift, så får du oversikt med en gang."
            )
        }

        if summary.planned <= 0 {
            if let top = rows.filter({ $0.spent > 0 }).max(by: { $0.spent < $1.spent }) {
                return BudgetInsight(
                    title: "Sporing er i gang",
                    detail: "Størst forbruk nå: \(top.title)."
                )
            }
            return BudgetInsight(title: "Sporing er i gang", detail: "Legg til flere transaksjoner for tydeligere innsikt.")
        }

        let ratio = summary.actual / max(summary.planned, 1)
        if ratio < 0.7 {
            return BudgetInsight(title: "God margin", detail: "Du har fortsatt god plass i månedsbudsjettet.")
        }
        if ratio <= 1.0 {
            return BudgetInsight(title: "Nærmer seg nivået", detail: "Du er nær planlagt nivå. Små justeringer holder flyten.")
        }

        if let top = rows.first(where: \.isOverBudget) {
            return BudgetInsight(title: "Mest press akkurat nå", detail: "\(top.title) ligger over plan denne måneden.")
        }

        return BudgetInsight(title: "Over plan totalt", detail: "Se kategoriene øverst for rask justering.")
    }

    func trendPoints(categoryID: String, periodKey: String, transactions: [Transaction]) -> [BudgetTrendPoint] {
        let monthTx = transactions
            .filter { DateService.periodKey(from: $0.date) == periodKey && $0.categoryID == categoryID }
            .sorted { $0.date < $1.date }

        var cumulative: Double = 0
        return monthTx.map { tx in
            cumulative += BudgetService.budgetImpact(tx)
            let day = Calendar.current.component(.day, from: tx.date)
            return BudgetTrendPoint(day: day, cumulative: cumulative)
        }
    }

    func transactionsForCategory(categoryID: String, periodKey: String, transactions: [Transaction]) -> [Transaction] {
        transactions
            .filter { DateService.periodKey(from: $0.date) == periodKey && $0.categoryID == categoryID }
            .sorted { $0.date > $1.date }
    }

    func upsertBudgetPlan(context: ModelContext, periodKey: String, categoryID: String, plannedAmount: Double, plans: [BudgetPlan]) {
        let targetKey = "\(periodKey)|\(categoryID)"
        if let existing = plans.first(where: { $0.uniqueKey == targetKey }) {
            existing.plannedAmount = max(0, plannedAmount)
        } else {
            context.insert(BudgetPlan(monthPeriodKey: periodKey, categoryID: categoryID, plannedAmount: max(0, plannedAmount)))
        }
        try? context.save()
    }

    func addTransaction(
        context: ModelContext,
        date: Date,
        amount: Double,
        kind: TransactionKind,
        categoryID: String?,
        note: String
    ) {
        let transaction = Transaction(
            date: date,
            amount: abs(amount),
            kind: kind,
            categoryID: categoryID,
            note: note
        )
        context.insert(transaction)
        try? context.save()
    }

    func deleteTransaction(context: ModelContext, transaction: Transaction) {
        if transaction.fixedItemID != nil {
            try? FixedItemsService.registerDeletionSkipIfNeeded(transaction: transaction, context: context)
        }
        context.delete(transaction)
        try? context.save()
    }

}
