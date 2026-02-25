import SwiftUI
import SwiftData

@main
struct Simple_Budget___Budskjett_planlegger_gjort_enkeltApp: App {
    private let container = Self.makeContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            BudgetMonth.self,
            Category.self,
            BudgetPlan.self,
            Transaction.self,
            Account.self,
            InvestmentBucket.self,
            InvestmentSnapshot.self,
            InvestmentSnapshotValue.self,
            FixedItem.self,
            FixedItemSkip.self,
            Goal.self,
            Challenge.self,
            UserPreference.self
        ])

        let storeURL = localStoreURL()
        do {
            let configuration = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Sikker recovery: aldri slett brukerdata automatisk.
            // Start i en separat recovery-store hvis primær store ikke kan åpnes.
            do {
                let configuration = ModelConfiguration(url: recoveryStoreURL(), cloudKitDatabase: .none)
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                // Siste nødnett: la appen starte i-memory.
                let memory = ModelConfiguration(isStoredInMemoryOnly: true)
                return try! ModelContainer(for: schema, configurations: [memory])
            }
        }
    }

    private static func localStoreURL() -> URL {
        let fm = FileManager.default
        let appSupport = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return appSupport.appendingPathComponent("SimpleBudget.store")
    }

    private static func recoveryStoreURL() -> URL {
        let fm = FileManager.default
        let appSupport = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return appSupport.appendingPathComponent("SimpleBudget.recovery.store")
    }
}
