import Foundation
import SwiftData

struct ChartPoint: Identifiable {
    let id = UUID()
    let periodKey: String
    let bucketID: String
    let bucketName: String
    let amount: Double
}

enum DateService {
    static let calendar = Calendar.current

    static func periodKey(from date: Date) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let year = comps.year ?? 2000
        let month = comps.month ?? 1
        return String(format: "%04d-%02d", year, month)
    }

    static func monthStart(from periodKey: String) -> Date? {
        let parts = periodKey.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        return calendar.date(from: comps)
    }

    static func offsetPeriodKey(_ periodKey: String, months: Int) -> String? {
        guard let start = monthStart(from: periodKey),
              let shifted = calendar.date(byAdding: .month, value: months, to: start) else { return nil }
        return self.periodKey(from: shifted)
    }

    static func monthBounds(for date: Date) -> (start: Date, end: Date) {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? date
        return (start, end)
    }

    static func monthsRemaining(from startDate: Date, to targetDate: Date) -> Int {
        let start = calendar.startOfDay(for: startDate)
        let target = calendar.startOfDay(for: targetDate)
        let diff = calendar.dateComponents([.month], from: start, to: target).month ?? 0
        return max(1, diff)
    }
}

enum BudgetService {
    static func budgetImpact(_ transaction: Transaction) -> Double {
        switch transaction.kind {
        case .expense:
            return abs(transaction.amount)
        case .refund:
            return -abs(transaction.amount)
        case .income, .transfer, .manualSaving:
            return 0
        }
    }

    static func plannedTotal(for periodKey: String, plans: [BudgetPlan], categories: [Category]) -> Double {
        let expenseIDs = Set(categories.filter { $0.type == .expense }.map(\.id))
        return plans
            .filter { $0.monthPeriodKey == periodKey && expenseIDs.contains($0.categoryID) }
            .reduce(0) { $0 + $1.plannedAmount }
    }

    static func actualExpenseTotal(for periodKey: String, transactions: [Transaction]) -> Double {
        transactions
            .filter { DateService.periodKey(from: $0.date) == periodKey }
            .reduce(0) { $0 + budgetImpact($1) }
    }

    static func spentByCategory(for periodKey: String, categoryID: String, transactions: [Transaction]) -> Double {
        transactions
            .filter { DateService.periodKey(from: $0.date) == periodKey && $0.categoryID == categoryID }
            .reduce(0) { $0 + budgetImpact($1) }
    }

    static func actualIncomeTotal(for periodKey: String, transactions: [Transaction]) -> Double {
        transactions
            .filter { DateService.periodKey(from: $0.date) == periodKey && $0.kind == .income }
            .reduce(0) { $0 + abs($1.amount) }
    }
}

enum FixedItemsService {
    static func recurringKey(fixedItemID: String, periodKey: String) -> String {
        "\(fixedItemID)|\(periodKey)"
    }

    static func generateForMonth(
        context: ModelContext,
        periodKey: String,
        monthStart: Date,
        monthEnd: Date,
        now: Date = .now
    ) throws {
        let fixedItems = try context.fetch(FetchDescriptor<FixedItem>())
        let existingTransactions = try context.fetch(FetchDescriptor<Transaction>())
        let skips = try context.fetch(FetchDescriptor<FixedItemSkip>())

        let existingRecurringKeys = Set(existingTransactions.compactMap(\.recurringKey))
        let skippedKeys = Set(skips.map(\.uniqueKey))

        var didChange = false
        for item in fixedItems where shouldGenerate(item, periodKey: periodKey, monthStart: monthStart, monthEnd: monthEnd, now: now) {
            let key = recurringKey(fixedItemID: item.id, periodKey: periodKey)
            if existingRecurringKeys.contains(key) || skippedKeys.contains(key) {
                continue
            }

            let generatedDate = generatedDateForItem(item, monthStart: monthStart)
            let transaction = Transaction(
                date: generatedDate,
                amount: abs(item.amount),
                kind: item.kind,
                categoryID: item.categoryID,
                note: "Fast post",
                recurringKey: key,
                fixedItemID: item.id
            )
            context.insert(transaction)
            item.lastGeneratedPeriodKey = periodKey
            didChange = true
        }

        if didChange {
            try context.save()
        }
    }

    static func generateForCurrentMonthForItem(
        context: ModelContext,
        fixedItemID: String,
        now: Date = .now
    ) throws {
        let bounds = DateService.monthBounds(for: now)
        let periodKey = DateService.periodKey(from: now)
        let items = try context.fetch(FetchDescriptor<FixedItem>())
        guard let item = items.first(where: { $0.id == fixedItemID }) else { return }
        guard item.isActive, item.autoCreate else { return }
        guard item.startDate <= bounds.end else { return }
        if let end = item.endDate, end < bounds.start { return }

        let key = recurringKey(fixedItemID: fixedItemID, periodKey: periodKey)
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        if transactions.contains(where: { $0.recurringKey == key }) { return }
        let skips = try context.fetch(FetchDescriptor<FixedItemSkip>())
        if skips.contains(where: { $0.uniqueKey == key }) { return }

        context.insert(
            Transaction(
                date: generatedDateForItem(item, monthStart: bounds.start),
                amount: abs(item.amount),
                kind: item.kind,
                categoryID: item.categoryID,
                note: "Fast post",
                recurringKey: key,
                fixedItemID: item.id
            )
        )
        item.lastGeneratedPeriodKey = periodKey
        try context.save()
    }

    static func fixedTotalForMonth(
        periodKey: String,
        transactions: [Transaction]
    ) -> Double {
        transactions
            .filter { DateService.periodKey(from: $0.date) == periodKey && $0.recurringKey != nil }
            .reduce(0) { total, tx in
                switch tx.kind {
                case .expense:
                    return total + abs(tx.amount)
                case .income:
                    return total + abs(tx.amount)
                case .refund, .transfer, .manualSaving:
                    return total
                }
            }
    }

    static func registerDeletionSkipIfNeeded(
        transaction: Transaction,
        context: ModelContext
    ) throws {
        guard let fixedItemID = transaction.fixedItemID else { return }
        let periodKey = DateService.periodKey(from: transaction.date)
        let uniqueKey = recurringKey(fixedItemID: fixedItemID, periodKey: periodKey)
        let existingSkips = try context.fetch(FetchDescriptor<FixedItemSkip>())
        if !existingSkips.contains(where: { $0.uniqueKey == uniqueKey }) {
            context.insert(FixedItemSkip(fixedItemID: fixedItemID, periodKey: periodKey))
            try context.save()
        }
    }

    private static func shouldGenerate(
        _ item: FixedItem,
        periodKey: String,
        monthStart: Date,
        monthEnd: Date,
        now: Date
    ) -> Bool {
        guard item.isActive, item.autoCreate else { return false }

        let periodDate = monthStart
        let itemStartMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: item.startDate)) ?? item.startDate
        guard itemStartMonth <= periodDate else { return false }

        if let endDate = item.endDate {
            let endMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: endDate)) ?? endDate
            if endMonth < periodDate { return false }
        }

        if item.lastGeneratedPeriodKey == periodKey {
            return false
        }

        if DateService.periodKey(from: now) == periodKey {
            let dueDate = generatedDateForItem(item, monthStart: monthStart)
            if dueDate < now && item.lastGeneratedPeriodKey == nil {
                return false
            }
        }

        return monthStart <= monthEnd
    }

    private static func generatedDateForItem(_ item: FixedItem, monthStart: Date) -> Date {
        let day = clampedDay(item.dayOfMonth, monthStart: monthStart)
        var components = Calendar.current.dateComponents([.year, .month], from: monthStart)
        components.day = day
        return Calendar.current.date(from: components) ?? monthStart
    }

    private static func clampedDay(_ dayOfMonth: Int, monthStart: Date) -> Int {
        let dayRange = Calendar.current.range(of: .day, in: .month, for: monthStart) ?? 1..<29
        let maxDay = dayRange.upperBound - 1
        return max(dayRange.lowerBound, min(dayOfMonth, maxDay))
    }
}

enum SavingsService {
    static func savedYearToDate(definition: SavingsDefinition, transactions: [Transaction], categories: [Category], now: Date = .now) -> Double {
        let cal = Calendar.current
        let year = cal.component(.year, from: now)

        let ytd = transactions.filter { cal.component(.year, from: $0.date) == year }
        switch definition {
        case .incomeMinusExpense:
            let income = ytd.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
            let expense = ytd.reduce(0) { $0 + max(BudgetService.budgetImpact($1), 0) }
            return income - expense
        case .savingsCategoryOnly:
            let savingsIDs = Set(categories.filter { $0.type == .savings }.map(\.id))
            return ytd
                .filter { $0.kind == .manualSaving || ($0.categoryID != nil && savingsIDs.contains($0.categoryID!)) }
                .reduce(0) { $0 + abs($1.amount) }
        }
    }
}

enum InvestmentService {
    static func sortedSnapshots(_ snapshots: [InvestmentSnapshot]) -> [InvestmentSnapshot] {
        snapshots.sorted { $0.periodKey < $1.periodKey }
    }

    static func latestSnapshot(_ snapshots: [InvestmentSnapshot], now: Date = .now) -> InvestmentSnapshot? {
        filteredSnapshots(range: .max, snapshots: snapshots, now: now).last
    }

    static func previousSnapshot(_ snapshots: [InvestmentSnapshot], now: Date = .now) -> InvestmentSnapshot? {
        let sorted = filteredSnapshots(range: .max, snapshots: snapshots, now: now)
        guard sorted.count > 1 else { return nil }
        return sorted[sorted.count - 2]
    }

    static func previousSnapshot(
        before periodKey: String,
        snapshots: [InvestmentSnapshot]
    ) -> InvestmentSnapshot? {
        sortedSnapshots(snapshots)
            .last(where: { $0.periodKey < periodKey })
    }

    static func snapshot(
        for periodKey: String,
        snapshots: [InvestmentSnapshot]
    ) -> InvestmentSnapshot? {
        snapshots.first(where: { $0.periodKey == periodKey })
    }

    static func monthChange(current: InvestmentSnapshot?, previous: InvestmentSnapshot?) -> (kr: Double, pct: Double?) {
        guard let current else { return (0, nil) }
        guard let previous, previous.totalValue != 0 else { return (current.totalValue, nil) }
        let change = current.totalValue - previous.totalValue
        return (change, change / previous.totalValue)
    }

    static func upsertSnapshot(
        context: ModelContext,
        periodKey: String,
        capturedAt: Date,
        values: [InvestmentSnapshotValue]
    ) throws {
        let total = values.reduce(0) { $0 + $1.amount }
        let descriptor = FetchDescriptor<InvestmentSnapshot>(
            predicate: #Predicate { $0.periodKey == periodKey }
        )
        let existing = try context.fetch(descriptor).first

        if let existing {
            existing.capturedAt = capturedAt
            existing.bucketValues = values
            existing.totalValue = total
        } else {
            context.insert(
                InvestmentSnapshot(
                    periodKey: periodKey,
                    capturedAt: capturedAt,
                    totalValue: total,
                    bucketValues: values
                )
            )
        }
        try context.save()
    }

    static func filteredSnapshots(
        range: GraphViewRange,
        snapshots: [InvestmentSnapshot],
        now: Date = .now
    ) -> [InvestmentSnapshot] {
        let sorted = sortedSnapshots(snapshots)
        let calendar = Calendar.current
        let nowDay = calendar.startOfDay(for: now)

        switch range {
        case .yearToDate:
            let year = calendar.component(.year, from: now)
            return sorted.filter {
                calendar.component(.year, from: $0.capturedAt) == year &&
                calendar.startOfDay(for: $0.capturedAt) <= nowDay
            }
        case .oneYear, .last12Months:
            return rollingWindowSnapshots(years: 1, sortedSnapshots: sorted, now: now)
        case .twoYears:
            return rollingWindowSnapshots(years: 2, sortedSnapshots: sorted, now: now)
        case .threeYears:
            return rollingWindowSnapshots(years: 3, sortedSnapshots: sorted, now: now)
        case .fiveYears:
            return rollingWindowSnapshots(years: 5, sortedSnapshots: sorted, now: now)
        case .max:
            return sorted.filter { calendar.startOfDay(for: $0.capturedAt) <= nowDay }
        }
    }

    static func chartPoints(
        range: GraphViewRange,
        snapshots: [InvestmentSnapshot],
        buckets: [InvestmentBucket],
        now: Date = .now
    ) -> [ChartPoint] {
        let sorted = filteredSnapshots(range: range, snapshots: snapshots, now: now)
        let targetKeys = Set(sorted.map(\.periodKey))

        let bucketNameByID = Dictionary(uniqueKeysWithValues: buckets.map { ($0.id, $0.name) })
        var result: [ChartPoint] = []
        for snapshot in sorted where targetKeys.contains(snapshot.periodKey) {
            for value in snapshot.bucketValues {
                result.append(
                    ChartPoint(
                        periodKey: snapshot.periodKey,
                        bucketID: value.bucketID,
                        bucketName: bucketNameByID[value.bucketID] ?? value.bucketID,
                        amount: value.amount
                    )
                )
            }
        }
        return result
    }

    private static func rollingWindowSnapshots(
        years: Int,
        sortedSnapshots: [InvestmentSnapshot],
        now: Date
    ) -> [InvestmentSnapshot] {
        let calendar = Calendar.current
        let nowDay = calendar.startOfDay(for: now)
        let monthStartNow = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let monthsBack = max(0, years * 12 - 1)
        let windowStart = calendar.date(byAdding: .month, value: -monthsBack, to: monthStartNow) ?? monthStartNow
        return sortedSnapshots.filter {
            let day = calendar.startOfDay(for: $0.capturedAt)
            return day >= windowStart && day <= nowDay
        }
    }
}

enum GoalService {
    static func currentWealth(latestInvestmentTotal: Double, accounts: [Account], includeAccounts: Bool) -> Double {
        let accountPart = includeAccounts
            ? accounts.filter(\.includeInNetWealth).reduce(0) { $0 + $1.currentBalance }
            : 0
        return latestInvestmentTotal + accountPart
    }

    static func requiredMonthlySaving(nowWealth: Double, targetAmount: Double, targetDate: Date, now: Date = .now) -> Double {
        let remaining = max(0, targetAmount - nowWealth)
        let months = DateService.monthsRemaining(from: now, to: targetDate)
        return remaining / Double(months)
    }
}

enum ChallengeService {
    static func progressText(_ challenge: Challenge) -> String {
        let pct = Int((challenge.progress * 100).rounded())
        switch challenge.status {
        case .active:
            return "Pågår · \(pct) %"
        case .paused:
            return "Pauset · \(pct) %"
        case .completed:
            return "Fullført · 100 %"
        case .cancelled:
            return "Avsluttet · \(pct) %"
        }
    }
    
    static func recalculate(
        challenge: Challenge,
        transactions: [Transaction],
        categories: [Category],
        preference: UserPreference?,
        now: Date = .now
    ) -> Double {
        guard challenge.status == .active || challenge.status == .paused else {
            return challenge.progress
        }

        let periodTransactions = transactions.filter { $0.date >= challenge.startDate && $0.date <= challenge.endDate }
        let savingsIDs = Set(categories.filter { $0.type == .savings }.map(\.id))

        let computed: Double
        switch challenge.measurementMode {
        case .manualCheckin:
            computed = challenge.manualProgress
        case .manualRoundUp:
            let amount = periodTransactions
                .filter { $0.kind == .manualSaving && $0.note.localizedCaseInsensitiveContains("roundup") }
                .reduce(0) { $0 + abs($1.amount) }
            let target = max(challenge.targetAmount ?? 0, 1)
            computed = amount / target
        case .savingsCategory:
            let amount = periodTransactions
                .filter { $0.kind == .manualSaving || ($0.categoryID != nil && savingsIDs.contains($0.categoryID!)) }
                .reduce(0) { $0 + abs($1.amount) }
            let target = max(challenge.targetAmount ?? 0, 1)
            computed = amount / target
        case .savingsDefinition:
            let definition = preference?.savingsDefinition ?? .incomeMinusExpense
            let amount = SavingsService.savedYearToDate(
                definition: definition,
                transactions: periodTransactions,
                categories: categories,
                now: now
            )
            let target = max(challenge.targetAmount ?? 0, 1)
            computed = amount / target
        }

        let clamped = min(max(computed, 0), 1)
        challenge.progress = clamped
        if clamped >= 1 && challenge.status == .active {
            challenge.status = .completed
        }
        return clamped
    }
}

enum BootstrapService {
    static func ensurePreference(context: ModelContext) throws {
        var didChange = false
        do {
            var descriptor = FetchDescriptor<UserPreference>()
            descriptor.fetchLimit = 1
            let existing = try context.fetch(descriptor)
            if existing.isEmpty {
                context.insert(UserPreference())
                didChange = true
            }

            if ensureDefaultCategories(context: context) {
                didChange = true
            }
            if ensureCategoryGroups(context: context) {
                didChange = true
            }

            if didChange {
                try context.save()
            }
        } catch {
            // Recovery path for broken/old local stores after schema changes.
            context.insert(UserPreference())
            _ = ensureDefaultCategories(context: context)
            _ = ensureCategoryGroups(context: context)
            try context.save()
        }
    }

    static func ensureCurrentBudgetMonthAndRecurring(context: ModelContext, now: Date = .now) throws {
        let currentKey = DateService.periodKey(from: now)
        let bounds = DateService.monthBounds(for: now)
        let months = try context.fetch(FetchDescriptor<BudgetMonth>())
        if !months.contains(where: { $0.periodKey == currentKey }) {
            context.insert(
                BudgetMonth(
                    periodKey: currentKey,
                    year: Calendar.current.component(.year, from: now),
                    month: Calendar.current.component(.month, from: now),
                    startDate: bounds.start,
                    endDate: bounds.end
                )
            )
            try context.save()
        }

        try FixedItemsService.generateForMonth(
            context: context,
            periodKey: currentKey,
            monthStart: bounds.start,
            monthEnd: bounds.end,
            now: now
        )
    }

    @discardableResult
    private static func ensureDefaultCategories(context: ModelContext) -> Bool {
        let existing = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let existingIDs = Set(existing.map(\.id))
        let defaults: [(String, String, CategoryType, Int)] = [
            ("cat_housing", "Bolig", .expense, 1),
            ("cat_food", "Mat", .expense, 2),
            ("cat_transport", "Transport", .expense, 3),
            ("cat_leisure", "Fritid", .expense, 4),
            ("cat_savings_buffer", "Buffer / nødfond", .savings, 5),
            ("cat_savings_account", "Sparekonto (generelt)", .savings, 6),
            ("cat_savings_bsu", "BSU", .savings, 7),
            ("cat_savings_home_equity", "Boligsparing / egenkapital", .savings, 8),
            ("cat_savings_investing", "Investeringer (innskudd fond/aksjer)", .savings, 9),
            ("cat_savings_travel", "Ferie / reise", .savings, 10),
            ("cat_savings_big_purchase", "Større kjøp (mobil/PC/møbler)", .savings, 11),
            ("cat_savings_car_transport", "Bil / transport (vedlikehold/egenkapital)", .savings, 12),
            ("cat_savings_ips", "IPS / pensjon", .savings, 13),
            ("cat_savings_gifts", "Gaver / julegaver", .savings, 14),

            ("cat_expense_bilvask", "Bilvask", .expense, 20),
            ("cat_expense_spotify", "Spotify", .expense, 21),
            ("cat_expense_apple_music", "Apple Music", .expense, 22),
            ("cat_expense_icloud", "iCloud", .expense, 23),
            ("cat_expense_playstation_plus", "PlayStation Plus", .expense, 24),
            ("cat_expense_xbox_live", "Xbox Live", .expense, 25),
            ("cat_expense_legebesok", "Legebesøk", .expense, 26),
            ("cat_expense_medisiner", "Medisiner", .expense, 27),
            ("cat_expense_frisor", "Frisør", .expense, 28),
            ("cat_expense_kommunale_avgifter", "Kommunale avgifter", .expense, 29),
            ("cat_expense_vann_avlop", "Vann og avløp", .expense, 30),
            ("cat_expense_feiing", "Feiing", .expense, 31),
            ("cat_expense_reise", "Reise", .expense, 32),
            ("cat_expense_klaer", "Klær", .expense, 33),
            ("cat_expense_mobler", "Møbler", .expense, 34),
            ("cat_expense_blomster", "Blomster", .expense, 35),
            ("cat_expense_barnehage", "Barnehage", .expense, 36),
            ("cat_expense_hyttelan", "Hyttelån", .expense, 37),
            ("cat_expense_nedbetaling_lan", "Nedbetaling av lån", .expense, 38),
            ("cat_expense_kjaeledyr", "Kjæledyr", .expense, 39),
            ("cat_expense_netflix", "Netflix", .expense, 40),
            ("cat_expense_prime_video", "Prime Video", .expense, 41),
            ("cat_expense_disney_plus", "Disney+", .expense, 42),
            ("cat_expense_matkasse", "Matkasse", .expense, 43),
            ("cat_expense_kollektivtransport", "Kollektivtransport", .expense, 44),
            ("cat_expense_trening", "Trening", .expense, 45),
            ("cat_expense_investering_aksjer", "Investering i aksjer", .expense, 46),
            ("cat_expense_investering_fond", "Investering i fond", .expense, 47),
            ("cat_expense_forsikring", "Forsikring", .expense, 48),
            ("cat_expense_reiseforsikring", "Reiseforsikring", .expense, 49),
            ("cat_expense_innboforsikring", "Innboforsikring", .expense, 50),
            ("cat_expense_bilforsikring", "Bilforsikring", .expense, 51),
            ("cat_expense_bompenger", "Bompenger", .expense, 52),
            ("cat_expense_parkering", "Parkering", .expense, 53),
            ("cat_expense_lading_elbil", "Lading av elbil", .expense, 54),
            ("cat_expense_drivstoff", "Drivstoff", .expense, 55),
            ("cat_expense_lunsj_jobb", "Lunsj på jobb", .expense, 56),
            ("cat_expense_uteliv", "Uteliv", .expense, 57),
            ("cat_expense_internett", "Internett", .expense, 58),
            ("cat_expense_mobilabonnement", "Mobilabonnement", .expense, 59),

            ("cat_income_salary", "Lønn", .income, 70),
            ("cat_income_lanekassen", "Lånekassen (stipend/lån)", .income, 71),
            ("cat_income_side_hustle", "Ekstrajobb / sideinntekt", .income, 72),
            ("cat_income_resale", "Salg (Finn.no / brukt)", .income, 73),
            ("cat_income_gifts_received", "Gaver / penger mottatt", .income, 74)
        ]

        var didInsert = false
        for item in defaults where !existingIDs.contains(item.0) {
            context.insert(Category(id: item.0, name: item.1, type: item.2, sortOrder: item.3))
            didInsert = true
        }
        return didInsert
    }

    @discardableResult
    private static func ensureCategoryGroups(context: ModelContext) -> Bool {
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        var didChange = false
        for category in categories {
            if category.groupKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                category.groupKey = Category.defaultGroupKey(forName: category.name, type: category.type)
                didChange = true
            }
        }
        return didChange
    }
}

enum OnboardingService {
    static func complete(
        context: ModelContext,
        preference: UserPreference,
        focus: OnboardingFocus,
        tone: AppToneStyle,
        firstWealthTotal: Double?,
        goalAmount: Double?,
        goalDate: Date?,
        snapshotValues: [String: Double],
        snapshotInputProvided: Bool,
        budgetCategories: [String],
        monthlyBudget: Double?,
        budgetTrackOnly: Bool,
        reminderEnabled: Bool,
        reminderDay: Int,
        reminderHour: Int,
        reminderMinute: Int,
        faceIDEnabled: Bool,
        selectedBuckets: [String],
        customBucketName: String?
    ) throws {
        if let customBucketName, !customBucketName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let name = customBucketName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !selectedBuckets.contains(name) {
                insertBucketIfMissing(context: context, name: name, sortOrder: selectedBuckets.count + 1)
            }
        }

        for (index, name) in selectedBuckets.enumerated() {
            insertBucketIfMissing(context: context, name: name, sortOrder: index + 1)
        }

        insertBaseCategoriesIfMissing(context: context)

        let monthKey = DateService.periodKey(from: .now)
        let existingMonths = try context.fetch(FetchDescriptor<BudgetMonth>())
        let hasMonth = existingMonths.contains(where: { $0.periodKey == monthKey })
        if !hasMonth {
            let bounds = DateService.monthBounds(for: .now)
            context.insert(
                BudgetMonth(
                    periodKey: monthKey,
                    year: Calendar.current.component(.year, from: .now),
                    month: Calendar.current.component(.month, from: .now),
                    startDate: bounds.start,
                    endDate: bounds.end
                )
            )
        }

        if let goalAmount, goalAmount > 0 {
            let resolvedDate = goalDate ?? Calendar.current.date(byAdding: .month, value: 24, to: .now) ?? .now
            context.insert(Goal(targetAmount: goalAmount, targetDate: resolvedDate, includeAccounts: true))
        }

        if snapshotInputProvided {
            let key = DateService.periodKey(from: .now)
            let values: [InvestmentSnapshotValue] = selectedBuckets.compactMap { name in
                let bucketID = "bucket_" + name.lowercased().replacingOccurrences(of: " ", with: "_")
                let typed = snapshotValues[name] ?? 0
                if typed <= 0 { return nil }
                return InvestmentSnapshotValue(
                    periodKey: key,
                    bucketID: bucketID,
                    amount: typed
                )
            }
            let breakdownTotal = values.reduce(0) { $0 + $1.amount }
            let total = breakdownTotal > 0 ? breakdownTotal : max(firstWealthTotal ?? 0, 0)
            context.insert(InvestmentSnapshot(periodKey: key, capturedAt: .now, totalValue: total, bucketValues: values))
        }

        let budgetCategoryIDs = budgetCategories.map { categoryID(for: $0) }
        for (index, id) in budgetCategoryIDs.enumerated() {
            let type: CategoryType = id.hasPrefix("cat_savings") ? .savings : .expense
            insertCategoryIfMissing(context: context, id: id, name: budgetCategories[index], type: type, sortOrder: 10 + index)
        }

        if !budgetTrackOnly, let monthlyBudget, monthlyBudget > 0, !budgetCategoryIDs.isEmpty {
            let monthKey = DateService.periodKey(from: .now)
            let perCategory = monthlyBudget / Double(budgetCategoryIDs.count)
            for id in budgetCategoryIDs {
                let planKey = "\(monthKey)|\(id)"
                let existingPlans = (try? context.fetch(FetchDescriptor<BudgetPlan>())) ?? []
                if !existingPlans.contains(where: { $0.uniqueKey == planKey }) {
                    context.insert(BudgetPlan(monthPeriodKey: monthKey, categoryID: id, plannedAmount: perCategory))
                }
            }
        }

        preference.checkInReminderEnabled = reminderEnabled
        preference.checkInReminderDay = max(1, min(28, reminderDay))
        preference.checkInReminderHour = max(0, min(23, reminderHour))
        preference.checkInReminderMinute = max(0, min(59, reminderMinute))
        preference.faceIDLockEnabled = faceIDEnabled
        preference.onboardingFocus = focus
        preference.toneStyle = tone
        preference.onboardingCompleted = true
        preference.onboardingCurrentStep = 0
        try context.save()
    }

    private static func insertBucketIfMissing(context: ModelContext, name: String, sortOrder: Int) {
        let key = "bucket_" + name.lowercased().replacingOccurrences(of: " ", with: "_")
        let existing = (try? context.fetch(FetchDescriptor<InvestmentBucket>())) ?? []
        let exists = existing.contains(where: { $0.id == key })
        if !exists {
            context.insert(InvestmentBucket(id: key, name: name, isDefault: true, sortOrder: sortOrder))
        }
    }

    private static func insertBaseCategoriesIfMissing(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let existingIDs = Set(existing.map(\.id))
        let defaults: [(String, String, CategoryType, Int)] = [
            ("cat_housing", "Bolig", .expense, 1),
            ("cat_food", "Mat", .expense, 2),
            ("cat_transport", "Transport", .expense, 3),
            ("cat_leisure", "Fritid", .expense, 4),
            ("cat_savings_buffer", "Buffer / nødfond", .savings, 5),
            ("cat_savings_account", "Sparekonto (generelt)", .savings, 6),
            ("cat_savings_bsu", "BSU", .savings, 7),
            ("cat_savings_home_equity", "Boligsparing / egenkapital", .savings, 8),
            ("cat_savings_investing", "Investeringer (innskudd fond/aksjer)", .savings, 9),
            ("cat_savings_travel", "Ferie / reise", .savings, 10),
            ("cat_savings_big_purchase", "Større kjøp (mobil/PC/møbler)", .savings, 11),
            ("cat_savings_car_transport", "Bil / transport (vedlikehold/egenkapital)", .savings, 12),
            ("cat_savings_ips", "IPS / pensjon", .savings, 13),
            ("cat_savings_gifts", "Gaver / julegaver", .savings, 14)
        ]
        for item in defaults {
            if !existingIDs.contains(item.0) {
                context.insert(Category(id: item.0, name: item.1, type: item.2, sortOrder: item.3))
            }
        }
    }

    private static func categoryID(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("mat") { return "cat_food" }
        if lower.contains("bolig") { return "cat_housing" }
        if lower.contains("transport") { return "cat_transport" }
        if lower.contains("fritid") { return "cat_leisure" }
        if lower.contains("bsu") { return "cat_savings_bsu" }
        if lower.contains("buffer") || lower.contains("nødfond") { return "cat_savings_buffer" }
        if lower.contains("ips") || lower.contains("pensjon") { return "cat_savings_ips" }
        if lower.contains("boligsparing") || lower.contains("egenkapital") { return "cat_savings_home_equity" }
        if lower.contains("ferie") || lower.contains("reise") { return "cat_savings_travel" }
        if lower.contains("gave") || lower.contains("jul") { return "cat_savings_gifts" }
        if lower.contains("større kjøp") || lower.contains("mobil") || lower.contains("pc") || lower.contains("møbler") { return "cat_savings_big_purchase" }
        if lower.contains("bil") || lower.contains("transport") { return "cat_savings_car_transport" }
        if lower.contains("investering") || lower.contains("fond") || lower.contains("aksjer") { return "cat_savings_investing" }
        if lower.contains("sparing") || lower.contains("sparekonto") { return "cat_savings_account" }
        return "cat_" + lower.replacingOccurrences(of: " ", with: "_")
    }

    private static func insertCategoryIfMissing(context: ModelContext, id: String, name: String, type: CategoryType, sortOrder: Int) {
        let existing = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        if !existing.contains(where: { $0.id == id }) {
            context.insert(Category(id: id, name: name, type: type, sortOrder: sortOrder))
        }
    }
}
