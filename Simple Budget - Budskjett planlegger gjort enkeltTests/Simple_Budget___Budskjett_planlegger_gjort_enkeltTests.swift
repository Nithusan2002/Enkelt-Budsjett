import Foundation
import Testing
@testable import Simple_Budget___Budskjett_planlegger_gjort_enkelt

struct Simple_Budget___Budskjett_planlegger_gjort_enkeltTests {

    @Test func calculatesSavingsIncomeMinusExpense() async throws {
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

    @Test func calculatesRequiredMonthlySaving() async throws {
        let targetDate = Calendar.current.date(byAdding: .month, value: 10, to: .now) ?? .now
        let monthly = GoalService.requiredMonthlySaving(
            nowWealth: 50000,
            targetAmount: 150000,
            targetDate: targetDate,
            now: .now
        )
        #expect(monthly > 0)
    }
}
