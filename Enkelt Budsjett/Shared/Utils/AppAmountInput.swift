import Foundation

enum AppAmountInput {
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withoutWhitespace = trimmed.components(separatedBy: .whitespacesAndNewlines).joined()
        let normalized = withoutWhitespace
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }

    static func formatLive(_ rawText: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let filtered = trimmed.filter { $0.isNumber || $0 == "," || $0 == "." }
        let separatorIndex = filtered.firstIndex(where: { $0 == "," || $0 == "." })

        let integerPartRaw: String
        let fractionRaw: String
        let hasSeparator: Bool
        let endsWithSeparator: Bool

        if let separatorIndex {
            integerPartRaw = String(filtered[..<separatorIndex])
            let after = filtered.index(after: separatorIndex)
            if after < filtered.endIndex {
                fractionRaw = String(filtered[after...]).filter(\.isNumber)
            } else {
                fractionRaw = ""
            }
            hasSeparator = true
            endsWithSeparator = separatorIndex == filtered.index(before: filtered.endIndex)
        } else {
            integerPartRaw = filtered.filter(\.isNumber)
            fractionRaw = ""
            hasSeparator = false
            endsWithSeparator = false
        }

        let integerDigits = integerPartRaw.filter(\.isNumber)
        let integerValue = Double(integerDigits) ?? 0
        let formattedInteger = format(integerValue)

        if hasSeparator {
            let fraction = String(fractionRaw.prefix(2))
            if endsWithSeparator || !fraction.isEmpty {
                return "\(formattedInteger),\(fraction)"
            }
        }
        return formattedInteger
    }
}
