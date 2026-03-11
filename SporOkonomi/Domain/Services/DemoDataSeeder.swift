import Foundation
import SwiftData

struct DemoSeedReport {
    let budgetMonths: Int
    let categories: Int
    let budgetPlans: Int
    let transactions: Int
    let buckets: Int
    let snapshots: Int
    let goals: Int
    let preferences: Int
}

enum DemoDataSeeder {
    private static let demoYears = 3
    private static let demoFixedItems: [(id: String, title: String, amount: Double, categoryID: String, day: Int)] = [
        ("fixed_demo_rent", "Husleie", 7600, "cat_housing", 1),
        ("fixed_demo_mobile", "Mobilabonnement", 349, "cat_fixed_costs", 2),
        ("fixed_demo_month_pass", "Månedskort", 490, "cat_transport", 4),
        ("fixed_demo_spotify", "Spotify", 149, "cat_fixed_costs", 5),
        ("fixed_demo_icloud", "iCloud+", 129, "cat_fixed_costs", 18)
    ]

    static func seedRealisticYear(context: ModelContext, year: Int? = nil) throws -> DemoSeedReport {
        try wipeAllData(context: context)

        let profile = loadProfile()
        let endYear = year ?? Calendar.current.component(.year, from: .now)
        let startYear = endYear - (demoYears - 1)
        let years = startYear...endYear

        let categories = try createCategories(context: context, profile: profile)
        try createFixedItems(context: context, startYear: startYear)
        try createInvestmentBuckets(context: context, profile: profile)
        try createBudgetMonths(context: context, years: years)
        try createBudgetPlans(context: context, years: years, categories: categories, profile: profile)
        try createBudgetGroupPlans(context: context, years: years, categories: categories, profile: profile)
        try createTransactions(context: context, years: years, categories: categories, profile: profile)
        try createInvestmentSnapshots(context: context, years: years, profile: profile)
        try createGoalAndPreference(context: context, endYear: endYear)

        try context.guardedSave(feature: "DemoData", operation: "save", enforceReadOnly: false)

        let report = try buildReport(context: context)
        print("[DemoDataSeeder] Seed fullført: months=\(report.budgetMonths), categories=\(report.categories), plans=\(report.budgetPlans), tx=\(report.transactions), buckets=\(report.buckets), snapshots=\(report.snapshots), goals=\(report.goals), prefs=\(report.preferences)")
        return report
    }

    static func seedMarketingDemo(
        context: ModelContext,
        referenceDate: Date = .now
    ) throws -> DemoSeedReport {
        try wipeAllData(context: context)

        let categories = try createMarketingCategories(context: context)
        try createMarketingBudgetMonth(context: context, referenceDate: referenceDate)
        let periodKey = DateService.periodKey(from: referenceDate)
        try createMarketingBudgetPlans(context: context, periodKey: periodKey)
        try createMarketingGroupPlans(context: context, periodKey: periodKey)
        try createMarketingTransactions(context: context, referenceDate: referenceDate)
        try createMarketingInvestmentBuckets(context: context)
        try createMarketingSnapshots(context: context, referenceDate: referenceDate)
        try createMarketingGoalAndPreference(context: context, referenceDate: referenceDate)

        _ = categories
        try context.guardedSave(feature: "DemoData", operation: "save", enforceReadOnly: false)

        let report = try buildReport(context: context)
        print("[DemoDataSeeder] Marketing-demo lastet: months=\(report.budgetMonths), categories=\(report.categories), plans=\(report.budgetPlans), tx=\(report.transactions), buckets=\(report.buckets), snapshots=\(report.snapshots), goals=\(report.goals), prefs=\(report.preferences)")
        return report
    }

    static func wipeAllData(context: ModelContext) throws {
        try deleteAll(BudgetPlan.self, context: context)
        try deleteAll(BudgetGroupPlan.self, context: context)
        try deleteAll(BudgetMonth.self, context: context)
        try deleteAll(Transaction.self, context: context)
        try deleteAll(FixedItemSkip.self, context: context)
        try deleteAll(FixedItem.self, context: context)
        try deleteAll(Category.self, context: context)
        try deleteAll(Account.self, context: context)
        try deleteAll(InvestmentSnapshot.self, context: context)
        try deleteAll(InvestmentBucket.self, context: context)
        try deleteAll(Goal.self, context: context)
        try deleteAll(Challenge.self, context: context)
        try deleteAll(UserPreference.self, context: context)
        UserDefaults.standard.removeObject(forKey: "onboarding_local_events")
        UserDefaults.standard.removeObject(forKey: "challenges_waitlist_optin")
        try context.guardedSave(feature: "DemoData", operation: "save", enforceReadOnly: false)
        print("[DemoDataSeeder] Alle lokale data er slettet")
    }

    private static func createCategories(
        context: ModelContext,
        profile: DemoProfile
    ) throws -> [String: Category] {
        var all: [String: Category] = [:]

        for item in profile.expenseCategories {
            let category = Category(id: item.id, name: item.name, type: .expense, isActive: true, sortOrder: item.sortOrder)
            context.insert(category)
            all[item.id] = category
        }

        for item in profile.incomeCategories {
            let category = Category(id: item.id, name: item.name, type: .income, isActive: true, sortOrder: item.sortOrder)
            context.insert(category)
            all[item.id] = category
        }

        for item in profile.savingsCategories {
            let category = Category(id: item.id, name: item.name, type: .savings, isActive: true, sortOrder: item.sortOrder)
            context.insert(category)
            all[item.id] = category
        }

        try context.guardedSave(feature: "DemoData", operation: "save", enforceReadOnly: false)
        return all
    }

    private static func createMarketingCategories(context: ModelContext) throws -> [String: Category] {
        let categoryDefinitions: [(id: String, name: String, type: CategoryType, groupKey: String?, sortOrder: Int)] = [
            ("cat_marketing_bolig", "Bolig", .expense, BudgetGroup.bolig.rawValue, 1),
            ("cat_marketing_fast", "Fast", .expense, BudgetGroup.fast.rawValue, 2),
            ("cat_marketing_mat", "Mat", .expense, BudgetGroup.hverdags.rawValue, 3),
            ("cat_marketing_transport", "Transport", .expense, BudgetGroup.hverdags.rawValue, 4),
            ("cat_marketing_fritid", "Fritid", .expense, BudgetGroup.fritid.rawValue, 5),
            ("cat_marketing_annet", "Annet", .expense, BudgetGroup.annet.rawValue, 6),
            ("cat_marketing_income_salary", "Lønn", .income, BudgetGroup.fast.rawValue, 101),
            ("cat_marketing_income_other", "Annen inntekt", .income, BudgetGroup.fast.rawValue, 102),
            ("cat_marketing_savings", "Sparing", .savings, BudgetGroup.hverdags.rawValue, 201)
        ]

        var inserted: [String: Category] = [:]
        for definition in categoryDefinitions {
            let category = Category(
                id: definition.id,
                name: definition.name,
                type: definition.type,
                groupKey: definition.groupKey,
                isActive: true,
                sortOrder: definition.sortOrder
            )
            context.insert(category)
            inserted[definition.id] = category
        }

        try context.guardedSave(feature: "DemoData", operation: "save", enforceReadOnly: false)
        return inserted
    }

    private static func createMarketingBudgetMonth(context: ModelContext, referenceDate: Date) throws {
        let periodKey = DateService.periodKey(from: referenceDate)
        let bounds = DateService.monthBounds(for: referenceDate)
        let components = Calendar.current.dateComponents([.year, .month], from: referenceDate)

        context.insert(
            BudgetMonth(
                periodKey: periodKey,
                year: components.year ?? Calendar.current.component(.year, from: referenceDate),
                month: components.month ?? Calendar.current.component(.month, from: referenceDate),
                startDate: bounds.start,
                endDate: bounds.end,
                isClosed: false
            )
        )

        try context.guardedSave(feature: "DemoData", operation: "save", enforceReadOnly: false)
    }

    private static func createMarketingBudgetPlans(context: ModelContext, periodKey: String) throws {
        let plans: [(String, Double)] = [
            ("cat_marketing_bolig", 12_000),
            ("cat_marketing_fast", 4_500),
            ("cat_marketing_mat", 4_000),
            ("cat_marketing_transport", 500),
            ("cat_marketing_fritid", 2_000),
            ("cat_marketing_annet", 1_500)
        ]

        for plan in plans {
            context.insert(BudgetPlan(monthPeriodKey: periodKey, categoryID: plan.0, plannedAmount: plan.1))
        }

        try context.guardedSave(feature: "DemoData", operation: "save", enforceReadOnly: false)
    }

    private static func createMarketingGroupPlans(context: ModelContext, periodKey: String) throws {
        let plans: [(BudgetGroup, Double)] = [
            (.bolig, 12_000),
            (.fast, 4_500),
            (.hverdags, 4_500),
            (.fritid, 2_000),
            (.annet, 1_500)
        ]

        for plan in plans {
            context.insert(
                BudgetGroupPlan(
                    monthPeriodKey: periodKey,
                    groupKey: plan.0.rawValue,
                    plannedAmount: plan.1
                )
            )
        }

        try context.guardedSave(feature: "DemoData", operation: "save", enforceReadOnly: false)
    }

    private static func createMarketingTransactions(context: ModelContext, referenceDate: Date) throws {
        let components = Calendar.current.dateComponents([.year, .month], from: referenceDate)
        let year = components.year ?? 2026
        let month = components.month ?? 3

        let transactions: [(day: Int, amount: Double, kind: TransactionKind, categoryID: String, note: String)] = [
            (5, 2_000, .income, "cat_marketing_income_other", "Vipps"),
            (15, 30_000, .income, "cat_marketing_income_salary", "Lønn"),

            (1, 10_400, .expense, "cat_marketing_bolig", "Husleie"),
            (3, 1_180, .expense, "cat_marketing_fast", "Strøm"),
            (5, 149, .expense, "cat_marketing_fast", "Spotify"),
            (8, 1_119, .expense, "cat_marketing_fast", "Forsikring"),
            (10, 1_140, .expense, "cat_marketing_mat", "Rema 1000"),
            (12, 329, .expense, "cat_marketing_mat", "Meny"),
            (17, 240, .expense, "cat_marketing_transport", "Flytoget"),
            (21, 1_420, .expense, "cat_marketing_mat", "Kiwi"),
            (23, 620, .expense, "cat_marketing_fritid", "Kaffebrenneriet"),
            (26, 1_223, .expense, "cat_marketing_fritid", "Kino"),
            (27, 1_120, .expense, "cat_marketing_annet", "Vipps"),

            (25, 1_200, .manualSaving, "cat_marketing_savings", "Overføring til buffer"),
            (28, 800, .manualSaving, "cat_marketing_savings", "Månedssparing")
        ]

        for transaction in transactions {
            insertTx(
                context,
                year,
                month,
                day: transaction.day,
                amount: transaction.amount,
                kind: transaction.kind,
                categoryID: transaction.categoryID,
                note: transaction.note
            )
        }

        try context.guardedSave(feature: "DemoData", operation: "save", enforceReadOnly: false)
    }

    private static func createMarketingInvestmentBuckets(context: ModelContext) throws {
        let buckets: [(String, String, Int, String)] = [
            ("bucket_marketing_funds", "Indeksfond", 1, "#2C8C7A"),
            ("bucket_marketing_stocks", "Aksjer", 2, "#5F7CF6"),
            ("bucket_marketing_crypto", "Krypto", 3, "#D08A2E"),
            ("bucket_marketing_buffer", "Buffer", 4, "#8BA7A1")
        ]

        for bucket in buckets {
            context.insert(
                InvestmentBucket(
                    id: bucket.0,
                    name: bucket.1,
                    colorHex: bucket.3,
                    isDefault: true,
                    isActive: true,
                    sortOrder: bucket.2
                )
            )
        }

        try context.guardedSave(feature: "DemoData", operation: "save", enforceReadOnly: false)
    }

    private static func createMarketingSnapshots(context: ModelContext, referenceDate: Date) throws {
        let snapshotDefinitions: [(periodKey: String, capturedAt: Date, values: [InvestmentSnapshotValue])] = [
            (
                "2025-09",
                date(year: 2025, month: 9, day: 26),
                [
                    .init(periodKey: "2025-09", bucketID: "bucket_marketing_funds", amount: 77_500),
                    .init(periodKey: "2025-09", bucketID: "bucket_marketing_stocks", amount: 28_200),
                    .init(periodKey: "2025-09", bucketID: "bucket_marketing_crypto", amount: 12_600),
                    .init(periodKey: "2025-09", bucketID: "bucket_marketing_buffer", amount: 22_700)
                ]
            ),
            (
                "2025-10",
                date(year: 2025, month: 10, day: 26),
                [
                    .init(periodKey: "2025-10", bucketID: "bucket_marketing_funds", amount: 79_200),
                    .init(periodKey: "2025-10", bucketID: "bucket_marketing_stocks", amount: 28_900),
                    .init(periodKey: "2025-10", bucketID: "bucket_marketing_crypto", amount: 13_400),
                    .init(periodKey: "2025-10", bucketID: "bucket_marketing_buffer", amount: 23_000)
                ]
            ),
            (
                "2025-11",
                date(year: 2025, month: 11, day: 26),
                [
                    .init(periodKey: "2025-11", bucketID: "bucket_marketing_funds", amount: 80_600),
                    .init(periodKey: "2025-11", bucketID: "bucket_marketing_stocks", amount: 29_300),
                    .init(periodKey: "2025-11", bucketID: "bucket_marketing_crypto", amount: 14_200),
                    .init(periodKey: "2025-11", bucketID: "bucket_marketing_buffer", amount: 22_700)
                ]
            ),
            (
                "2025-12",
                date(year: 2025, month: 12, day: 26),
                [
                    .init(periodKey: "2025-12", bucketID: "bucket_marketing_funds", amount: 82_000),
                    .init(periodKey: "2025-12", bucketID: "bucket_marketing_stocks", amount: 29_900),
                    .init(periodKey: "2025-12", bucketID: "bucket_marketing_crypto", amount: 14_800),
                    .init(periodKey: "2025-12", bucketID: "bucket_marketing_buffer", amount: 22_500)
                ]
            ),
            (
                "2026-01",
                date(year: 2026, month: 1, day: 26),
                [
                    .init(periodKey: "2026-01", bucketID: "bucket_marketing_funds", amount: 84_000),
                    .init(periodKey: "2026-01", bucketID: "bucket_marketing_stocks", amount: 31_600),
                    .init(periodKey: "2026-01", bucketID: "bucket_marketing_crypto", amount: 15_000),
                    .init(periodKey: "2026-01", bucketID: "bucket_marketing_buffer", amount: 23_600)
                ]
            ),
            (
                "2026-02",
                date(year: 2026, month: 2, day: 26),
                [
                    .init(periodKey: "2026-02", bucketID: "bucket_marketing_funds", amount: 87_120),
                    .init(periodKey: "2026-02", bucketID: "bucket_marketing_stocks", amount: 31_680),
                    .init(periodKey: "2026-02", bucketID: "bucket_marketing_crypto", amount: 15_840),
                    .init(periodKey: "2026-02", bucketID: "bucket_marketing_buffer", amount: 23_760)
                ]
            )
        ]

        _ = referenceDate
        for definition in snapshotDefinitions {
            try InvestmentService.upsertSnapshot(
                context: context,
                periodKey: definition.periodKey,
                capturedAt: definition.capturedAt,
                values: definition.values
            )
        }
    }

    private static func createMarketingGoalAndPreference(context: ModelContext, referenceDate: Date) throws {
        let goal = Goal(
            targetAmount: 250_000,
            targetDate: date(year: 2028, month: 12, day: 1),
            scope: .wealth,
            includeAccounts: false,
            isActive: true,
            createdAt: date(year: 2025, month: 9, day: 1)
        )
        context.insert(goal)

        context.insert(
            Account(
                id: "account_marketing_buffer_offset",
                name: "Hovedkonto",
                type: .checking,
                includeInNetWealth: true,
                currentBalance: -7_980
            )
        )

        context.insert(
            UserPreference(
                singletonKey: "main",
                authSessionModeRaw: AuthSessionMode.local.rawValue,
                savingsDefinition: .incomeMinusExpense,
                yearStartRule: "calendarYear",
                checkInReminderEnabled: true,
                checkInReminderDay: 5,
                checkInReminderHour: 18,
                checkInReminderMinute: 0,
                defaultGraphView: .oneYear,
                faceIDLockEnabled: false,
                onboardingCompleted: true,
                onboardingCurrentStep: 0,
                onboardingFocus: .both,
                toneStyle: .warm
            )
        )

        _ = referenceDate
        try context.guardedSave(feature: "DemoData", operation: "save", enforceReadOnly: false)
    }

    private static func createInvestmentBuckets(context: ModelContext, profile: DemoProfile) throws {
        for item in profile.investmentBuckets {
            context.insert(
                InvestmentBucket(
                    id: item.id,
                    name: item.name,
                    colorHex: item.colorHex,
                    isDefault: true,
                    isActive: true,
                    sortOrder: item.sortOrder
                )
            )
        }
        try context.guardedSave(feature: "DemoData", operation: "save", enforceReadOnly: false)
    }

    private static func createFixedItems(context: ModelContext, startYear: Int) throws {
        let startDate = date(year: startYear, month: 1, day: 1)
        for item in demoFixedItems {
            context.insert(
                FixedItem(
                    id: item.id,
                    title: item.title,
                    amount: item.amount,
                    categoryID: item.categoryID,
                    kind: .expense,
                    dayOfMonth: item.day,
                    startDate: startDate,
                    endDate: nil,
                    isActive: true,
                    autoCreate: false
                )
            )
        }

        try context.guardedSave(feature: "DemoData", operation: "save", enforceReadOnly: false)
    }

    private static func createBudgetMonths(context: ModelContext, years: ClosedRange<Int>) throws {
        let now = Date()
        let nowYear = Calendar.current.component(.year, from: now)
        let nowMonth = Calendar.current.component(.month, from: now)

        for year in years {
            for month in 1...12 {
                var components = DateComponents()
                components.year = year
                components.month = month
                components.day = 1
                let startDate = Calendar.current.date(from: components) ?? .now
                let endDate = Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: startDate) ?? startDate
                let isClosed = year < nowYear || (year == nowYear && month < nowMonth)
                context.insert(
                    BudgetMonth(
                        periodKey: String(format: "%04d-%02d", year, month),
                        year: year,
                        month: month,
                        startDate: startDate,
                        endDate: endDate,
                        isClosed: isClosed
                    )
                )
            }
        }
        try context.guardedSave(feature: "DemoData", operation: "save", enforceReadOnly: false)
    }

    private static func createBudgetPlans(
        context: ModelContext,
        years: ClosedRange<Int>,
        categories: [String: Category],
        profile: DemoProfile
    ) throws {
        let base: [String: Double] = [
            "cat_housing": 7800,
            "cat_food": 4500,
            "cat_transport": 760,
            "cat_fixed_costs": 620,
            "cat_leisure": 850,
            "cat_other": 970
        ]

        for year in years {
            for month in 1...12 {
                let factor = profile.monthlyFactor(for: month)
                let periodKey = String(format: "%04d-%02d", year, month)
                for (categoryID, amount) in base {
                    guard categories[categoryID] != nil else { continue }
                    let planned = roundToNearestTen(amount * factor)
                    context.insert(BudgetPlan(monthPeriodKey: periodKey, categoryID: categoryID, plannedAmount: planned))
                }
            }
        }
        try context.guardedSave(feature: "DemoData", operation: "save", enforceReadOnly: false)
    }

    private static func createBudgetGroupPlans(
        context: ModelContext,
        years: ClosedRange<Int>,
        categories: [String: Category],
        profile: DemoProfile
    ) throws {
        let categoryBase: [String: Double] = [
            "cat_rent": 7800,
            "cat_food": 3400,
            "cat_transport": 760,
            "cat_subscriptions": 620,
            "cat_eating_out": 1100,
            "cat_shopping": 850,
            "cat_health": 320,
            "cat_misc": 650
        ]

        var groupBase: [String: Double] = [:]
        for (categoryID, amount) in categoryBase {
            guard let category = categories[categoryID] else { continue }
            groupBase[category.groupKey, default: 0] += amount
        }

        for year in years {
            for month in 1...12 {
                let factor = profile.monthlyFactor(for: month)
                let periodKey = String(format: "%04d-%02d", year, month)
                for group in BudgetGroup.allCases {
                    let base = groupBase[group.rawValue] ?? 0
                    guard base > 0 else { continue }
                    let planned = roundToNearestTen(base * factor)
                    context.insert(
                        BudgetGroupPlan(
                            monthPeriodKey: periodKey,
                            groupKey: group.rawValue,
                            plannedAmount: planned
                        )
                    )
                }
            }
        }
        try context.guardedSave(feature: "DemoData", operation: "save", enforceReadOnly: false)
    }

    private static func createTransactions(
        context: ModelContext,
        years: ClosedRange<Int>,
        categories: [String: Category],
        profile: DemoProfile
    ) throws {
        let groceryStores = ["KIWI", "REMA 1000", "Coop Extra", "Meny"]
        let diningNotes = ["Kafé", "Lunsj ute", "Takeaway", "Sushi", "Burger"]
        let shoppingNotes = ["Klær", "Sport Outlet", "Normal", "Apotekvarer", "Interiør"]
        let miscNotes = ["Diverse", "Vipps venn", "Småkjøp", "Gave", "Bokhandel"]

        for year in years {
            for month in 1...12 {
                let factor = profile.monthlyFactor(for: month)

                // Inntekt: Lånekassen + lønn/ekstrajobb
                insertTx(context, year, month, day: 7, amount: stipendAmount(month: month), kind: .income, categoryID: "cat_income_other", note: "Lånekassen")
                insertTx(context, year, month, day: 15, amount: salaryAmount(month: month), kind: .income, categoryID: "cat_income_salary", note: "Lønn")
                if month % 2 == 0 {
                    insertTx(context, year, month, day: 27, amount: salaryAmount(month: month) * 0.4, kind: .income, categoryID: "cat_income_other", note: "Vakt")
                }
                if month % 3 == 0 {
                    insertTx(context, year, month, day: 23, amount: 450, kind: .income, categoryID: "cat_income_other", note: "Salg brukt")
                }
                if month == 12 {
                    insertTx(context, year, month, day: 20, amount: 900, kind: .income, categoryID: "cat_income_other", note: "Penger mottatt")
                }

                // Faste utgifter
                insertFixedTx(context, year, month, fixedItemID: "fixed_demo_rent", amount: roundToNearestTen(7600 * factor), categoryID: "cat_housing", day: 1, note: "Husleie")
                insertFixedTx(context, year, month, fixedItemID: "fixed_demo_mobile", amount: 349, categoryID: "cat_fixed_costs", day: 2, note: "Mobilabonnement")
                insertFixedTx(context, year, month, fixedItemID: "fixed_demo_month_pass", amount: roundToNearestTen(440 + Double((month * 11) % 90)), categoryID: "cat_transport", day: 4, note: "Månedskort")
                insertFixedTx(context, year, month, fixedItemID: "fixed_demo_spotify", amount: 149, categoryID: "cat_fixed_costs", day: 5, note: "Spotify")
                insertFixedTx(context, year, month, fixedItemID: "fixed_demo_icloud", amount: 129, categoryID: "cat_fixed_costs", day: 18, note: "iCloud")

                // Mat i butikk: 12-17 kjøp
                let foodCount = 12 + (month % 6)
                for idx in 0..<foodCount {
                    let day = 2 + ((idx * 2 + month) % 26)
                    let amount = roundToNearestTen(110 + Double((idx * 37 + month * 11) % 260) * (month >= 6 && month <= 8 ? 0.9 : 1.0))
                    let note = groceryStores[(idx + month) % groceryStores.count]
                    insertTx(context, year, month, day: day, amount: amount, kind: .expense, categoryID: "cat_food", note: note)
                }

                // Transport: enkeltturer utover månedskort
                let transportCount = 2 + (month % 3)
                for idx in 0..<transportCount {
                    let day = 8 + ((idx * 5 + month) % 20)
                    let amount = roundToNearestTen(36 + Double((idx * 19 + month * 7) % 90))
                    insertTx(context, year, month, day: day, amount: amount, kind: .expense, categoryID: "cat_transport", note: "Ruter")
                }

                // Mat ute / kaffe (høyere sommer og desember)
                let diningCount = month == 12 ? 6 : (month >= 6 && month <= 8 ? 5 : 3 + (month % 2))
                for idx in 0..<diningCount {
                    let day = 8 + ((idx * 6 + month) % 18)
                    let seasonalMultiplier = month == 12 ? 1.30 : (month >= 6 && month <= 8 ? 1.12 : 1.0)
                    let amount = roundToNearestTen((95 + Double((idx * 29 + month * 9) % 260)) * seasonalMultiplier)
                    let note = diningNotes[(idx + month) % diningNotes.count]
                    insertTx(context, year, month, day: day, amount: amount, kind: .expense, categoryID: "cat_food", note: note)
                }

                // Shopping
                let shoppingCount = month == 12 ? 4 : (month >= 6 && month <= 8 ? 3 : 2)
                for idx in 0..<shoppingCount {
                    let day = 10 + ((idx * 7 + month) % 17)
                    let amount = roundToNearestTen(180 + Double((idx * 53 + month * 13) % 520))
                    let note = shoppingNotes[(idx + month) % shoppingNotes.count]
                    insertTx(context, year, month, day: day, amount: amount, kind: .expense, categoryID: "cat_leisure", note: note)
                }

                // Helse / apotek
                if month % 2 == 1 || month == 12 {
                    let healthAmount = roundToNearestTen(90 + Double((month * 17) % 170))
                    insertTx(context, year, month, day: 11 + (month % 9), amount: healthAmount, kind: .expense, categoryID: "cat_other", note: month % 3 == 0 ? "Legebesøk" : "Apotek")
                }

                let miscCount = 2 + (month % 2)
                for idx in 0..<miscCount {
                    let day = 6 + ((idx * 9 + month) % 20)
                    let amount = roundToNearestTen(120 + Double((idx * 41 + month * 5) % 340))
                    let note = miscNotes[(idx + month) % miscNotes.count]
                    insertTx(context, year, month, day: day, amount: amount, kind: .expense, categoryID: "cat_other", note: note)
                }

                if month == 1 || month == 8 {
                    insertTx(context, year, month, day: 14, amount: roundToNearestTen(950 + Double(month * 40)), kind: .expense, categoryID: "cat_other", note: "Semester / studiebøker")
                }

                // Sparing
                insertTx(context, year, month, day: 25, amount: savingAmount(month: month), kind: .manualSaving, categoryID: "cat_savings_account", note: "Fast sparing")
                insertTx(context, year, month, day: 26, amount: roundToNearestTen(350 + Double((month * 23) % 260)), kind: .manualSaving, categoryID: "cat_savings_account", note: "Månedsinvestering")
                if month % 3 == 0 {
                    insertTx(context, year, month, day: 29, amount: 300, kind: .manualSaving, categoryID: "cat_savings_account", note: "Ekstra sparing")
                }
                if month == 4 || month == 10 || month == 12 {
                    insertTx(context, year, month, day: 28, amount: month == 12 ? 1200 : 800, kind: .manualSaving, categoryID: "cat_savings_account", note: "BSU")
                }

                // Refusjon av og til
                if month % 4 == 0 {
                    insertTx(context, year, month, day: 21, amount: 180, kind: .refund, categoryID: "cat_food", note: "Refusjon")
                }
            }
        }

        _ = categories
        try context.guardedSave(feature: "DemoData", operation: "save", enforceReadOnly: false)
    }

    private static func createInvestmentSnapshots(context: ModelContext, years: ClosedRange<Int>, profile: DemoProfile) throws {
        let volatility: [Double] = [0, 450, -300, 700, 350, -500, 900, 300, -250, 420, 380, 520]
        let yearMonthPairs = years.flatMap { year in (1...12).map { (year, $0) } }
        let sortedBuckets = profile.investmentBuckets.sorted { $0.sortOrder < $1.sortOrder }

        for (globalIndex, pair) in yearMonthPairs.enumerated() {
            let year = pair.0
            let month = pair.1
            let periodKey = String(format: "%04d-%02d", year, month)
            let capturedAt = date(year: year, month: month, day: 26)
            let values: [InvestmentSnapshotValue] = sortedBuckets.map { bucket in
                let amount = seededBucketAmount(
                    bucketID: bucket.id,
                    globalIndex: globalIndex,
                    month: month,
                    volatility: volatility
                )
                return InvestmentSnapshotValue(
                    periodKey: periodKey,
                    bucketID: bucket.id,
                    amount: roundToNearestTen(amount)
                )
            }

            try InvestmentService.upsertSnapshot(
                context: context,
                periodKey: periodKey,
                capturedAt: capturedAt,
                values: values
            )
        }

    }

    private static func seededBucketAmount(
        bucketID: String,
        globalIndex: Int,
        month: Int,
        volatility: [Double]
    ) -> Double {
        let m = Double(globalIndex)
        let seasonal = volatility[month - 1]

        switch bucketID {
        case "funds":
            return max(0, 9000 + m * 2300 + seasonal * 0.35)
        case "stocks":
            return max(0, 5000 + m * 1400 + seasonal * 0.45)
        case "bsu":
            return max(0, 3500 + m * 650)
        case "buffer":
            return max(0, 2200 + m * 420)
        case "crypto":
            return max(0, 1200 + m * 380 + seasonal * 0.9)
        default:
            let base = 1800 + Double(abs(bucketID.hashValue % 1200))
            let growth = 280 + Double(abs(bucketID.hashValue % 260))
            let swing = seasonal * Double(abs(bucketID.hashValue % 40) + 15) / 100.0
            return max(0, base + m * growth + swing)
        }
    }

    private static func createGoalAndPreference(context: ModelContext, endYear: Int) throws {
        let targetDate = date(year: endYear + 2, month: 12, day: 1)
        context.insert(
            Goal(
                targetAmount: 250_000,
                targetDate: targetDate,
                scope: .wealth,
                includeAccounts: true,
                isActive: true,
                createdAt: date(year: endYear - (demoYears - 1), month: 1, day: 1)
            )
        )

        context.insert(
            UserPreference(
                singletonKey: "main",
                authSessionModeRaw: AuthSessionMode.local.rawValue,
                savingsDefinition: .incomeMinusExpense,
                yearStartRule: "calendarYear",
                checkInReminderEnabled: true,
                checkInReminderDay: 5,
                checkInReminderHour: 18,
                checkInReminderMinute: 0,
                defaultGraphView: .last12Months,
                faceIDLockEnabled: false,
                onboardingCompleted: true,
                onboardingCurrentStep: 0,
                onboardingFocus: .both,
                toneStyle: .warm
            )
        )

        try context.guardedSave(feature: "DemoData", operation: "save", enforceReadOnly: false)
    }

    private static func buildReport(context: ModelContext) throws -> DemoSeedReport {
        DemoSeedReport(
            budgetMonths: try context.fetch(FetchDescriptor<BudgetMonth>()).count,
            categories: try context.fetch(FetchDescriptor<Category>()).count,
            budgetPlans: try context.fetch(FetchDescriptor<BudgetPlan>()).count,
            transactions: try context.fetch(FetchDescriptor<Transaction>()).count,
            buckets: try context.fetch(FetchDescriptor<InvestmentBucket>()).count,
            snapshots: try context.fetch(FetchDescriptor<InvestmentSnapshot>()).count,
            goals: try context.fetch(FetchDescriptor<Goal>()).count,
            preferences: try context.fetch(FetchDescriptor<UserPreference>()).count
        )
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, context: ModelContext) throws {
        let models = try context.fetch(FetchDescriptor<T>())
        for model in models {
            context.delete(model)
        }
    }

    private static func insertTx(
        _ context: ModelContext,
        _ year: Int,
        _ month: Int,
        day: Int,
        amount: Double,
        kind: TransactionKind,
        categoryID: String,
        note: String
    ) {
        context.insert(
            Transaction(
                date: date(year: year, month: month, day: day),
                amount: max(0, amount),
                kind: kind,
                categoryID: categoryID,
                note: note
            )
        )
    }

    private static func insertFixedTx(
        _ context: ModelContext,
        _ year: Int,
        _ month: Int,
        fixedItemID: String,
        amount: Double,
        categoryID: String,
        day: Int,
        note: String
    ) {
        let periodKey = String(format: "%04d-%02d", year, month)
        context.insert(
            Transaction(
                date: date(year: year, month: month, day: day),
                amount: max(0, amount),
                kind: .expense,
                categoryID: categoryID,
                note: note,
                recurringKey: FixedItemsService.recurringKey(fixedItemID: fixedItemID, periodKey: periodKey),
                fixedItemID: fixedItemID
            )
        )
    }

    private static func stipendAmount(month: Int) -> Double {
        switch month {
        case 1, 8:
            return 9100
        case 6, 7:
            return 0
        default:
            return 8600
        }
    }

    private static func salaryAmount(month: Int) -> Double {
        switch month {
        case 6, 7, 8:
            return 7800
        case 12:
            return 6900
        default:
            return 5200
        }
    }

    private static func savingAmount(month: Int) -> Double {
        switch month {
        case 12:
            return 300
        case 6, 7, 8:
            return 700
        default:
            return 1100
        }
    }

    private static func date(year: Int, month: Int, day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        let monthStart = Calendar.current.date(from: comps) ?? .now
        let maxDay = (Calendar.current.range(of: .day, in: .month, for: monthStart)?.upperBound ?? 29) - 1
        comps.day = min(max(1, day), maxDay)
        comps.hour = 12
        return Calendar.current.date(from: comps) ?? monthStart
    }

    private static func roundToNearestTen(_ value: Double) -> Double {
        (value / 10).rounded() * 10
    }

    private static func loadProfile() -> DemoProfile {
        if let url = Bundle.main.url(forResource: "demo_year_realistic", withExtension: "json", subdirectory: "DemoData"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(DemoProfile.self, from: data) {
            return decoded
        }
        return DemoProfile.defaultProfile
    }
}

private struct DemoProfile: Decodable {
    struct CategoryItem: Decodable {
        let id: String
        let name: String
        let sortOrder: Int
    }

    struct BucketItem: Decodable {
        let id: String
        let name: String
        let sortOrder: Int
        let colorHex: String?
    }

    let version: Int
    let name: String
    let expenseCategories: [CategoryItem]
    let incomeCategories: [CategoryItem]
    let savingsCategories: [CategoryItem]
    let monthlyFactors: [String: Double]
    let investmentBuckets: [BucketItem]

    func monthlyFactor(for month: Int) -> Double {
        monthlyFactors["\(month)"] ?? 1.0
    }

    static let defaultProfile = DemoProfile(
        version: 2,
        name: "young-adult_realistic_no_v2",
        expenseCategories: [
            .init(id: "cat_housing", name: "Bolig", sortOrder: 1),
            .init(id: "cat_food", name: "Mat", sortOrder: 2),
            .init(id: "cat_transport", name: "Transport", sortOrder: 3),
            .init(id: "cat_leisure", name: "Fritid", sortOrder: 4),
            .init(id: "cat_fixed_costs", name: "Faste utgifter", sortOrder: 5),
            .init(id: "cat_other", name: "Annet", sortOrder: 6)
        ],
        incomeCategories: [
            .init(id: "cat_income_salary", name: "Lønn", sortOrder: 101),
            .init(id: "cat_income_other", name: "Annen inntekt", sortOrder: 102)
        ],
        savingsCategories: [
            .init(id: "cat_savings_account", name: "Sparing", sortOrder: 201)
        ],
        monthlyFactors: [
            "1": 1.00, "2": 0.97, "3": 1.00, "4": 1.02,
            "5": 1.05, "6": 1.08, "7": 1.10, "8": 1.06,
            "9": 0.98, "10": 1.00, "11": 1.04, "12": 1.22
        ],
        investmentBuckets: [
            .init(id: "funds", name: "Fond", sortOrder: 1, colorHex: "#1F9BD3"),
            .init(id: "stocks", name: "Aksjer", sortOrder: 2, colorHex: "#7A5AD6"),
            .init(id: "bsu", name: "BSU", sortOrder: 3, colorHex: "#2FB66B"),
            .init(id: "buffer", name: "Buffer", sortOrder: 4, colorHex: "#D9951F"),
            .init(id: "crypto", name: "Krypto", sortOrder: 5, colorHex: "#D9671E")
        ]
    )
}
