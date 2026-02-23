import Foundation
import Combine
import SwiftData
import SwiftUI

struct InvestmentHeroData {
    let total: Double
    let changeKr: Double
    let changePct: Double?
    let lastCheckInText: String
    let nextCheckInText: String
    let reminderText: String
}

struct InvestmentBucketRowData: Identifiable {
    let id: String
    let name: String
    let amount: Double
    let changeKr: Double
    let changePct: Double?
    let sparkline: [Double]
    let shareOfPortfolio: Double
    let lastUpdated: Date?
}

struct InvestmentInsightData {
    let title: String
    let detail: String
}

@MainActor
final class InvestmentsViewModel: ObservableObject {
    @Published var showCheckIn = false
    @Published var selectedRange: GraphViewRange = .yearToDate
    @Published var selectedBucketForEdit: InvestmentBucket?
    @Published var displayedTotal: Double = 0
    @Published var showTrendChip = false

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

    func onAppear(preference: UserPreference?, snapshots: [InvestmentSnapshot]) {
        if let preference {
            selectedRange = preference.defaultGraphView
        }
        updateDisplayedTotal(snapshots: snapshots, animate: false)
        showTrendChip = latestSnapshot(snapshots) != nil
    }

    func refreshData(snapshots: [InvestmentSnapshot]) {
        updateDisplayedTotal(snapshots: snapshots, animate: true)
        withAnimation(.easeOut(duration: 0.3)) {
            showTrendChip = false
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85).delay(0.1)) {
            showTrendChip = latestSnapshot(snapshots) != nil
        }
    }

    func filteredSnapshots(_ snapshots: [InvestmentSnapshot], range: GraphViewRange, now: Date = .now) -> [InvestmentSnapshot] {
        let sorted = InvestmentService.sortedSnapshots(snapshots)
        switch range {
        case .yearToDate:
            let year = Calendar.current.component(.year, from: now)
            return sorted.filter { $0.periodKey.hasPrefix("\(year)-") }
        case .last12Months:
            return Array(sorted.suffix(12))
        }
    }

    func heroData(
        snapshots: [InvestmentSnapshot],
        preference: UserPreference?,
        now: Date = .now
    ) -> InvestmentHeroData {
        let latest = latestSnapshot(snapshots)
        let previous = previousSnapshot(snapshots)
        let change = monthChange(current: latest, previous: previous)
        let day = max(1, min(28, preference?.checkInReminderDay ?? 5))
        let reminderEnabled = preference?.checkInReminderEnabled ?? true
        let lastText = latest.map { "Siste: \(formattedMonthDay($0.capturedAt))" } ?? "Siste: Ikke satt"
        let nextText = reminderEnabled ? "Neste: \(daysUntilNextCheckIn(day: day, now: now))" : "Neste: Ikke satt"
        let reminderText = reminderEnabled ? "Påminnelse: På" : "Påminnelse: Av"
        return InvestmentHeroData(
            total: latest?.totalValue ?? 0,
            changeKr: change.kr,
            changePct: change.pct,
            lastCheckInText: lastText,
            nextCheckInText: nextText,
            reminderText: reminderText
        )
    }

    func totalSparkline(snapshots: [InvestmentSnapshot], range: GraphViewRange) -> [Double] {
        filteredSnapshots(snapshots, range: range).map(\.totalValue)
    }

    func bucketRows(
        buckets: [InvestmentBucket],
        snapshots: [InvestmentSnapshot],
        range: GraphViewRange
    ) -> [InvestmentBucketRowData] {
        let active = buckets.filter(\.isActive)
        let latest = latestSnapshot(snapshots)
        let previous = previousSnapshot(snapshots)
        let filtered = filteredSnapshots(snapshots, range: range)
        let latestTotal = latest?.totalValue ?? 0

        return active.map { bucket in
            let latestAmount = latest?.bucketValues.first(where: { $0.bucketID == bucket.id })?.amount ?? 0
            let previousAmount = previous?.bucketValues.first(where: { $0.bucketID == bucket.id })?.amount ?? 0
            let change = latestAmount - previousAmount
            let pct: Double? = previousAmount == 0 ? nil : change / previousAmount
            let share = latestTotal > 0 ? latestAmount / latestTotal : 0
            let lastUpdated = latest?.capturedAt
            let series = filtered.map { snapshot in
                snapshot.bucketValues.first(where: { $0.bucketID == bucket.id })?.amount ?? 0
            }
            return InvestmentBucketRowData(
                id: bucket.id,
                name: bucket.name,
                amount: latestAmount,
                changeKr: change,
                changePct: pct,
                sparkline: series,
                shareOfPortfolio: share,
                lastUpdated: lastUpdated
            )
        }
    }

    func distributionData(
        latestSnapshot: InvestmentSnapshot?,
        buckets: [InvestmentBucket]
    ) -> [(bucketID: String, bucketName: String, amount: Double, percent: Double)] {
        guard let latestSnapshot, latestSnapshot.totalValue > 0 else { return [] }
        let names = Dictionary(uniqueKeysWithValues: buckets.map { ($0.id, $0.name) })
        return latestSnapshot.bucketValues
            .filter { $0.amount > 0 }
            .map { value in
                let name = names[value.bucketID] ?? value.bucketID
                let pct = value.amount / latestSnapshot.totalValue
                return (value.bucketID, name, value.amount, pct)
            }
            .sorted { $0.amount > $1.amount }
    }

    func shouldShowDonut(distributionData: [(bucketID: String, bucketName: String, amount: Double, percent: Double)]) -> Bool {
        distributionData.count >= 2
    }

    func latestHistory(_ snapshots: [InvestmentSnapshot], limit: Int = 6) -> [InvestmentSnapshot] {
        Array(history(snapshots).prefix(limit))
    }

    func insight(
        snapshots: [InvestmentSnapshot],
        buckets: [InvestmentBucket],
        goal: Goal?,
        accounts: [Account]
    ) -> InvestmentInsightData {
        let latest = latestSnapshot(snapshots)
        let previous = previousSnapshot(snapshots)
        let rows = bucketRows(buckets: buckets, snapshots: snapshots, range: .last12Months)
        if let top = rows.max(by: { $0.changeKr < $1.changeKr }), top.changeKr > 0 {
            return InvestmentInsightData(
                title: "Største bidrag siste måned",
                detail: "\(top.name): +\(formatNOK(top.changeKr))"
            )
        }

        if let latest, latest.totalValue > 0 {
            let distribution = distributionData(latestSnapshot: latest, buckets: buckets)
            if let first = distribution.first {
                return InvestmentInsightData(
                    title: "Porteføljefordeling",
                    detail: "\(first.bucketName) utgjør \(formatPercent(first.percent)) av porteføljen."
                )
            }
        }

        if let goal {
            let wealth = GoalService.currentWealth(
                latestInvestmentTotal: latest?.totalValue ?? 0,
                accounts: accounts,
                includeAccounts: goal.includeAccounts
            )
            if goal.targetAmount > 0 {
                let progress = min(1, wealth / goal.targetAmount)
                return InvestmentInsightData(
                    title: "Målfremdrift",
                    detail: "Du er \(Int((progress * 100).rounded())) % mot målet ditt."
                )
            }
        }

        let change = monthChange(current: latest, previous: previous)
        return InvestmentInsightData(
            title: "Siste utvikling",
            detail: change.pct != nil
                ? "\(formatNOK(change.kr)) (\(formatPercent(change.pct ?? 0))) siden sist."
                : "\(formatNOK(change.kr)) siden siste oppdatering."
        )
    }

    func bucketSparklinePoints(_ values: [Double]) -> [SparklinePoint] {
        values.enumerated().map { index, value in
            SparklinePoint(index: index, value: value)
        }
    }

    func shouldShowEmptyState(_ snapshots: [InvestmentSnapshot]) -> Bool {
        latestSnapshot(snapshots) == nil
    }

    func hideBucket(_ bucket: InvestmentBucket, context: ModelContext) {
        bucket.isActive = false
        try? context.save()
    }

    private func formattedMonthDay(_ date: Date) -> String {
        formatDate(date)
    }

    private func daysUntilNextCheckIn(day: Int, now: Date) -> String {
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month], from: now)
        components.day = day
        components.hour = 12
        let candidate = cal.date(from: components) ?? now
        let next = candidate >= now ? candidate : cal.date(byAdding: .month, value: 1, to: candidate) ?? candidate
        let days = max(0, cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: next)).day ?? 0)
        if days == 0 { return "i dag" }
        if days == 1 { return "i morgen" }
        return "om \(days) dager"
    }

    private func updateDisplayedTotal(snapshots: [InvestmentSnapshot], animate: Bool) {
        let target = latestSnapshot(snapshots)?.totalValue ?? 0
        if animate {
            withAnimation(.easeInOut(duration: 0.5)) {
                displayedTotal = target
            }
        } else {
            displayedTotal = target
        }
    }
}

struct SparklinePoint: Identifiable {
    let id = UUID()
    let index: Int
    let value: Double
}
