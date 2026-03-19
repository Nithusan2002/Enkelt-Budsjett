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
    func onboardingFlowHasFourStepsWithoutInvestmentsSelected() {
        let preference = UserPreference(onboardingCompleted: false, onboardingFocus: .budget)
        let viewModel = OnboardingViewModel(preference: preference)

        let order = viewModel.orderedSteps
        #expect(order.count == 4)
        #expect(order.first == .intro)
        #expect(order[1] == .goals)
        #expect(order[2] == .income)
        #expect(order.last == .fixedCosts)
    }

    @Test
    @MainActor
    func onboardingFlowSkipsBudgetSetupWhenOnlyInvestmentsAreRelevant() {
        let preference = UserPreference(onboardingCompleted: false)
        let viewModel = OnboardingViewModel(preference: preference)

        viewModel.toggleGoal(.followInvestments)

        let order = viewModel.orderedSteps
        #expect(order.count == 3)
        #expect(order == [.intro, .goals, .investmentTypes])
    }

    @Test
    @MainActor
    func onboardingFlowKeepsBudgetSetupWhenBudgetAndInvestmentsAreRelevant() {
        let preference = UserPreference(onboardingCompleted: false)
        let viewModel = OnboardingViewModel(preference: preference)

        viewModel.toggleGoal(.followInvestments)
        viewModel.toggleGoal(.saveMore)

        let order = viewModel.orderedSteps
        #expect(order.count == 5)
        #expect(order[2] == .income)
        #expect(order[3] == .fixedCosts)
        #expect(order.last == .investmentTypes)
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

        viewModel.currentStep = .income
        #expect(viewModel.secondaryButtonTitle == "Ikke nå")

        viewModel.currentStep = .fixedCosts
        #expect(viewModel.primaryButtonTitle == "Ferdig")
        #expect(viewModel.secondaryButtonTitle == "Ikke nå")

        viewModel.currentStep = .investmentTypes
        #expect(viewModel.primaryButtonTitle == "Ferdig")
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
    func onboardingIncomeStepAllowsEmptyValueButRejectsInvalidInput() {
        let preference = UserPreference(onboardingCompleted: false)
        let viewModel = OnboardingViewModel(preference: preference)

        viewModel.currentStep = .income
        viewModel.monthlyIncomeText = ""
        #expect(viewModel.isPrimaryDisabled == false)

        viewModel.monthlyIncomeText = "abc"
        #expect(viewModel.isPrimaryDisabled == true)

        viewModel.monthlyIncomeText = "32 000"
        #expect(viewModel.isPrimaryDisabled == false)
    }

    @Test
    @MainActor
    func onboardingSecondaryActionFromIncomeAdvancesWithoutIncome() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(onboardingCompleted: false)
        context.insert(preference)
        try context.save()

        let viewModel = OnboardingViewModel(preference: preference)
        viewModel.currentStep = .income
        viewModel.monthlyIncomeText = ""

        viewModel.secondaryAction(preference: preference, context: context)

        #expect(viewModel.currentStep == .fixedCosts)
        #expect(preference.onboardingCurrentStep == OnboardingStep.fixedCosts.rawValue)
    }

    @Test
    @MainActor
    func onboardingSecondaryActionFromFixedCostsAdvancesToInvestmentTypesWhenRelevant() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(onboardingCompleted: false)
        context.insert(preference)
        try context.save()

        let viewModel = OnboardingViewModel(preference: preference)
        viewModel.toggleGoal(.followInvestments)
        viewModel.currentStep = .fixedCosts

        viewModel.secondaryAction(preference: preference, context: context)

        #expect(viewModel.currentStep == .investmentTypes)
        #expect(preference.onboardingCurrentStep == OnboardingStep.investmentTypes.rawValue)
    }

    @Test
    @MainActor
    func onboardingCanFinishWhenIncomeIsEmpty() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(onboardingCompleted: false)
        context.insert(preference)
        try context.save()

        let viewModel = OnboardingViewModel(preference: preference)
        viewModel.currentStep = .fixedCosts
        viewModel.monthlyIncomeText = ""

        viewModel.primaryAction(preference: preference, context: context)

        let fixedItems = try context.fetch(FetchDescriptor<FixedItem>())
        let transactions = try context.fetch(FetchDescriptor<Transaction>())

        #expect(preference.onboardingCompleted)
        #expect(fixedItems.isEmpty)
        #expect(transactions.isEmpty)
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
    func onboardingCompleteMapsRentToExistingHousingCategoryID() throws {
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
        let categoryIDs = Set(categories.map(\.id))

        #expect(categoryIDs.contains("cat_housing"))
        #expect(categoryIDs.contains("cat_transport"))
        #expect(categoryIDs.contains("cat_husleie") == false)
    }

    @Test
    @MainActor
    func onboardingLegacyStoredStepMapsToClosestSimplifiedStep() {
        let preference = UserPreference(onboardingCompleted: false, onboardingCurrentStep: 4)
        let viewModel = OnboardingViewModel(preference: preference)

        #expect(viewModel.currentStep == .investmentTypes)
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
    func onboardingPrimaryActionFromFixedCostsFinishesFlow() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(onboardingCompleted: false)
        context.insert(preference)
        try context.save()

        let viewModel = OnboardingViewModel(preference: preference)
        viewModel.currentStep = .fixedCosts
        viewModel.monthlyIncomeText = "40 000"
        viewModel.selectedFixedCosts = [.rent]

        viewModel.primaryAction(preference: preference, context: context)

        #expect(preference.onboardingCompleted)
    }

    @Test
    @MainActor
    func onboardingFinishWithInvestmentGoalCreatesNoTypesWhenNothingIsChosen() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(onboardingCompleted: false)
        context.insert(preference)
        try context.save()

        let viewModel = OnboardingViewModel(preference: preference)
        viewModel.toggleGoal(.followInvestments)
        viewModel.selectedInvestmentTypes.removeAll()
        viewModel.currentStep = .investmentTypes

        viewModel.primaryAction(preference: preference, context: context)

        let buckets = try context.fetch(FetchDescriptor<InvestmentBucket>())
        #expect(buckets.isEmpty)
    }

    @Test
    @MainActor
    func onboardingFinishCreatesOnlyChosenInvestmentTypes() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(onboardingCompleted: false)
        context.insert(preference)
        try context.save()

        let viewModel = OnboardingViewModel(preference: preference)
        viewModel.toggleGoal(.followInvestments)
        viewModel.selectedInvestmentTypes = [.funds, .bsu]
        viewModel.customInvestmentTypeName = "Eiendom"
        #expect(viewModel.saveCustomInvestmentType())
        viewModel.currentStep = .investmentTypes

        viewModel.primaryAction(preference: preference, context: context)

        let buckets = try context.fetch(FetchDescriptor<InvestmentBucket>())
        #expect(Set(buckets.map(\.name)) == ["Fond", "BSU", "Eiendom"])
    }

    @Test
    @MainActor
    func onboardingInvestmentTypesStartWithoutPreselectedChoices() {
        let preference = UserPreference(onboardingCompleted: false)
        let viewModel = OnboardingViewModel(preference: preference)

        #expect(viewModel.selectedInvestmentTypes.isEmpty)
    }
}
