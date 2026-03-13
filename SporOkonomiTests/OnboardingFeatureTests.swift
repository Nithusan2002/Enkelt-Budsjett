import Foundation
import SwiftData
import Testing
@testable import SporOkonomi

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
        viewModel.monthlyIncomeText = "50 000"

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
        #expect(order.first == .intro)
        #expect(order[1] == .goals)
        #expect(order[2] == .income)
        #expect(order[3] == .fixedCosts)
        #expect(order.last == .summary)
    }

    @Test
    @MainActor
    func onboardingIntroUsesNewHeroCopy() {
        let preference = UserPreference(onboardingCompleted: false)
        let viewModel = OnboardingViewModel(preference: preference)

        viewModel.currentStep = .intro

        #expect(viewModel.showsProgressHeader == false)
        #expect(viewModel.primaryButtonTitle == "Kom i gang")
        #expect(viewModel.secondaryButtonTitle == "Hopp over intro")
        #expect(viewModel.introTitle == "Se hvor mye du faktisk har igjen hver måned")
        #expect(viewModel.introBodyText == "Få roligere oversikt uten komplisert oppsett.")
        #expect(viewModel.introPreviewEyebrow == "Eksempel")
        #expect(viewModel.introPreviewTitle == "6 200 kr igjen denne måneden")
    }

    @Test
    @MainActor
    func onboardingSkipTitlesMatchRequestedFlow() {
        let preference = UserPreference(onboardingCompleted: false)
        let viewModel = OnboardingViewModel(preference: preference)

        viewModel.currentStep = .fixedCosts
        #expect(viewModel.primaryButtonTitle == "Se resultat")
        #expect(viewModel.secondaryButtonTitle == "Ikke nå")

        viewModel.currentStep = .summary
        #expect(viewModel.primaryButtonTitle == "Start appen")
        #expect(viewModel.secondaryButtonTitle == nil)
    }

    @Test
    @MainActor
    func onboardingCanGoBackOneStepAtATime() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(onboardingCompleted: false)
        context.insert(preference)
        try context.save()

        let viewModel = OnboardingViewModel(preference: preference)

        #expect(viewModel.canGoBack == false)

        viewModel.currentStep = .fixedCosts
        #expect(viewModel.canGoBack == true)

        viewModel.goBack(preference: preference, context: context)
        #expect(viewModel.currentStep == .income)
        #expect(preference.onboardingCurrentStep == OnboardingStep.income.rawValue)

        viewModel.goBack(preference: preference, context: context)
        #expect(viewModel.currentStep == .goals)
        #expect(preference.onboardingCurrentStep == OnboardingStep.goals.rawValue)
    }

    @Test
    @MainActor
    func onboardingIncomeStepRequiresAValidAmount() {
        let preference = UserPreference(onboardingCompleted: false)
        let viewModel = OnboardingViewModel(preference: preference)

        viewModel.currentStep = .income
        viewModel.monthlyIncomeText = ""
        #expect(viewModel.isPrimaryDisabled == true)

        viewModel.monthlyIncomeText = "abc"
        #expect(viewModel.isPrimaryDisabled == true)

        viewModel.monthlyIncomeText = "32 000"
        #expect(viewModel.isPrimaryDisabled == false)
    }

    @Test
    @MainActor
    func onboardingGoalStepAllowsMultipleSelectionsAndMapsFocus() {
        let preference = UserPreference(onboardingCompleted: false)
        let viewModel = OnboardingViewModel(preference: preference)

        viewModel.toggleGoal(.followInvestments)
        #expect(viewModel.selectedGoals == [.followInvestments])
        #expect(viewModel.focus == .investments)

        viewModel.toggleGoal(.saveMore)
        #expect(viewModel.selectedGoals == [.saveMore, .followInvestments])
        #expect(viewModel.focus == .both)

        viewModel.toggleGoal(.followInvestments)
        #expect(viewModel.selectedGoals == [.saveMore])
        #expect(viewModel.focus == .budget)
    }

    @Test
    @MainActor
    func onboardingResultSubtractsSelectedFixedExpenseEstimates() {
        let preference = UserPreference(onboardingCompleted: false)
        let viewModel = OnboardingViewModel(preference: preference)

        viewModel.monthlyIncomeText = "12 000"
        viewModel.selectedFixedCosts = [.rent, .electricity, .subscriptions, .transport]

        #expect(viewModel.resultAmount == 6_200)
        #expect(viewModel.resultAmountText == "6 200 kr")
        #expect(viewModel.summaryResultText == "Du har ca. 6 200 kr igjen denne måneden")
    }

    @Test
    @MainActor
    func onboardingCompleteIncludesChosenFixedCostsAsBudgetCategories() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(onboardingCompleted: false)
        context.insert(preference)
        try context.save()

        let viewModel = OnboardingViewModel(preference: preference)
        viewModel.monthlyIncomeText = "45 000"
        viewModel.selectedFixedCosts = [.rent, .transport]
        viewModel.finish(preference: preference, context: context)

        let categories = try context.fetch(FetchDescriptor<SporOkonomi.Category>())
        let categoryNames = Set(categories.map(\.name))

        #expect(categoryNames.contains("Husleie"))
        #expect(categoryNames.contains("Transport"))
    }

    @Test
    @MainActor
    func onboardingLegacyStoredStepMapsToClosestSimplifiedStep() {
        let preference = UserPreference(onboardingCompleted: false, onboardingCurrentStep: 4)
        let viewModel = OnboardingViewModel(preference: preference)

        #expect(viewModel.currentStep == .summary)
    }

    @Test
    @MainActor
    func onboardingSkipCompletesWithoutCreatingIncomeData() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(onboardingCompleted: false)
        context.insert(preference)
        try context.save()

        let viewModel = OnboardingViewModel(preference: preference)
        viewModel.skipAll(preference: preference, context: context)

        let fixedItems = try context.fetch(FetchDescriptor<FixedItem>())
        let transactions = try context.fetch(FetchDescriptor<Transaction>())

        #expect(preference.onboardingCompleted)
        #expect(fixedItems.isEmpty)
        #expect(transactions.isEmpty)
    }

    @Test
    @MainActor
    func onboardingSummaryCopyUsesConcreteResult() {
        let preference = UserPreference(onboardingCompleted: false)
        let viewModel = OnboardingViewModel(preference: preference)

        viewModel.monthlyIncomeText = "12 000"
        viewModel.selectedFixedCosts = [.rent, .electricity, .subscriptions, .transport]

        #expect(viewModel.summaryTitle == "Du er klar")
        #expect(viewModel.summaryBadgeText == "Klar til bruk")
        #expect(viewModel.summaryConfirmationText == "Økonomien din er satt opp")
        #expect(viewModel.summaryResultText == "Du har ca. 6 200 kr igjen denne måneden")
        #expect(viewModel.summaryHelpText == "Basert på det du har lagt inn så langt.")
    }
}
