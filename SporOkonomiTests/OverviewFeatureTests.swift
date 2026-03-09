import Testing
@testable import SporOkonomi

struct OverviewFeatureTests {

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

        #expect(viewModel.registeredSavingsHeadline() == "Satt til side")
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
}
