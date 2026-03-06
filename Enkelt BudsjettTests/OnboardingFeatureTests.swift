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

    @Test
    @MainActor
    func onboardingCanGoBackToPreviousStep() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(onboardingCompleted: false, onboardingCurrentStep: OnboardingStep.minimumData.rawValue)
        context.insert(preference)
        try context.save()

        let viewModel = OnboardingViewModel(preference: preference)

        #expect(viewModel.canGoBack)
        #expect(viewModel.backButtonTitle == "Tilbake")

        viewModel.back(preference: preference, context: context)

        #expect(viewModel.currentStep == .goal)
        #expect(preference.onboardingCurrentStep == OnboardingStep.goal.rawValue)
        #expect(viewModel.canGoBack == false)
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
}
