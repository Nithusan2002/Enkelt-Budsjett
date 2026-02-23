import Foundation
import Combine

@MainActor
final class InvestmentsViewModel: ObservableObject {
    @Published var showCheckIn = false

    func latestSnapshot(_ snapshots: [InvestmentSnapshot]) -> InvestmentSnapshot? {
        InvestmentService.latestSnapshot(snapshots)
    }

    func previousSnapshot(_ snapshots: [InvestmentSnapshot]) -> InvestmentSnapshot? {
        InvestmentService.previousSnapshot(snapshots)
    }

    func monthChange(current: InvestmentSnapshot?, previous: InvestmentSnapshot?) -> (kr: Double, pct: Double?) {
        InvestmentService.monthChange(current: current, previous: previous)
    }

    func value(for bucketID: String, latest: InvestmentSnapshot?) -> Double {
        latest?.bucketValues.first(where: { $0.bucketID == bucketID })?.amount ?? 0
    }

    func history(_ snapshots: [InvestmentSnapshot]) -> [InvestmentSnapshot] {
        snapshots.reversed()
    }
}
