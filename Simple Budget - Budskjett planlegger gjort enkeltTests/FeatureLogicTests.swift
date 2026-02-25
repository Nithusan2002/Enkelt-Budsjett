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

    @Test
    @MainActor
    func fixedItemsGenerateOneTransactionPerMonth() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let now = Date()
        let key = DateService.periodKey(from: now)
        let bounds = DateService.monthBounds(for: now)
        let category = Category(id: "cat_food", name: "Mat", type: .expense, sortOrder: 1)
        context.insert(category)
        context.insert(
            FixedItem(
                title: "Husleie",
                amount: 9000,
                categoryID: category.id,
                kind: .expense,
                dayOfMonth: 5,
                startDate: bounds.start,
                isActive: true,
                autoCreate: true
            )
        )
        try context.save()

        try FixedItemsService.generateForMonth(
            context: context,
            periodKey: key,
            monthStart: bounds.start,
            monthEnd: bounds.end
        )

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(transactions.count == 1)
        #expect(transactions.first?.recurringKey != nil)
    }

    @Test
    @MainActor
    func fixedItemsGenerationIsIdempotentAcrossMultipleCalls() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let now = Date()
        let key = DateService.periodKey(from: now)
        let bounds = DateService.monthBounds(for: now)
        let category = Category(id: "cat_food", name: "Mat", type: .expense, sortOrder: 1)
        context.insert(category)
        context.insert(
            FixedItem(
                title: "Spotify",
                amount: 149,
                categoryID: category.id,
                kind: .expense,
                dayOfMonth: 10,
                startDate: bounds.start,
                isActive: true,
                autoCreate: true
            )
        )
        try context.save()

        try FixedItemsService.generateForMonth(
            context: context,
            periodKey: key,
            monthStart: bounds.start,
            monthEnd: bounds.end
        )
        try FixedItemsService.generateForMonth(
            context: context,
            periodKey: key,
            monthStart: bounds.start,
            monthEnd: bounds.end
        )

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(transactions.count == 1)
    }

    @Test
    @MainActor
    func fixedItemsClampDayToLastDayOfMonth() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        var comps = DateComponents()
        comps.year = 2026
        comps.month = 2
        comps.day = 1
        let febStart = Calendar.current.date(from: comps) ?? .now
        let febEnd = Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: febStart) ?? febStart
        let key = DateService.periodKey(from: febStart)

        let category = Category(id: "cat_housing", name: "Bolig", type: .expense, sortOrder: 1)
        context.insert(category)
        context.insert(
            FixedItem(
                title: "Husleie",
                amount: 12000,
                categoryID: category.id,
                kind: .expense,
                dayOfMonth: 31,
                startDate: febStart,
                isActive: true,
                autoCreate: true
            )
        )
        try context.save()

        try FixedItemsService.generateForMonth(
            context: context,
            periodKey: key,
            monthStart: febStart,
            monthEnd: febEnd,
            now: febStart
        )

        let tx = try context.fetch(FetchDescriptor<Transaction>()).first
        let day = Calendar.current.component(.day, from: tx?.date ?? febStart)
        #expect(day == 28)
    }

    @Test
    @MainActor
    func fixedItemsSkipPreventsRegenerationAfterDelete() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let now = Date()
        let key = DateService.periodKey(from: now)
        let bounds = DateService.monthBounds(for: now)
        let category = Category(id: "cat_food", name: "Mat", type: .expense, sortOrder: 1)
        context.insert(category)
        let item = FixedItem(
            title: "Matkasse",
            amount: 899,
            categoryID: category.id,
            kind: .expense,
            dayOfMonth: 6,
            startDate: bounds.start,
            isActive: true,
            autoCreate: true
        )
        context.insert(item)
        try context.save()

        try FixedItemsService.generateForMonth(
            context: context,
            periodKey: key,
            monthStart: bounds.start,
            monthEnd: bounds.end
        )
        var transactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(transactions.count == 1)

        if let first = transactions.first {
            try FixedItemsService.registerDeletionSkipIfNeeded(transaction: first, context: context)
            context.delete(first)
            try context.save()
        }

        try FixedItemsService.generateForMonth(
            context: context,
            periodKey: key,
            monthStart: bounds.start,
            monthEnd: bounds.end
        )

        transactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(transactions.isEmpty)
        let skips = try context.fetch(FetchDescriptor<FixedItemSkip>())
        #expect(skips.count == 1)
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
            FixedItem.self,
            FixedItemSkip.self,
            Goal.self,
            Challenge.self,
            UserPreference.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
