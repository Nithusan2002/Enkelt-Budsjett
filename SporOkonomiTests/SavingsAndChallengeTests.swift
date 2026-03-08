import Foundation
import Testing
@testable import SporOkonomi

private typealias Category = SporOkonomi.Category

struct SavingsAndChallengeTests {

    @Test
    @MainActor
    func appAmountInputParsesKrPrefixAndCommaDecimals() {
        #expect(AppAmountInput.parse("kr 12 345,67") == 12_345.67)
        #expect(AppAmountInput.parse("12\u{00A0}345,67") == 12_345.67)
    }

    @Test
    @MainActor
    func appAmountInputFormatsLiveInputWithGroupingAndDecimals() {
        #expect(AppAmountInput.formatLive("12345") == "12 345")
        #expect(AppAmountInput.formatLive("kr 12345,6") == "12 345,6")
        #expect(AppAmountInput.formatLive("12345,678") == "12 345,67")
    }

    @Test
    @MainActor
    func savedYearToDateSavingsOnlyIgnoresIncomeAndExpense() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15)) ?? .now
        let monthStart = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 1)) ?? now

        let categories = [
            Category(id: "cat_savings", name: "Sparing", type: .savings, sortOrder: 1),
            Category(id: "cat_food", name: "Mat", type: .expense, sortOrder: 2)
        ]
        let transactions = [
            Transaction(date: monthStart, amount: 20_000, kind: .income),
            Transaction(date: monthStart, amount: 3_000, kind: .expense, categoryID: "cat_food"),
            Transaction(date: monthStart, amount: 500, kind: .manualSaving),
            Transaction(date: monthStart, amount: 700, kind: .expense, categoryID: "cat_savings")
        ]

        let saved = SavingsService.savedYearToDate(
            definition: .savingsCategoryOnly,
            transactions: transactions,
            categories: categories,
            now: now
        )
        #expect(saved == 1_200)
    }

    @Test
    @MainActor
    func savedYearToDateSavingsOnlyIgnoresTransactionsWithoutCategory() {
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
    func savedYearToDateExcludesFutureTransactionsInSameYear() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15)) ?? .now
        let past = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 10)) ?? now
        let future = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 1)) ?? now

        let transactions = [
            Transaction(date: past, amount: 10_000, kind: .income),
            Transaction(date: past, amount: 2_000, kind: .expense),
            Transaction(date: future, amount: 50_000, kind: .income)
        ]

        let saved = SavingsService.savedYearToDate(
            definition: .incomeMinusExpense,
            transactions: transactions,
            categories: [],
            now: now
        )
        #expect(saved == 8_000)
    }

    @Test
    @MainActor
    func savedYearToDateIncomeMinusExpenseAccountsForRefunds() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15)) ?? .now
        let monthStart = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 1)) ?? now

        let transactions = [
            Transaction(date: monthStart, amount: 20_000, kind: .income),
            Transaction(date: monthStart, amount: 5_000, kind: .expense),
            Transaction(date: monthStart, amount: 1_000, kind: .refund)
        ]

        let saved = SavingsService.savedYearToDate(
            definition: .incomeMinusExpense,
            transactions: transactions,
            categories: [],
            now: now
        )

        #expect(saved == 16_000)
    }

    @Test
    @MainActor
    func challengeSavingsDefinitionCountsTransactionsAcrossYearBoundary() {
        let startDate = Calendar.current.date(from: DateComponents(year: 2025, month: 12, day: 15, hour: 8)) ?? .now
        let endDate = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 23, minute: 59)) ?? .now
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 10, hour: 12)) ?? .now

        let challenge = Challenge(
            type: .save1000In30Days,
            startDate: startDate,
            endDate: endDate,
            targetAmount: 1_500,
            measurementMode: .savingsDefinition
        )
        let preference = UserPreference(savingsDefinition: .savingsCategoryOnly)
        let categories = [
            Category(id: "cat_savings", name: "Sparing", type: .savings, sortOrder: 1)
        ]
        let transactions = [
            Transaction(date: Calendar.current.date(from: DateComponents(year: 2025, month: 12, day: 20)) ?? startDate, amount: 1_000, kind: .manualSaving),
            Transaction(date: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5)) ?? now, amount: 500, kind: .manualSaving)
        ]

        let progress = ChallengeService.recalculate(
            challenge: challenge,
            transactions: transactions,
            categories: categories,
            preference: preference,
            now: now
        )

        #expect(progress == 1)
        #expect(challenge.status == .completed)
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
    func challengeSavingsDefinitionCountsOnlyChallengePeriodAcrossYearBoundary() {
        let calendar = Calendar.current
        let startDate = calendar.date(from: DateComponents(year: 2025, month: 12, day: 15)) ?? .now
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15)) ?? .now
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10)) ?? .now

        let challenge = Challenge(
            type: .save1000In30Days,
            startDate: startDate,
            endDate: endDate,
            targetAmount: 4_000,
            targetDays: 31,
            status: .active,
            progress: 0,
            measurementMode: .savingsDefinition,
            manualProgress: 0
        )
        let preference = UserPreference(savingsDefinition: .incomeMinusExpense)
        let transactions = [
            Transaction(date: calendar.date(from: DateComponents(year: 2025, month: 11, day: 30)) ?? startDate, amount: 9_000, kind: .income),
            Transaction(date: calendar.date(from: DateComponents(year: 2025, month: 12, day: 20)) ?? startDate, amount: 5_000, kind: .income),
            Transaction(date: calendar.date(from: DateComponents(year: 2026, month: 1, day: 5)) ?? startDate, amount: 1_000, kind: .expense),
            Transaction(date: calendar.date(from: DateComponents(year: 2026, month: 1, day: 20)) ?? endDate, amount: 500, kind: .expense)
        ]

        let progress = ChallengeService.recalculate(
            challenge: challenge,
            transactions: transactions,
            categories: [],
            preference: preference,
            now: now
        )

        #expect(progress == 1)
        #expect(challenge.status == .completed)
    }
}
