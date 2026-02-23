import Foundation
import Combine
import SwiftData

@MainActor
final class InvestmentCheckInViewModel: ObservableObject {
    @Published var values: [String: Double] = [:]

    func periodKey(now: Date = .now) -> String {
        DateService.periodKey(from: now)
    }

    func prepareValues(buckets: [InvestmentBucket], latestSnapshot: InvestmentSnapshot?) {
        for bucket in buckets where values[bucket.id] == nil {
            values[bucket.id] = latestSnapshot?.bucketValues.first(where: { $0.bucketID == bucket.id })?.amount ?? 0
        }
    }

    func binding(for bucketID: String) -> Double {
        values[bucketID] ?? 0
    }

    func setBinding(_ value: Double, for bucketID: String) {
        values[bucketID] = value
    }

    func total() -> Double {
        values.values.reduce(0, +)
    }

    func saveSnapshot(context: ModelContext, periodKey: String, total: Double) {
        let descriptor = FetchDescriptor<InvestmentSnapshot>(
            predicate: #Predicate { $0.periodKey == periodKey }
        )
        let existing = try? context.fetch(descriptor).first
        let snapshotValues = values.map { InvestmentSnapshotValue(periodKey: periodKey, bucketID: $0.key, amount: $0.value) }
        if let existing {
            existing.capturedAt = .now
            existing.totalValue = total
            existing.bucketValues = snapshotValues
        } else {
            context.insert(InvestmentSnapshot(periodKey: periodKey, capturedAt: .now, totalValue: total, bucketValues: snapshotValues))
        }
        try? context.save()
    }
}
