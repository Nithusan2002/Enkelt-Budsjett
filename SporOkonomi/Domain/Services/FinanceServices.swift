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
        let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        let end = calendar.date(byAdding: .second, value: -1, to: nextMonthStart) ?? nextMonthStart
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
    static func expenseImpact(_ transaction: Transaction) -> Double {
        trackedBudgetImpact(transaction)
    }

    static func incomeImpact(_ transaction: Transaction) -> Double {
        guard transaction.kind == .income else { return 0 }
        return abs(transaction.amount)
    }

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

    static func trackedBudgetImpact(_ transaction: Transaction) -> Double {
        switch transaction.kind {
        case .manualSaving:
            return abs(transaction.amount)
        default:
            return budgetImpact(transaction)
        }
    }

    static func plannedTotal(for periodKey: String, plans: [BudgetPlan], categories: [Category]) -> Double {
        let expenseIDs = Set(categories.filter { $0.type == .expense }.map(\.id))
        return plans
            .filter { $0.monthPeriodKey == periodKey && expenseIDs.contains($0.categoryID) }
            .reduce(0) { $0 + $1.plannedAmount }
    }

    static func plannedGroupTotal(for periodKey: String, groupPlans: [BudgetGroupPlan]) -> Double {
        groupPlans
            .filter { $0.monthPeriodKey == periodKey }
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
            try context.guardedSave(feature: "FixedItems", operation: "generate_for_month")
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
        try context.guardedSave(feature: "FixedItems", operation: "generate_current_month_for_item")
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
            try context.guardedSave(feature: "FixedItems", operation: "register_skip")
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
    static func savedInPeriod(
        definition: SavingsDefinition,
        transactions: [Transaction],
        categories: [Category]
    ) -> Double {
        switch definition {
        case .incomeMinusExpense:
            let income = transactions
                .filter { $0.kind == .income }
                .reduce(0) { $0 + $1.amount }
            let expense = transactions
                .reduce(0) { $0 + BudgetService.budgetImpact($1) }
            return income - expense
        case .savingsCategoryOnly:
            let savingsIDs = Set(categories.filter { $0.type == .savings }.map(\.id))
            return transactions
                .filter {
                    $0.kind == .manualSaving ||
                    ($0.categoryID.map(savingsIDs.contains) == true)
                }
                .reduce(0) { $0 + abs($1.amount) }
        }
    }

    static func savedYearToDate(definition: SavingsDefinition, transactions: [Transaction], categories: [Category], now: Date = .now) -> Double {
        let cal = Calendar.current
        let yearStart = cal.date(from: cal.dateComponents([.year], from: now)) ?? now
        return savedInRange(
            definition: definition,
            transactions: transactions,
            categories: categories,
            start: yearStart,
            end: now
        )
    }

    static func savedInRange(
        definition: SavingsDefinition,
        transactions: [Transaction],
        categories: [Category],
        start: Date,
        end: Date
    ) -> Double {
        guard end >= start else { return 0 }
        let rangeTransactions = transactions.filter { $0.date >= start && $0.date <= end }
        return savedInPeriod(
            definition: definition,
            transactions: rangeTransactions,
            categories: categories
        )
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
        try context.guardedSave(feature: "Investments", operation: "upsert_snapshot")
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

        let bucketNameByID = Dictionary(
            buckets.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
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
                .filter { $0.kind == .manualSaving || ($0.categoryID.map(savingsIDs.contains) == true) }
                .reduce(0) { $0 + abs($1.amount) }
            let target = max(challenge.targetAmount ?? 0, 1)
            computed = amount / target
        case .savingsDefinition:
            let definition = preference?.savingsDefinition ?? .incomeMinusExpense
            let rangeEnd = min(challenge.endDate, now)
            let amount = SavingsService.savedInRange(
                definition: definition,
                transactions: transactions,
                categories: categories,
                start: challenge.startDate,
                end: rangeEnd
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
    private static let dedupeLastRunKey = "bootstrap_dedupe_last_run_at"
    private static let dedupeInterval: TimeInterval = 60 * 60 * 24

    static func ensurePreference(context: ModelContext) throws {
        var didChange = false
        let ranDeduplication = shouldRunDeduplication()
        do {
            if try deduplicate(context: context, key: { (category: Category) in category.id }) {
                didChange = true
            }

            if ranDeduplication,
               try deduplicateKeyedModels(context: context) {
                didChange = true
            }

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
            if ensureDefaultInvestmentBuckets(context: context) {
                didChange = true
            }
            if ensureCategoryGroups(context: context) {
                didChange = true
            }
            if ensureAuthChoiceMigration(context: context) {
                didChange = true
            }

            if didChange {
                try context.guardedSave(
                    feature: "Bootstrap",
                    operation: "ensure_preference_changes",
                    enforceReadOnly: false
                )
            }
            if ranDeduplication {
                markDeduplicationRun()
            }
        } catch {
            // Recovery path for broken/old local stores after schema changes.
            context.insert(UserPreference())
            _ = ensureDefaultCategories(context: context)
            _ = ensureDefaultInvestmentBuckets(context: context)
            _ = ensureCategoryGroups(context: context)
            _ = ensureAuthChoiceMigration(context: context)
            try context.guardedSave(
                feature: "Bootstrap",
                operation: "ensure_preference_recovery",
                enforceReadOnly: false
            )
            if ranDeduplication {
                markDeduplicationRun()
            }
        }
    }

    private static func shouldRunDeduplication(now: Date = .now) -> Bool {
        guard let lastRun = UserDefaults.standard.object(forKey: dedupeLastRunKey) as? Date else {
            return true
        }
        return now.timeIntervalSince(lastRun) >= dedupeInterval
    }

    private static func markDeduplicationRun(now: Date = .now) {
        UserDefaults.standard.set(now, forKey: dedupeLastRunKey)
    }

    @discardableResult
    private static func deduplicateKeyedModels(context: ModelContext) throws -> Bool {
        var didChange = false
        if try deduplicate(context: context, key: { (month: BudgetMonth) in month.periodKey }) { didChange = true }
        if try deduplicate(context: context, key: { (plan: BudgetPlan) in plan.uniqueKey }) { didChange = true }
        if try deduplicate(context: context, key: { (plan: BudgetGroupPlan) in plan.uniqueKey }) { didChange = true }
        if try deduplicate(context: context, key: { (item: FixedItem) in item.id }) { didChange = true }
        if try deduplicate(context: context, key: { (skip: FixedItemSkip) in skip.uniqueKey }) { didChange = true }
        if try deduplicate(context: context, key: { (account: Account) in account.id }) { didChange = true }
        if try deduplicate(context: context, key: { (bucket: InvestmentBucket) in bucket.id }) { didChange = true }
        if try deduplicate(context: context, key: { (snapshot: InvestmentSnapshot) in snapshot.periodKey }) { didChange = true }
        if try deduplicate(context: context, key: { (challenge: Challenge) in challenge.uniqueKey }) { didChange = true }
        if try deduplicate(context: context, key: { (preference: UserPreference) in preference.singletonKey }) { didChange = true }
        return didChange
    }

    private static func deduplicate<Model: PersistentModel, Key: Hashable>(
        context: ModelContext,
        key: (Model) -> Key
    ) throws -> Bool {
        let rows = try context.fetch(FetchDescriptor<Model>())
        var seen = Set<Key>()
        var didDelete = false
        for row in rows {
            let value = key(row)
            if seen.contains(value) {
                context.delete(row)
                didDelete = true
            } else {
                seen.insert(value)
            }
        }
        return didDelete
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
            try context.guardedSave(
                feature: "Bootstrap",
                operation: "ensure_current_month",
                enforceReadOnly: false
            )
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
            ("cat_fixed_costs", "Faste utgifter", .expense, 5),
            ("cat_savings_account", "Sparing", .savings, 6),
            ("cat_other", "Annet", .expense, 7),

            ("cat_income_salary", "Lønn", .income, 70),
            ("cat_income_other", "Annen inntekt", .income, 71)
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

    @discardableResult
    private static func ensureDefaultInvestmentBuckets(context: ModelContext) -> Bool {
        let existing = (try? context.fetch(FetchDescriptor<InvestmentBucket>())) ?? []
        guard !existing.isEmpty else { return false }
        let defaults: [(String, String, Int)] = [
            ("bucket_fond", "Fond", 1),
            ("bucket_aksjer", "Aksjer", 2),
            ("bucket_krypto", "Krypto", 3),
            ("bucket_kontanter", "Kontanter", 4)
        ]
        let legacyIDMap: [String: String] = [
            "funds": "bucket_fond",
            "stocks": "bucket_aksjer",
            "bsu": "bucket_kontanter",
            "buffer": "bucket_kontanter"
        ]

        func normalizedBucketName(_ name: String) -> String {
            name
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "nb_NO"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var bucketsByCanonicalID: [String: InvestmentBucket] = [:]
        var bucketsByNormalizedName: [String: InvestmentBucket] = [:]
        var duplicatesToDelete: [InvestmentBucket] = []
        var didChange = false

        for bucket in existing {
            let canonicalID = legacyIDMap[bucket.id] ?? bucket.id
            let canonicalName = defaults.first(where: { $0.0 == canonicalID })?.1 ?? bucket.name
            let normalizedName = normalizedBucketName(canonicalName)

            if let survivor = bucketsByCanonicalID[canonicalID] ?? bucketsByNormalizedName[normalizedName] {
                if survivor !== bucket {
                    duplicatesToDelete.append(bucket)
                    didChange = true
                }
                continue
            }

            if bucket.id != canonicalID {
                bucket.id = canonicalID
                didChange = true
            }
            if bucket.name != canonicalName {
                bucket.name = canonicalName
                didChange = true
            }

            bucketsByCanonicalID[canonicalID] = bucket
            bucketsByNormalizedName[normalizedName] = bucket
        }

        for bucket in duplicatesToDelete {
            context.delete(bucket)
        }
        return didChange
    }

    @discardableResult
    private static func ensureAuthChoiceMigration(context: ModelContext) -> Bool {
        let preferences = (try? context.fetch(FetchDescriptor<UserPreference>())) ?? []
        var didChange = false

        for preference in preferences {
            let rawMode = preference.authSessionModeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            if rawMode.isEmpty {
                preference.authSessionModeRaw = AuthSessionMode.undecided.rawValue
            }

            let isLegacyUser = preference.onboardingCompleted || preference.onboardingCurrentStep > 0
            if preference.authSessionModeRaw == AuthSessionMode.undecided.rawValue && isLegacyUser {
                preference.authSessionModeRaw = AuthSessionMode.local.rawValue
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
        firstName: String,
        focus: OnboardingFocus,
        tone: AppToneStyle,
        firstWealthTotal: Double?,
        goalAmount: Double?,
        goalDate: Date?,
        snapshotValues: [String: Double],
        snapshotInputProvided: Bool,
        budgetCategories: [String],
        monthlyBudget: Double?,
        monthlyIncome: Double?,
        incomeDayOfMonth: Int,
        budgetTrackOnly: Bool,
        reminderEnabled: Bool,
        reminderDay: Int,
        reminderHour: Int,
        reminderMinute: Int,
        faceIDEnabled: Bool,
        selectedBuckets: [String],
        customBucketName: String?
    ) throws {
        let onboardingBucketNames = resolvedOnboardingBucketNames(
            selectedBuckets: selectedBuckets,
            customBucketName: customBucketName
        )

        for (index, name) in onboardingBucketNames.enumerated() {
            insertBucketIfMissing(context: context, name: name, sortOrder: index + 1)
        }

        insertBaseCategoriesIfMissing(context: context)
        let existingCategories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        var existingCategoryIDs = Set(existingCategories.map(\.id))

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
            upsertActiveGoal(
                context: context,
                targetAmount: goalAmount,
                targetDate: resolvedDate
            )
        }

        if snapshotInputProvided {
            let key = DateService.periodKey(from: .now)
            let values: [InvestmentSnapshotValue] = onboardingBucketNames.compactMap { name in
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
            upsertSnapshot(
                context: context,
                periodKey: key,
                totalValue: total,
                values: values
            )
        }

        let budgetCategoryIDs = budgetCategories.map { categoryID(for: $0) }
        for (index, id) in budgetCategoryIDs.enumerated() {
            let type: CategoryType = id.hasPrefix("cat_savings") ? .savings : .expense
            insertCategoryIfMissing(
                context: context,
                id: id,
                name: budgetCategories[index],
                type: type,
                sortOrder: 10 + index,
                existingCategoryIDs: &existingCategoryIDs
            )
        }

        if !budgetTrackOnly, let monthlyBudget, monthlyBudget > 0, !budgetCategoryIDs.isEmpty {
            let monthKey = DateService.periodKey(from: .now)
            let perCategory = monthlyBudget / Double(budgetCategoryIDs.count)
            let existingPlans = (try? context.fetch(FetchDescriptor<BudgetPlan>())) ?? []
            var existingPlanKeys = Set(existingPlans.map(\.uniqueKey))
            for id in budgetCategoryIDs {
                let planKey = "\(monthKey)|\(id)"
                if existingPlanKeys.insert(planKey).inserted {
                    context.insert(BudgetPlan(monthPeriodKey: monthKey, categoryID: id, plannedAmount: perCategory))
                }
            }
        }

        if let monthlyIncome, monthlyIncome > 0 {
            insertCategoryIfMissing(
                context: context,
                id: "cat_income_salary",
                name: "Lønn",
                type: .income,
                sortOrder: 70,
                existingCategoryIDs: &existingCategoryIDs
            )
            try upsertIncomeFixedItem(
                context: context,
                monthlyIncome: monthlyIncome,
                incomeDayOfMonth: incomeDayOfMonth
            )
        }

        preference.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        preference.checkInReminderEnabled = reminderEnabled
        preference.checkInReminderDay = max(1, min(28, reminderDay))
        preference.checkInReminderHour = max(0, min(23, reminderHour))
        preference.checkInReminderMinute = max(0, min(59, reminderMinute))
        preference.faceIDLockEnabled = faceIDEnabled
        preference.onboardingFocus = focus
        preference.toneStyle = tone
        preference.onboardingCompleted = true
        preference.onboardingCurrentStep = 0
        try context.guardedSave(feature: "Onboarding", operation: "complete")
    }

    private static func resolvedOnboardingBucketNames(
        selectedBuckets: [String],
        customBucketName: String?
    ) -> [String] {
        var names = selectedBuckets.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let customBucketName {
            let normalizedCustomName = customBucketName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedCustomName.isEmpty && !names.contains(normalizedCustomName) {
                names.append(normalizedCustomName)
            }
        }

        return names
    }

    private static func upsertActiveGoal(
        context: ModelContext,
        targetAmount: Double,
        targetDate: Date
    ) {
        let goals = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
        if let activeGoal = goals.first(where: \.isActive) {
            activeGoal.targetAmount = targetAmount
            activeGoal.targetDate = targetDate
            activeGoal.includeAccounts = true
            activeGoal.scope = .wealth
            activeGoal.isActive = true
            return
        }

        context.insert(
            Goal(
                targetAmount: targetAmount,
                targetDate: targetDate,
                scope: .wealth,
                includeAccounts: true,
                isActive: true
            )
        )
    }

    private static func upsertSnapshot(
        context: ModelContext,
        periodKey: String,
        totalValue: Double,
        values: [InvestmentSnapshotValue]
    ) {
        let snapshots = (try? context.fetch(FetchDescriptor<InvestmentSnapshot>())) ?? []
        if let existing = snapshots.first(where: { $0.periodKey == periodKey }) {
            existing.capturedAt = .now
            existing.totalValue = max(totalValue, 0)
            existing.bucketValues = values
            return
        }

        context.insert(
            InvestmentSnapshot(
                periodKey: periodKey,
                capturedAt: .now,
                totalValue: max(totalValue, 0),
                bucketValues: values
            )
        )
    }

    private static func upsertIncomeFixedItem(
        context: ModelContext,
        monthlyIncome: Double,
        incomeDayOfMonth: Int
    ) throws {
        let fixedID = "fixed_income_salary_onboarding"
        let normalizedDay = max(1, min(28, incomeDayOfMonth))
        let normalizedAmount = abs(monthlyIncome)
        let now = Date()
        let monthBounds = DateService.monthBounds(for: now)
        let items = try context.fetch(FetchDescriptor<FixedItem>())

        if let item = items.first(where: { $0.id == fixedID }) {
            item.title = "Lønn"
            item.amount = normalizedAmount
            item.categoryID = "cat_income_salary"
            item.kind = .income
            item.dayOfMonth = normalizedDay
            item.isActive = true
            item.autoCreate = true
            if item.startDate > monthBounds.start {
                item.startDate = monthBounds.start
            }
            item.endDate = nil
        } else {
            context.insert(
                FixedItem(
                    id: fixedID,
                    title: "Lønn",
                    amount: normalizedAmount,
                    categoryID: "cat_income_salary",
                    kind: .income,
                    dayOfMonth: normalizedDay,
                    startDate: monthBounds.start,
                    endDate: nil,
                    isActive: true,
                    autoCreate: true
                )
            )
        }

        try context.guardedSave(feature: "Onboarding", operation: "upsert_income_fixed_item")
        try FixedItemsService.generateForCurrentMonthForItem(context: context, fixedItemID: fixedID, now: now)
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
        if lower.contains("husleie") { return "cat_housing" }
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

    private static func insertCategoryIfMissing(
        context: ModelContext,
        id: String,
        name: String,
        type: CategoryType,
        sortOrder: Int,
        existingCategoryIDs: inout Set<String>
    ) {
        if existingCategoryIDs.insert(id).inserted {
            context.insert(Category(id: id, name: name, type: type, sortOrder: sortOrder))
        }
    }
}
