import SwiftUI
import UIKit

enum AppTheme {
    static let background = Color(light: "#FFF8F1", dark: "#0D1118")
    static let surface = Color(light: "#FFFFFF", dark: "#151C26")
    static let surfaceElevated = Color(light: "#FFFFFF", dark: "#1B2430")
    static let primary = Color(light: "#EA580C", dark: "#FB8A3C")
    static let secondary = Color(light: "#0EA5E9", dark: "#53C8FF")
    static let textPrimary = Color(light: "#1F2937", dark: "#F5F7FA")
    static let textSecondary = Color(light: "#6B7280", dark: "#A5B2C5")
    static let divider = Color(light: "#F1E7DC", dark: "#273244")
    static let positive = Color(light: "#16A34A", dark: "#3DD67A")
    static let warning = Color(light: "#D97706", dark: "#FFB547")
    static let negative = Color(light: "#DC2626", dark: "#FF6B6B")

    static let portfolioFund = Color(light: "#0EA5E9", dark: "#53C8FF")
    static let portfolioStock = Color(light: "#8B5CF6", dark: "#BE9BFF")
    static let portfolioBSU = Color(light: "#22C55E", dark: "#5CE08D")
    static let portfolioBuffer = Color(light: "#F59E0B", dark: "#FFC15D")
    static let portfolioIPS = Color(light: "#22C55E", dark: "#5CE08D")
    static let portfolioCrypto = Color(light: "#EA580C", dark: "#FB8A3C")
    static let customBucketPalette: [String] = [
        "#0EA5E9", "#8B5CF6", "#22C55E", "#EA580C",
        "#F43F5E", "#14B8A6", "#6366F1", "#F59E0B",
        "#10B981", "#EF4444", "#06B6D4", "#A855F7"
    ]

    static func portfolioColor(for bucketIDOrName: String) -> Color {
        let key = bucketIDOrName.lowercased()
        if key.contains("fond") || key.contains("fund") { return portfolioFund }
        if key.contains("aksjer") || key.contains("stock") { return portfolioStock }
        if key.contains("bsu") { return portfolioBSU }
        if key.contains("buffer") { return portfolioBuffer }
        if key.contains("ips") { return portfolioIPS }
        if key.contains("krypto") || key.contains("crypto") { return portfolioCrypto }
        return secondary
    }

    static func portfolioColor(for bucket: InvestmentBucket) -> Color {
        if let colorHex = bucket.colorHex, !colorHex.isEmpty {
            return Color(hex: colorHex)
        }
        return portfolioColor(for: bucket.name)
    }
}

extension Color {
    init(light: String, dark: String) {
        self.init(
            UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(Color(hex: dark))
                    : UIColor(Color(hex: light))
            }
        )
    }

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
