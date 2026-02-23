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

    static func latestSnapshot(_ snapshots: [InvestmentSnapshot]) -> InvestmentSnapshot? {
        sortedSnapshots(snapshots).last
    }

    static func previousSnapshot(_ snapshots: [InvestmentSnapshot]) -> InvestmentSnapshot? {
        let sorted = sortedSnapshots(snapshots)
        guard sorted.count > 1 else { return nil }
        return sorted[sorted.count - 2]
    }

    static func monthChange(current: InvestmentSnapshot?, previous: InvestmentSnapshot?) -> (kr: Double, pct: Double?) {
        guard let current else { return (0, nil) }
        guard let previous, previous.totalValue != 0 else { return (current.totalValue, nil) }
        let change = current.totalValue - previous.totalValue
        return (change, change / previous.totalValue)
    }

    static func chartPoints(
        range: GraphViewRange,
        snapshots: [InvestmentSnapshot],
        buckets: [InvestmentBucket],
        now: Date = .now
    ) -> [ChartPoint] {
        let sorted = sortedSnapshots(snapshots)
        let targetKeys: Set<String>
        switch range {
        case .yearToDate:
            let year = Calendar.current.component(.year, from: now)
            targetKeys = Set(sorted.filter { $0.periodKey.hasPrefix("\(year)-") }.map(\.periodKey))
        case .last12Months:
            let last12 = sorted.suffix(12)
            targetKeys = Set(last12.map(\.periodKey))
        }

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
        do {
            var descriptor = FetchDescriptor<UserPreference>()
            descriptor.fetchLimit = 1
            let existing = try context.fetch(descriptor)
            if existing.isEmpty {
                context.insert(UserPreference())
                try context.save()
            }
        } catch {
            // Recovery path for broken/old local stores after schema changes.
            context.insert(UserPreference())
            try context.save()
        }
    }
}

enum OnboardingService {
    static func complete(
        context: ModelContext,
        preference: UserPreference,
        focus: OnboardingFocus,
        tone: AppToneStyle,
        includeIncome: Bool,
        monthlyIncome: Double?,
        goalAmount: Double?,
        goalDate: Date?,
        snapshotValues: [String: Double],
        snapshotInputProvided: Bool,
        monthlyFlow: Double?,
        budgetCategories: [String],
        monthlyBudget: Double?,
        budgetTrackOnly: Bool,
        reminderEnabled: Bool,
        reminderDay: Int,
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

        if includeIncome, let monthlyIncome, monthlyIncome > 0 {
            context.insert(Transaction(date: .now, amount: monthlyIncome, kind: .income, note: "Onboarding: inntekt"))
        }

        if let goalAmount, goalAmount > 0 {
            let resolvedDate = goalDate ?? Calendar.current.date(byAdding: .month, value: 24, to: .now) ?? .now
            context.insert(Goal(targetAmount: goalAmount, targetDate: resolvedDate, includeAccounts: true))
        }

        if snapshotInputProvided {
            let key = DateService.periodKey(from: .now)
            let values: [InvestmentSnapshotValue] = selectedBuckets.map { name in
                let bucketID = "bucket_" + name.lowercased().replacingOccurrences(of: " ", with: "_")
                return InvestmentSnapshotValue(
                    periodKey: key,
                    bucketID: bucketID,
                    amount: snapshotValues[name] ?? 0
                )
            }
            let total = values.reduce(0) { $0 + $1.amount }
            context.insert(InvestmentSnapshot(periodKey: key, capturedAt: .now, totalValue: total, bucketValues: values))
        }

        if let monthlyFlow, monthlyFlow != 0 {
            context.insert(Transaction(date: .now, amount: monthlyFlow, kind: .transfer, note: "Onboarding: inn/ut denne måneden"))
        }

        let budgetCategoryIDs = budgetCategories.map { categoryID(for: $0) }
        for (index, id) in budgetCategoryIDs.enumerated() {
            insertCategoryIfMissing(context: context, id: id, name: budgetCategories[index], type: id == "cat_savings" ? .savings : .expense, sortOrder: 10 + index)
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
            ("cat_savings", "Sparingskonto", .savings, 5)
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
        if lower.contains("sparing") { return "cat_savings" }
        return "cat_" + lower.replacingOccurrences(of: " ", with: "_")
    }

    private static func insertCategoryIfMissing(context: ModelContext, id: String, name: String, type: CategoryType, sortOrder: Int) {
        let existing = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        if !existing.contains(where: { $0.id == id }) {
            context.insert(Category(id: id, name: name, type: type, sortOrder: sortOrder))
        }
    }
}
