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
    func investmentWizardEffectiveValuesAndTotalsFollowRules() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let previousPeriodDate = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? .now
        let currentPeriodDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? .now
        let previousPeriodKey = DateService.periodKey(from: previousPeriodDate)

        let buckets = [
            InvestmentBucket(id: "bucket_fond", name: "Fond", isDefault: true, sortOrder: 1),
            InvestmentBucket(id: "bucket_aksjer", name: "Aksjer", isDefault: true, sortOrder: 2),
            InvestmentBucket(id: "bucket_ny", name: "Ny type", isDefault: false, sortOrder: 3)
        ]
        buckets.forEach { context.insert($0) }
        let previousValues = [
            InvestmentSnapshotValue(periodKey: previousPeriodKey, bucketID: "bucket_fond", amount: 100_000),
            InvestmentSnapshotValue(periodKey: previousPeriodKey, bucketID: "bucket_aksjer", amount: 25_000)
        ]
        context.insert(
            InvestmentSnapshot(
                periodKey: previousPeriodKey,
                capturedAt: previousPeriodDate,
                totalValue: 125_000,
                bucketValues: previousValues
            )
        )
        try context.save()

        let viewModel = InvestmentCheckInWizardViewModel()
        viewModel.loadInitialState(buckets: buckets, snapshots: try context.fetch(FetchDescriptor<InvestmentSnapshot>()), selectedMonth: currentPeriodDate)
        viewModel.start()

        viewModel.setMode(.unchanged, for: "bucket_fond")
        viewModel.setMode(.changed, for: "bucket_aksjer")
        viewModel.updateInput("26 500", for: "bucket_aksjer")
        viewModel.setMode(.unchanged, for: "bucket_ny")

        #expect(viewModel.effectiveValue(for: "bucket_fond") == 100_000)
        #expect(viewModel.effectiveValue(for: "bucket_aksjer") == 26_500)
        #expect(viewModel.effectiveValue(for: "bucket_ny") == 0)
        #expect(viewModel.prevTotal == 125_000)
        #expect(viewModel.newTotal == 126_500)
        #expect(viewModel.delta == 1_500)
    }

    @Test
    @MainActor
    func investmentWizardSortOrderAndNewBucketInclusion() {
        let buckets = [
            InvestmentBucket(id: "b3", name: "Tre", isDefault: false, sortOrder: 3),
            InvestmentBucket(id: "b1", name: "En", isDefault: false, sortOrder: 1),
            InvestmentBucket(id: "b2", name: "To", isDefault: false, sortOrder: 2),
            InvestmentBucket(id: "inactive", name: "Skjult", isDefault: false, isActive: false, sortOrder: 0)
        ]
        let viewModel = InvestmentCheckInWizardViewModel()
        viewModel.loadInitialState(buckets: buckets, snapshots: [], selectedMonth: .now)

        #expect(viewModel.buckets.map(\.id) == ["b1", "b2", "b3"])
        #expect(viewModel.isNewType("b1"))
        #expect(viewModel.isNewType("b2"))
        #expect(viewModel.isNewType("b3"))
    }

    @Test
    @MainActor
    func investmentWizardUpsertsSnapshotPerPeriodKey() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let currentPeriodDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? .now
        let currentPeriodKey = DateService.periodKey(from: currentPeriodDate)

        let bucket = InvestmentBucket(id: "bucket_fond", name: "Fond", isDefault: true, sortOrder: 1)
        context.insert(bucket)
        let existing = InvestmentSnapshot(
            periodKey: currentPeriodKey,
            capturedAt: currentPeriodDate,
            totalValue: 1000,
            bucketValues: [
                InvestmentSnapshotValue(periodKey: currentPeriodKey, bucketID: bucket.id, amount: 1000)
            ]
        )
        context.insert(existing)
        try context.save()

        let viewModel = InvestmentCheckInWizardViewModel()
        viewModel.loadInitialState(
            buckets: [bucket],
            snapshots: try context.fetch(FetchDescriptor<InvestmentSnapshot>()),
            selectedMonth: currentPeriodDate
        )
        viewModel.start()
        viewModel.setMode(.changed, for: bucket.id)
        viewModel.updateInput("2 500", for: bucket.id)
        viewModel.goNext()
        try viewModel.saveSnapshot(context: context)

        let snapshots = try context.fetch(FetchDescriptor<InvestmentSnapshot>())
        #expect(snapshots.count == 1)
        #expect(snapshots.first?.totalValue == 2500)

        let values = snapshots.first?.bucketValues ?? []
        #expect(values.count == 1)
        #expect(values.contains(where: { $0.bucketID == bucket.id && $0.amount == 2500 }))
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
