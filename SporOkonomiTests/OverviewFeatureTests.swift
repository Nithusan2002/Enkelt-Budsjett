import Foundation
import Testing
@testable import SporOkonomi

struct OverviewFeatureTests {

    @Test
    @MainActor
    func overviewDoesNotShowEmptyStateWhenActiveGoalExists() {
        let viewModel = OverviewViewModel()
        let goal = Goal(
            targetAmount: 250_000,
            targetDate: Calendar.current.date(byAdding: .year, value: 1, to: .now)!,
            isActive: true
        )

        let shouldShowEmptyState = viewModel.shouldShowEmptyState(
            transactions: [],
            snapshots: [],
            plans: [],
            accounts: [],
            activeGoal: goal
        )

        #expect(shouldShowEmptyState == false)
    }

    @Test
    @MainActor
    func overviewReturnsExpiredWhenGoalDateHasPassed() {
        let viewModel = OverviewViewModel()
        let summary = GoalSummary(
            targetAmount: 100_000,
            targetDate: Calendar.current.date(byAdding: .day, value: -2, to: .now)!,
            createdAt: Calendar.current.date(byAdding: .month, value: -6, to: .now)!,
            progress: 0.45,
            monthsRemaining: 1,
            perMonth: 10_000
        )

        #expect(viewModel.goalPlanState(summary: summary) == .expired)
    }

    @Test
    @MainActor
    func overviewHeroCopyExplainsIncomeOnlyMonth() {
        let viewModel = OverviewViewModel()
        let status = OverviewBudgetStatus(
            hasPlan: false,
            planned: 0,
            remaining: 0,
            net: 32_000,
            income: 32_000,
            spent: 0
        )

        #expect(viewModel.heroTitle() == "Tilgjengelig denne måneden")
        #expect(viewModel.heroStatusLine(status: status, hasTransactions: true) == "Legg til flere transaksjoner for en mer presis oversikt.")
        #expect(viewModel.heroPrimaryCTATitle() == "Legg til transaksjon")
        #expect(viewModel.dailyBudgetText(status: status, now: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 10))!, areAmountsHidden: false) == "≈ 1 455 kr per dag resten av måneden")
    }

    @Test
    @MainActor
    func overviewHeroUsesRoundedKrAndOverLabel() {
        let viewModel = OverviewViewModel()
        let positive = OverviewBudgetStatus(
            hasPlan: false,
            planned: 0,
            remaining: 0,
            net: 1_143.24,
            income: 15_500,
            spent: 14_356.76
        )
        let overBudget = OverviewBudgetStatus(
            hasPlan: true,
            planned: 12_000,
            remaining: -677.4,
            net: 3_200,
            income: 15_000,
            spent: 12_677.4
        )

        #expect(viewModel.heroAmountText(status: positive) == "1 143 kr")
        #expect(viewModel.heroMetricValue(amount: positive.spent) == "14 357 kr")
        #expect(viewModel.heroMetricValue(amount: overBudget.planned) == "12 000 kr")
        #expect(viewModel.heroAmountText(status: overBudget) == "677 kr over")
        #expect(viewModel.heroStatusLine(status: overBudget, hasTransactions: true) == "Over budsjett med 677 kr")
    }

    @Test
    @MainActor
    func overviewShowsMonthlyProgressWhenBudgetExists() {
        let viewModel = OverviewViewModel()
        let withPlan = OverviewBudgetStatus(
            hasPlan: true,
            planned: 10_000,
            remaining: 10_000,
            net: 32_000,
            income: 32_000,
            spent: 0
        )
        let withPlanAndSpend = OverviewBudgetStatus(
            hasPlan: true,
            planned: 10_000,
            remaining: 6_000,
            net: 28_000,
            income: 32_000,
            spent: 4_000
        )
        let withoutPlan = OverviewBudgetStatus(
            hasPlan: false,
            planned: 0,
            remaining: 0,
            net: 26_000,
            income: 32_000,
            spent: 4_000
        )

        let progressWithoutSpend = viewModel.monthlyProgress(status: withPlan)
        let progressWithSpend = viewModel.monthlyProgress(status: withPlanAndSpend)

        #expect(progressWithoutSpend?.value == 0)
        #expect(progressWithoutSpend?.total == 10_000)
        #expect(progressWithSpend?.value == 4_000)
        #expect(progressWithSpend?.total == 10_000)
        #expect(viewModel.monthlyProgress(status: withoutPlan) == nil)
    }

    @Test
    @MainActor
    func overviewUsesDistinctHistoricalSavingsLabels() {
        let viewModel = OverviewViewModel()

        #expect(viewModel.registeredSavingsHeadline() == "Registrert sparing")
        #expect(viewModel.registeredSavingsSupportText() == "Penger du har registrert til sparing.")
        #expect(viewModel.investmentsEmptySupportText() == "Legg inn verdien når du vil følge utviklingen over tid.")
    }

    @Test
    @MainActor
    func overviewUsesNaturalCopyWhenMonthlyNetIsNegative() {
        let viewModel = OverviewViewModel()
        let status = OverviewBudgetStatus(
            hasPlan: false,
            planned: 0,
            remaining: 0,
            net: -500,
            income: 10_000,
            spent: 10_500
        )

        #expect(viewModel.heroStatusLine(status: status, hasTransactions: true) == "Registrer flere transaksjoner for en mer presis oversikt.")
    }

    @Test
    @MainActor
    func overviewScreenStatusReflectsBudgetUrgency() {
        let viewModel = OverviewViewModel()
        let nearLimit = OverviewBudgetStatus(
            hasPlan: true,
            planned: 10_000,
            remaining: 1_000,
            net: 20_000,
            income: 30_000,
            spent: 9_000
        )
        let overBudget = OverviewBudgetStatus(
            hasPlan: true,
            planned: 10_000,
            remaining: -500,
            net: 20_000,
            income: 30_000,
            spent: 10_500
        )

        #expect(viewModel.screenStatusText(status: nearLimit, goalSummary: nil, hasTransactions: true) == "Nær budsjettgrensen")
        #expect(viewModel.screenStatusText(status: overBudget, goalSummary: nil, hasTransactions: true) == "Over budsjett")
    }

    @Test
    @MainActor
    func overviewInvestmentCopyUsesUpdatedWording() {
        let viewModel = OverviewViewModel()
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 26)) ?? .now
        let snapshot = InvestmentSnapshot(periodKey: "2026-02", capturedAt: now, totalValue: 100_000)

        #expect(viewModel.investmentLastUpdatedText(snapshot: snapshot) == "Oppdatert 26 feb")
        #expect(viewModel.investmentChangeText(change: 5_920, previousSnapshot: snapshot, areAmountsHidden: false) == "Siden sist: +5 920 kr")
    }
}
