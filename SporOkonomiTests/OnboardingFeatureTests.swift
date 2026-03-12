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
    func onboardingFlowHasExactlyThreeSteps() {
        let preference = UserPreference(onboardingCompleted: false, onboardingFocus: .budget)
        let viewModel = OnboardingViewModel(preference: preference)

        let order = viewModel.orderedSteps
        #expect(order.count == 4)
        #expect(order.first == .intro)
        #expect(order[1] == .income)
        #expect(order[2] == .goal)
        #expect(order.last == .summary)
    }

    @Test
    @MainActor
    func onboardingIntroUsesWelcomeScreenHierarchy() {
        let preference = UserPreference(onboardingCompleted: false)
        let viewModel = OnboardingViewModel(preference: preference)

        viewModel.currentStep = .intro

        #expect(viewModel.showsProgressHeader == false)
        #expect(viewModel.showsLoginAction == true)
        #expect(viewModel.primaryButtonTitle == "Kom i gang")
        #expect(viewModel.introTitle == "Få roligere oversikt over økonomien")
        #expect(viewModel.introBodyText == "Se hva du har igjen denne måneden uten komplisert oppsett.")
        #expect(viewModel.introPreviewLabel == "Tilgjengelig denne måneden")
        #expect(viewModel.introPreviewAmount == "5 560 kr")
    }

    @Test
    @MainActor
    func onboardingSkipIsAvailableOnAllSteps() {
        let preference = UserPreference(onboardingCompleted: false)
        let viewModel = OnboardingViewModel(preference: preference)

        for step in viewModel.orderedSteps {
            viewModel.currentStep = step
            #expect(viewModel.secondaryButtonTitle == "Hopp over")
        }
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

        viewModel.currentStep = .goal
        #expect(viewModel.canGoBack == true)

        viewModel.goBack(preference: preference, context: context)
        #expect(viewModel.currentStep == .income)
        #expect(preference.onboardingCurrentStep == OnboardingStep.income.rawValue)

        viewModel.goBack(preference: preference, context: context)
        #expect(viewModel.currentStep == .intro)
        #expect(preference.onboardingCurrentStep == OnboardingStep.intro.rawValue)

        viewModel.goBack(preference: preference, context: context)
        #expect(viewModel.currentStep == .intro)
    }

    @Test
    @MainActor
    func onboardingIncomeStepAllowsEmptyValueButRejectsInvalidInput() {
        let preference = UserPreference(onboardingCompleted: false)
        let viewModel = OnboardingViewModel(preference: preference)

        viewModel.currentStep = .income
        viewModel.monthlyIncomeText = ""
        #expect(viewModel.isPrimaryDisabled == false)

        viewModel.monthlyIncomeText = "32 000"
        #expect(viewModel.isPrimaryDisabled == false)
    }

    @Test
    @MainActor
    func onboardingGoalStepRequiresValidAmountOnlyWhenGoalIsEnabled() {
        let preference = UserPreference(onboardingCompleted: false)
        let viewModel = OnboardingViewModel(preference: preference)

        viewModel.currentStep = .goal
        viewModel.wantsGoal = false
        viewModel.goalAmountText = ""
        #expect(viewModel.isPrimaryDisabled == false)

        viewModel.wantsGoal = true
        viewModel.goalAmountText = ""
        #expect(viewModel.isPrimaryDisabled == true)

        viewModel.goalAmountText = "250 000"
        #expect(viewModel.isPrimaryDisabled == false)
        #expect(viewModel.goalMonthlyPreviewText?.contains("kr per måned") == true)
    }

    @Test
    @MainActor
    func onboardingCompleteIncludesCustomBucketInFirstSnapshot() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(onboardingCompleted: false)
        context.insert(preference)
        try context.save()

        try OnboardingService.complete(
            context: context,
            preference: preference,
            firstName: "Nora",
            focus: .investments,
            tone: .calm,
            firstWealthTotal: nil,
            goalAmount: nil,
            goalDate: nil,
            snapshotValues: [
                "Fond": 150_000,
                "Eiendom": 500_000
            ],
            snapshotInputProvided: true,
            budgetCategories: [],
            monthlyBudget: nil,
            monthlyIncome: nil,
            incomeDayOfMonth: 25,
            budgetTrackOnly: true,
            reminderEnabled: false,
            reminderDay: 5,
            reminderHour: 18,
            reminderMinute: 0,
            faceIDEnabled: false,
            selectedBuckets: ["Fond"],
            customBucketName: "Eiendom"
        )

        let buckets = try context.fetch(FetchDescriptor<InvestmentBucket>())
        let snapshots = try context.fetch(FetchDescriptor<InvestmentSnapshot>())

        #expect(buckets.contains(where: { $0.name == "Eiendom" }))
        #expect(snapshots.count == 1)
        #expect(snapshots[0].bucketValues.contains(where: { $0.bucketID == "bucket_eiendom" && $0.amount == 500_000 }))
        #expect(snapshots[0].bucketValues.contains(where: { $0.bucketID == "bucket_fond" && $0.amount == 150_000 }))
    }

    @Test
    @MainActor
    func onboardingDefaultBucketsExcludeCrypto() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(onboardingCompleted: false)
        context.insert(preference)
        try context.save()

        let viewModel = OnboardingViewModel(preference: preference)
        viewModel.monthlyIncomeText = "45 000"
        viewModel.finish(preference: preference, context: context)

        let buckets = try context.fetch(FetchDescriptor<InvestmentBucket>())
        let bucketNames = Set(buckets.map(\.name))

        #expect(bucketNames == ["Fond", "Aksjer", "Krypto", "Kontanter"])
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
    func onboardingSummaryCopyConnectsToMonthlyOverview() {
        let preference = UserPreference(onboardingCompleted: false)
        let viewModel = OnboardingViewModel(preference: preference)

        viewModel.monthlyIncomeText = "32 000"
        #expect(viewModel.summaryTitle == "Du er klar")
        #expect(viewModel.summaryBodyText.contains("Du kan bruke ca."))
        #expect(viewModel.summaryHelpText == "Basert på det du har lagt inn så langt.")

        viewModel.monthlyIncomeText = ""
        #expect(viewModel.summaryBodyText.contains("oversikt"))
        #expect(viewModel.summaryHelpText == "Basert på det du har lagt inn så langt.")
    }

    @Test
    @MainActor
    func onboardingFinishCreatesGoalWhenOptionalGoalIsProvided() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(onboardingCompleted: false)
        context.insert(preference)
        try context.save()

        let goalDate = Calendar.current.date(from: DateComponents(year: 2028, month: 12, day: 1)) ?? .now
        let viewModel = OnboardingViewModel(preference: preference)
        viewModel.monthlyIncomeText = "32 000"
        viewModel.wantsGoal = true
        viewModel.goalAmountText = "250 000"
        viewModel.goalDate = goalDate

        viewModel.finish(preference: preference, context: context)

        let goals = try context.fetch(FetchDescriptor<Goal>())
        #expect(goals.count == 1)
        #expect(goals[0].targetAmount == 250_000)
    }
}
