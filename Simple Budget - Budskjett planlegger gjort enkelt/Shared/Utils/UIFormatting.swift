import Foundation
import SwiftUI
import UIKit

enum AppDateFormatters {
    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter
    }()

    static let monthYearShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    static let monthName: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "MMMM"
        return formatter
    }()
}

struct AppInputFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.body)
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.divider, lineWidth: 1)
            )
    }
}

func formatNOK(_ value: Double) -> String {
    value.formatted(.currency(code: "NOK"))
}

func formatPercent(_ value: Double) -> String {
    value.formatted(.percent.precision(.fractionLength(1)))
}

func clampedProgress(value: Double, total: Double) -> (value: Double, total: Double) {
    let safeTotal = max(total, 1)
    let safeValue = min(max(value, 0), safeTotal)
    return (safeValue, safeTotal)
}

func formatDate(_ date: Date) -> String {
    AppDateFormatters.fullDate.string(from: date)
}

func formatMonthYearShort(_ date: Date) -> String {
    AppDateFormatters.monthYearShort.string(from: date)
}

func formatMonthName(_ date: Date) -> String {
    AppDateFormatters.monthName.string(from: date)
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

    func appInputShellStyle() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.divider, lineWidth: 1)
            )
    }

    func appKeyboardDismissToolbar() -> some View {
        self.modifier(AppKeyboardDismissToolbarModifier())
    }
}

extension TextFieldStyle where Self == AppInputFieldStyle {
    static var appInput: AppInputFieldStyle { AppInputFieldStyle() }
}

private struct AppKeyboardDismissToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3.weight(.semibold))
                }
                .accessibilityLabel("Lukk tastatur")
            }
        }
    }
}
