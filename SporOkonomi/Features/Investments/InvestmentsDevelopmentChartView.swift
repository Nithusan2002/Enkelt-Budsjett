import SwiftUI
import Charts
import UIKit

enum InvestmentsDevelopmentPeriod: String, CaseIterable {
    case oneMonth
    case sixMonths
    case last12Months
    case total

    var title: String {
        switch self {
        case .oneMonth:
            return "1 mnd"
        case .sixMonths:
            return "6 mnd"
        case .last12Months:
            return "12 mnd"
        case .total:
            return "Totalt"
        }
    }
}

struct InvestmentsDevelopmentBucketPoint: Identifiable {
    let id: String
    let bucketID: String
    let seriesKey: String
    let name: String
    let color: Color
    let amount: Double
}

struct InvestmentsDevelopmentChartPoint: Identifiable {
    let id: String
    let date: Date
    let periodKey: String
    let total: Double
    let buckets: [InvestmentsDevelopmentBucketPoint]
}

private struct InvestmentsDevelopmentStackedRow: Identifiable {
    let id: String
    let date: Date
    let seriesKey: String
    let bucketName: String
    let amount: Double
}

enum InvestmentsDevelopmentChartDataBuilder {
    static func points(
        snapshots: [InvestmentSnapshot],
        buckets: [InvestmentBucket],
        period: InvestmentsDevelopmentPeriod,
        now: Date = .now
    ) -> [InvestmentsDevelopmentChartPoint] {
        let filteredSnapshots: [InvestmentSnapshot]
        switch period {
        case .oneMonth:
            filteredSnapshots = rollingSnapshots(months: 1, snapshots: snapshots, now: now)
        case .sixMonths:
            filteredSnapshots = rollingSnapshots(months: 6, snapshots: snapshots, now: now)
        case .last12Months:
            filteredSnapshots = InvestmentService.filteredSnapshots(range: .oneYear, snapshots: snapshots, now: now)
        case .total:
            filteredSnapshots = InvestmentService.filteredSnapshots(range: .max, snapshots: snapshots, now: now)
        }
        let sortedBuckets = buckets
            .filter(\.isActive)
            .sorted { $0.sortOrder < $1.sortOrder }

        return filteredSnapshots.map { snapshot in
            let rows = mergedBucketPoints(snapshot: snapshot, buckets: sortedBuckets)
            return InvestmentsDevelopmentChartPoint(
                id: snapshot.periodKey,
                date: snapshot.capturedAt,
                periodKey: snapshot.periodKey,
                total: snapshot.totalValue,
                buckets: rows
            )
        }
    }

    static func nearestPoint(to date: Date, points: [InvestmentsDevelopmentChartPoint]) -> InvestmentsDevelopmentChartPoint? {
        points.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        })
    }

    static func deltaSincePrevious(for point: InvestmentsDevelopmentChartPoint, in points: [InvestmentsDevelopmentChartPoint]) -> Double {
        guard let index = points.firstIndex(where: { $0.id == point.id }), index > 0 else { return 0 }
        return point.total - points[index - 1].total
    }

    static func yTicks(points: [InvestmentsDevelopmentChartPoint]) -> [Double] {
        let values: [Double] = points.flatMap { $0.buckets.map(\.amount) + [$0.total] }

        guard let maxValue = values.max(), maxValue > 0 else { return [0, 10_000] }

        let rawStep = maxValue / 4
        let step = roundedTickStep(rawStep)
        let upper = ceil(maxValue / step) * step
        var ticks: [Double] = [0]
        var cursor = step
        while cursor <= upper {
            ticks.append(cursor)
            cursor += step
        }
        return ticks
    }

    static func xAxisDates(points: [InvestmentsDevelopmentChartPoint], period: InvestmentsDevelopmentPeriod) -> [Date] {
        let dates = points.map(\.date)
        guard !dates.isEmpty else { return [] }
        let targetCount: Int
        switch period {
        case .oneMonth:
            targetCount = 3
        case .sixMonths:
            targetCount = 4
        case .last12Months:
            targetCount = 4
        case .total:
            targetCount = 5
        }
        if dates.count <= targetCount { return dates }

        let step = max(1, dates.count / targetCount)
        var selected = stride(from: 0, to: dates.count, by: step).map { dates[$0] }
        if selected.last != dates.last, let last = dates.last {
            selected.append(last)
        }
        return selected
    }

    static func accessibilitySummary(
        points: [InvestmentsDevelopmentChartPoint],
        period: InvestmentsDevelopmentPeriod,
        areAmountsHidden: Bool = false
    ) -> String {
        guard let first = points.first, let last = points.last else {
            return "Ingen utviklingsdata ennå."
        }

        let delta = last.total - first.total
        let sign = delta >= 0 ? "opp" : "ned"
        let top = topBuckets(for: last)
        let topText: String
        if let firstTop = top.first {
            if areAmountsHidden {
                topText = "Største bøtte: \(firstTop.name)."
            } else {
                let share = last.total > 0 ? firstTop.amount / last.total : 0
                topText = "Største bøtte: \(firstTop.name) (\(formatPercent(share)))."
            }
        } else {
            topText = "Ingen bøtter med verdi ennå."
        }
        if areAmountsHidden {
            return "\(period.title): total \(sign). \(topText)"
        }
        return "\(period.title): total \(sign) \(formatNOK(abs(delta))). \(topText)"
    }

    static func topBuckets(for point: InvestmentsDevelopmentChartPoint) -> [InvestmentsDevelopmentBucketPoint] {
        point.buckets
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
    }

    private static func mergedBucketPoints(
        snapshot: InvestmentSnapshot,
        buckets: [InvestmentBucket]
    ) -> [InvestmentsDevelopmentBucketPoint] {
        struct Accumulator {
            var bucketIDs: [String]
            var name: String
            var color: Color
            var amount: Double
            var sortOrder: Int
        }

        var merged: [String: Accumulator] = [:]

        for bucket in buckets {
            let amount = snapshot.bucketValues.first(where: { $0.bucketID == bucket.id })?.amount ?? 0
            let key = normalizedSeriesKey(for: bucket.name)

            if var existing = merged[key] {
                existing.bucketIDs.append(bucket.id)
                existing.amount += amount
                existing.sortOrder = min(existing.sortOrder, bucket.sortOrder)
                merged[key] = existing
            } else {
                merged[key] = Accumulator(
                    bucketIDs: [bucket.id],
                    name: bucket.name,
                    color: AppTheme.portfolioColor(for: bucket),
                    amount: amount,
                    sortOrder: bucket.sortOrder
                )
            }
        }

        return merged
            .map { key, value in
                InvestmentsDevelopmentBucketPoint(
                    id: "\(snapshot.periodKey)-\(key)",
                    bucketID: value.bucketIDs.first ?? key,
                    seriesKey: key,
                    name: value.name,
                    color: value.color,
                    amount: value.amount
                )
            }
            .sorted { lhs, rhs in
                let lhsOrder = merged[lhs.seriesKey]?.sortOrder ?? .max
                let rhsOrder = merged[rhs.seriesKey]?.sortOrder ?? .max
                if lhsOrder == rhsOrder {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhsOrder < rhsOrder
            }
    }

    private static func normalizedSeriesKey(for name: String) -> String {
        name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func roundedTickStep(_ value: Double) -> Double {
        let steps: [Double] = [1_000, 2_500, 5_000, 10_000, 25_000, 50_000, 100_000, 250_000, 500_000, 1_000_000]
        return steps.first(where: { value <= $0 }) ?? 2_000_000
    }

    private static func rollingSnapshots(
        months: Int,
        snapshots: [InvestmentSnapshot],
        now: Date
    ) -> [InvestmentSnapshot] {
        let sorted = InvestmentService.sortedSnapshots(snapshots)
        let calendar = Calendar.current
        let nowDay = calendar.startOfDay(for: now)
        let monthStartNow = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let monthsBack = max(0, months - 1)
        let windowStart = calendar.date(byAdding: .month, value: -monthsBack, to: monthStartNow) ?? monthStartNow
        return sorted.filter {
            let day = calendar.startOfDay(for: $0.capturedAt)
            return day >= windowStart && day <= nowDay
        }
    }
}

struct InvestmentsDevelopmentChartView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("overview_amounts_hidden") private var areAmountsHidden = false
    let points: [InvestmentsDevelopmentChartPoint]
    @Binding var period: InvestmentsDevelopmentPeriod
    let onUpdateValues: () -> Void
    var embedded: Bool = false
    var showStatusRow: Bool = true

    @State private var selectedDate: Date?
    @State private var selectedPointID: String?
    @State private var interactionStart: Date?
    @State private var isScrubbing = false
    @State private var lastHapticAt: Date = .distantPast

    private var selectedPoint: InvestmentsDevelopmentChartPoint? {
        guard let selectedDate else { return nil }
        return InvestmentsDevelopmentChartDataBuilder.nearestPoint(to: selectedDate, points: points)
    }

    private var yTicks: [Double] {
        InvestmentsDevelopmentChartDataBuilder.yTicks(points: points)
    }

    private var stackedRows: [InvestmentsDevelopmentStackedRow] {
        points.flatMap { point in
            point.buckets.map { bucket in
                InvestmentsDevelopmentStackedRow(
                    id: "\(point.id)-\(bucket.bucketID)",
                    date: point.date,
                    seriesKey: bucket.seriesKey,
                    bucketName: bucket.name,
                    amount: bucket.amount
                )
            }
        }
    }

    private var stackedColorDomain: [String] {
        latest.buckets.map(\.seriesKey)
    }

    private var stackedColorRange: [Color] {
        latest.buckets.map(areaFillColor(for:))
    }

    private var latest: InvestmentsDevelopmentChartPoint {
        points.last ?? InvestmentsDevelopmentChartPoint(
            id: "empty",
            date: .now,
            periodKey: "",
            total: 0,
            buckets: []
        )
    }

    private var areaOpacity: Double {
        1
    }

    private var totalLineOutlineColor: Color {
        colorScheme == .dark ? AppTheme.surface.opacity(0.94) : AppTheme.background
    }

    private var totalLineColor: Color {
        colorScheme == .dark ? AppTheme.textPrimary : .black
    }

    private var latestVisibleBuckets: [InvestmentsDevelopmentBucketPoint] {
        latest.buckets.filter { $0.amount > 0 }
    }

    private var periodDelta: Double {
        guard let first = points.first, let last = points.last else { return 0 }
        return last.total - first.total
    }

    private var periodDeltaText: String {
        if areAmountsHidden {
            if periodDelta == 0 { return "Uendret" }
            return periodDelta > 0 ? "Opp" : "Ned"
        }
        let sign = periodDelta >= 0 ? "+" : "-"
        return "\(sign)\(formatNOK(abs(periodDelta)))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showStatusRow {
                statusRow
            }
            controls
            content
        }
        .padding(embedded ? 0 : 14)
        .background {
            if !embedded {
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppTheme.surface)
            }
        }
        .overlay(
            Group {
                if embedded {
                    EmptyView()
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppTheme.divider, lineWidth: 1)
                }
            }
        )
        .accessibilityLabel("Utviklingsgraf")
        .accessibilityValue(
            InvestmentsDevelopmentChartDataBuilder.accessibilitySummary(
                points: points,
                period: period,
                areAmountsHidden: areAmountsHidden
            )
        )
    }

    private var statusRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if points.count > 1 {
                    Text("Siden sist (\(period.title.lowercased()))")
                        .appSecondaryStyle()
                    Text(periodDeltaText)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(periodDelta >= 0 ? AppTheme.positive : AppTheme.negative)
                        .monospacedDigit()
                } else if points.count == 1 {
                    Text("Én innsjekk registrert")
                        .appSecondaryStyle()
                } else {
                    Text("Ingen data ennå")
                        .appSecondaryStyle()
                }
            }
            Spacer()
            if let last = points.last {
                Text("Sist \(monthTitle(last.date))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var controls: some View {
        Picker("Periode", selection: $period) {
            ForEach(InvestmentsDevelopmentPeriod.allCases, id: \.rawValue) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var content: some View {
        if points.isEmpty {
            emptyState(
                title: "Ingen registreringer ennå",
                body: "Oppdater verdien når du vil følge utviklingen."
            )
        } else if points.count == 1 {
            singlePointState(points[0])
        } else {
            chartContent
        }
    }

    private var chartContent: some View {
        Chart {
            ForEach(stackedRows) { row in
                AreaMark(
                    x: .value("Måned", row.date),
                    y: .value("Beløp", row.amount),
                    stacking: .standard
                )
                .foregroundStyle(by: .value("Beholdning", row.seriesKey))
                .interpolationMethod(.catmullRom)
                .opacity(areaOpacity)
            }

            ForEach(points) { point in
                LineMark(
                    x: .value("Måned", point.date),
                    y: .value("Total", point.total)
                )
                .lineStyle(StrokeStyle(lineWidth: 7.6, lineCap: .round, lineJoin: .round))
                .foregroundStyle(totalLineOutlineColor)
                .offset(y: -1)

                LineMark(
                    x: .value("Måned", point.date),
                    y: .value("Total", point.total)
                )
                .lineStyle(StrokeStyle(lineWidth: 4.8, lineCap: .round, lineJoin: .round))
                .foregroundStyle(totalLineColor)
                .offset(y: -1)
            }

            PointMark(
                x: .value("Siste måned", latest.date),
                y: .value("Siste total", latest.total)
            )
            .symbolSize(92)
            .foregroundStyle(totalLineOutlineColor)
            .offset(y: -1)

            PointMark(
                x: .value("Siste måned", latest.date),
                y: .value("Siste total", latest.total)
            )
            .symbolSize(30)
            .foregroundStyle(totalLineColor)
            .offset(y: -1)

            if let selectedPoint {
                RuleMark(x: .value("Valgt", selectedPoint.date))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                PointMark(
                    x: .value("Valgt", selectedPoint.date),
                    y: .value("Total", selectedPoint.total)
                )
                .symbolSize(isScrubbing ? 150 : 110)
                .foregroundStyle(AppTheme.primary)
                .opacity(isScrubbing ? 1 : 0.8)
            }
        }
        .frame(height: 260)
        .chartForegroundStyleScale(domain: stackedColorDomain, range: stackedColorRange)
        .chartLegend(position: .bottom, spacing: 2) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), alignment: .leading)], alignment: .leading, spacing: 2) {
                ForEach(latestVisibleBuckets) { bucket in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(areaFillColor(for: bucket))
                            .frame(width: 5, height: 5)
                        Text(bucket.name)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.78))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        }
        .chartXScale(domain: chartDateDomain())
        .chartXAxis {
            AxisMarks(values: InvestmentsDevelopmentChartDataBuilder.xAxisDates(points: points, period: period)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(monthLabel(date))
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(AppTheme.textSecondary.opacity(0.8))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: yTicks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(AppTheme.divider.opacity(0.12))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(formatAxisNOK(amount))
                    }
                }
                .foregroundStyle(AppTheme.textSecondary.opacity(0.76))
            }
        }
        .overlay(alignment: .topLeading) {
            if let selectedPoint {
                tooltip(for: selectedPoint)
                    .padding(10)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if interactionStart == nil {
                                    interactionStart = Date()
                                    return
                                }

                                guard let interactionStart else { return }
                                let holdDuration = Date().timeIntervalSince(interactionStart)
                                guard holdDuration >= 0.12 else { return }

                                if !isScrubbing {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                        isScrubbing = true
                                    }
                                    let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
                                    mediumHaptic.impactOccurred()
                                }

                                updateSelection(at: value.location, proxy: proxy, geometry: geometry)
                            }
                            .onEnded { _ in
                                interactionStart = nil
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.92)) {
                                    isScrubbing = false
                                    selectedPointID = nil
                                    selectedDate = nil
                                }
                            }
                    )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: period)
        .animation(.spring(response: 0.26, dampingFraction: 0.9), value: selectedPointID)
    }

    private func areaFillColor(for bucket: InvestmentsDevelopmentBucketPoint) -> Color {
        let base = bucket.color
        let opacity = colorScheme == .dark ? 0.34 : 0.22
        return base.opacity(opacity)
    }

    private func tooltip(for point: InvestmentsDevelopmentChartPoint) -> some View {
        let delta = InvestmentsDevelopmentChartDataBuilder.deltaSincePrevious(for: point, in: points)
        let topBuckets = InvestmentsDevelopmentChartDataBuilder.topBuckets(for: point)
        let rows = Array(topBuckets.prefix(3))
        return VStack(alignment: .leading, spacing: 4) {
            Text(monthTitle(point.date))
                .font(.caption.weight(.semibold))
            Text("Total: \(areAmountsHidden ? "•••• kr" : formatNOK(point.total))")
                .font(.caption.weight(.semibold))
            ForEach(rows) { row in
                HStack(spacing: 6) {
                    Circle()
                        .fill(row.color)
                        .frame(width: 7, height: 7)
                    Text("\(row.name): \(areAmountsHidden ? "•••• kr" : formatNOK(row.amount))")
                        .font(.caption2)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                Text(tooltipDeltaText(delta: delta))
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((delta >= 0 ? AppTheme.positive : AppTheme.negative).opacity(0.14), in: Capsule())
        }
        .padding(8)
        .frame(maxWidth: 220, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.divider, lineWidth: 1)
        )
    }

    private func tooltipDeltaText(delta: Double) -> String {
        if areAmountsHidden {
            if delta == 0 { return "Siden forrige: uendret" }
            return delta > 0 ? "Siden forrige: opp" : "Siden forrige: ned"
        }
        return "Siden forrige: \(delta >= 0 ? "+" : "-")\(formatNOK(abs(delta)))"
    }

    private func emptyState(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .appCardTitleStyle()
            Text(body)
                .appSecondaryStyle()
            Button("Oppdater verdi") {
                onUpdateValues()
            }
            .appProminentCTAStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private func singlePointState(_ point: InvestmentsDevelopmentChartPoint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Legg inn én måned til for å se utvikling.")
                .appSecondaryStyle()

            Chart {
                PointMark(
                    x: .value("Måned", point.date),
                    y: .value("Total", point.total)
                )
                .symbolSize(78)
                .foregroundStyle(AppTheme.primary)
            }
            .frame(height: 120)
            .chartXAxis {
                AxisMarks {
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisValueLabel()
                }
            }

            Button("Ny innsjekk") {
                onUpdateValues()
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.primary)
        }
    }

    private func chartDateDomain() -> ClosedRange<Date> {
        guard let first = points.first?.date, let last = points.last?.date else {
            let now = Date()
            return now ... now
        }
        return first ... last
    }

    private func monthLabel(_ date: Date) -> String {
        let month = Calendar.current.component(.month, from: date)
        let shortMonths = ["jan", "feb", "mar", "apr", "mai", "jun", "jul", "aug", "sep", "okt", "nov", "des"]
        guard month >= 1 && month <= shortMonths.count else { return "" }
        if period == .total {
            let year = Calendar.current.component(.year, from: date) % 100
            return "\(shortMonths[month - 1]) \(String(format: "%02d", year))"
        }
        return shortMonths[month - 1]
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date).capitalized
    }

    private func formatAxisNOK(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func updateSelection(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        let clampedX = min(max(location.x, frame.minX), frame.maxX)
        let relativeX = clampedX - frame.origin.x

        guard let date: Date = proxy.value(atX: relativeX),
              let nearest = InvestmentsDevelopmentChartDataBuilder.nearestPoint(to: date, points: points) else { return }

        if selectedPointID != nearest.id {
            let now = Date()
            if now.timeIntervalSince(lastHapticAt) > 0.06 {
                let lightHaptic = UIImpactFeedbackGenerator(style: .light)
                lightHaptic.impactOccurred()
                lastHapticAt = now
            }
        }

        selectedPointID = nearest.id
        selectedDate = nearest.date
    }
}
