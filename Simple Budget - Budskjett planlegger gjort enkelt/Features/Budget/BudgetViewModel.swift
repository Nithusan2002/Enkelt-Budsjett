import Foundation
import Combine
import SwiftData

enum BudgetGroupFilter: String, CaseIterable {
    case all = "Alle"
    case overLimit = "Over budsjett"
}

struct BudgetSummaryData {
    let planned: Double
    let trackedActual: Double
    let expenseTotal: Double
    let income: Double
    let net: Double
    let remaining: Double

    var actual: Double { trackedActual }
}

struct BudgetGroupRow: Identifiable {
    let id: String
    let group: BudgetGroup
    let title: String
    let planned: Double?
    let spent: Double
    let categoryIDs: [String]

    var hasLimit: Bool { planned != nil }
    var isOverBudget: Bool {
        guard let planned else { return false }
        return spent > planned
    }
    var isNearLimit: Bool {
        guard let planned, planned > 0 else { return false }
        let ratio = spent / planned
        return ratio >= 0.8 && ratio <= 1.0
    }
}

@MainActor
final class BudgetViewModel: ObservableObject {
    @Published var selectedMonthDate: Date = .now
    @Published var selectedFilter: BudgetGroupFilter = .all
    @Published var showAddTransaction = false
    @Published var showGroupLimitsSheet = false

    func periodKey() -> String {
        DateService.periodKey(from: selectedMonthDate)
    }

    func changeMonth(by offset: Int) {
        selectedMonthDate = Calendar.current.date(byAdding: .month, value: offset, to: selectedMonthDate) ?? selectedMonthDate
    }

    func ensureMonthExists(
        context: ModelContext,
        months: [BudgetMonth]
    ) {
        let currentKey = periodKey()
        if !months.contains(where: { $0.periodKey == currentKey }) {
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

        try? context.save()
    }

    func summary(
        periodKey: String,
        groupRows: [BudgetGroupRow],
        transactions: [Transaction]
    ) -> BudgetSummaryData {
        let monthTransactions = monthTransactions(periodKey: periodKey, transactions: transactions)
        return summary(groupRows: groupRows, periodTransactions: monthTransactions)
    }

    func summary(
        groupRows: [BudgetGroupRow],
        periodTransactions: [Transaction]
    ) -> BudgetSummaryData {
        let planned = groupRows.compactMap(\.planned).reduce(0, +)
        let trackedActual = groupRows.filter(\.hasLimit).reduce(0) { $0 + $1.spent }
        let expenseTotal = periodTransactions.reduce(0) { $0 + BudgetService.expenseImpact($1) }
        return makeSummary(
            planned: planned,
            trackedActual: trackedActual,
            expenseTotal: expenseTotal,
            periodTransactions: periodTransactions,
            fallbackRemainingToNet: false
        )
    }

    func summary(
        periodKey: String,
        plans: [BudgetPlan],
        categories: [Category],
        transactions: [Transaction]
    ) -> BudgetSummaryData {
        let planned = BudgetService.plannedTotal(for: periodKey, plans: plans, categories: categories)
        let actual = BudgetService.actualExpenseTotal(for: periodKey, transactions: transactions)
        let monthTransactions = monthTransactions(periodKey: periodKey, transactions: transactions)
        return makeSummary(
            planned: planned,
            trackedActual: actual,
            expenseTotal: actual,
            periodTransactions: monthTransactions,
            fallbackRemainingToNet: true
        )
    }

    private func makeSummary(
        planned: Double,
        trackedActual: Double,
        expenseTotal: Double,
        periodTransactions: [Transaction],
        fallbackRemainingToNet: Bool
    ) -> BudgetSummaryData {
        let income = periodTransactions.reduce(0) { $0 + BudgetService.incomeImpact($1) }
        let net = income - expenseTotal
        let remaining = planned > 0 ? (planned - trackedActual) : (fallbackRemainingToNet ? net : 0)
        return BudgetSummaryData(
            planned: planned,
            trackedActual: trackedActual,
            expenseTotal: expenseTotal,
            income: income,
            net: net,
            remaining: remaining
        )
    }

    func groupRows(
        periodKey: String,
        categories: [Category],
        groupPlans: [BudgetGroupPlan],
        transactions: [Transaction]
    ) -> [BudgetGroupRow] {
        let monthTransactions = monthTransactions(periodKey: periodKey, transactions: transactions)
        return groupRows(
            periodKey: periodKey,
            categories: categories,
            groupPlans: groupPlans,
            periodTransactions: monthTransactions
        )
    }

    func groupRows(
        periodKey: String,
        categories: [Category],
        groupPlans: [BudgetGroupPlan],
        periodTransactions: [Transaction]
    ) -> [BudgetGroupRow] {
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        let actualByGroup = Dictionary(grouping: periodTransactions) { tx in
            guard let categoryID = tx.categoryID, let category = categoryByID[categoryID] else {
                return BudgetGroup.annet.rawValue
            }
            return category.groupKey
        }
        .mapValues { tx in
            tx.reduce(0) { $0 + BudgetService.budgetImpact($1) }
        }

        let categoryIDsByGroup = Dictionary(grouping: categories.filter { $0.type != .income && $0.isActive }) { $0.groupKey }
            .mapValues { rows in rows.map(\.id) }

        let plansByKey = Dictionary(uniqueKeysWithValues: groupPlans.filter { $0.monthPeriodKey == periodKey }.map { ($0.groupKey, $0) })

        let rows = BudgetGroup.allCases.compactMap { group -> BudgetGroupRow? in
            let groupKey = group.rawValue
            let hasCategories = !(categoryIDsByGroup[groupKey] ?? []).isEmpty
            let spent = max(actualByGroup[groupKey] ?? 0, 0)
            let planned = plansByKey[groupKey].map { max(0, $0.plannedAmount) }
            guard hasCategories || planned != nil else { return nil }
            return BudgetGroupRow(
                id: groupKey,
                group: group,
                title: group.title,
                planned: planned,
                spent: spent,
                categoryIDs: categoryIDsByGroup[groupKey] ?? []
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
        case .overLimit:
            return sorted.filter(\.isOverBudget)
        }
    }

    func fixedSpentByGroup(
        periodKey: String,
        categories: [Category],
        transactions: [Transaction]
    ) -> [String: Double] {
        let monthTransactions = monthTransactions(periodKey: periodKey, transactions: transactions)
        return fixedSpentByGroup(categories: categories, periodTransactions: monthTransactions)
    }

    func fixedSpentByGroup(
        categories: [Category],
        periodTransactions: [Transaction]
    ) -> [String: Double] {
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var totals: [String: Double] = [:]
        for tx in periodTransactions where tx.recurringKey != nil {
            guard let categoryID = tx.categoryID,
                  let category = categoryByID[categoryID] else { continue }
            let impact = max(BudgetService.budgetImpact(tx), 0)
            totals[category.groupKey, default: 0] += impact
        }
        return totals
    }

    func monthTransactions(periodKey: String, transactions: [Transaction]) -> [Transaction] {
        transactions.filter { DateService.periodKey(from: $0.date) == periodKey }
    }

    func upsertGroupPlans(
        context: ModelContext,
        periodKey: String,
        values: [BudgetGroup: Double?],
        existingPlans: [BudgetGroupPlan]
    ) {
        for group in BudgetGroup.allCases {
            let key = "\(periodKey)|\(group.rawValue)"
            let existing = existingPlans.first(where: { $0.uniqueKey == key })
            let input = values[group] ?? nil
            let normalized = max(0, input ?? 0)

            if normalized > 0 {
                if let existing {
                    existing.plannedAmount = normalized
                } else {
                    context.insert(BudgetGroupPlan(monthPeriodKey: periodKey, groupKey: group.rawValue, plannedAmount: normalized))
                }
            } else if let existing {
                context.delete(existing)
            }
        }
        try? context.save()
    }

    func copyPreviousMonthGroupPlans(
        periodKey: String,
        groupPlans: [BudgetGroupPlan]
    ) -> [BudgetGroup: Double?] {
        guard let previousKey = DateService.offsetPeriodKey(periodKey, months: -1) else {
            return Dictionary(uniqueKeysWithValues: BudgetGroup.allCases.map { ($0, nil) })
        }

        let previous = groupPlans.filter { $0.monthPeriodKey == previousKey }
        var output: [BudgetGroup: Double?] = Dictionary(uniqueKeysWithValues: BudgetGroup.allCases.map { ($0, nil) })
        for plan in previous {
            output[BudgetGroup.from(key: plan.groupKey)] = max(0, plan.plannedAmount)
        }
        return output
    }

    func categoriesForGroup(_ group: BudgetGroup, categories: [Category]) -> [Category] {
        categories
            .filter { $0.groupKey == group.rawValue && $0.type != .income && $0.isActive }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func transactionsForGroup(
        _ group: BudgetGroup,
        periodKey: String,
        categories: [Category],
        transactions: [Transaction]
    ) -> [Transaction] {
        let ids = Set(categoriesForGroup(group, categories: categories).map(\.id))
        return transactions
            .filter { DateService.periodKey(from: $0.date) == periodKey && (($0.categoryID != nil && ids.contains($0.categoryID!))) }
            .sorted { $0.date > $1.date }
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
