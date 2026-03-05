import Foundation

enum InvestmentsHistoryHelper {
    static func filteredHistorySnapshots(
        _ history: [InvestmentSnapshot],
        months: Int?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [InvestmentSnapshot] {
        guard let months else { return history }
        let normalizedMonths = max(months, 1)
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let start = calendar.date(byAdding: .month, value: -(normalizedMonths - 1), to: monthStart) ?? monthStart
        return history.filter { snapshot in
            guard let snapshotDate = DateService.monthStart(from: snapshot.periodKey) else { return false }
            return snapshotDate >= start
        }
    }
}

enum InvestmentsBucketChartHelper {
    private static let monthLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "MMM yy"
        return formatter
    }()

    static func normalizedRange(_ range: GraphViewRange) -> GraphViewRange {
        range == .last12Months ? .oneYear : range
    }

    static func rangeTitle(_ range: GraphViewRange) -> String {
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

    static func chartDateDomain(for snapshots: [InvestmentSnapshot], now: Date = .now) -> ClosedRange<Date> {
        guard let first = snapshots.first?.capturedAt,
              let last = snapshots.last?.capturedAt else {
            return now ... now
        }
        return first ... last
    }

    static func xAxisDates(for snapshots: [InvestmentSnapshot], range: GraphViewRange) -> [Date] {
        let dates = snapshots.map(\.capturedAt)
        guard !dates.isEmpty else { return [] }

        let targetCount: Int
        switch normalizedRange(range) {
        case .yearToDate:
            targetCount = 4
        case .oneYear:
            targetCount = 6
        case .twoYears:
            targetCount = 6
        case .threeYears:
            targetCount = 7
        case .fiveYears:
            targetCount = 7
        case .max:
            targetCount = 8
        case .last12Months:
            targetCount = 6
        }

        if dates.count <= targetCount { return dates }
        let step = max(1, dates.count / targetCount)
        var selected = stride(from: 0, to: dates.count, by: step).map { dates[$0] }
        if selected.last != dates.last, let last = dates.last {
            selected.append(last)
        }
        return selected
    }

    static func nearestSnapshot(to date: Date, in snapshots: [InvestmentSnapshot]) -> InvestmentSnapshot? {
        snapshots.min(by: {
            abs($0.capturedAt.timeIntervalSince(date)) < abs($1.capturedAt.timeIntervalSince(date))
        })
    }

    static func monthLabel(_ date: Date) -> String {
        monthLabelFormatter.string(from: date).capitalized
    }

    static func compactNOK(_ value: Double) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""
        if absValue >= 1_000_000 {
            return "\(sign)\((absValue / 1_000_000).formatted(.number.precision(.fractionLength(1))))m"
        }
        if absValue >= 1_000 {
            return "\(sign)\((absValue / 1_000).formatted(.number.precision(.fractionLength(0))))k"
        }
        return "\(sign)\(Int(absValue.rounded()))"
    }
}
