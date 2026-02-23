import SwiftUI

enum AppTheme {
    static let background = Color(hex: "#FFF8F1")
    static let surface = Color(hex: "#FFFFFF")
    static let primary = Color(hex: "#EA580C")
    static let secondary = Color(hex: "#0EA5E9")
    static let textPrimary = Color(hex: "#1F2937")
    static let textSecondary = Color(hex: "#6B7280")
    static let divider = Color(hex: "#F1E7DC")
    static let positive = Color(hex: "#16A34A")
    static let warning = Color(hex: "#D97706")
    static let negative = Color(hex: "#DC2626")

    static let portfolioFund = Color(hex: "#0EA5E9")
    static let portfolioStock = Color(hex: "#8B5CF6")
    static let portfolioIPS = Color(hex: "#22C55E")
    static let portfolioCrypto = Color(hex: "#EA580C")

    static func portfolioColor(for bucketIDOrName: String) -> Color {
        let key = bucketIDOrName.lowercased()
        if key.contains("fond") || key.contains("fund") { return portfolioFund }
        if key.contains("aksjer") || key.contains("stock") { return portfolioStock }
        if key.contains("ips") { return portfolioIPS }
        if key.contains("krypto") || key.contains("crypto") { return portfolioCrypto }
        return secondary
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
