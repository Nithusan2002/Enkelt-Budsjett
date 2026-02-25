import Foundation
import Combine
import SwiftData

@MainActor
final class SettingsViewModel: ObservableObject {
    func shouldShowDemoTools() -> Bool {
#if DEBUG
        return true
#else
        if let receiptURL = Bundle.main.appStoreReceiptURL {
            return receiptURL.lastPathComponent == "sandboxReceipt"
        }
        return false
#endif
    }

    func seedDemoRealisticYear(context: ModelContext, year: Int? = nil) throws -> DemoSeedReport {
        try DemoDataSeeder.seedRealisticYear(context: context, year: year)
    }

    func wipeAllDataForDemo(context: ModelContext) throws {
        try DemoDataSeeder.wipeAllData(context: context)
    }

    func preference(from preferences: [UserPreference], context: ModelContext) -> UserPreference {
        if let existing = preferences.first {
            return existing
        }
        let newPref = UserPreference()
        context.insert(newPref)
        try? context.save()
        return newPref
    }

    func save(context: ModelContext) {
        try? context.save()
    }

    func exportData(context: ModelContext) throws -> URL {
        let payload = ExportPayload(
            exportedAt: .now,
            budgetMonths: try context.fetch(FetchDescriptor<BudgetMonth>()).map(BudgetMonthDTO.init),
            categories: try context.fetch(FetchDescriptor<Category>()).map(CategoryDTO.init),
            plans: try context.fetch(FetchDescriptor<BudgetPlan>()).map(BudgetPlanDTO.init),
            transactions: try context.fetch(FetchDescriptor<Transaction>()).map(TransactionDTO.init),
            fixedItems: try context.fetch(FetchDescriptor<FixedItem>()).map(FixedItemDTO.init),
            fixedItemSkips: try context.fetch(FetchDescriptor<FixedItemSkip>()).map(FixedItemSkipDTO.init),
            accounts: try context.fetch(FetchDescriptor<Account>()).map(AccountDTO.init),
            buckets: try context.fetch(FetchDescriptor<InvestmentBucket>()).map(InvestmentBucketDTO.init),
            snapshots: try context.fetch(FetchDescriptor<InvestmentSnapshot>()).map(InvestmentSnapshotDTO.init),
            goals: try context.fetch(FetchDescriptor<Goal>()).map(GoalDTO.init),
            challenges: try context.fetch(FetchDescriptor<Challenge>()).map(ChallengeDTO.init),
            preferences: try context.fetch(FetchDescriptor<UserPreference>()).map(UserPreferenceDTO.init)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let name = "enkelt-budsjett-export-\(formatter.string(from: .now)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    func deleteAllData(context: ModelContext) throws {
        try DemoDataSeeder.wipeAllData(context: context)
    }
}

private struct ExportPayload: Codable {
    let exportedAt: Date
    let budgetMonths: [BudgetMonthDTO]
    let categories: [CategoryDTO]
    let plans: [BudgetPlanDTO]
    let transactions: [TransactionDTO]
    let fixedItems: [FixedItemDTO]
    let fixedItemSkips: [FixedItemSkipDTO]
    let accounts: [AccountDTO]
    let buckets: [InvestmentBucketDTO]
    let snapshots: [InvestmentSnapshotDTO]
    let goals: [GoalDTO]
    let challenges: [ChallengeDTO]
    let preferences: [UserPreferenceDTO]
}

private struct BudgetMonthDTO: Codable {
    let periodKey: String
    let year: Int
    let month: Int
    let startDate: Date
    let endDate: Date
    let isClosed: Bool
    init(_ model: BudgetMonth) {
        periodKey = model.periodKey
        year = model.year
        month = model.month
        startDate = model.startDate
        endDate = model.endDate
        isClosed = model.isClosed
    }
}

private struct CategoryDTO: Codable {
    let id: String
    let name: String
    let type: String
    let isActive: Bool
    let sortOrder: Int
    init(_ model: Category) {
        id = model.id
        name = model.name
        type = model.type.rawValue
        isActive = model.isActive
        sortOrder = model.sortOrder
    }
}

private struct BudgetPlanDTO: Codable {
    let uniqueKey: String
    let monthPeriodKey: String
    let categoryID: String
    let plannedAmount: Double
    init(_ model: BudgetPlan) {
        uniqueKey = model.uniqueKey
        monthPeriodKey = model.monthPeriodKey
        categoryID = model.categoryID
        plannedAmount = model.plannedAmount
    }
}

private struct TransactionDTO: Codable {
    let date: Date
    let amount: Double
    let kind: String
    let categoryID: String?
    let accountID: String?
    let note: String
    let recurringKey: String?
    let fixedItemID: String?
    @MainActor
    init(_ model: Transaction) {
        date = model.date
        amount = model.amount
        kind = model.kind.rawValue
        categoryID = model.categoryID
        accountID = model.accountID
        note = model.note
        recurringKey = model.recurringKey
        fixedItemID = model.fixedItemID
    }
}

private struct FixedItemDTO: Codable {
    let id: String
    let title: String
    let amount: Double
    let categoryID: String
    let kind: String
    let dayOfMonth: Int
    let startDate: Date
    let endDate: Date?
    let isActive: Bool
    let autoCreate: Bool
    let lastGeneratedPeriodKey: String?
    @MainActor
    init(_ model: FixedItem) {
        id = model.id
        title = model.title
        amount = model.amount
        categoryID = model.categoryID
        kind = model.kind.rawValue
        dayOfMonth = model.dayOfMonth
        startDate = model.startDate
        endDate = model.endDate
        isActive = model.isActive
        autoCreate = model.autoCreate
        lastGeneratedPeriodKey = model.lastGeneratedPeriodKey
    }
}

private struct FixedItemSkipDTO: Codable {
    let uniqueKey: String
    let fixedItemID: String
    let periodKey: String
    let createdAt: Date
    @MainActor
    init(_ model: FixedItemSkip) {
        uniqueKey = model.uniqueKey
        fixedItemID = model.fixedItemID
        periodKey = model.periodKey
        createdAt = model.createdAt
    }
}

private struct AccountDTO: Codable {
    let id: String
    let name: String
    let type: String
    let includeInNetWealth: Bool
    let currentBalance: Double
    init(_ model: Account) {
        id = model.id
        name = model.name
        type = model.type.rawValue
        includeInNetWealth = model.includeInNetWealth
        currentBalance = model.currentBalance
    }
}

private struct InvestmentBucketDTO: Codable {
    let id: String
    let name: String
    let colorHex: String?
    let isDefault: Bool
    let isActive: Bool
    let sortOrder: Int
    init(_ model: InvestmentBucket) {
        id = model.id
        name = model.name
        colorHex = model.colorHex
        isDefault = model.isDefault
        isActive = model.isActive
        sortOrder = model.sortOrder
    }
}

private struct InvestmentSnapshotDTO: Codable {
    let periodKey: String
    let capturedAt: Date
    let totalValue: Double
    let bucketValues: [InvestmentSnapshotValueDTO]
    @MainActor
    init(_ model: InvestmentSnapshot) {
        periodKey = model.periodKey
        capturedAt = model.capturedAt
        totalValue = model.totalValue
        bucketValues = model.bucketValues.map(InvestmentSnapshotValueDTO.init)
    }
}

private struct InvestmentSnapshotValueDTO: Codable {
    let periodKey: String
    let bucketID: String
    let amount: Double
    @MainActor
    init(_ model: InvestmentSnapshotValue) {
        periodKey = model.periodKey
        bucketID = model.bucketID
        amount = model.amount
    }
}

private struct GoalDTO: Codable {
    let targetAmount: Double
    let targetDate: Date
    let scope: String
    let includeAccounts: Bool
    let isActive: Bool
    let createdAt: Date
    init(_ model: Goal) {
        targetAmount = model.targetAmount
        targetDate = model.targetDate
        scope = model.scope.rawValue
        includeAccounts = model.includeAccounts
        isActive = model.isActive
        createdAt = model.createdAt
    }
}

private struct ChallengeDTO: Codable {
    let uniqueKey: String
    let type: String
    let startDate: Date
    let endDate: Date
    let targetAmount: Double?
    let targetDays: Int?
    let status: String
    let progress: Double
    let measurementMode: String
    let manualProgress: Double
    init(_ model: Challenge) {
        uniqueKey = model.uniqueKey
        type = model.type.rawValue
        startDate = model.startDate
        endDate = model.endDate
        targetAmount = model.targetAmount
        targetDays = model.targetDays
        status = model.status.rawValue
        progress = model.progress
        measurementMode = model.measurementMode.rawValue
        manualProgress = model.manualProgress
    }
}

private struct UserPreferenceDTO: Codable {
    let singletonKey: String
    let savingsDefinition: String
    let yearStartRule: String
    let checkInReminderEnabled: Bool
    let checkInReminderDay: Int
    let checkInReminderHour: Int
    let checkInReminderMinute: Int
    let defaultGraphView: String
    let faceIDLockEnabled: Bool
    let onboardingCompleted: Bool
    let onboardingCurrentStep: Int
    let onboardingFocus: String
    let toneStyle: String
    init(_ model: UserPreference) {
        singletonKey = model.singletonKey
        savingsDefinition = model.savingsDefinition.rawValue
        yearStartRule = model.yearStartRule
        checkInReminderEnabled = model.checkInReminderEnabled
        checkInReminderDay = model.checkInReminderDay
        checkInReminderHour = model.checkInReminderHour
        checkInReminderMinute = model.checkInReminderMinute
        defaultGraphView = model.defaultGraphView.rawValue
        faceIDLockEnabled = model.faceIDLockEnabled
        onboardingCompleted = model.onboardingCompleted
        onboardingCurrentStep = model.onboardingCurrentStep
        onboardingFocus = model.onboardingFocus.rawValue
        toneStyle = model.toneStyle.rawValue
    }
}
