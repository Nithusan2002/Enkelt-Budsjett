import Foundation
import SwiftUI

func formatNOK(_ value: Double) -> String {
    value.formatted(.currency(code: "NOK"))
}

func formatPercent(_ value: Double) -> String {
    value.formatted(.percent.precision(.fractionLength(1)))
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
