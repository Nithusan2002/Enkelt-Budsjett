import Foundation
import Testing
@testable import SporOkonomi

private typealias Category = SporOkonomi.Category

struct BudgetFeatureTests {

    @Test
    @MainActor
    func budgetTrackedImpactCountsManualSaving() {
        let transaction = Transaction(
            date: .now,
            amount: 1_500,
            kind: .manualSaving
        )

        #expect(BudgetService.budgetImpact(transaction) == 0)
        #expect(BudgetService.trackedBudgetImpact(transaction) == 1_500)
    }

    @Test
    @MainActor
    func budgetGroupRowsIncludeManualSavingInSpentTotals() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15)) ?? .now
        let periodKey = DateService.periodKey(from: now)
        let category = Category(
            id: "cat_savings",
            name: "Målsparekonto",
            type: .savings,
            groupKey: BudgetGroup.hverdags.rawValue,
            sortOrder: 1
        )
        let transaction = Transaction(
            date: now,
            amount: 800,
            kind: .manualSaving,
            categoryID: category.id
        )

        let viewModel = BudgetViewModel()
        let rows = viewModel.groupRows(
            periodKey: periodKey,
            categories: [category],
            groupPlans: [],
            periodTransactions: [transaction]
        )
        let summary = viewModel.summary(groupRows: rows, periodTransactions: [transaction])

        #expect(rows.first(where: { $0.group == .hverdags })?.spent == 800)
        #expect(summary.expenseTotal == 800)
    }

    @Test
    @MainActor
    func budgetTransactionsForGroupIgnoreTransactionsWithoutCategory() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15)) ?? .now
        let previousMonth = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 15)) ?? now
        let periodKey = DateService.periodKey(from: now)

        let categories = [
            Category(id: "cat_fast", name: "Internett", type: .expense, groupKey: BudgetGroup.fast.rawValue, sortOrder: 1),
            Category(id: "cat_fritid", name: "Hobby", type: .expense, groupKey: BudgetGroup.fritid.rawValue, sortOrder: 2)
        ]
        let transactions = [
            Transaction(date: now, amount: 900, kind: .expense, categoryID: "cat_fast"),
            Transaction(date: now, amount: 500, kind: .expense, categoryID: nil),
            Transaction(date: now, amount: 300, kind: .expense, categoryID: "cat_fritid"),
            Transaction(date: previousMonth, amount: 400, kind: .expense, categoryID: "cat_fast")
        ]

        let viewModel = BudgetViewModel()
        let rows = viewModel.transactionsForGroup(
            .fast,
            periodKey: periodKey,
            categories: categories,
            transactions: transactions
        )

        #expect(rows.count == 1)
        #expect(rows.first?.categoryID == "cat_fast")
    }

    @Test
    @MainActor
    func budgetGroupRowsAreSortedByRiskOverNearThenRemaining() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15)) ?? .now
        let periodKey = DateService.periodKey(from: now)

        let categories = [
            Category(id: "cat_bolig", name: "Husleie", type: .expense, groupKey: BudgetGroup.bolig.rawValue, sortOrder: 1),
            Category(id: "cat_fast", name: "Internett", type: .expense, groupKey: BudgetGroup.fast.rawValue, sortOrder: 2),
            Category(id: "cat_fritid", name: "Hobby", type: .expense, groupKey: BudgetGroup.fritid.rawValue, sortOrder: 3)
        ]

        let plans = [
            BudgetGroupPlan(monthPeriodKey: periodKey, groupKey: BudgetGroup.bolig.rawValue, plannedAmount: 5_000),
            BudgetGroupPlan(monthPeriodKey: periodKey, groupKey: BudgetGroup.fast.rawValue, plannedAmount: 4_000),
            BudgetGroupPlan(monthPeriodKey: periodKey, groupKey: BudgetGroup.fritid.rawValue, plannedAmount: 3_000)
        ]

        let transactions = [
            Transaction(date: now, amount: 5_500, kind: .expense, categoryID: "cat_bolig"),
            Transaction(date: now, amount: 3_400, kind: .expense, categoryID: "cat_fast"),
            Transaction(date: now, amount: 1_000, kind: .expense, categoryID: "cat_fritid")
        ]

        let viewModel = BudgetViewModel()
        let rows = viewModel.groupRows(
            periodKey: periodKey,
            categories: categories,
            groupPlans: plans,
            periodTransactions: transactions
        )

        #expect(rows.map(\.group) == [.bolig, .fast, .fritid])
    }

    @Test
    @MainActor
    func budgetSummaryIncludesIncomeAndNet() {
        let viewModel = BudgetViewModel()
        let periodKey = DateService.periodKey(from: .now)

        let categories = [
            Category(id: "cat_food", name: "Mat", type: .expense, sortOrder: 1),
            Category(id: "cat_savings", name: "Sparing", type: .savings, sortOrder: 2)
        ]
        let plans = [
            BudgetPlan(monthPeriodKey: periodKey, categoryID: "cat_food", plannedAmount: 8000)
        ]
        let transactions = [
            Transaction(date: .now, amount: 20000, kind: .income),
            Transaction(date: .now, amount: 4500, kind: .expense, categoryID: "cat_food")
        ]

        let summary = viewModel.summary(periodKey: periodKey, plans: plans, categories: categories, transactions: transactions)
        #expect(summary.planned == 8000)
        #expect(summary.actual == 4500)
        #expect(summary.income == 20000)
        #expect(summary.net == 15500)
        #expect(summary.remaining == 3500)
    }

    @Test
    @MainActor
    func budgetSummaryUsesNetAsRemainingWhenNoPlanExists() {
        let viewModel = BudgetViewModel()
        let periodKey = DateService.periodKey(from: .now)

        let categories = [
            Category(id: "cat_food", name: "Mat", type: .expense, sortOrder: 1)
        ]
        let transactions = [
            Transaction(date: .now, amount: 10000, kind: .income),
            Transaction(date: .now, amount: 3000, kind: .expense, categoryID: "cat_food")
        ]

        let summary = viewModel.summary(periodKey: periodKey, plans: [], categories: categories, transactions: transactions)
        #expect(summary.planned == 0)
        #expect(summary.net == 7000)
        #expect(summary.remaining == 7000)
    }

    @Test
    @MainActor
    func budgetDetailIncomeRowsIgnoreDuplicateCategoryModels() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 12)) ?? .now
        let categories = [
            Category(id: "cat_income_salary", name: "Lønn", type: .income, sortOrder: 1),
            Category(id: "cat_income_salary", name: "Lønn", type: .income, sortOrder: 1)
        ]
        let transactions = [
            Transaction(date: now, amount: 52_000, kind: .income, categoryID: "cat_income_salary")
        ]

        let viewModel = BudgetViewModel()
        let rows = viewModel.incomeRows(categories: categories, periodTransactions: transactions)

        #expect(rows.count == 1)
        #expect(rows.first?.title == "Lønn")
        #expect(rows.first?.amount == 52_000)
    }

    @Test
    @MainActor
    func budgetDetailSavingsRowsIgnoreDuplicateCategoryModels() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 12)) ?? .now
        let categories = [
            Category(id: "cat_savings_account", name: "Sparekonto (generelt)", type: .savings, sortOrder: 1),
            Category(id: "cat_savings_account", name: "Sparekonto (generelt)", type: .savings, sortOrder: 1)
        ]
        let transactions = [
            Transaction(date: now, amount: 1_100, kind: .manualSaving, categoryID: "cat_savings_account")
        ]

        let viewModel = BudgetViewModel()
        let rows = viewModel.savingsRows(categories: categories, periodTransactions: transactions)

        #expect(rows.count == 1)
        #expect(rows.first?.title == "Sparekonto (generelt)")
        #expect(rows.first?.amount == 1_100)
    }
}
