import SwiftUI
import SwiftData

enum AppStoreMode {
    case primary
    case primaryWithoutCloud
    case recovery
    case memoryOnly
}

@main
struct Simple_Budget___Budskjett_planlegger_gjort_enkeltApp: App {
    private let container = Self.makeContainer()
    static private(set) var activeStoreMode: AppStoreMode = .primary

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
            BudgetGroupPlan.self,
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

        if ProcessInfo.processInfo.arguments.contains("UITEST_IN_MEMORY_STORE") {
            let memory = ModelConfiguration(isStoredInMemoryOnly: true)
            activeStoreMode = .memoryOnly
            return try! ModelContainer(for: schema, configurations: [memory])
        }

        let storeURL = localStoreURL()
        do {
            let configuration = ModelConfiguration(url: storeURL, cloudKitDatabase: .automatic)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            activeStoreMode = .primary
            return container
        } catch {
            // Fallback: behold samme lokale store selv om iCloud ikke kan initialiseres.
            do {
                let configuration = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
                let container = try ModelContainer(for: schema, configurations: [configuration])
                activeStoreMode = .primaryWithoutCloud
                return container
            } catch {
                // Sikker recovery: aldri slett brukerdata automatisk.
                // Start i en separat recovery-store hvis primær store ikke kan åpnes.
                do {
                    let configuration = ModelConfiguration(url: recoveryStoreURL(), cloudKitDatabase: .none)
                    let container = try ModelContainer(for: schema, configurations: [configuration])
                    activeStoreMode = .recovery
                    return container
                } catch {
                    // Siste nødnett: la appen starte i-memory.
                    let memory = ModelConfiguration(isStoredInMemoryOnly: true)
                    activeStoreMode = .memoryOnly
                    return try! ModelContainer(for: schema, configurations: [memory])
                }
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
