import Foundation
import SwiftData
import Testing
@testable import Simple_Budget___Budskjett_planlegger_gjort_enkelt

struct OnboardingFeatureTests {

    @Test
    @MainActor
    func onboardingCompleteIsIdempotentForIncomeItem() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(onboardingCompleted: false)
        context.insert(preference)
        try context.save()

        let viewModel = OnboardingViewModel(preference: preference)
        viewModel.selectGoal(.reduceSpending)
        viewModel.monthlyIncomeText = "50 000"
        viewModel.monthlyBudgetText = "20 000"
        viewModel.payday = 25

        viewModel.finish(preference: preference, context: context)
        viewModel.finish(preference: preference, context: context)

        let fixedItems = try context.fetch(FetchDescriptor<FixedItem>())
        let transactions = try context.fetch(FetchDescriptor<Transaction>())

        #expect(try context.fetch(FetchDescriptor<InvestmentSnapshot>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Goal>()).isEmpty)
        #expect(fixedItems.filter { $0.id == "fixed_income_salary_onboarding" }.count == 1)
        #expect(transactions.filter { $0.fixedItemID == "fixed_income_salary_onboarding" }.count == 1)
        #expect(preference.onboardingCompleted)
    }

    @Test
    @MainActor
    func onboardingFlowHasExactlyFiveSteps() {
        let preference = UserPreference(onboardingCompleted: false, onboardingFocus: .budget)
        let viewModel = OnboardingViewModel(preference: preference)

        let order = viewModel.orderedSteps
        #expect(order.count == 5)
        #expect(order.first == .goal)
        #expect(order[1] == .minimumData)
        #expect(order[2] == .template)
        #expect(order[3] == .summary)
        #expect(order.last == .firstAction)
    }

    @Test
    @MainActor
    func onboardingFinalActionTitleDependsOnGoal() {
        let preference = UserPreference(onboardingCompleted: false)
        let viewModel = OnboardingViewModel(preference: preference)

        viewModel.selectGoal(.trackInvestments)
        #expect(viewModel.firstActionPrimaryButtonTitle == "Legg til første investering")

        viewModel.selectGoal(.getOverview)
        #expect(viewModel.firstActionPrimaryButtonTitle == "Legg til første utgift")
    }

    @Test
    @MainActor
    func onboardingIncomeRequirementDependsOnGoal() {
        let preference = UserPreference(onboardingCompleted: false)
        let viewModel = OnboardingViewModel(preference: preference)

        viewModel.currentStep = .minimumData
        viewModel.selectGoal(.trackInvestments)
        viewModel.monthlyIncomeText = ""
        #expect(viewModel.isPrimaryDisabled == false)

        viewModel.selectGoal(.reduceSpending)
        #expect(viewModel.isPrimaryDisabled == true)
    }
}
