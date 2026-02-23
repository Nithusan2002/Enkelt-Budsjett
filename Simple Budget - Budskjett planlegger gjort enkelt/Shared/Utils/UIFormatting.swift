import Foundation
import SwiftUI

func formatNOK(_ value: Double) -> String {
    value.formatted(.currency(code: "NOK"))
}

func formatPercent(_ value: Double) -> String {
    value.formatted(.percent.precision(.fractionLength(1)))
}

func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "nb_NO")
    formatter.dateFormat = "dd-MM-yyyy"
    return formatter.string(from: date)
}

func formatPeriodKeyAsDate(_ periodKey: String) -> String {
    let parts = periodKey.split(separator: "-")
    guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else {
        return periodKey
    }
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = 1
    let date = Calendar.current.date(from: components) ?? .now
    return formatDate(date)
}

extension View {
    func appBigNumberStyle() -> some View {
        self
            .font(.system(.largeTitle, design: .default).weight(.semibold))
            .monospacedDigit()
    }

    func appCardTitleStyle() -> some View {
        self.font(.headline.weight(.semibold))
    }

    func appBodyStyle() -> some View {
        self.font(.subheadline)
    }

    func appSecondaryStyle() -> some View {
        self
            .font(.footnote)
            .foregroundStyle(AppTheme.textSecondary)
    }

    func appCoachStyle() -> some View {
        self
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .monospacedDigit()
    }

    func appCTAStyle() -> some View {
        self.font(.headline.weight(.semibold))
    }
}
