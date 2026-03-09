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
        #expect(viewModel.heroIntroText(status: status, hasTransactions: true) == "Dette er det du har å gå på denne måneden basert på inntekten du har lagt inn.")
        #expect(viewModel.heroStatusLine(status: status, hasTransactions: true) == "Du er i gang denne måneden.")
        #expect(viewModel.heroSupportText(status: status, hasTransactions: true) == "Legg til utgifter underveis for en mer presis oversikt.")
        #expect(viewModel.heroPrimaryCTATitle() == "Legg til transaksjon")
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

        #expect(viewModel.savingsHeadline() == "Til overs i år")
        #expect(viewModel.savingsSupportText() == "Forskjellen mellom inntekter og utgifter så langt i år.")
        #expect(viewModel.registeredSavingsHeadline() == "Satt til side")
        #expect(viewModel.registeredSavingsSupportText() == "Penger du har registrert til sparing.")
        #expect(viewModel.investmentsEmptySupportText() == "Legg inn verdien når du vil følge utviklingen over tid.")
    }
}
