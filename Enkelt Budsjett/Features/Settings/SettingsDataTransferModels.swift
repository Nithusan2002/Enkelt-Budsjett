import Foundation

struct ExportPayload: Codable {
    let exportedAt: Date
    let budgetMonths: [BudgetMonthDTO]
    let categories: [CategoryDTO]
    let plans: [BudgetPlanDTO]
    let groupPlans: [BudgetGroupPlanDTO]
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

struct EncryptedExportEnvelope: Codable {
    let format: String
    let exportedAt: Date
    let saltBase64: String
    let sealedBoxBase64: String
}

struct BudgetMonthDTO: Codable {
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

struct CategoryDTO: Codable {
    let id: String
    let name: String
    let type: String
    let groupKey: String
    let isActive: Bool
    let sortOrder: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case groupKey
        case isActive
        case sortOrder
    }

    init(_ model: Category) {
        id = model.id
        name = model.name
        type = model.type.rawValue
        groupKey = model.groupKey
        isActive = model.isActive
        sortOrder = model.sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)

        if let value = try container.decodeIfPresent(String.self, forKey: .groupKey) {
            groupKey = value
        } else {
            let resolvedType = CategoryType(rawValue: type) ?? .expense
            groupKey = Category.defaultGroupKey(forName: name, type: resolvedType)
        }
    }
}

struct BudgetPlanDTO: Codable {
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

struct BudgetGroupPlanDTO: Codable {
    let uniqueKey: String
    let monthPeriodKey: String
    let groupKey: String
    let plannedAmount: Double

    init(_ model: BudgetGroupPlan) {
        uniqueKey = model.uniqueKey
        monthPeriodKey = model.monthPeriodKey
        groupKey = model.groupKey
        plannedAmount = model.plannedAmount
    }
}

struct TransactionDTO: Codable {
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

struct FixedItemDTO: Codable {
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

struct FixedItemSkipDTO: Codable {
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

struct AccountDTO: Codable {
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

struct InvestmentBucketDTO: Codable {
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

struct InvestmentSnapshotDTO: Codable {
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

struct InvestmentSnapshotValueDTO: Codable {
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

struct GoalDTO: Codable {
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

struct ChallengeDTO: Codable {
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

struct UserPreferenceDTO: Codable {
    let singletonKey: String
    let firstName: String?
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
        firstName = model.firstName
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
