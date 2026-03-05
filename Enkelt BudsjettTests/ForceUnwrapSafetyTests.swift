import Foundation
import Testing
@testable import Simple_Budget___Budskjett_planlegger_gjort_enkelt

private typealias Category = Simple_Budget___Budskjett_planlegger_gjort_enkelt.Category

struct ForceUnwrapSafetyTests {

    @Test
    @MainActor
    func savingsCategoryOnlyIgnoresTransactionsWithoutCategory() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15)) ?? .now
        let monthStart = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 1)) ?? now

        let categories = [
            Category(id: "cat_savings", name: "Sparing", type: .savings, sortOrder: 1)
        ]
        let transactions = [
            Transaction(date: monthStart, amount: 300, kind: .expense, categoryID: "cat_savings"),
            Transaction(date: monthStart, amount: 200, kind: .manualSaving),
            Transaction(date: monthStart, amount: 500, kind: .expense, categoryID: nil)
        ]

        let saved = SavingsService.savedYearToDate(
            definition: .savingsCategoryOnly,
            transactions: transactions,
            categories: categories,
            now: now
        )

        #expect(saved == 500)
    }

    @Test
    @MainActor
    func challengeSavingsCategoryIgnoresTransactionsWithoutCategory() {
        let startDate = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 1)) ?? .now
        let endDate = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 30)) ?? .now
        let challenge = Challenge(
            type: .save1000In30Days,
            startDate: startDate,
            endDate: endDate,
            targetAmount: 1_000,
            measurementMode: .savingsCategory
        )
        let categories = [
            Category(id: "cat_savings", name: "Sparing", type: .savings, sortOrder: 1),
            Category(id: "cat_food", name: "Mat", type: .expense, sortOrder: 2)
        ]
        let transactions = [
            Transaction(date: startDate, amount: 300, kind: .manualSaving),
            Transaction(date: startDate, amount: 400, kind: .expense, categoryID: "cat_savings"),
            Transaction(date: startDate, amount: 600, kind: .expense, categoryID: nil),
            Transaction(date: startDate, amount: 500, kind: .expense, categoryID: "cat_food")
        ]

        let progress = ChallengeService.recalculate(
            challenge: challenge,
            transactions: transactions,
            categories: categories,
            preference: nil,
            now: startDate
        )

        #expect(abs(progress - 0.7) < 0.000_1)
        #expect(challenge.status == .active)
    }

    @Test
    @MainActor
    func transactionsForGroupIgnoresTransactionsWithoutCategory() {
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
}
