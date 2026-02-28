import Foundation
import Combine
import SwiftData
import CryptoKit

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
    case passwordTooShort
    case passwordRequiredForEncryptedImport
    case passwordRequiredForReplaceBackup
    case encryptedPayloadInvalid
    case encryptedPayloadWrongPassword
    case replaceFailedRollbackFailed

    var errorDescription: String? {
        switch self {
        case .passwordTooShort:
            return "Velg et passord med minst 8 tegn."
        case .passwordRequiredForEncryptedImport:
            return "Denne filen er kryptert. Skriv inn passord for å importere."
        case .passwordRequiredForReplaceBackup:
            return "Erstatt alt krever passord for automatisk kryptert backup."
        case .encryptedPayloadInvalid:
            return "Filen kunne ikke leses som gyldig eksportformat."
        case .encryptedPayloadWrongPassword:
            return "Feil passord eller ugyldig kryptert fil."
        case .replaceFailedRollbackFailed:
            return "Import feilet, og automatisk gjenoppretting fra backup feilet også. Bruk backup-filen manuelt."
        }
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var preferencePersistenceErrorMessage: String?

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
        if PersistenceGate.isReadOnlyMode {
            throw PersistenceWriteError.readOnlyMode
        }
        return try DemoDataSeeder.seedRealisticYear(context: context, year: year)
    }

    func wipeAllDataForDemo(context: ModelContext) throws {
        if PersistenceGate.isReadOnlyMode {
            throw PersistenceWriteError.readOnlyMode
        }
        try DemoDataSeeder.wipeAllData(context: context)
        try BootstrapService.ensurePreference(context: context)
        try BootstrapService.ensureCurrentBudgetMonthAndRecurring(context: context)
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

    func exportData(context: ModelContext, password: String) throws -> URL {
        guard password.count >= 8 else {
            throw DataTransferError.passwordTooShort
        }
        let payload = try makeExportPayload(context: context)
        return try writeEncryptedPayload(payload, password: password, filePrefix: "enkelt-budsjett-export")
    }

    private func makeExportPayload(context: ModelContext) throws -> ExportPayload {
        ExportPayload(
            exportedAt: .now,
            budgetMonths: try context.fetch(FetchDescriptor<BudgetMonth>()).map(BudgetMonthDTO.init),
            categories: try context.fetch(FetchDescriptor<Category>()).map(CategoryDTO.init),
            plans: try context.fetch(FetchDescriptor<BudgetPlan>()).map(BudgetPlanDTO.init),
            groupPlans: try context.fetch(FetchDescriptor<BudgetGroupPlan>()).map(BudgetGroupPlanDTO.init),
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
    }

    func deleteAllData(context: ModelContext) throws {
        if PersistenceGate.isReadOnlyMode {
            throw PersistenceWriteError.readOnlyMode
        }
        try DemoDataSeeder.wipeAllData(context: context)
        try BootstrapService.ensurePreference(context: context)
        try BootstrapService.ensureCurrentBudgetMonthAndRecurring(context: context)
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
        let payload = try decodeImportPayload(from: data, password: password)
        try preflightImport(payload: payload)

        var backupFileName: String?
        var backupPayloadForRollback: ExportPayload?
        if mode == .replace {
            guard let password, password.count >= 8 else {
                throw DataTransferError.passwordRequiredForReplaceBackup
            }
            let backupPayload = try makeExportPayload(context: context)
            backupPayloadForRollback = backupPayload
            let backupURL = try writeEncryptedPayload(
                backupPayload,
                password: password,
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

    private func decodeImportPayload(from data: Data, password: String?) throws -> ExportPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let plain = try? decoder.decode(ExportPayload.self, from: data) {
            return plain
        }

        guard let envelope = try? decoder.decode(EncryptedExportEnvelope.self, from: data) else {
            throw DataTransferError.encryptedPayloadInvalid
        }
        guard envelope.format == "enkelt-budsjett-export-encrypted-v1" else {
            throw DataTransferError.encryptedPayloadInvalid
        }
        guard let password, !password.isEmpty else {
            throw DataTransferError.passwordRequiredForEncryptedImport
        }

        do {
            guard let salt = Data(base64Encoded: envelope.saltBase64),
                  let sealedCombined = Data(base64Encoded: envelope.sealedBoxBase64) else {
                throw DataTransferError.encryptedPayloadInvalid
            }
            let key = deriveKey(password: password, salt: salt)
            let box = try AES.GCM.SealedBox(combined: sealedCombined)
            let decrypted = try AES.GCM.open(box, using: key)
            return try decoder.decode(ExportPayload.self, from: decrypted)
        } catch let error as DataTransferError {
            throw error
        } catch {
            throw DataTransferError.encryptedPayloadWrongPassword
        }
    }

    private func writeEncryptedPayload(
        _ payload: ExportPayload,
        password: String,
        filePrefix: String
    ) throws -> URL {
        guard password.count >= 8 else {
            throw DataTransferError.passwordTooShort
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let plainData = try encoder.encode(payload)
        let salt = randomBytes(count: 16)
        let key = deriveKey(password: password, salt: salt)
        let sealed = try AES.GCM.seal(plainData, using: key)
        guard let combined = sealed.combined else {
            throw DataTransferError.encryptedPayloadInvalid
        }

        let envelope = EncryptedExportEnvelope(
            format: "enkelt-budsjett-export-encrypted-v1",
            exportedAt: payload.exportedAt,
            saltBase64: salt.base64EncodedString(),
            sealedBoxBase64: combined.base64EncodedString()
        )
        let encryptedData = try encoder.encode(envelope)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "\(filePrefix)-\(formatter.string(from: .now)).sbx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try encryptedData.write(to: url, options: .atomic)
        return url
    }

    private func deriveKey(password: String, salt: Data) -> SymmetricKey {
        let material = SymmetricKey(data: Data(password.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: material,
            salt: salt,
            info: Data("enkelt-budsjett-export-v1".utf8),
            outputByteCount: 32
        )
    }

    private func randomBytes(count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: 0...255) })
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
        let existing = try context.fetch(FetchDescriptor<Goal>())
        var fingerprints = Set(existing.map(goalFingerprint))
        for row in rows {
            let fingerprint = goalFingerprint(row)
            if fingerprints.contains(fingerprint) { continue }
            context.insert(
                Goal(
                    targetAmount: row.targetAmount,
                    targetDate: row.targetDate,
                    scope: GoalScope(rawValue: row.scope) ?? .wealth,
                    includeAccounts: row.includeAccounts,
                    isActive: row.isActive,
                    createdAt: row.createdAt
                )
            )
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
}

private struct ExportPayload: Codable {
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

private struct EncryptedExportEnvelope: Codable {
    let format: String
    let exportedAt: Date
    let saltBase64: String
    let sealedBoxBase64: String
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

private struct BudgetGroupPlanDTO: Codable {
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
