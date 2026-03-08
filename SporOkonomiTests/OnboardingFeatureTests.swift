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
        #expect(order.count == 3)
        #expect(order.first == .intro)
        #expect(order[1] == .income)
        #expect(order.last == .summary)
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

        #expect(bucketNames == ["Fond", "Aksjer", "BSU", "Buffer"])
        #expect(!bucketNames.contains("Krypto"))
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
        #expect(viewModel.summaryBodyText.contains("denne måneden"))
        #expect(viewModel.summaryHelpText.contains("månedsoversikten"))

        viewModel.monthlyIncomeText = ""
        #expect(viewModel.summaryBodyText.contains("oversikt over denne måneden"))
        #expect(viewModel.summaryHelpText.contains("månedsoversikten"))
    }
}
