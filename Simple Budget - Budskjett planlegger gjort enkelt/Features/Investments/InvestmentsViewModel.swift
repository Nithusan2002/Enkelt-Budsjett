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
    @Published var showAddBucketSheet = false
    @Published var selectedRange: GraphViewRange = .yearToDate
    @Published var developmentPeriod: InvestmentsDevelopmentPeriod = .last12Months
    @Published var selectedBucketForEdit: InvestmentBucket?
    @Published var displayedTotal: Double = 0
    @Published var showTrendChip = false
    @Published var newBucketName: String = ""
    @Published var selectedBucketColorHex: String = AppTheme.customBucketPalette[0]
    @Published var addBucketError: String?

    var rangeOptions: [GraphViewRange] {
        [.yearToDate, .oneYear, .twoYears, .threeYears, .fiveYears, .max]
    }

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
        InvestmentService
            .filteredSnapshots(range: .max, snapshots: snapshots)
            .reversed()
    }

    func onAppear(preference: UserPreference?, snapshots: [InvestmentSnapshot]) {
        if let preference {
            selectedRange = normalizedRange(preference.defaultGraphView)
        }
        updateDisplayedTotal(snapshots: snapshots, animate: false)
        showTrendChip = previousSnapshot(snapshots) != nil
    }

    func refreshData(snapshots: [InvestmentSnapshot]) {
        updateDisplayedTotal(snapshots: snapshots, animate: true)
        withAnimation(.easeOut(duration: 0.3)) {
            showTrendChip = false
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85).delay(0.1)) {
            showTrendChip = previousSnapshot(snapshots) != nil
        }
    }

    func filteredSnapshots(_ snapshots: [InvestmentSnapshot], range: GraphViewRange, now: Date = .now) -> [InvestmentSnapshot] {
        InvestmentService.filteredSnapshots(range: normalizedRange(range), snapshots: snapshots, now: now)
    }

    func developmentChartPoints(
        snapshots: [InvestmentSnapshot],
        buckets: [InvestmentBucket],
        now: Date = .now
    ) -> [InvestmentsDevelopmentChartPoint] {
        InvestmentsDevelopmentChartDataBuilder.points(
            snapshots: snapshots,
            buckets: buckets,
            period: developmentPeriod,
            now: now
        )
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
        buckets: [InvestmentBucket]
    ) -> InvestmentInsightData {
        let latest = latestSnapshot(snapshots)
        let previous = previousSnapshot(snapshots)
        let rows = bucketRows(buckets: buckets, snapshots: snapshots, range: .oneYear)
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

        let change = monthChange(current: latest, previous: previous)
        return InvestmentInsightData(
            title: "Siste utvikling",
            detail: change.pct != nil
                ? "\(formatNOK(change.kr)) (\(formatPercent(change.pct ?? 0))) siden sist."
                : "\(formatNOK(change.kr)) siden siste oppdatering."
        )
    }

    func rangeTitle(_ range: GraphViewRange) -> String {
        switch normalizedRange(range) {
        case .yearToDate:
            return "I år"
        case .oneYear:
            return "1 år"
        case .twoYears:
            return "2 år"
        case .threeYears:
            return "3 år"
        case .fiveYears:
            return "5 år"
        case .max:
            return "Maks"
        case .last12Months:
            return "1 år"
        }
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

    func restoreBucket(_ bucket: InvestmentBucket, context: ModelContext, existingBuckets: [InvestmentBucket]) {
        bucket.isActive = true
        bucket.sortOrder = (existingBuckets.map(\.sortOrder).max() ?? 0) + 1
        try? context.save()
    }

    func moveActiveBuckets(
        from source: IndexSet,
        to destination: Int,
        allBuckets: [InvestmentBucket],
        context: ModelContext
    ) {
        var activeBuckets = allBuckets.filter(\.isActive).sorted { $0.sortOrder < $1.sortOrder }
        guard !activeBuckets.isEmpty else { return }

        activeBuckets.move(fromOffsets: source, toOffset: destination)
        for (index, bucket) in activeBuckets.enumerated() {
            bucket.sortOrder = index
        }

        let hiddenBuckets = allBuckets.filter { !$0.isActive }.sorted { $0.sortOrder < $1.sortOrder }
        for (offset, bucket) in hiddenBuckets.enumerated() {
            bucket.sortOrder = activeBuckets.count + offset
        }

        try? context.save()
    }

    func updateBucket(
        _ bucket: InvestmentBucket,
        name: String,
        colorHex: String,
        context: ModelContext,
        existingBuckets: [InvestmentBucket]
    ) -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return "Navn kan ikke være tomt."
        }

        if existingBuckets.contains(where: {
            $0.id != bucket.id &&
            $0.name.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            return "En beholdningstype med dette navnet finnes allerede."
        }

        bucket.name = trimmedName
        bucket.colorHex = colorHex
        try? context.save()
        return nil
    }

    func deleteBucket(
        _ bucket: InvestmentBucket,
        context: ModelContext,
        snapshots: [InvestmentSnapshot]
    ) {
        for snapshot in snapshots {
            snapshot.bucketValues.removeAll(where: { $0.bucketID == bucket.id })
            snapshot.totalValue = snapshot.bucketValues.reduce(0) { $0 + $1.amount }
        }
        context.delete(bucket)
        try? context.save()
    }

    func addBucket(context: ModelContext, existingBuckets: [InvestmentBucket]) -> Bool {
        let trimmedName = newBucketName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            addBucketError = "Skriv inn et navn på beholdningstypen."
            return false
        }

        if let existing = existingBuckets.first(where: { $0.name.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            if existing.isActive {
                addBucketError = "Denne beholdningstypen finnes allerede."
                return false
            }
            existing.name = trimmedName
            existing.colorHex = selectedBucketColorHex
            existing.isActive = true
            existing.sortOrder = (existingBuckets.map(\.sortOrder).max() ?? 0) + 1
            try? context.save()
            newBucketName = ""
            selectedBucketColorHex = AppTheme.customBucketPalette[0]
            addBucketError = nil
            showAddBucketSheet = false
            return true
        }

        let id = uniqueBucketID(for: trimmedName, existingBuckets: existingBuckets)
        let sortOrder = (existingBuckets.map(\.sortOrder).max() ?? 0) + 1
        context.insert(
            InvestmentBucket(
                id: id,
                name: trimmedName,
                colorHex: selectedBucketColorHex,
                isDefault: false,
                isActive: true,
                sortOrder: sortOrder
            )
        )
        try? context.save()
        newBucketName = ""
        selectedBucketColorHex = AppTheme.customBucketPalette[0]
        addBucketError = nil
        showAddBucketSheet = false
        return true
    }

    func resetAddBucketState() {
        newBucketName = ""
        selectedBucketColorHex = AppTheme.customBucketPalette[0]
        addBucketError = nil
    }

    func ensureDefaultBuckets(context: ModelContext, existingBuckets: [InvestmentBucket]) {
        let legacyDefaultHex: Set<String> = ["#0EA5E9", "#8B5CF6", "#22C55E", "#F59E0B", "#EA580C"]
        let defaults: [(id: String, name: String, colorHex: String)] = [
            ("funds", "Fond", "#1F9BD3"),
            ("stocks", "Aksjer", "#7A5AD6"),
            ("bsu", "BSU", "#2FB66B"),
            ("buffer", "Buffer", "#D9951F"),
            ("crypto", "Krypto", "#D9671E")
        ]

        var didChange = false
        var nextSortOrder = (existingBuckets.map(\.sortOrder).max() ?? 0) + 1

        for item in defaults {
            if let existing = existingBuckets.first(where: {
                $0.id == item.id ||
                $0.name.compare(item.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                let existingHex = existing.colorHex?.uppercased()
                if existingHex == nil || existingHex?.isEmpty == true || legacyDefaultHex.contains(existingHex ?? "") {
                    existing.colorHex = item.colorHex
                    didChange = true
                }
                continue
            }

            context.insert(
                InvestmentBucket(
                    id: item.id,
                    name: item.name,
                    colorHex: item.colorHex,
                    isDefault: true,
                    isActive: true,
                    sortOrder: nextSortOrder
                )
            )
            nextSortOrder += 1
            didChange = true
        }

        if didChange {
            try? context.save()
        }
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

    private func uniqueBucketID(for name: String, existingBuckets: [InvestmentBucket]) -> String {
        let existingIDs = Set(existingBuckets.map(\.id))
        let base = slugify(name)
        var candidate = "bucket_\(base)"
        var suffix = 2

        while existingIDs.contains(candidate) {
            candidate = "bucket_\(base)_\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func slugify(_ value: String) -> String {
        let lower = value.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        let allowed = lower.map { char -> Character in
            if char.isLetter || char.isNumber { return char }
            return "_"
        }
        let raw = String(allowed)
        let collapsed = raw.replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() : trimmed
    }

    private func normalizedRange(_ range: GraphViewRange) -> GraphViewRange {
        range == .last12Months ? .oneYear : range
    }
}

struct SparklinePoint: Identifiable {
    let id = UUID()
    let index: Int
    let value: Double
}
