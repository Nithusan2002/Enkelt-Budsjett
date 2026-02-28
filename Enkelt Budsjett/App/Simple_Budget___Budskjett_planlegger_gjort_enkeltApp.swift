import SwiftUI
import SwiftData
import CloudKit

enum AppStoreMode {
    case primary
    case primaryWithoutCloud
    case recovery
    case memoryOnly
}

@main
struct Simple_Budget___Budskjett_planlegger_gjort_enkeltApp: App {
    private static let cloudContainerID = "iCloud.com.nithusan.Enkelt-Budsjett"
    private let container = Self.makeContainer()
    static private(set) var activeStoreMode: AppStoreMode = .primary
    static private(set) var lastCloudInitError: String?
    static private(set) var lastCloudAccountStatus: String?
    static private(set) var lastCloudProbeStatus: String?
    static private(set) var lastCloudCompatibilityAnalysis: String?

    init() {
        Self.refreshCloudAccountStatus()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }

    private static func makeContainer() -> ModelContainer {
        let schema = Schema(allModelTypes())

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
            lastCloudInitError = nil
            lastCloudProbeStatus = "ikke nødvendig (primær iCloud-last OK)"
            lastCloudCompatibilityAnalysis = nil
            return container
        } catch {
            lastCloudInitError = describe(error)
            lastCloudProbeStatus = runCloudProbe(schema: schema)
            lastCloudCompatibilityAnalysis = runCloudCompatibilityAnalysis()
#if DEBUG
            print("CloudKit init feilet: \(lastCloudInitError ?? "ukjent feil")")
            print("CloudKit probe: \(lastCloudProbeStatus ?? "ikke kjørt")")
            print("CloudKit analyse: \(lastCloudCompatibilityAnalysis ?? "ingen")")
#endif
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

    private static func describe(_ error: Error) -> String {
        var segments: [String] = ["\(String(reflecting: error))"]
        var visited = Set<String>()

        func appendNSError(_ nsError: NSError, prefix: String) {
            let key = "\(nsError.domain)#\(nsError.code)#\(nsError.localizedDescription)"
            guard !visited.contains(key) else { return }
            visited.insert(key)

            segments.append("\(prefix)\(nsError.domain) (\(nsError.code))")
            segments.append("\(prefix)\(nsError.localizedDescription)")

            if let reason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String, !reason.isEmpty {
                segments.append("\(prefix)Reason: \(reason)")
            }
            if let suggestion = nsError.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String, !suggestion.isEmpty {
                segments.append("\(prefix)Suggestion: \(suggestion)")
            }
            if let detailed = nsError.userInfo["NSDetailedErrors"] as? [NSError], !detailed.isEmpty {
                for detail in detailed {
                    appendNSError(detail, prefix: "\(prefix)Detalj -> ")
                }
            }
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                appendNSError(underlying, prefix: "\(prefix)Underliggende -> ")
            }
        }

        appendNSError(error as NSError, prefix: "")
        return segments.joined(separator: " | ")
    }

    private static func refreshCloudAccountStatus() {
        let container = CKContainer(identifier: cloudContainerID)
        container.accountStatus { status, error in
            if let error {
                lastCloudAccountStatus = "accountStatus-feil: \(describe(error))"
                return
            }
            switch status {
            case .available:
                lastCloudAccountStatus = "available"
            case .noAccount:
                lastCloudAccountStatus = "noAccount"
            case .restricted:
                lastCloudAccountStatus = "restricted"
            case .couldNotDetermine:
                lastCloudAccountStatus = "couldNotDetermine"
            case .temporarilyUnavailable:
                lastCloudAccountStatus = "temporarilyUnavailable"
            @unknown default:
                lastCloudAccountStatus = "unknown"
            }
        }
    }

    private static func runCloudProbe(schema: Schema) -> String {
        let probeURL = probeStoreURL()
        cleanupStoreFiles(at: probeURL)
        do {
            let configuration = ModelConfiguration(url: probeURL, cloudKitDatabase: .automatic)
            _ = try ModelContainer(for: schema, configurations: [configuration])
            cleanupStoreFiles(at: probeURL)
            return "OK (tom probe-store kunne starte med iCloud)"
        } catch {
            cleanupStoreFiles(at: probeURL)
            return "FEIL (tom probe-store feilet): \(describe(error))"
        }
    }

    private static func runCloudCompatibilityAnalysis() -> String {
        let models = allNamedModelTypes()
        let minimalResult = runProbe(for: [("CloudProbeMinimalModel", CloudProbeMinimalModel.self)], tag: "minimal")
        var singleModelResults: [String] = []
        var offenders: [String] = []
        var diagnostics: [String] = []

        for model in models {
            let result = runProbe(for: [model], tag: "single_\(model.name)")
            singleModelResults.append("\(model.name): \(result)")
        }

        for (index, removed) in models.enumerated() {
            var reduced = models
            reduced.remove(at: index)
            let result = runProbe(for: reduced, tag: "without_\(index)")
            if result == "OK" {
                offenders.append(removed.name)
            }
            diagnostics.append("uten \(removed.name): \(result)")
        }

        let summaryPrefix = "Minimal: \(minimalResult). Enkeltmodell: \(singleModelResults.joined(separator: " | ")). "

        if offenders.isEmpty {
            return summaryPrefix + "Ingen enkelmodell-kandidat funnet (feil kan kreve kombinasjon av modeller). " +
                diagnostics.joined(separator: " | ")
        }
        return summaryPrefix + "Mistenkte modeller: \(offenders.joined(separator: ", ")). " + diagnostics.joined(separator: " | ")
    }

    private static func runProbe(for models: [(name: String, type: any PersistentModel.Type)], tag: String) -> String {
        let schema = Schema(models.map(\.type))
        let probeURL = probeStoreURL(tag: tag)
        cleanupStoreFiles(at: probeURL)
        do {
            let configuration = ModelConfiguration(url: probeURL, cloudKitDatabase: .automatic)
            _ = try ModelContainer(for: schema, configurations: [configuration])
            cleanupStoreFiles(at: probeURL)
            return "OK"
        } catch {
            cleanupStoreFiles(at: probeURL)
            return "FEIL"
        }
    }

    private static func probeStoreURL() -> URL {
        probeStoreURL(tag: "full")
    }

    private static func probeStoreURL(tag: String) -> URL {
        let fm = FileManager.default
        let appSupport = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return appSupport.appendingPathComponent("SimpleBudget.cloudprobe.\(tag).store")
    }

    private static func cleanupStoreFiles(at url: URL) {
        let fm = FileManager.default
        let candidates = [
            url,
            URL(fileURLWithPath: url.path + "-shm"),
            URL(fileURLWithPath: url.path + "-wal")
        ]
        for candidate in candidates {
            try? fm.removeItem(at: candidate)
        }
    }

    private static func allModelTypes() -> [any PersistentModel.Type] {
        allNamedModelTypes().map(\.type)
    }

    private static func allNamedModelTypes() -> [(name: String, type: any PersistentModel.Type)] {
        [
            ("BudgetMonth", BudgetMonth.self),
            ("Category", Category.self),
            ("BudgetPlan", BudgetPlan.self),
            ("BudgetGroupPlan", BudgetGroupPlan.self),
            ("Transaction", Transaction.self),
            ("Account", Account.self),
            ("InvestmentBucket", InvestmentBucket.self),
            ("InvestmentSnapshot", InvestmentSnapshot.self),
            ("FixedItem", FixedItem.self),
            ("FixedItemSkip", FixedItemSkip.self),
            ("Goal", Goal.self),
            ("Challenge", Challenge.self),
            ("UserPreference", UserPreference.self)
        ]
    }
}
