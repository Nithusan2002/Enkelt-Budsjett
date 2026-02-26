import SwiftUI
import Charts
import UIKit

enum InvestmentsDevelopmentPeriod: String, CaseIterable {
    case sixMonths
    case last12Months
    case total

    var title: String {
        switch self {
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
            let rows = sortedBuckets.map { bucket in
                let amount = snapshot.bucketValues.first(where: { $0.bucketID == bucket.id })?.amount ?? 0
                return InvestmentsDevelopmentBucketPoint(
                    id: "\(snapshot.periodKey)-\(bucket.id)",
                    bucketID: bucket.id,
                    name: bucket.name,
                    color: AppTheme.portfolioColor(for: bucket),
                    amount: amount
                )
            }
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
        period: InvestmentsDevelopmentPeriod
    ) -> String {
        guard let first = points.first, let last = points.last else {
            return "Ingen utviklingsdata ennå."
        }

        let delta = last.total - first.total
        let sign = delta >= 0 ? "opp" : "ned"
        let top = topBuckets(for: last)
        let topText: String
        if let firstTop = top.first {
            let share = last.total > 0 ? firstTop.amount / last.total : 0
            topText = "Største bøtte: \(firstTop.name) (\(formatPercent(share)))."
        } else {
            topText = "Ingen bøtter med verdi ennå."
        }
        return "\(period.title): total \(sign) \(formatNOK(abs(delta))). \(topText)"
    }

    static func topBuckets(for point: InvestmentsDevelopmentChartPoint) -> [InvestmentsDevelopmentBucketPoint] {
        point.buckets
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
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
    let points: [InvestmentsDevelopmentChartPoint]
    @Binding var period: InvestmentsDevelopmentPeriod
    let onUpdateValues: () -> Void

    @State private var selectedDate: Date?
    @State private var selectedPointID: String?

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
                    bucketName: bucket.name,
                    amount: bucket.amount
                )
            }
        }
    }

    private var stackedColorDomain: [String] {
        latest.buckets.map(\.name)
    }

    private var stackedColorRange: [Color] {
        latest.buckets.map(\.color)
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
        colorScheme == .dark ? 0.82 : 0.88
    }

    private var totalLineColor: Color {
        colorScheme == .dark ? AppTheme.textPrimary.opacity(0.55) : AppTheme.textPrimary.opacity(0.42)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            controls
            content
            Text("Basert på totalsummene du legger inn.")
                .appSecondaryStyle()
        }
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.divider, lineWidth: 1)
        )
        .accessibilityLabel("Utviklingsgraf")
        .accessibilityValue(
            InvestmentsDevelopmentChartDataBuilder.accessibilitySummary(
                points: points,
                period: period
            )
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Utvikling")
                .appCardTitleStyle()
            if let last = points.last {
                Text(formatNOK(last.total))
                    .font(.system(size: 34, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("Ingen data")
                    .font(.title3.weight(.semibold))
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
                title: "Legg inn første insjekk",
                body: "Oppdater verdier for å starte utviklingsgrafen."
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
                .foregroundStyle(by: .value("Beholdning", row.bucketName))
                .interpolationMethod(.catmullRom)
                .opacity(areaOpacity)
            }

            ForEach(points) { point in
                LineMark(
                    x: .value("Måned", point.date),
                    y: .value("Total", point.total)
                )
                .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                .foregroundStyle(totalLineColor)
            }

            if let selectedPoint {
                RuleMark(x: .value("Valgt", selectedPoint.date))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .topLeading) {
                        tooltip(for: selectedPoint)
                    }
            }
        }
        .frame(height: 260)
        .chartForegroundStyleScale(domain: stackedColorDomain, range: stackedColorRange)
        .chartLegend(position: .bottom, spacing: 8)
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
                .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: yTicks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.7))
                    .foregroundStyle(AppTheme.divider.opacity(0.35))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(formatAxisNOK(amount))
                    }
                }
                .foregroundStyle(AppTheme.textSecondary)
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
                                guard let plotFrame = proxy.plotFrame else { return }
                                let origin = geometry[plotFrame].origin
                                let relativeX = value.location.x - origin.x
                                guard let date: Date = proxy.value(atX: relativeX),
                                      let nearest = InvestmentsDevelopmentChartDataBuilder.nearestPoint(to: date, points: points) else { return }
                                if selectedPointID != nearest.id {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                                selectedPointID = nearest.id
                                selectedDate = nearest.date
                            }
                            .onEnded { _ in
                                selectedPointID = nil
                                selectedDate = nil
                            }
                    )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: period)
    }

    private func tooltip(for point: InvestmentsDevelopmentChartPoint) -> some View {
        let delta = InvestmentsDevelopmentChartDataBuilder.deltaSincePrevious(for: point, in: points)
        let topBuckets = InvestmentsDevelopmentChartDataBuilder.topBuckets(for: point)
        let rows = topBuckets.count <= 5 ? topBuckets : Array(topBuckets.prefix(3))
        return VStack(alignment: .leading, spacing: 4) {
            Text(monthTitle(point.date))
                .font(.caption.weight(.semibold))
            Text("Total: \(formatNOK(point.total))")
                .font(.caption.weight(.semibold))
            ForEach(rows) { row in
                HStack(spacing: 6) {
                    Circle()
                        .fill(row.color)
                        .frame(width: 7, height: 7)
                    Text("\(row.name): \(formatNOK(row.amount))")
                        .font(.caption2)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                Text("Siden forrige: \(delta >= 0 ? "+" : "-")\(formatNOK(abs(delta)))")
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((delta >= 0 ? AppTheme.positive : AppTheme.negative).opacity(0.14), in: Capsule())
        }
        .padding(8)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.divider, lineWidth: 1)
        )
    }

    private func emptyState(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .appCardTitleStyle()
            Text(body)
                .appSecondaryStyle()
            Button("Oppdater verdier") {
                onUpdateValues()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primary)
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

            Button("Oppdater verdier") {
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
}
