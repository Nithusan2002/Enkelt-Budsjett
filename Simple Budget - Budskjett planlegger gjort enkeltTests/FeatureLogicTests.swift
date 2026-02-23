import Foundation
import SwiftData
import Testing
@testable import Simple_Budget___Budskjett_planlegger_gjort_enkelt

struct FeatureLogicTests {

    @Test
    @MainActor
    func onboardingFinishCreatesSnapshotFromFirstWealthTotal() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(onboardingCompleted: false)
        context.insert(preference)
        try context.save()

        let viewModel = OnboardingViewModel(preference: preference)
        viewModel.firstWealthTotalText = "120 000"
        viewModel.snapshotText = ["Fond": "", "Aksjer": "", "IPS": "", "Krypto": ""]
        viewModel.budgetPackage = .trackingOnly

        viewModel.finish(preference: preference, context: context)

        let snapshots = try context.fetch(FetchDescriptor<InvestmentSnapshot>())
        #expect(snapshots.count == 1)
        #expect(snapshots.first?.totalValue == 120000)
        #expect((snapshots.first?.bucketValues.count ?? -1) == 0)
        #expect(preference.onboardingCompleted)
    }

    @Test
    @MainActor
    func onboardingBudgetFocusChangesStepOrder() {
        let preference = UserPreference(onboardingCompleted: false, onboardingFocus: .budget)
        let viewModel = OnboardingViewModel(preference: preference)

        let order = viewModel.orderedSteps
        #expect(order.first == .welcome)
        #expect(order[1] == .focus)
        #expect(order[2] == .budget)
        #expect(order[3] == .firstWealth)
        #expect(order.last == .habits)
    }

    @Test
    @MainActor
    func investmentCheckInParsesTextValuesIntoTotalAndSnapshot() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let now = Date()

        let buckets = [
            InvestmentBucket(id: "bucket_fond", name: "Fond", isDefault: true, sortOrder: 1),
            InvestmentBucket(id: "bucket_aksjer", name: "Aksjer", isDefault: true, sortOrder: 2)
        ]
        buckets.forEach { context.insert($0) }

        let viewModel = InvestmentCheckInViewModel()
        viewModel.prepareValues(buckets: buckets, latestSnapshot: nil)
        viewModel.setBinding("10 500", for: "bucket_fond")
        viewModel.setBinding("1 200,5", for: "bucket_aksjer")

        let total = viewModel.total()
        #expect(total == 11700.5)

        let periodKey = DateService.periodKey(from: now)
        viewModel.saveSnapshot(context: context, periodKey: periodKey, total: total, capturedAt: now)

        let snapshots = try context.fetch(FetchDescriptor<InvestmentSnapshot>())
        #expect(snapshots.count == 1)
        #expect(snapshots.first?.totalValue == 11700.5)

        let values = snapshots.first?.bucketValues ?? []
        #expect(values.contains(where: { $0.bucketID == "bucket_fond" && $0.amount == 10500 }))
        #expect(values.contains(where: { $0.bucketID == "bucket_aksjer" && $0.amount == 1200.5 }))
    }

    @Test
    @MainActor
    func budgetSummaryIncludesIncomeAndNet() {
        let viewModel = BudgetViewModel()
        let periodKey = DateService.periodKey(from: .now)

        let categories = [
            Category(id: "cat_food", name: "Mat", type: .expense, sortOrder: 1),
            Category(id: "cat_savings", name: "Sparing", type: .savings, sortOrder: 2)
        ]
        let plans = [
            BudgetPlan(monthPeriodKey: periodKey, categoryID: "cat_food", plannedAmount: 8000)
        ]
        let transactions = [
            Transaction(date: .now, amount: 20000, kind: .income),
            Transaction(date: .now, amount: 4500, kind: .expense, categoryID: "cat_food")
        ]

        let summary = viewModel.summary(periodKey: periodKey, plans: plans, categories: categories, transactions: transactions)
        #expect(summary.planned == 8000)
        #expect(summary.actual == 4500)
        #expect(summary.income == 20000)
        #expect(summary.net == 15500)
        #expect(summary.remaining == 3500)
    }

    @Test
    @MainActor
    func budgetSummaryUsesNetAsRemainingWhenNoPlanExists() {
        let viewModel = BudgetViewModel()
        let periodKey = DateService.periodKey(from: .now)

        let categories = [
            Category(id: "cat_food", name: "Mat", type: .expense, sortOrder: 1)
        ]
        let transactions = [
            Transaction(date: .now, amount: 10000, kind: .income),
            Transaction(date: .now, amount: 3000, kind: .expense, categoryID: "cat_food")
        ]

        let summary = viewModel.summary(periodKey: periodKey, plans: [], categories: categories, transactions: transactions)
        #expect(summary.planned == 0)
        #expect(summary.net == 7000)
        #expect(summary.remaining == 7000)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            BudgetMonth.self,
            Category.self,
            BudgetPlan.self,
            Transaction.self,
            Account.self,
            InvestmentBucket.self,
            InvestmentSnapshot.self,
            InvestmentSnapshotValue.self,
            Goal.self,
            Challenge.self,
            UserPreference.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

