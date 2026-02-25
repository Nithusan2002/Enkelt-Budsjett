import Foundation
import SwiftData

enum CategoryType: String, Codable, CaseIterable {
    case expense
    case income
    case savings
}

enum TransactionKind: String, Codable, CaseIterable {
    case expense
    case income
    case refund
    case transfer
    case manualSaving
}

enum AccountType: String, Codable, CaseIterable {
    case checking
    case savings
    case cash
}

enum SavingsDefinition: String, Codable, CaseIterable {
    case incomeMinusExpense
    case savingsCategoryOnly
}

enum GraphViewRange: String, Codable, CaseIterable {
    case yearToDate
    case oneYear
    case twoYears
    case threeYears
    case fiveYears
    case max
    // Legacy value used in existing local stores.
    case last12Months
}

enum ChallengeType: String, Codable, CaseIterable {
    case noCoffeeWeek
    case save1000In30Days
    case roundUpManual
    case foodBudgetWeek
}

enum ChallengeStatus: String, Codable, CaseIterable {
    case active
    case paused
    case completed
    case cancelled
}

enum ChallengeMeasurementMode: String, Codable, CaseIterable {
    case savingsDefinition
    case savingsCategory
    case manualRoundUp
    case manualCheckin
}

enum GoalScope: String, Codable, CaseIterable {
    case wealth
}

enum OnboardingFocus: String, Codable, CaseIterable {
    case budget
    case investments
    case both
}

enum AppToneStyle: String, Codable, CaseIterable {
    case calm
    case warm
    case nudges
}

@Model
final class BudgetMonth {
    @Attribute(.unique) var periodKey: String
    var year: Int
    var month: Int
    var startDate: Date
    var endDate: Date
    var isClosed: Bool

    init(periodKey: String, year: Int, month: Int, startDate: Date, endDate: Date, isClosed: Bool = false) {
        self.periodKey = periodKey
        self.year = year
        self.month = month
        self.startDate = startDate
        self.endDate = endDate
        self.isClosed = isClosed
    }
}

@Model
final class Category {
    @Attribute(.unique) var id: String
    var name: String
    var type: CategoryType
    var isActive: Bool
    var sortOrder: Int

    init(id: String = UUID().uuidString, name: String, type: CategoryType, isActive: Bool = true, sortOrder: Int) {
        self.id = id
        self.name = name
        self.type = type
        self.isActive = isActive
        self.sortOrder = sortOrder
    }
}

@Model
final class BudgetPlan {
    @Attribute(.unique) var uniqueKey: String
    var monthPeriodKey: String
    var categoryID: String
    var plannedAmount: Double

    init(monthPeriodKey: String, categoryID: String, plannedAmount: Double) {
        self.monthPeriodKey = monthPeriodKey
        self.categoryID = categoryID
        self.plannedAmount = plannedAmount
        self.uniqueKey = "\(monthPeriodKey)|\(categoryID)"
    }
}

@Model
final class Transaction {
    var date: Date
    var amount: Double
    var kind: TransactionKind
    var categoryID: String?
    var accountID: String?
    var note: String
    var recurringKey: String?
    var fixedItemID: String?

    init(
        date: Date,
        amount: Double,
        kind: TransactionKind,
        categoryID: String? = nil,
        accountID: String? = nil,
        note: String = "",
        recurringKey: String? = nil,
        fixedItemID: String? = nil
    ) {
        self.date = date
        self.amount = amount
        self.kind = kind
        self.categoryID = categoryID
        self.accountID = accountID
        self.note = note
        self.recurringKey = recurringKey
        self.fixedItemID = fixedItemID
    }
}

@Model
final class FixedItem {
    @Attribute(.unique) var id: String
    var title: String
    var amount: Double
    var categoryID: String
    var kind: TransactionKind
    var dayOfMonth: Int
    var startDate: Date
    var endDate: Date?
    var isActive: Bool
    var autoCreate: Bool
    var lastGeneratedPeriodKey: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        amount: Double,
        categoryID: String,
        kind: TransactionKind = .expense,
        dayOfMonth: Int,
        startDate: Date = .now,
        endDate: Date? = nil,
        isActive: Bool = true,
        autoCreate: Bool = true,
        lastGeneratedPeriodKey: String? = nil
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.categoryID = categoryID
        self.kind = kind
        self.dayOfMonth = dayOfMonth
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
        self.autoCreate = autoCreate
        self.lastGeneratedPeriodKey = lastGeneratedPeriodKey
    }
}

@Model
final class FixedItemSkip {
    @Attribute(.unique) var uniqueKey: String
    var fixedItemID: String
    var periodKey: String
    var createdAt: Date

    init(fixedItemID: String, periodKey: String, createdAt: Date = .now) {
        self.fixedItemID = fixedItemID
        self.periodKey = periodKey
        self.createdAt = createdAt
        self.uniqueKey = "\(fixedItemID)|\(periodKey)"
    }
}

@Model
final class Account {
    @Attribute(.unique) var id: String
    var name: String
    var type: AccountType
    var includeInNetWealth: Bool
    var currentBalance: Double

    init(id: String = UUID().uuidString, name: String, type: AccountType, includeInNetWealth: Bool = true, currentBalance: Double = 0) {
        self.id = id
        self.name = name
        self.type = type
        self.includeInNetWealth = includeInNetWealth
        self.currentBalance = currentBalance
    }
}

@Model
final class InvestmentBucket {
    @Attribute(.unique) var id: String
    var name: String
    var colorHex: String?
    var isDefault: Bool
    var isActive: Bool
    var sortOrder: Int

    init(
        id: String = UUID().uuidString,
        name: String,
        colorHex: String? = nil,
        isDefault: Bool = false,
        isActive: Bool = true,
        sortOrder: Int
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isDefault = isDefault
        self.isActive = isActive
        self.sortOrder = sortOrder
    }
}

@Model
final class InvestmentSnapshot {
    @Attribute(.unique) var periodKey: String
    var capturedAt: Date
    var totalValue: Double
    @Relationship(deleteRule: .cascade) var bucketValues: [InvestmentSnapshotValue]

    init(periodKey: String, capturedAt: Date, totalValue: Double, bucketValues: [InvestmentSnapshotValue] = []) {
        self.periodKey = periodKey
        self.capturedAt = capturedAt
        self.totalValue = totalValue
        self.bucketValues = bucketValues
    }
}

@Model
final class InvestmentSnapshotValue {
    var periodKey: String
    var bucketID: String
    var amount: Double

    init(periodKey: String, bucketID: String, amount: Double) {
        self.periodKey = periodKey
        self.bucketID = bucketID
        self.amount = amount
    }
}

@Model
final class Goal {
    var targetAmount: Double
    var targetDate: Date
    var scope: GoalScope
    var includeAccounts: Bool
    var isActive: Bool
    var createdAt: Date

    init(targetAmount: Double, targetDate: Date, scope: GoalScope = .wealth, includeAccounts: Bool = true, isActive: Bool = true, createdAt: Date = .now) {
        self.targetAmount = targetAmount
        self.targetDate = targetDate
        self.scope = scope
        self.includeAccounts = includeAccounts
        self.isActive = isActive
        self.createdAt = createdAt
    }
}

@Model
final class Challenge {
    @Attribute(.unique) var uniqueKey: String
    var type: ChallengeType
    var startDate: Date
    var endDate: Date
    var targetAmount: Double?
    var targetDays: Int?
    var status: ChallengeStatus
    var progress: Double
    var measurementMode: ChallengeMeasurementMode
    var manualProgress: Double

    init(
        type: ChallengeType,
        startDate: Date,
        endDate: Date,
        targetAmount: Double? = nil,
        targetDays: Int? = nil,
        status: ChallengeStatus = .active,
        progress: Double = 0,
        measurementMode: ChallengeMeasurementMode = .manualCheckin,
        manualProgress: Double = 0
    ) {
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.targetAmount = targetAmount
        self.targetDays = targetDays
        self.status = status
        self.progress = progress
        self.measurementMode = measurementMode
        self.manualProgress = manualProgress
        self.uniqueKey = "\(type.rawValue)|\(startDate.timeIntervalSince1970)"
    }
}

@Model
final class UserPreference {
    @Attribute(.unique) var singletonKey: String
    var savingsDefinition: SavingsDefinition
    var yearStartRule: String
    var checkInReminderEnabled: Bool
    var checkInReminderDay: Int
    var checkInReminderHour: Int
    var checkInReminderMinute: Int
    var defaultGraphView: GraphViewRange
    var faceIDLockEnabled: Bool
    var onboardingCompleted: Bool
    var onboardingCurrentStep: Int
    var onboardingFocus: OnboardingFocus
    var toneStyle: AppToneStyle

    init(
        singletonKey: String = "main",
        savingsDefinition: SavingsDefinition = .incomeMinusExpense,
        yearStartRule: String = "calendarYear",
        checkInReminderEnabled: Bool = true,
        checkInReminderDay: Int = 5,
        checkInReminderHour: Int = 19,
        checkInReminderMinute: Int = 0,
        defaultGraphView: GraphViewRange = .yearToDate,
        faceIDLockEnabled: Bool = false,
        onboardingCompleted: Bool = false,
        onboardingCurrentStep: Int = 0,
        onboardingFocus: OnboardingFocus = .both,
        toneStyle: AppToneStyle = .warm
    ) {
        self.singletonKey = singletonKey
        self.savingsDefinition = savingsDefinition
        self.yearStartRule = yearStartRule
        self.checkInReminderEnabled = checkInReminderEnabled
        self.checkInReminderDay = checkInReminderDay
        self.checkInReminderHour = checkInReminderHour
        self.checkInReminderMinute = checkInReminderMinute
        self.defaultGraphView = defaultGraphView
        self.faceIDLockEnabled = faceIDLockEnabled
        self.onboardingCompleted = onboardingCompleted
        self.onboardingCurrentStep = onboardingCurrentStep
        self.onboardingFocus = onboardingFocus
        self.toneStyle = toneStyle
    }
}
