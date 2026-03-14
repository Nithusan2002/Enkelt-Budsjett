import Foundation
import SwiftData
import Testing
@testable import SporOkonomi

private typealias Category = SporOkonomi.Category

struct RecurringAndDemoTests {

    @Test
    @MainActor
    func fixedItemsGenerateOneTransactionPerMonth() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
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
        let container = try TestModelContainerFactory.makeInMemoryContainer()
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
        let container = try TestModelContainerFactory.makeInMemoryContainer()
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
        let generatedTransactionExists = transactions.contains { $0.fixedItemID == fixedItem.id }
        #expect(generatedTransactionExists)
    }

    @Test
    @MainActor
    func fixedItemsClampDayToLastDayOfMonth() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
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
        let container = try TestModelContainerFactory.makeInMemoryContainer()
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
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let report = try DemoDataSeeder.seedRealisticYear(context: context, year: 2026)

        #expect(report.budgetMonths == 36)
        let months = try context.fetch(FetchDescriptor<BudgetMonth>())
        #expect(months.count == 36)
    }

    @Test
    @MainActor
    func demoSeedUsesSimplifiedV1Categories() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext

        _ = try DemoDataSeeder.seedRealisticYear(context: context, year: 2026)

        let categories = try context.fetch(FetchDescriptor<Category>())
        let ids = Set(categories.map(\.id))
        let expenseIDs = Set(categories.filter { $0.type == .expense }.map(\.id))
        let incomeIDs = Set(categories.filter { $0.type == .income }.map(\.id))
        let savingsIDs = Set(categories.filter { $0.type == .savings }.map(\.id))

        #expect(expenseIDs == [
            "cat_housing",
            "cat_food",
            "cat_transport",
            "cat_leisure",
            "cat_fixed_costs",
            "cat_other"
        ])
        #expect(incomeIDs == [
            "cat_income_salary",
            "cat_income_other"
        ])
        #expect(savingsIDs == [
            "cat_savings_account"
        ])
        #expect(!ids.contains("cat_rent"))
        #expect(!ids.contains("cat_subscriptions"))
        #expect(!ids.contains("cat_eating_out"))
        #expect(!ids.contains("cat_savings_bsu"))
    }

    @Test
    @MainActor
    func demoSeedCreatesRealisticTransactionVolumeAcrossMonths() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        _ = try DemoDataSeeder.seedRealisticYear(context: context, year: 2026)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(transactions.count > 900)

        let grouped = Dictionary(grouping: transactions, by: { DateService.periodKey(from: $0.date) })
        let allMonthsHaveMinimumTransactions = grouped.values.allSatisfy { $0.count >= 20 }
        #expect(grouped.keys.count == 36)
        #expect(allMonthsHaveMinimumTransactions)
    }

    @Test
    @MainActor
    func demoSeedCreatesSnapshotsWithAllActiveBuckets() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        _ = try DemoDataSeeder.seedRealisticYear(context: context, year: 2026)

        let buckets = try context.fetch(FetchDescriptor<InvestmentBucket>()).filter(\.isActive)
        let snapshots = try context.fetch(FetchDescriptor<InvestmentSnapshot>())
        #expect(snapshots.count == 36)
        #expect(!buckets.isEmpty)

        let bucketIDs = Set(buckets.map(\.id))
        let allSnapshotsCoverActiveBuckets = snapshots.allSatisfy { snapshot in
            Set(snapshot.bucketValues.map(\.bucketID)) == bucketIDs
        }
        #expect(allSnapshotsCoverActiveBuckets)
    }

    @Test
    @MainActor
    func demoSeedSetsPreferenceToLocalSessionMode() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext

        _ = try DemoDataSeeder.seedRealisticYear(context: context, year: 2026)

        let preferences = try context.fetch(FetchDescriptor<UserPreference>())
        #expect(preferences.count == 1)
        #expect(preferences.first?.authSessionModeRaw == AuthSessionMode.local.rawValue)
    }

    @Test
    @MainActor
    func demoSeedCreatesMoreThanOneSavingsCategoryInTransactions() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext

        _ = try DemoDataSeeder.seedRealisticYear(context: context, year: 2026)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let savingsCategoryIDs = Set(
            transactions
                .filter { $0.kind == .manualSaving }
                .compactMap(\.categoryID)
        )

        #expect(savingsCategoryIDs.contains("cat_savings_account"))
        #expect(savingsCategoryIDs.contains("cat_savings_investing"))
        #expect(savingsCategoryIDs.count >= 3)
    }

    @Test
    @MainActor
    func demoSeedCreatesFixedItemsForRecurringCosts() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext

        _ = try DemoDataSeeder.seedRealisticYear(context: context, year: 2026)

        let fixedItems = try context.fetch(FetchDescriptor<FixedItem>())
        let titles = Set(fixedItems.map(\.title))
        let allFixedItemsAreActive = fixedItems.allSatisfy(\.isActive)

        #expect(fixedItems.count >= 5)
        #expect(allFixedItemsAreActive)
        #expect(titles.contains("Husleie"))
        #expect(titles.contains("Mobilabonnement"))
        #expect(titles.contains("Månedskort"))
        #expect(titles.contains("Spotify"))
        #expect(titles.contains("iCloud+"))
    }

    @Test
    @MainActor
    func demoSeedCreatesRecurringTransactionsForFixedItems() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext

        _ = try DemoDataSeeder.seedRealisticYear(context: context, year: 2026)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let januaryFixedTotal = FixedItemsService.fixedTotalForMonth(
            periodKey: "2026-01",
            transactions: transactions
        )
        let hasRent = transactions.contains { $0.fixedItemID == "fixed_demo_rent" && $0.recurringKey != nil }
        let hasMobile = transactions.contains { $0.fixedItemID == "fixed_demo_mobile" && $0.recurringKey != nil }
        let hasMonthPass = transactions.contains { $0.fixedItemID == "fixed_demo_month_pass" && $0.recurringKey != nil }
        let hasSpotify = transactions.contains { $0.fixedItemID == "fixed_demo_spotify" && $0.recurringKey != nil }
        let hasICloud = transactions.contains { $0.fixedItemID == "fixed_demo_icloud" && $0.recurringKey != nil }

        #expect(januaryFixedTotal > 0)
        #expect(hasRent)
        #expect(hasMobile)
        #expect(hasMonthPass)
        #expect(hasSpotify)
        #expect(hasICloud)
    }

    @Test
    @MainActor
    func demoSeedIsIdempotentWhenRunTwice() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
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
    func marketingDemoSeedCreatesCuratedCurrentMonthScenario() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let referenceDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 12)) ?? .now

        let report = try DemoDataSeeder.seedMarketingDemo(context: context, referenceDate: referenceDate)

        #expect(report.budgetMonths == 1)
        #expect(report.categories == 9)
        #expect(report.buckets == 4)
        #expect(report.snapshots == 36)
        #expect(report.goals == 1)

        let periodKey = "2026-03"
        let categories = try context.fetch(FetchDescriptor<Category>())
        let plans = try context.fetch(FetchDescriptor<BudgetPlan>())
        let groupPlans = try context.fetch(FetchDescriptor<BudgetGroupPlan>())
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let snapshots = try context.fetch(FetchDescriptor<InvestmentSnapshot>())
        let goals = try context.fetch(FetchDescriptor<Goal>())
        let accounts = try context.fetch(FetchDescriptor<Account>())

        #expect(Set(categories.map(\.name)) == [
            "Bolig",
            "Fast",
            "Mat",
            "Transport",
            "Fritid",
            "Annet",
            "Lønn",
            "Annen inntekt",
            "Sparing"
        ])
        #expect(BudgetService.plannedTotal(for: periodKey, plans: plans, categories: categories) == 24_500)
        #expect(BudgetService.actualExpenseTotal(for: periodKey, transactions: transactions) == 18_940)
        #expect(BudgetService.actualIncomeTotal(for: periodKey, transactions: transactions) == 32_000)
        #expect(groupPlans.filter { $0.monthPeriodKey == periodKey }.count == 5)
        #expect(transactions.filter { DateService.periodKey(from: $0.date) == periodKey }.count == 15)
        #expect(transactions.filter { $0.kind == .manualSaving }.count == 2)
        #expect(transactions.contains { $0.note == "Meny" && $0.amount == 329 && $0.kind == .expense })

        let latestSnapshot = snapshots.sorted { $0.periodKey < $1.periodKey }.last
        let previousSnapshot = snapshots.sorted { $0.periodKey < $1.periodKey }.dropLast().last
        #expect(snapshots.count == 36)
        #expect(snapshots.sorted { $0.periodKey < $1.periodKey }.first?.periodKey == "2023-03")
        #expect(latestSnapshot?.periodKey == "2026-02")
        #expect(latestSnapshot?.totalValue == 158_400)
        #expect((previousSnapshot?.totalValue ?? 0) < (latestSnapshot?.totalValue ?? 0))
        #expect(Calendar.current.component(.month, from: latestSnapshot?.capturedAt ?? referenceDate) == 2)
        #expect(Calendar.current.component(.day, from: latestSnapshot?.capturedAt ?? referenceDate) == 26)

        #expect(goals.count == 1)
        #expect(goals.first?.targetAmount == 250_000)
        #expect(accounts.reduce(0) { $0 + $1.currentBalance } == -7_980)
    }

    @Test
    @MainActor
    func marketingDemoSeedIsIdempotentWhenRunTwice() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let referenceDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 12)) ?? .now

        let first = try DemoDataSeeder.seedMarketingDemo(context: context, referenceDate: referenceDate)
        let second = try DemoDataSeeder.seedMarketingDemo(context: context, referenceDate: referenceDate)

        #expect(first.budgetMonths == second.budgetMonths)
        #expect(first.categories == second.categories)
        #expect(first.transactions == second.transactions)
        #expect(first.snapshots == second.snapshots)
        #expect(first.goals == second.goals)
    }
}
