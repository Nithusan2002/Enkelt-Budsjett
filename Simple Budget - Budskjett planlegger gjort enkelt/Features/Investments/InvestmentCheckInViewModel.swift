import Foundation
import Combine
import SwiftData

@MainActor
final class InvestmentCheckInViewModel: ObservableObject {
    @Published var values: [String: String] = [:]
    @Published var selectedDate: Date = .now

    func periodKey(for date: Date? = nil) -> String {
        DateService.periodKey(from: date ?? selectedDate)
    }

    func prepareValues(buckets: [InvestmentBucket], latestSnapshot: InvestmentSnapshot?) {
        _ = latestSnapshot
        for bucket in buckets where values[bucket.id] == nil {
            values[bucket.id] = ""
        }
    }

    func binding(for bucketID: String) -> String {
        values[bucketID] ?? ""
    }

    func setBinding(_ value: String, for bucketID: String) {
        values[bucketID] = value
    }

    func total() -> Double {
        values.values.compactMap(parseInputAmount).reduce(0, +)
    }

    func saveSnapshot(context: ModelContext, periodKey: String, total: Double, capturedAt: Date) {
        let descriptor = FetchDescriptor<InvestmentSnapshot>(
            predicate: #Predicate { $0.periodKey == periodKey }
        )
        let existing = try? context.fetch(descriptor).first
        let snapshotValues = values.map {
            InvestmentSnapshotValue(periodKey: periodKey, bucketID: $0.key, amount: parseInputAmount($0.value) ?? 0)
        }
        if let existing {
            existing.capturedAt = capturedAt
            existing.totalValue = total
            existing.bucketValues = snapshotValues
        } else {
            context.insert(InvestmentSnapshot(periodKey: periodKey, capturedAt: capturedAt, totalValue: total, bucketValues: snapshotValues))
        }
        try? context.save()
    }

    private func parseInputAmount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
}
