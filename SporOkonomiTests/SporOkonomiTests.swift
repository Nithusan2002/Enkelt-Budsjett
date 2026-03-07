import Foundation
import Testing
import SwiftData
@testable import SporOkonomi

struct SporOkonomiTests {

    @Test @MainActor func calculatesSavingsIncomeMinusExpense() async throws {
        let now = Date()
        let transactions = [
            Transaction(date: now, amount: 20000, kind: .income),
            Transaction(date: now, amount: -5000, kind: .expense),
            Transaction(date: now, amount: -2000, kind: .expense)
        ]
        let value = SavingsService.savedYearToDate(
            definition: .incomeMinusExpense,
            transactions: transactions,
            categories: []
        )
        #expect(value == 13000)
    }

    @Test @MainActor func calculatesRequiredMonthlySaving() async throws {
        let targetDate = Calendar.current.date(byAdding: .month, value: 10, to: .now) ?? .now
        let monthly = GoalService.requiredMonthlySaving(
            nowWealth: 50000,
            targetAmount: 150000,
            targetDate: targetDate,
            now: .now
        )
        #expect(monthly > 0)
    }

    @Test @MainActor func goalEditorSavesWealthGoalsIncludingAccounts() async throws {
        let schema = Schema([Goal.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let viewModel = GoalEditorViewModel()

        viewModel.targetAmountText = "250 000"
        let didSave = viewModel.save(goal: nil, context: context)
        let goals = try context.fetch(FetchDescriptor<Goal>())

        #expect(didSave)
        #expect(goals.count == 1)
        #expect(goals.first?.includeAccounts == true)
    }

    @Test @MainActor func aggregatesBudgetByGroupAndSummary() async throws {
        let viewModel = BudgetViewModel()
        let periodKey = "2026-02"
        let date = DateService.monthStart(from: periodKey) ?? .now

        let categories = [
            Category(id: "cat_rent", name: "Husleie", type: .expense, groupKey: BudgetGroup.bolig.rawValue, sortOrder: 1),
            Category(id: "cat_food", name: "Mat", type: .expense, groupKey: BudgetGroup.hverdags.rawValue, sortOrder: 2)
        ]
        let groupPlans = [
            BudgetGroupPlan(monthPeriodKey: periodKey, groupKey: BudgetGroup.bolig.rawValue, plannedAmount: 7000)
        ]
        let transactions = [
            Transaction(date: date, amount: 7500, kind: .expense, categoryID: "cat_rent"),
            Transaction(date: date, amount: 500, kind: .expense, categoryID: "cat_food")
        ]

        let rows = viewModel.groupRows(
            periodKey: periodKey,
            categories: categories,
            groupPlans: groupPlans,
            transactions: transactions
        )
        let summary = viewModel.summary(periodKey: periodKey, groupRows: rows, transactions: transactions)

        let bolig = rows.first(where: { $0.group == .bolig })
        let hverdags = rows.first(where: { $0.group == .hverdags })

        #expect(bolig != nil)
        #expect(bolig?.planned == 7000)
        #expect(bolig?.spent == 7500)
        #expect(bolig?.isOverBudget == true)

        #expect(hverdags != nil)
        #expect(hverdags?.planned == nil)
        #expect(hverdags?.spent == 500)

        #expect(summary.planned == 7000)
        #expect(summary.trackedActual == 7500)
        #expect(summary.expenseTotal == 8000)
        #expect(summary.remaining == -500)
    }

    @Test @MainActor func upsertAndDeleteGroupPlans() async throws {
        let schema = Schema([BudgetGroupPlan.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let viewModel = BudgetViewModel()
        let periodKey = "2026-03"

        context.insert(BudgetGroupPlan(monthPeriodKey: periodKey, groupKey: BudgetGroup.fast.rawValue, plannedAmount: 1200))
        try context.save()

        let existingBefore = try context.fetch(FetchDescriptor<BudgetGroupPlan>())
        #expect(existingBefore.count == 1)

        viewModel.upsertGroupPlans(
            context: context,
            periodKey: periodKey,
            values: [
                .bolig: 8000,
                .fast: nil
            ],
            existingPlans: existingBefore
        )

        let after = try context.fetch(FetchDescriptor<BudgetGroupPlan>())
        let bolig = after.first(where: { $0.groupKey == BudgetGroup.bolig.rawValue })
        let fast = after.first(where: { $0.groupKey == BudgetGroup.fast.rawValue })

        #expect(bolig != nil)
        #expect(bolig?.plannedAmount == 8000)
        #expect(fast == nil)
    }

    @Test @MainActor func summaryWithoutLimitsUsesTrackingOnly() async throws {
        let viewModel = BudgetViewModel()
        let periodKey = "2026-04"
        let date = DateService.monthStart(from: periodKey) ?? .now

        let categories = [
            Category(id: "cat_food", name: "Mat", type: .expense, groupKey: BudgetGroup.hverdags.rawValue, sortOrder: 1)
        ]
        let transactions = [
            Transaction(date: date, amount: 900, kind: .expense, categoryID: "cat_food")
        ]

        let rows = viewModel.groupRows(periodKey: periodKey, categories: categories, groupPlans: [], transactions: transactions)
        let summary = viewModel.summary(periodKey: periodKey, groupRows: rows, transactions: transactions)

        #expect(summary.planned == 0)
        #expect(summary.trackedActual == 0)
        #expect(summary.expenseTotal == 900)
        #expect(summary.remaining == 0)
    }
}
