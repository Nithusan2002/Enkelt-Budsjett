import Foundation
import SwiftData
import Testing
@testable import Simple_Budget___Budskjett_planlegger_gjort_enkelt

private typealias Category = Simple_Budget___Budskjett_planlegger_gjort_enkelt.Category

struct FeatureLogicTests {

    @Test
    @MainActor
    func onboardingCompleteIsIdempotentForIncomeItem() throws {
        let container = try makeInMemoryContainer()
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
    func savedYearToDateSavingsOnlyIgnoresIncomeAndExpense() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15)) ?? .now
        let monthStart = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 1)) ?? now

        let categories = [
            Category(id: "cat_savings", name: "Sparing", type: .savings, sortOrder: 1),
            Category(id: "cat_food", name: "Mat", type: .expense, sortOrder: 2)
        ]
        let transactions = [
            Transaction(date: monthStart, amount: 20_000, kind: .income),
            Transaction(date: monthStart, amount: 3_000, kind: .expense, categoryID: "cat_food"),
            Transaction(date: monthStart, amount: 500, kind: .manualSaving),
            Transaction(date: monthStart, amount: 700, kind: .expense, categoryID: "cat_savings")
        ]

        let saved = SavingsService.savedYearToDate(
            definition: .savingsCategoryOnly,
            transactions: transactions,
            categories: categories,
            now: now
        )
        #expect(saved == 1_200)
    }

    @Test
    @MainActor
    func savedYearToDateExcludesFutureTransactionsInSameYear() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15)) ?? .now
        let past = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 10)) ?? now
        let future = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 1)) ?? now

        let transactions = [
            Transaction(date: past, amount: 10_000, kind: .income),
            Transaction(date: past, amount: 2_000, kind: .expense),
            Transaction(date: future, amount: 50_000, kind: .income)
        ]

        let saved = SavingsService.savedYearToDate(
            definition: .incomeMinusExpense,
            transactions: transactions,
            categories: [],
            now: now
        )
        #expect(saved == 8_000)
    }

    @Test
    @MainActor
    func challengeSavingsDefinitionCountsTransactionsAcrossYearBoundary() {
        let startDate = Calendar.current.date(from: DateComponents(year: 2025, month: 12, day: 15, hour: 8)) ?? .now
        let endDate = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 23, minute: 59)) ?? .now
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 10, hour: 12)) ?? .now

        let challenge = Challenge(
            type: .save1000In30Days,
            startDate: startDate,
            endDate: endDate,
            targetAmount: 1_500,
            measurementMode: .savingsDefinition
        )
        let preference = UserPreference(savingsDefinition: .savingsCategoryOnly)
        let categories = [
            Category(id: "cat_savings", name: "Sparing", type: .savings, sortOrder: 1)
        ]
        let transactions = [
            Transaction(date: Calendar.current.date(from: DateComponents(year: 2025, month: 12, day: 20)) ?? startDate, amount: 1_000, kind: .manualSaving),
            Transaction(date: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5)) ?? now, amount: 500, kind: .manualSaving)
        ]

        let progress = ChallengeService.recalculate(
            challenge: challenge,
            transactions: transactions,
            categories: categories,
            preference: preference,
            now: now
        )

        #expect(progress == 1)
        #expect(challenge.status == .completed)
    }

    @Test
    @MainActor
    func budgetTrackedImpactCountsManualSaving() {
        let transaction = Transaction(
            date: .now,
            amount: 1_500,
            kind: .manualSaving
        )

        #expect(BudgetService.budgetImpact(transaction) == 0)
        #expect(BudgetService.trackedBudgetImpact(transaction) == 1_500)
    }

    @Test
    @MainActor
    func budgetGroupRowsIncludeManualSavingInSpentTotals() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15)) ?? .now
        let periodKey = DateService.periodKey(from: now)
        let category = Category(
            id: "cat_savings",
            name: "Målsparekonto",
            type: .savings,
            groupKey: BudgetGroup.hverdags.rawValue,
            sortOrder: 1
        )
        let transaction = Transaction(
            date: now,
            amount: 800,
            kind: .manualSaving,
            categoryID: category.id
        )

        let viewModel = BudgetViewModel()
        let rows = viewModel.groupRows(
            periodKey: periodKey,
            categories: [category],
            groupPlans: [],
            periodTransactions: [transaction]
        )
        let summary = viewModel.summary(groupRows: rows, periodTransactions: [transaction])

        #expect(rows.first(where: { $0.group == .hverdags })?.spent == 800)
        #expect(summary.expenseTotal == 800)
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
    func investmentWizardUsesExistingPeriodAsBaselineWhenEditing() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let bucket = InvestmentBucket(id: "bucket_fond", name: "Fond", isDefault: true, sortOrder: 1)
        context.insert(bucket)

        let previousDate = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? .now
        let currentDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? .now
        let previousKey = DateService.periodKey(from: previousDate)
        let currentKey = DateService.periodKey(from: currentDate)

        context.insert(
            InvestmentSnapshot(
                periodKey: previousKey,
                capturedAt: previousDate,
                totalValue: 100_000,
                bucketValues: [
                    InvestmentSnapshotValue(periodKey: previousKey, bucketID: bucket.id, amount: 100_000)
                ]
            )
        )
        context.insert(
            InvestmentSnapshot(
                periodKey: currentKey,
                capturedAt: currentDate,
                totalValue: 120_000,
                bucketValues: [
                    InvestmentSnapshotValue(periodKey: currentKey, bucketID: bucket.id, amount: 120_000)
                ]
            )
        )
        try context.save()

        let viewModel = InvestmentCheckInWizardViewModel()
        viewModel.loadInitialState(
            buckets: [bucket],
            snapshots: try context.fetch(FetchDescriptor<InvestmentSnapshot>()),
            selectedMonth: currentDate
        )

        #expect(viewModel.isEditingExistingPeriod)
        #expect(viewModel.previousValues[bucket.id] == 100_000)
        #expect(viewModel.existingPeriodValues[bucket.id] == 120_000)
        #expect(viewModel.previousValue(for: bucket.id) == 120_000)
        #expect(viewModel.effectiveValue(for: bucket.id) == 120_000)
    }

    @Test
    @MainActor
    func investmentWizardCopyPreviousUsesPreviousMonthValues() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let bucket = InvestmentBucket(id: "bucket_fond", name: "Fond", isDefault: true, sortOrder: 1)
        context.insert(bucket)

        let previousDate = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? .now
        let currentDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? .now
        let previousKey = DateService.periodKey(from: previousDate)
        let currentKey = DateService.periodKey(from: currentDate)

        context.insert(
            InvestmentSnapshot(
                periodKey: previousKey,
                capturedAt: previousDate,
                totalValue: 100_000,
                bucketValues: [
                    InvestmentSnapshotValue(periodKey: previousKey, bucketID: bucket.id, amount: 100_000)
                ]
            )
        )
        context.insert(
            InvestmentSnapshot(
                periodKey: currentKey,
                capturedAt: currentDate,
                totalValue: 120_000,
                bucketValues: [
                    InvestmentSnapshotValue(periodKey: currentKey, bucketID: bucket.id, amount: 120_000)
                ]
            )
        )
        try context.save()

        let viewModel = InvestmentCheckInWizardViewModel()
        viewModel.loadInitialState(
            buckets: [bucket],
            snapshots: try context.fetch(FetchDescriptor<InvestmentSnapshot>()),
            selectedMonth: currentDate
        )
        viewModel.copyPreviousToChanged()

        #expect(viewModel.stepStates[bucket.id]?.mode == .changed)
        #expect(viewModel.effectiveValue(for: bucket.id) == 100_000)
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
    func fixedItemStartingAtNoonOnLastDayIsGeneratedForCurrentMonth() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 10, hour: 9)) ?? .now
        let lastDayAtNoon = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 12)) ?? now

        let category = Category(id: "cat_food", name: "Mat", type: .expense, sortOrder: 1)
        context.insert(category)
        let fixedItem = FixedItem(
            id: "fixed_last_day_noon",
            title: "Siste dag",
            amount: 399,
            categoryID: category.id,
            kind: .expense,
            dayOfMonth: 31,
            startDate: lastDayAtNoon,
            isActive: true,
            autoCreate: true
        )
        context.insert(fixedItem)
        try context.save()

        try FixedItemsService.generateForCurrentMonthForItem(
            context: context,
            fixedItemID: fixedItem.id,
            now: now
        )

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(transactions.contains(where: { $0.fixedItemID == fixedItem.id }))
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

    @Test
    @MainActor
    func demoSeedCreatesThreeYearsOfBudgetMonths() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let report = try DemoDataSeeder.seedRealisticYear(context: context, year: 2026)

        #expect(report.budgetMonths == 36)
        let months = try context.fetch(FetchDescriptor<BudgetMonth>())
        #expect(months.count == 36)
    }

    @Test
    @MainActor
    func demoSeedCreatesRealisticTransactionVolumeAcrossMonths() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        _ = try DemoDataSeeder.seedRealisticYear(context: context, year: 2026)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(transactions.count > 900)

        let grouped = Dictionary(grouping: transactions, by: { DateService.periodKey(from: $0.date) })
        #expect(grouped.keys.count == 36)
        #expect(grouped.values.allSatisfy { $0.count >= 20 })
    }

    @Test
    @MainActor
    func demoSeedCreatesSnapshotsWithAllActiveBuckets() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        _ = try DemoDataSeeder.seedRealisticYear(context: context, year: 2026)

        let buckets = try context.fetch(FetchDescriptor<InvestmentBucket>()).filter(\.isActive)
        let snapshots = try context.fetch(FetchDescriptor<InvestmentSnapshot>())
        #expect(snapshots.count == 36)
        #expect(!buckets.isEmpty)

        let bucketIDs = Set(buckets.map(\.id))
        #expect(snapshots.allSatisfy { snapshot in
            Set(snapshot.bucketValues.map(\.bucketID)) == bucketIDs
        })
    }

    @Test
    @MainActor
    func demoSeedIsIdempotentWhenRunTwice() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let first = try DemoDataSeeder.seedRealisticYear(context: context, year: 2026)
        let second = try DemoDataSeeder.seedRealisticYear(context: context, year: 2026)

        #expect(first.budgetMonths == second.budgetMonths)
        #expect(first.transactions == second.transactions)
        #expect(first.snapshots == second.snapshots)
        #expect(first.buckets == second.buckets)
    }

    @Test
    @MainActor
    func developmentChartBuilderFiltersYearToDateAndLast12() {
        let bucket = InvestmentBucket(id: "funds", name: "Fond", isDefault: true, sortOrder: 1)
        let now = Date()
        let snapshots: [InvestmentSnapshot] = (0..<16).compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .month, value: -offset, to: now) else { return nil }
            let key = DateService.periodKey(from: date)
            let value = 10_000 + Double((15 - offset) * 1_000)
            let row = InvestmentSnapshotValue(periodKey: key, bucketID: bucket.id, amount: value)
            return InvestmentSnapshot(periodKey: key, capturedAt: date, totalValue: value, bucketValues: [row])
        }
        .sorted { $0.periodKey < $1.periodKey }

        let ytd = InvestmentsDevelopmentChartDataBuilder.points(
            snapshots: snapshots,
            buckets: [bucket],
            period: .sixMonths,
            now: now
        )
        #expect(ytd.count <= 6)

        let last12 = InvestmentsDevelopmentChartDataBuilder.points(
            snapshots: snapshots,
            buckets: [bucket],
            period: .last12Months,
            now: now
        )
        #expect(last12.count <= 12)
        #expect(last12.count > 1)
    }

    @Test
    @MainActor
    func developmentChartBuilderFillsMissingBucketValuesWithZero() {
        let fund = InvestmentBucket(id: "funds", name: "Fond", isDefault: true, sortOrder: 1)
        let stock = InvestmentBucket(id: "stocks", name: "Aksjer", isDefault: true, sortOrder: 2)
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? .now
        let key = DateService.periodKey(from: date)
        let snapshot = InvestmentSnapshot(
            periodKey: key,
            capturedAt: date,
            totalValue: 50_000,
            bucketValues: [
                InvestmentSnapshotValue(periodKey: key, bucketID: fund.id, amount: 50_000)
            ]
        )

        let points = InvestmentsDevelopmentChartDataBuilder.points(
            snapshots: [snapshot],
            buckets: [fund, stock],
            period: .sixMonths,
            now: date
        )

        #expect(points.count == 1)
        #expect(points[0].buckets.count == 2)
        #expect(points[0].buckets.first(where: { $0.bucketID == stock.id })?.amount == 0)
    }

    @Test
    @MainActor
    func developmentChartDeltaSincePreviousIsCorrect() {
        let date1 = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? .now
        let date2 = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? .now
        let date3 = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? .now
        let points = [
            InvestmentsDevelopmentChartPoint(id: "2026-01", date: date1, periodKey: "2026-01", total: 100_000, buckets: []),
            InvestmentsDevelopmentChartPoint(id: "2026-02", date: date2, periodKey: "2026-02", total: 103_500, buckets: []),
            InvestmentsDevelopmentChartPoint(id: "2026-03", date: date3, periodKey: "2026-03", total: 102_000, buckets: [])
        ]

        let secondDelta = InvestmentsDevelopmentChartDataBuilder.deltaSincePrevious(for: points[1], in: points)
        let thirdDelta = InvestmentsDevelopmentChartDataBuilder.deltaSincePrevious(for: points[2], in: points)

        #expect(secondDelta == 3_500)
        #expect(thirdDelta == -1_500)
    }

    @Test
    @MainActor
    func investmentsHeroUsesReminderClockTimeForSameDayCheckInText() {
        let viewModel = InvestmentsViewModel()
        let preference = UserPreference(
            checkInReminderEnabled: true,
            checkInReminderDay: 5,
            checkInReminderHour: 19,
            checkInReminderMinute: 0
        )
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 13, minute: 0)) ?? .now

        let hero = viewModel.heroData(
            snapshots: [],
            preference: preference,
            now: now
        )

        #expect(hero.nextCheckInText == "Neste: i dag")
    }

    @Test
    @MainActor
    func settingsImportReplaceRestoresExportedCategoryAndPreference() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let settingsVM = SettingsViewModel()

        let category = Category(
            id: "cat_test_custom",
            name: "Test-kategori",
            type: .expense,
            groupKey: BudgetGroup.fast.rawValue,
            isActive: true,
            sortOrder: 99
        )
        let preference = UserPreference(
            singletonKey: "main",
            checkInReminderEnabled: false,
            onboardingCompleted: true,
            onboardingCurrentStep: 0,
            onboardingFocus: .investments,
            toneStyle: .calm
        )
        context.insert(category)
        context.insert(preference)
        try context.save()

        let exportURL = try settingsVM.exportData(context: context)
        _ = try settingsVM.importData(from: exportURL, mode: .replace, context: context)

        let categories = try context.fetch(FetchDescriptor<Category>())
        let preferences = try context.fetch(FetchDescriptor<UserPreference>())

        let importedCategory = categories.first(where: { $0.id == "cat_test_custom" })
        #expect(importedCategory != nil)
        #expect(importedCategory?.groupKey == BudgetGroup.fast.rawValue)

        let importedPreference = preferences.first(where: { $0.singletonKey == "main" })
        #expect(importedPreference != nil)
        #expect(importedPreference?.onboardingCompleted == true)
        #expect(importedPreference?.checkInReminderEnabled == false)
        #expect(importedPreference?.toneStyle == .calm)
    }

    @Test
    @MainActor
    func settingsImportMergeAvoidsDuplicateTransactionsFromSameExport() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let settingsVM = SettingsViewModel()

        context.insert(
            Transaction(
                date: Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 15)) ?? .now,
                amount: 499,
                kind: .expense,
                categoryID: "cat_food",
                note: "Testimport"
            )
        )
        context.insert(UserPreference(onboardingCompleted: true))
        try context.save()

        let exportURL = try settingsVM.exportData(context: context)
        _ = try settingsVM.importData(from: exportURL, mode: .merge, context: context)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let matching = transactions.filter {
            $0.amount == 499 &&
            $0.kind == .expense &&
            $0.categoryID == "cat_food" &&
            $0.note == "Testimport"
        }
        #expect(matching.count == 1)
    }

    @Test
    @MainActor
    func challengeSavingsDefinitionCountsOnlyChallengePeriodAcrossYearBoundary() {
        let calendar = Calendar.current
        let startDate = calendar.date(from: DateComponents(year: 2025, month: 12, day: 15)) ?? .now
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15)) ?? .now
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10)) ?? .now

        let challenge = Challenge(
            type: .save1000In30Days,
            startDate: startDate,
            endDate: endDate,
            targetAmount: 4_000,
            targetDays: 31,
            status: .active,
            progress: 0,
            measurementMode: .savingsDefinition,
            manualProgress: 0
        )
        let preference = UserPreference(savingsDefinition: .incomeMinusExpense)
        let transactions = [
            Transaction(date: calendar.date(from: DateComponents(year: 2025, month: 11, day: 30)) ?? startDate, amount: 9_000, kind: .income),
            Transaction(date: calendar.date(from: DateComponents(year: 2025, month: 12, day: 20)) ?? startDate, amount: 5_000, kind: .income),
            Transaction(date: calendar.date(from: DateComponents(year: 2026, month: 1, day: 5)) ?? startDate, amount: 1_000, kind: .expense),
            Transaction(date: calendar.date(from: DateComponents(year: 2026, month: 1, day: 20)) ?? endDate, amount: 500, kind: .expense)
        ]

        let progress = ChallengeService.recalculate(
            challenge: challenge,
            transactions: transactions,
            categories: [],
            preference: preference,
            now: now
        )

        #expect(progress == 1)
        #expect(challenge.status == .completed)
    }

    @Test
    @MainActor
    func investmentsHeroMovesToNextMonthAfterReminderTimeHasPassedSameDay() {
        let viewModel = InvestmentsViewModel()
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 20, minute: 30)) ?? .now
        let preference = UserPreference(
            checkInReminderEnabled: true,
            checkInReminderDay: 5,
            checkInReminderHour: 8,
            checkInReminderMinute: 0
        )

        let hero = viewModel.heroData(
            snapshots: [],
            preference: preference,
            now: now
        )

        #expect(hero.nextCheckInText == "Neste: om 31 dager")
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            BudgetMonth.self,
            Category.self,
            BudgetPlan.self,
            BudgetGroupPlan.self,
            Transaction.self,
            Account.self,
            InvestmentBucket.self,
            InvestmentSnapshot.self,
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
