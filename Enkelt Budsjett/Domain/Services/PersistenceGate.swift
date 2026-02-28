import Foundation
import SwiftData
import os

enum PersistenceWriteError: LocalizedError {
    case readOnlyMode

    var errorDescription: String? {
        switch self {
        case .readOnlyMode:
            return "Lagring er midlertidig slått av fordi appen kjører uten varig lokal lagring. Start appen på nytt og prøv igjen."
        }
    }
}

private struct PersistenceTelemetryEvent: Codable {
    let timestamp: Date
    let level: String
    let feature: String
    let operation: String
    let storeMode: String
    let message: String
}

enum PersistenceGate {
    private static let logger = Logger(subsystem: "EnkeltBudsjett", category: "Persistence")
    private static let telemetryKey = "persistence_write_events"
    private static let maxTelemetryEvents = 250

    static var isReadOnlyMode: Bool {
        Simple_Budget___Budskjett_planlegger_gjort_enkeltApp.activeStoreMode == .memoryOnly
    }

    static func save(
        context: ModelContext,
        feature: String,
        operation: String,
        enforceReadOnly: Bool = true
    ) throws {
        if enforceReadOnly && isReadOnlyMode {
            let error = PersistenceWriteError.readOnlyMode
            record(level: "error", feature: feature, operation: operation, message: error.localizedDescription)
            throw error
        }

        do {
            try context.save()
            record(level: "info", feature: feature, operation: operation, message: "save_ok")
        } catch {
            let message = "\(String(reflecting: error))"
            record(level: "error", feature: feature, operation: operation, message: "save_failed: \(message)")
            throw error
        }
    }

    static func recordInfo(feature: String, operation: String, message: String) {
        record(level: "info", feature: feature, operation: operation, message: message)
    }

    static func recordError(feature: String, operation: String, error: Error) {
        record(level: "error", feature: feature, operation: operation, message: String(reflecting: error))
    }

    private static func record(level: String, feature: String, operation: String, message: String) {
        if level == "error" {
            logger.error("[\(feature)] \(operation): \(message, privacy: .public)")
        } else {
            logger.log("[\(feature)] \(operation): \(message, privacy: .public)")
        }

        let mode = "\(Simple_Budget___Budskjett_planlegger_gjort_enkeltApp.activeStoreMode)"
        let event = PersistenceTelemetryEvent(
            timestamp: .now,
            level: level,
            feature: feature,
            operation: operation,
            storeMode: mode,
            message: message
        )
        var events = loadTelemetry()
        events.append(event)
        if events.count > maxTelemetryEvents {
            events = Array(events.suffix(maxTelemetryEvents))
        }
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: telemetryKey)
        }
    }

    private static func loadTelemetry() -> [PersistenceTelemetryEvent] {
        guard let data = UserDefaults.standard.data(forKey: telemetryKey) else { return [] }
        return (try? JSONDecoder().decode([PersistenceTelemetryEvent].self, from: data)) ?? []
    }
}

extension ModelContext {
    func guardedSave(
        feature: String,
        operation: String,
        enforceReadOnly: Bool = true
    ) throws {
        try PersistenceGate.save(
            context: self,
            feature: feature,
            operation: operation,
            enforceReadOnly: enforceReadOnly
        )
    }
}
