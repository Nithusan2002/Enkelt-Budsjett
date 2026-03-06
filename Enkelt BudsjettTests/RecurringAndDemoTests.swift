import Foundation
import SwiftData
import Testing
@testable import Simple_Budget___Budskjett_planlegger_gjort_enkelt

private typealias Category = Simple_Budget___Budskjett_planlegger_gjort_enkelt.Category

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
        #expect(transactions.contains(where: { $0.fixedItemID == fixedItem.id }))
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
    func demoSeedCreatesRealisticTransactionVolumeAcrossMonths() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
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
        let container = try TestModelContainerFactory.makeInMemoryContainer()
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

        #expect(fixedItems.count >= 5)
        #expect(fixedItems.allSatisfy(\.isActive))
        #expect(titles.contains("Husleie"))
        #expect(titles.contains("Mobilabonnement"))
        #expect(titles.contains("Månedskort"))
        #expect(titles.contains("Spotify"))
        #expect(titles.contains("iCloud+"))
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
}
