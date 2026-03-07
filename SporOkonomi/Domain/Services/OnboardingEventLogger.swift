import Foundation

enum OnboardingEventLogger {
    private static let key = "onboarding_local_events"
    private static let maxEvents = 100

    static func log(_ event: String, at date: Date = .now) {
        let formatter = ISO8601DateFormatter()
        let row = "\(formatter.string(from: date))|\(event)"
        var existing = UserDefaults.standard.stringArray(forKey: key) ?? []
        existing.append(row)
        if existing.count > maxEvents {
            existing = Array(existing.suffix(maxEvents))
        }
        UserDefaults.standard.set(existing, forKey: key)
    }
}

