import Foundation
import SwiftData
import Testing
@testable import SporOkonomi

private typealias Category = SporOkonomi.Category

struct SettingsImportTests {

    @Test
    @MainActor
    func settingsImportMergeIsIdempotentForBucketsGoalsAndPreference() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let settingsVM = SettingsViewModel()
        let calendar = Calendar.current
        let goalDate = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31)) ?? .now
        let createdAt = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 8)) ?? .now

        context.insert(
            InvestmentBucket(
                id: "bucket_index",
                name: "Indeksfond",
                colorHex: "#123456",
                isDefault: true,
                sortOrder: 7
            )
        )
        context.insert(
            Goal(
                targetAmount: 250_000,
                targetDate: goalDate,
                scope: .wealth,
                includeAccounts: true,
                isActive: true,
                createdAt: createdAt
            )
        )
        context.insert(
            UserPreference(
                singletonKey: "main",
                firstName: "Nora",
                checkInReminderEnabled: false,
                defaultGraphView: .max,
                onboardingCompleted: true,
                toneStyle: .calm
            )
        )
        try context.save()

        let exportURL = try settingsVM.exportData(context: context)
        _ = try settingsVM.importData(from: exportURL, mode: .merge, context: context, password: nil)
        _ = try settingsVM.importData(from: exportURL, mode: .merge, context: context, password: nil)

        let buckets = try context.fetch(FetchDescriptor<InvestmentBucket>())
        let goals = try context.fetch(FetchDescriptor<Goal>())
        let preferences = try context.fetch(FetchDescriptor<UserPreference>())

        let matchingBuckets = buckets.filter { $0.id == "bucket_index" }
        let matchingGoals = goals.filter {
            $0.targetAmount == 250_000 &&
            $0.targetDate == goalDate &&
            $0.createdAt == createdAt
        }
        let mainPreferences = preferences.filter { $0.singletonKey == "main" }

        #expect(matchingBuckets.count == 1)
        #expect(matchingBuckets.first?.name == "Indeksfond")
        #expect(matchingGoals.count == 1)
        #expect(mainPreferences.count == 1)
        #expect(mainPreferences.first?.firstName == "Nora")
        #expect(mainPreferences.first?.defaultGraphView == .max)
        #expect(mainPreferences.first?.toneStyle == .calm)
    }

    @Test
    @MainActor
    func settingsImportReplaceRemovesPostExportDataAndReportsBackupFile() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let settingsVM = SettingsViewModel()

        context.insert(Category(id: "cat_exported", name: "Eksportert kategori", type: .expense, sortOrder: 1))
        context.insert(UserPreference(singletonKey: "main", firstName: "Ada", onboardingCompleted: true))
        try context.save()

        let exportURL = try settingsVM.exportData(context: context)

        context.insert(Category(id: "cat_extra", name: "Skal bort", type: .expense, sortOrder: 2))
        try context.save()

        let report = try settingsVM.importData(from: exportURL, mode: .replace, context: context, password: nil)
        let categories = try context.fetch(FetchDescriptor<Category>())

        let reportIsReplace: Bool
        switch report.mode {
        case .replace:
            reportIsReplace = true
        case .merge:
            reportIsReplace = false
        }

        #expect(reportIsReplace)
        #expect(report.backupFileName?.hasPrefix("enkelt-budsjett-auto-backup-") == true)
        #expect(categories.contains(where: { $0.id == "cat_exported" }))
        #expect(categories.contains(where: { $0.id == "cat_extra" }) == false)
    }

    @Test
    @MainActor
    func settingsImportDecodesLegacyCategoryPayloadWithoutGroupKey() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let settingsVM = SettingsViewModel()
        let importURL = try makeLegacyImportFile()

        let report = try settingsVM.importData(from: importURL, mode: .merge, context: context, password: nil)
        let categories = try context.fetch(FetchDescriptor<Category>())
        let importedCategory = categories.first(where: { $0.id == "cat_legacy_food" })

        #expect(report.categories == 1)
        #expect(importedCategory != nil)
        #expect(importedCategory?.groupKey == BudgetGroup.hverdags.rawValue)
    }

    @Test
    @MainActor
    func settingsImportMergeKeepsExactlyOneActiveGoal() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let settingsVM = SettingsViewModel()
        let calendar = Calendar.current

        context.insert(
            Goal(
                targetAmount: 200_000,
                targetDate: calendar.date(from: DateComponents(year: 2026, month: 12, day: 31)) ?? .now,
                scope: .wealth,
                includeAccounts: true,
                isActive: true,
                createdAt: calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 8)) ?? .now
            )
        )
        try context.save()

        let importURL = try makeGoalImportFile(
            targetAmount: 350_000,
            targetDate: calendar.date(from: DateComponents(year: 2027, month: 6, day: 30)) ?? .now,
            createdAt: calendar.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 9)) ?? .now
        )

        _ = try settingsVM.importData(from: importURL, mode: .merge, context: context, password: nil)

        let goals = try context.fetch(FetchDescriptor<Goal>())
        let activeGoals = goals.filter(\.isActive)

        #expect(activeGoals.count == 1)
        #expect(activeGoals.first?.targetAmount == 350_000)
        #expect(activeGoals.first?.targetDate == calendar.date(from: DateComponents(year: 2027, month: 6, day: 30)))
    }

    private func makeLegacyImportFile() throws -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let exportedAt = formatter.string(from: Date(timeIntervalSince1970: 1_772_323_200))

        let payload: [String: Any] = [
            "exportedAt": exportedAt,
            "budgetMonths": [],
            "categories": [
                [
                    "id": "cat_legacy_food",
                    "name": "Mat",
                    "type": "expense",
                    "isActive": true,
                    "sortOrder": 4
                ]
            ],
            "plans": [],
            "groupPlans": [],
            "transactions": [],
            "fixedItems": [],
            "fixedItemSkips": [],
            "accounts": [],
            "buckets": [],
            "snapshots": [],
            "goals": [],
            "challenges": [],
            "preferences": []
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-settings-import-\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func makeGoalImportFile(targetAmount: Double, targetDate: Date, createdAt: Date) throws -> URL {
        let goal = Goal(
            targetAmount: targetAmount,
            targetDate: targetDate,
            scope: .wealth,
            includeAccounts: true,
            isActive: true,
            createdAt: createdAt
        )
        let payload = ExportPayload(
            exportedAt: Date(timeIntervalSince1970: 1_772_323_200),
            budgetMonths: [],
            categories: [],
            plans: [],
            groupPlans: [],
            transactions: [],
            fixedItems: [],
            fixedItemSkips: [],
            accounts: [],
            buckets: [],
            snapshots: [],
            goals: [
                GoalDTO(goal)
            ],
            challenges: [],
            preferences: []
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("goal-settings-import-\(UUID().uuidString).json")
        try data.write(to: url, options: Data.WritingOptions.atomic)
        return url
    }
}
