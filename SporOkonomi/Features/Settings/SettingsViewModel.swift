import Foundation
import StoreKit
import SwiftData

enum DataImportMode {
    case merge
    case replace

    var title: String {
        switch self {
        case .merge:
            return "Slå sammen"
        case .replace:
            return "Erstatt alt"
        }
    }
}

struct DataImportReport {
    let mode: DataImportMode
    let budgetMonths: Int
    let categories: Int
    let plans: Int
    let groupPlans: Int
    let transactions: Int
    let fixedItems: Int
    let accounts: Int
    let buckets: Int
    let snapshots: Int
    let goals: Int
    let challenges: Int
    let preferences: Int
    let backupFileName: String?
}

enum DataTransferError: LocalizedError {
    case passwordRequiredForEncryptedImport
    case encryptedPayloadInvalid
    case encryptedPayloadWrongPassword
    case replaceFailedRollbackFailed

    var errorDescription: String? {
        switch self {
        case .passwordRequiredForEncryptedImport:
            return "Denne filen er kryptert og kan ikke importeres (eksporter på nytt uten kryptering)."
        case .encryptedPayloadInvalid:
            return "Filen kunne ikke leses som gyldig eksportformat."
        case .encryptedPayloadWrongPassword:
            return "Feil passord eller ugyldig kryptert fil."
        case .replaceFailedRollbackFailed:
            return "Import feilet, og automatisk gjenoppretting fra backup feilet også. Bruk backup-filen manuelt."
        }
    }
}

@Observable
@MainActor
final class SettingsViewModel {
    var preferencePersistenceErrorMessage: String?
    private var didResolveDemoToolsVisibility = false
    private(set) var showsDemoToolsOutsideDebug = false

    func shouldShowDemoTools() -> Bool {
#if DEBUG
        return true
#else
        return showsDemoToolsOutsideDebug
#endif
    }

    func refreshDemoToolVisibilityIfNeeded() async {
#if DEBUG
        return
#else
        guard !didResolveDemoToolsVisibility else { return }
        didResolveDemoToolsVisibility = true
        showsDemoToolsOutsideDebug = await isSandboxEnvironment()
#endif
    }

    func seedDemoRealisticYear(context: ModelContext, year: Int? = nil) throws -> DemoSeedReport {
        if PersistenceGate.isReadOnlyMode {
            throw PersistenceWriteError.readOnlyMode
        }
        let report = try DemoDataSeeder.seedRealisticYear(context: context, year: year)
        try ensureLocalAuthPreference(context: context)
        return report
    }

    func wipeAllDataForDemo(context: ModelContext) throws {
        if PersistenceGate.isReadOnlyMode {
            throw PersistenceWriteError.readOnlyMode
        }
        try DemoDataSeeder.wipeAllData(context: context)
        try BootstrapService.ensurePreference(context: context)
        try BootstrapService.ensureCurrentBudgetMonthAndRecurring(context: context)
        try ensureLocalAuthPreference(context: context)
    }

    func preference(from preferences: [UserPreference], context: ModelContext) -> UserPreference {
        if let existing = preferences.first {
            return existing
        }
        let newPref = UserPreference()
        context.insert(newPref)
        do {
            try context.guardedSave(
                feature: "Settings",
                operation: "create_default_preference",
                enforceReadOnly: false
            )
        } catch {
            preferencePersistenceErrorMessage = "Kunne ikke opprette standardinnstillinger."
        }
        return newPref
    }

    func clearPreferencePersistenceError() {
        preferencePersistenceErrorMessage = nil
    }

    func save(context: ModelContext) throws {
        if PersistenceGate.isReadOnlyMode {
            throw PersistenceWriteError.readOnlyMode
        }
        try context.guardedSave(feature: "Settings", operation: "save_preferences")
    }

    func syncCheckInReminder(preference: UserPreference) async throws {
        try await CheckInReminderService.syncFromPreference(preference)
    }

    func exportData(context: ModelContext) throws -> URL {
        let payload = try SettingsDataTransferService.makeExportPayload(context: context)
        return try SettingsDataTransferService.writePlainPayload(
            payload,
            filePrefix: "enkelt-budsjett-export"
        )
    }

    func deleteAllData(context: ModelContext) throws {
        if PersistenceGate.isReadOnlyMode {
            throw PersistenceWriteError.readOnlyMode
        }
        try DemoDataSeeder.wipeAllData(context: context)
        try BootstrapService.ensurePreference(context: context)
        try BootstrapService.ensureCurrentBudgetMonthAndRecurring(context: context)
        try ensureLocalAuthPreference(context: context)
    }

    private func ensureLocalAuthPreference(context: ModelContext) throws {
        let preferences = try context.fetch(FetchDescriptor<UserPreference>())
        guard let preference = preferences.first else { return }
        guard preference.authSessionModeRaw != AuthSessionMode.local.rawValue else { return }
        preference.authSessionModeRaw = AuthSessionMode.local.rawValue
        preference.authProviderRaw = nil
        preference.authUserID = nil
        preference.authEmail = nil
        preference.authDisplayName = nil
        try context.guardedSave(feature: "Settings", operation: "normalize_demo_auth", enforceReadOnly: false)
    }

    func importData(
        from url: URL,
        mode: DataImportMode,
        context: ModelContext,
        password: String?
    ) throws -> DataImportReport {
        if PersistenceGate.isReadOnlyMode {
            throw PersistenceWriteError.readOnlyMode
        }
        let data = try Data(contentsOf: url)
        let payload = try SettingsDataTransferService.decodeImportPayload(from: data, password: password)
        try preflightImport(payload: payload)

        var backupFileName: String?
        var backupPayloadForRollback: ExportPayload?
        if mode == .replace {
            let backupPayload = try SettingsDataTransferService.makeExportPayload(context: context)
            backupPayloadForRollback = backupPayload
            let backupURL = try SettingsDataTransferService.writePlainPayload(
                backupPayload,
                filePrefix: "enkelt-budsjett-auto-backup"
            )
            backupFileName = backupURL.lastPathComponent
            try DemoDataSeeder.wipeAllData(context: context)
        }

        do {
            try applyImportPayload(payload, context: context)
            try context.guardedSave(feature: "Import", operation: "commit_import")
        } catch {
            if mode == .replace, let backupPayloadForRollback {
                do {
                    try DemoDataSeeder.wipeAllData(context: context)
                    try applyImportPayload(backupPayloadForRollback, context: context)
                    try context.guardedSave(feature: "Import", operation: "rollback_restore")
                } catch {
                    throw DataTransferError.replaceFailedRollbackFailed
                }
            }
            throw error
        }

        return DataImportReport(
            mode: mode,
            budgetMonths: payload.budgetMonths.count,
            categories: payload.categories.count,
            plans: payload.plans.count,
            groupPlans: payload.groupPlans.count,
            transactions: payload.transactions.count,
            fixedItems: payload.fixedItems.count,
            accounts: payload.accounts.count,
            buckets: payload.buckets.count,
            snapshots: payload.snapshots.count,
            goals: payload.goals.count,
            challenges: payload.challenges.count,
            preferences: payload.preferences.count,
            backupFileName: backupFileName
        )
    }

    private func applyImportPayload(_ payload: ExportPayload, context: ModelContext) throws {
        try upsertBudgetMonths(payload.budgetMonths, context: context)
        try upsertCategories(payload.categories, context: context)
        try upsertBudgetPlans(payload.plans, context: context)
        try upsertBudgetGroupPlans(payload.groupPlans, context: context)
        try upsertAccounts(payload.accounts, context: context)
        try upsertBuckets(payload.buckets, context: context)
        try upsertSnapshots(payload.snapshots, context: context)
        try upsertFixedItems(payload.fixedItems, context: context)
        try upsertFixedItemSkips(payload.fixedItemSkips, context: context)
        try mergeTransactions(payload.transactions, context: context)
        try mergeGoals(payload.goals, context: context)
        try upsertChallenges(payload.challenges, context: context)
        try upsertPreferences(payload.preferences, context: context)
        try BootstrapService.ensurePreference(context: context)
        try BootstrapService.ensureCurrentBudgetMonthAndRecurring(context: context)
    }

    private func preflightImport(payload: ExportPayload) throws {
        let schema = Schema([
            BudgetMonth.self,
            Category.self,
            BudgetPlan.self,
            BudgetGroupPlan.self,
            Transaction.self,
            Account.self,
            InvestmentBucket.self,
            InvestmentSnapshot.self,
            FixedItem.self,
            FixedItemSkip.self,
            Goal.self,
            Challenge.self,
            UserPreference.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        try applyImportPayload(payload, context: context)
        try context.guardedSave(
            feature: "Import",
            operation: "preflight_validation",
            enforceReadOnly: false
        )
    }

    private func upsertBudgetMonths(_ rows: [BudgetMonthDTO], context: ModelContext) throws {
        var existingByKey = Dictionary(
            try context.fetch(FetchDescriptor<BudgetMonth>()).map { ($0.periodKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for row in rows {
            if let existing = existingByKey[row.periodKey] {
                existing.year = row.year
                existing.month = row.month
                existing.startDate = row.startDate
                existing.endDate = row.endDate
                existing.isClosed = row.isClosed
            } else {
                let month = BudgetMonth(
                    periodKey: row.periodKey,
                    year: row.year,
                    month: row.month,
                    startDate: row.startDate,
                    endDate: row.endDate,
                    isClosed: row.isClosed
                )
                context.insert(month)
                existingByKey[row.periodKey] = month
            }
        }
    }

    private func upsertCategories(_ rows: [CategoryDTO], context: ModelContext) throws {
        var existingByID = Dictionary(
            try context.fetch(FetchDescriptor<Category>()).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for row in rows {
            if let existing = existingByID[row.id] {
                existing.name = row.name
                existing.type = CategoryType(rawValue: row.type) ?? .expense
                existing.groupKey = row.groupKey
                existing.isActive = row.isActive
                existing.sortOrder = row.sortOrder
            } else {
                let category = Category(
                    id: row.id,
                    name: row.name,
                    type: CategoryType(rawValue: row.type) ?? .expense,
                    groupKey: row.groupKey,
                    isActive: row.isActive,
                    sortOrder: row.sortOrder
                )
                context.insert(category)
                existingByID[row.id] = category
            }
        }
    }

    private func upsertBudgetPlans(_ rows: [BudgetPlanDTO], context: ModelContext) throws {
        var existingByKey = Dictionary(
            try context.fetch(FetchDescriptor<BudgetPlan>()).map { ($0.uniqueKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for row in rows {
            if let existing = existingByKey[row.uniqueKey] {
                existing.monthPeriodKey = row.monthPeriodKey
                existing.categoryID = row.categoryID
                existing.plannedAmount = row.plannedAmount
            } else {
                let plan = BudgetPlan(
                    monthPeriodKey: row.monthPeriodKey,
                    categoryID: row.categoryID,
                    plannedAmount: row.plannedAmount
                )
                context.insert(plan)
                existingByKey[row.uniqueKey] = plan
            }
        }
    }

    private func upsertBudgetGroupPlans(_ rows: [BudgetGroupPlanDTO], context: ModelContext) throws {
        var existingByKey = Dictionary(
            try context.fetch(FetchDescriptor<BudgetGroupPlan>()).map { ($0.uniqueKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for row in rows {
            if let existing = existingByKey[row.uniqueKey] {
                existing.monthPeriodKey = row.monthPeriodKey
                existing.groupKey = row.groupKey
                existing.plannedAmount = row.plannedAmount
            } else {
                let plan = BudgetGroupPlan(
                    monthPeriodKey: row.monthPeriodKey,
                    groupKey: row.groupKey,
                    plannedAmount: row.plannedAmount
                )
                context.insert(plan)
                existingByKey[row.uniqueKey] = plan
            }
        }
    }

    private func upsertAccounts(_ rows: [AccountDTO], context: ModelContext) throws {
        var existingByID = Dictionary(
            try context.fetch(FetchDescriptor<Account>()).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for row in rows {
            if let existing = existingByID[row.id] {
                existing.name = row.name
                existing.type = AccountType(rawValue: row.type) ?? .checking
                existing.includeInNetWealth = row.includeInNetWealth
                existing.currentBalance = row.currentBalance
            } else {
                let account = Account(
                    id: row.id,
                    name: row.name,
                    type: AccountType(rawValue: row.type) ?? .checking,
                    includeInNetWealth: row.includeInNetWealth,
                    currentBalance: row.currentBalance
                )
                context.insert(account)
                existingByID[row.id] = account
            }
        }
    }

    private func upsertBuckets(_ rows: [InvestmentBucketDTO], context: ModelContext) throws {
        var existingByID = Dictionary(
            try context.fetch(FetchDescriptor<InvestmentBucket>()).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for row in rows {
            if let existing = existingByID[row.id] {
                existing.name = row.name
                existing.colorHex = row.colorHex
                existing.isDefault = row.isDefault
                existing.isActive = row.isActive
                existing.sortOrder = row.sortOrder
            } else {
                let bucket = InvestmentBucket(
                    id: row.id,
                    name: row.name,
                    colorHex: row.colorHex,
                    isDefault: row.isDefault,
                    isActive: row.isActive,
                    sortOrder: row.sortOrder
                )
                context.insert(bucket)
                existingByID[row.id] = bucket
            }
        }
    }

    private func upsertSnapshots(_ rows: [InvestmentSnapshotDTO], context: ModelContext) throws {
        var existingByKey = Dictionary(
            try context.fetch(FetchDescriptor<InvestmentSnapshot>()).map { ($0.periodKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for row in rows {
            let values = row.bucketValues.map {
                InvestmentSnapshotValue(periodKey: row.periodKey, bucketID: $0.bucketID, amount: $0.amount)
            }
            if let existing = existingByKey[row.periodKey] {
                existing.capturedAt = row.capturedAt
                existing.totalValue = row.totalValue
                existing.bucketValues = values
            } else {
                let snapshot = InvestmentSnapshot(
                    periodKey: row.periodKey,
                    capturedAt: row.capturedAt,
                    totalValue: row.totalValue,
                    bucketValues: values
                )
                context.insert(snapshot)
                existingByKey[row.periodKey] = snapshot
            }
        }
    }

    private func upsertFixedItems(_ rows: [FixedItemDTO], context: ModelContext) throws {
        var existingByID = Dictionary(
            try context.fetch(FetchDescriptor<FixedItem>()).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for row in rows {
            if let existing = existingByID[row.id] {
                existing.title = row.title
                existing.amount = row.amount
                existing.categoryID = row.categoryID
                existing.kind = TransactionKind(rawValue: row.kind) ?? .expense
                existing.dayOfMonth = row.dayOfMonth
                existing.startDate = row.startDate
                existing.endDate = row.endDate
                existing.isActive = row.isActive
                existing.autoCreate = row.autoCreate
                existing.lastGeneratedPeriodKey = row.lastGeneratedPeriodKey
            } else {
                let item = FixedItem(
                    id: row.id,
                    title: row.title,
                    amount: row.amount,
                    categoryID: row.categoryID,
                    kind: TransactionKind(rawValue: row.kind) ?? .expense,
                    dayOfMonth: row.dayOfMonth,
                    startDate: row.startDate,
                    endDate: row.endDate,
                    isActive: row.isActive,
                    autoCreate: row.autoCreate,
                    lastGeneratedPeriodKey: row.lastGeneratedPeriodKey
                )
                context.insert(item)
                existingByID[row.id] = item
            }
        }
    }

    private func upsertFixedItemSkips(_ rows: [FixedItemSkipDTO], context: ModelContext) throws {
        var existingByKey = Dictionary(
            try context.fetch(FetchDescriptor<FixedItemSkip>()).map { ($0.uniqueKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for row in rows {
            if let existing = existingByKey[row.uniqueKey] {
                existing.fixedItemID = row.fixedItemID
                existing.periodKey = row.periodKey
                existing.createdAt = row.createdAt
            } else {
                let skip = FixedItemSkip(
                    fixedItemID: row.fixedItemID,
                    periodKey: row.periodKey,
                    createdAt: row.createdAt
                )
                context.insert(skip)
                existingByKey[row.uniqueKey] = skip
            }
        }
    }

    private func mergeTransactions(_ rows: [TransactionDTO], context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<Transaction>())
        var fingerprints = Set(existing.map(transactionFingerprint))
        for row in rows {
            let fingerprint = transactionFingerprint(row)
            if fingerprints.contains(fingerprint) { continue }
            context.insert(
                Transaction(
                    date: row.date,
                    amount: row.amount,
                    kind: TransactionKind(rawValue: row.kind) ?? .expense,
                    categoryID: row.categoryID,
                    accountID: row.accountID,
                    note: row.note,
                    recurringKey: row.recurringKey,
                    fixedItemID: row.fixedItemID
                )
            )
            fingerprints.insert(fingerprint)
        }
    }

    private func mergeGoals(_ rows: [GoalDTO], context: ModelContext) throws {
        var existing = try context.fetch(FetchDescriptor<Goal>())
        var fingerprints = Set(existing.map(goalFingerprint))
        for row in rows {
            if row.isActive {
                let fingerprint = goalFingerprint(row)
                let targetGoal = existing.first(where: { goalFingerprint($0) == fingerprint })
                    ?? existing.first(where: \.isActive)

                if let targetGoal {
                    targetGoal.targetAmount = row.targetAmount
                    targetGoal.targetDate = row.targetDate
                    targetGoal.scope = GoalScope(rawValue: row.scope) ?? .wealth
                    targetGoal.includeAccounts = row.includeAccounts
                    targetGoal.isActive = true
                    targetGoal.createdAt = row.createdAt

                    for goal in existing where goal.persistentModelID != targetGoal.persistentModelID && goal.isActive {
                        goal.isActive = false
                    }

                    fingerprints = Set(existing.map(goalFingerprint))
                    continue
                }
            }

            let fingerprint = goalFingerprint(row)
            if fingerprints.contains(fingerprint) { continue }

            let goal = Goal(
                targetAmount: row.targetAmount,
                targetDate: row.targetDate,
                scope: GoalScope(rawValue: row.scope) ?? .wealth,
                includeAccounts: row.includeAccounts,
                isActive: row.isActive,
                createdAt: row.createdAt
            )
            context.insert(goal)
            existing.append(goal)
            fingerprints.insert(fingerprint)
        }
    }

    private func upsertChallenges(_ rows: [ChallengeDTO], context: ModelContext) throws {
        var existingByKey = Dictionary(
            try context.fetch(FetchDescriptor<Challenge>()).map { ($0.uniqueKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for row in rows {
            if let existing = existingByKey[row.uniqueKey] {
                existing.type = ChallengeType(rawValue: row.type) ?? .save1000In30Days
                existing.startDate = row.startDate
                existing.endDate = row.endDate
                existing.targetAmount = row.targetAmount
                existing.targetDays = row.targetDays
                existing.status = ChallengeStatus(rawValue: row.status) ?? .active
                existing.progress = row.progress
                existing.measurementMode = ChallengeMeasurementMode(rawValue: row.measurementMode) ?? .manualCheckin
                existing.manualProgress = row.manualProgress
            } else {
                let challenge = Challenge(
                    type: ChallengeType(rawValue: row.type) ?? .save1000In30Days,
                    startDate: row.startDate,
                    endDate: row.endDate,
                    targetAmount: row.targetAmount,
                    targetDays: row.targetDays,
                    status: ChallengeStatus(rawValue: row.status) ?? .active,
                    progress: row.progress,
                    measurementMode: ChallengeMeasurementMode(rawValue: row.measurementMode) ?? .manualCheckin,
                    manualProgress: row.manualProgress
                )
                context.insert(challenge)
                existingByKey[row.uniqueKey] = challenge
            }
        }
    }

    private func upsertPreferences(_ rows: [UserPreferenceDTO], context: ModelContext) throws {
        var existingByKey = Dictionary(
            try context.fetch(FetchDescriptor<UserPreference>()).map { ($0.singletonKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for row in rows {
            if let existing = existingByKey[row.singletonKey] {
                applyPreference(row, to: existing)
            } else {
                let preference = UserPreference(singletonKey: row.singletonKey)
                applyPreference(row, to: preference)
                context.insert(preference)
                existingByKey[row.singletonKey] = preference
            }
        }
    }

    private func applyPreference(_ row: UserPreferenceDTO, to preference: UserPreference) {
        preference.firstName = row.firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        preference.savingsDefinition = SavingsDefinition(rawValue: row.savingsDefinition) ?? .incomeMinusExpense
        preference.yearStartRule = row.yearStartRule
        preference.checkInReminderEnabled = row.checkInReminderEnabled
        preference.checkInReminderDay = max(1, min(28, row.checkInReminderDay))
        preference.checkInReminderHour = max(0, min(23, row.checkInReminderHour))
        preference.checkInReminderMinute = max(0, min(59, row.checkInReminderMinute))
        preference.defaultGraphView = GraphViewRange(rawValue: row.defaultGraphView) ?? .yearToDate
        preference.faceIDLockEnabled = row.faceIDLockEnabled
        preference.onboardingCompleted = row.onboardingCompleted
        preference.onboardingCurrentStep = row.onboardingCurrentStep
        preference.onboardingFocus = OnboardingFocus(rawValue: row.onboardingFocus) ?? .both
        preference.toneStyle = AppToneStyle(rawValue: row.toneStyle) ?? .warm
    }

    private func transactionFingerprint(_ transaction: Transaction) -> String {
        transactionFingerprint(
            date: transaction.date,
            amount: transaction.amount,
            kind: transaction.kind.rawValue,
            categoryID: transaction.categoryID,
            accountID: transaction.accountID,
            note: transaction.note,
            recurringKey: transaction.recurringKey,
            fixedItemID: transaction.fixedItemID
        )
    }

    private func transactionFingerprint(_ transaction: TransactionDTO) -> String {
        transactionFingerprint(
            date: transaction.date,
            amount: transaction.amount,
            kind: transaction.kind,
            categoryID: transaction.categoryID,
            accountID: transaction.accountID,
            note: transaction.note,
            recurringKey: transaction.recurringKey,
            fixedItemID: transaction.fixedItemID
        )
    }

    private func transactionFingerprint(
        date: Date,
        amount: Double,
        kind: String,
        categoryID: String?,
        accountID: String?,
        note: String,
        recurringKey: String?,
        fixedItemID: String?
    ) -> String {
        let roundedAmount = (amount * 100).rounded() / 100
        return [
            "\(date.timeIntervalSince1970)",
            "\(roundedAmount)",
            kind,
            categoryID ?? "",
            accountID ?? "",
            note,
            recurringKey ?? "",
            fixedItemID ?? ""
        ].joined(separator: "|")
    }

    private func goalFingerprint(_ goal: Goal) -> String {
        goalFingerprint(
            targetAmount: goal.targetAmount,
            targetDate: goal.targetDate,
            scope: goal.scope.rawValue,
            includeAccounts: goal.includeAccounts,
            isActive: goal.isActive,
            createdAt: goal.createdAt
        )
    }

    private func goalFingerprint(_ goal: GoalDTO) -> String {
        goalFingerprint(
            targetAmount: goal.targetAmount,
            targetDate: goal.targetDate,
            scope: goal.scope,
            includeAccounts: goal.includeAccounts,
            isActive: goal.isActive,
            createdAt: goal.createdAt
        )
    }

    private func goalFingerprint(
        targetAmount: Double,
        targetDate: Date,
        scope: String,
        includeAccounts: Bool,
        isActive: Bool,
        createdAt: Date
    ) -> String {
        [
            "\((targetAmount * 100).rounded() / 100)",
            "\(targetDate.timeIntervalSince1970)",
            scope,
            includeAccounts ? "1" : "0",
            isActive ? "1" : "0",
            "\(createdAt.timeIntervalSince1970)"
        ].joined(separator: "|")
    }

    private func isSandboxEnvironment() async -> Bool {
        guard #available(iOS 16.0, *) else { return false }

        do {
            let verificationResult = try await AppTransaction.shared
            switch verificationResult {
            case .verified(let appTransaction), .unverified(let appTransaction, _):
                return appTransaction.environment == .sandbox
            }
        } catch {
            return false
        }
    }
}
