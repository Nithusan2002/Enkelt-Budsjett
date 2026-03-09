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
        #expect(viewModel.heroIntroText(status: status, hasTransactions: true) == "Dette er utgangspunktet ditt for denne måneden basert på inntekten du har lagt inn.")
        #expect(viewModel.heroSupportText(status: status, hasTransactions: true) == "Legg til utgifter underveis, eller sett grenser når du vil ha mer oversikt.")
        #expect(viewModel.heroPrimaryCTATitle() == "Legg til transaksjon")
    }

    @Test
    @MainActor
    func overviewShowsMonthlyProgressOnlyWhenBudgetMakesSense() {
        let viewModel = OverviewViewModel()
        let withPlan = OverviewBudgetStatus(
            hasPlan: true,
            planned: 10_000,
            remaining: 6_000,
            net: 26_000,
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

        let progress = viewModel.monthlyProgress(status: withPlan)

        #expect(progress?.value == 4_000)
        #expect(progress?.total == 10_000)
        #expect(viewModel.monthlyProgress(status: withoutPlan) == nil)
    }
}
