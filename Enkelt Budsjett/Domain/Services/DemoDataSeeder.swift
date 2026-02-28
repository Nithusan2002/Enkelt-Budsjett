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

    static func seedRealisticYear(context: ModelContext, year: Int? = nil) throws -> DemoSeedReport {
        try wipeAllData(context: context)

        let profile = loadProfile()
        let endYear = year ?? Calendar.current.component(.year, from: .now)
        let startYear = endYear - (demoYears - 1)
        let years = startYear...endYear

        let categories = try createCategories(context: context, profile: profile)
        try createInvestmentBuckets(context: context, profile: profile)
        try createBudgetMonths(context: context, years: years)
        try createBudgetPlans(context: context, years: years, categories: categories, profile: profile)
        try createBudgetGroupPlans(context: context, years: years, categories: categories, profile: profile)
        try createTransactions(context: context, years: years, categories: categories, profile: profile)
        try createInvestmentSnapshots(context: context, years: years, profile: profile)
        try createGoalAndPreference(context: context, endYear: endYear)

        try context.save()

        let report = try buildReport(context: context)
        print("[DemoDataSeeder] Seed fullført: months=\(report.budgetMonths), categories=\(report.categories), plans=\(report.budgetPlans), tx=\(report.transactions), buckets=\(report.buckets), snapshots=\(report.snapshots), goals=\(report.goals), prefs=\(report.preferences)")
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
        try context.save()
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

        try context.save()
        return all
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
        try context.save()
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
        try context.save()
    }

    private static func createBudgetPlans(
        context: ModelContext,
        years: ClosedRange<Int>,
        categories: [String: Category],
        profile: DemoProfile
    ) throws {
        let base: [String: Double] = [
            "cat_rent": 7500,
            "cat_food": 3200,
            "cat_transport": 620,
            "cat_subscriptions": 290,
            "cat_nightlife": 900,
            "cat_shopping": 700,
            "cat_misc": 550
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
        try context.save()
    }

    private static func createBudgetGroupPlans(
        context: ModelContext,
        years: ClosedRange<Int>,
        categories: [String: Category],
        profile: DemoProfile
    ) throws {
        let categoryBase: [String: Double] = [
            "cat_rent": 7500,
            "cat_food": 3200,
            "cat_transport": 620,
            "cat_subscriptions": 290,
            "cat_nightlife": 900,
            "cat_shopping": 700,
            "cat_misc": 550
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
        try context.save()
    }

    private static func createTransactions(
        context: ModelContext,
        years: ClosedRange<Int>,
        categories: [String: Category],
        profile: DemoProfile
    ) throws {
        for year in years {
            for month in 1...12 {
                let factor = profile.monthlyFactor(for: month)

                // Inntekt: Lånekassen + lønn/ekstrajobb
                insertTx(context, year, month, day: 7, amount: stipendAmount(month: month), kind: .income, categoryID: "cat_income_lanekassen", note: "Lånekassen")
                insertTx(context, year, month, day: 15, amount: salaryAmount(month: month), kind: .income, categoryID: "cat_income_salary", note: "Lønn")
                if month % 2 == 0 {
                    insertTx(context, year, month, day: 27, amount: salaryAmount(month: month) * 0.4, kind: .income, categoryID: "cat_income_side_hustle", note: "Vakt")
                }
                if month % 3 == 0 {
                    insertTx(context, year, month, day: 23, amount: 450, kind: .income, categoryID: "cat_income_resale", note: "Salg brukt")
                }
                if month == 12 {
                    insertTx(context, year, month, day: 20, amount: 900, kind: .income, categoryID: "cat_income_gifts_received", note: "Penger mottatt")
                }

                // Fast utgift
                insertTx(context, year, month, day: 1, amount: roundToNearestTen(7300 * factor), kind: .expense, categoryID: "cat_rent", note: "Husleie")

                // Mat: 10-15 kjøp
                let foodCount = 10 + (month % 6)
                for idx in 0..<foodCount {
                    let day = 2 + ((idx * 2 + month) % 26)
                    let amount = roundToNearestTen(110 + Double((idx * 37 + month * 11) % 260) * (month >= 6 && month <= 8 ? 0.9 : 1.0))
                    insertTx(context, year, month, day: day, amount: amount, kind: .expense, categoryID: "cat_food", note: idx % 2 == 0 ? "KIWI" : "REMA")
                }

                // Abonnement
                insertTx(context, year, month, day: 3, amount: 79, kind: .expense, categoryID: "cat_subscriptions", note: "Spotify")
                insertTx(context, year, month, day: 5, amount: 129, kind: .expense, categoryID: "cat_subscriptions", note: "Apple iCloud")
                insertTx(context, year, month, day: 19, amount: 99, kind: .expense, categoryID: "cat_subscriptions", note: "Netflix")

                // Transport 3-6
                let transportCount = 3 + (month % 4)
                for idx in 0..<transportCount {
                    let day = 4 + ((idx * 5 + month) % 24)
                    let amount = roundToNearestTen(42 + Double((idx * 19 + month * 7) % 120))
                    insertTx(context, year, month, day: day, amount: amount, kind: .expense, categoryID: "cat_transport", note: "Ruter")
                }

                // Uteliv (høyere sommer og desember)
                let nightlifeCount = (month == 12 ? 6 : (month >= 6 && month <= 8 ? 4 : 2 + (month % 2)))
                for idx in 0..<nightlifeCount {
                    let day = 8 + ((idx * 6 + month) % 18)
                    let amount = roundToNearestTen((220 + Double((idx * 29 + month * 9) % 380)) * (month == 12 ? 1.35 : (month >= 6 && month <= 8 ? 1.15 : 1.0)))
                    insertTx(context, year, month, day: day, amount: amount, kind: .expense, categoryID: "cat_nightlife", note: idx % 2 == 0 ? "Uteliv" : "Kafé")
                }

                // Shopping/diverse
                let shoppingCount = month == 12 ? 4 : 2
                for idx in 0..<shoppingCount {
                    let day = 10 + ((idx * 7 + month) % 17)
                    let amount = roundToNearestTen(180 + Double((idx * 53 + month * 13) % 520))
                    insertTx(context, year, month, day: day, amount: amount, kind: .expense, categoryID: "cat_shopping", note: "Shopping")
                }

                let miscCount = 2 + (month % 2)
                for idx in 0..<miscCount {
                    let day = 6 + ((idx * 9 + month) % 20)
                    let amount = roundToNearestTen(120 + Double((idx * 41 + month * 5) % 340))
                    insertTx(context, year, month, day: day, amount: amount, kind: .expense, categoryID: "cat_misc", note: "Diverse")
                }

                // Sparing
                insertTx(context, year, month, day: 25, amount: savingAmount(month: month), kind: .manualSaving, categoryID: "cat_savings_account", note: "Fast sparing")
                if month % 3 == 0 {
                    insertTx(context, year, month, day: 29, amount: 300, kind: .manualSaving, categoryID: "cat_savings_buffer", note: "Ekstra sparing")
                }

                // Refusjon av og til
                if month % 4 == 0 {
                    insertTx(context, year, month, day: 21, amount: 180, kind: .refund, categoryID: "cat_food", note: "Refusjon")
                }
            }
        }

        _ = categories
        try context.save()
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
                targetAmount: 150_000,
                targetDate: targetDate,
                scope: .wealth,
                includeAccounts: false,
                isActive: true,
                createdAt: date(year: endYear - (demoYears - 1), month: 1, day: 1)
            )
        )

        context.insert(
            UserPreference(
                singletonKey: "main",
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

        try context.save()
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
        version: 1,
        name: "student_realistic_no_v1",
        expenseCategories: [
            .init(id: "cat_rent", name: "Husleie", sortOrder: 1),
            .init(id: "cat_food", name: "Mat", sortOrder: 2),
            .init(id: "cat_transport", name: "Transport", sortOrder: 3),
            .init(id: "cat_subscriptions", name: "Abonnement", sortOrder: 4),
            .init(id: "cat_nightlife", name: "Uteliv", sortOrder: 5),
            .init(id: "cat_shopping", name: "Shopping", sortOrder: 6),
            .init(id: "cat_misc", name: "Diverse", sortOrder: 7)
        ],
        incomeCategories: [
            .init(id: "cat_income_salary", name: "Lønn", sortOrder: 101),
            .init(id: "cat_income_lanekassen", name: "Lånekassen (stipend/lån)", sortOrder: 102),
            .init(id: "cat_income_side_hustle", name: "Ekstrajobb / sideinntekt", sortOrder: 103),
            .init(id: "cat_income_resale", name: "Salg (Finn.no / brukt)", sortOrder: 104),
            .init(id: "cat_income_gifts_received", name: "Gaver / penger mottatt", sortOrder: 105)
        ],
        savingsCategories: [
            .init(id: "cat_savings_buffer", name: "Buffer / nødfond", sortOrder: 201),
            .init(id: "cat_savings_account", name: "Sparekonto (generelt)", sortOrder: 202),
            .init(id: "cat_savings_bsu", name: "BSU", sortOrder: 203),
            .init(id: "cat_savings_home_equity", name: "Boligsparing / egenkapital", sortOrder: 204),
            .init(id: "cat_savings_investing", name: "Investeringer (innskudd fond/aksjer)", sortOrder: 205),
            .init(id: "cat_savings_travel", name: "Ferie / reise", sortOrder: 206),
            .init(id: "cat_savings_big_purchase", name: "Større kjøp (mobil/PC/møbler)", sortOrder: 207),
            .init(id: "cat_savings_car_transport", name: "Bil / transport (vedlikehold/egenkapital)", sortOrder: 208),
            .init(id: "cat_savings_ips", name: "IPS / pensjon", sortOrder: 209),
            .init(id: "cat_savings_gifts", name: "Gaver / julegaver", sortOrder: 210)
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
