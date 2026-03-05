import Foundation
import SwiftData
import CryptoKit

enum SettingsDataTransferService {
    static func makeExportPayload(context: ModelContext) throws -> ExportPayload {
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

    static func decodeImportPayload(from data: Data, password: String?) throws -> ExportPayload {
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

    static func writePlainPayload(_ payload: ExportPayload, filePrefix: String) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "\(filePrefix)-\(formatter.string(from: .now)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func deriveKey(password: String, salt: Data) -> SymmetricKey {
        let material = SymmetricKey(data: Data(password.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: material,
            salt: salt,
            info: Data("enkelt-budsjett-export-v1".utf8),
            outputByteCount: 32
        )
    }
}
