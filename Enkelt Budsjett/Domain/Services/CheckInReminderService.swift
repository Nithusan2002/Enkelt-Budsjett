import Foundation
import UserNotifications

enum CheckInReminderError: LocalizedError {
    case authorizationDenied
    case scheduleFailed

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Varsler er avslått. Aktiver varsler i Innstillinger for å få påminnelser."
        case .scheduleFailed:
            return "Kunne ikke planlegge påminnelse akkurat nå."
        }
    }
}

enum CheckInReminderService {
    static let notificationIdentifier = "monthly_checkin_reminder"

    static func syncFromPreference(_ preference: UserPreference) async throws {
        try await update(
            enabled: preference.checkInReminderEnabled,
            day: preference.checkInReminderDay,
            hour: preference.checkInReminderHour,
            minute: preference.checkInReminderMinute
        )
    }

    static func update(enabled: Bool, day: Int, hour: Int, minute: Int) async throws {
        let center = UNUserNotificationCenter.current()
        if !enabled {
            center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
            center.removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])
            return
        }

        let granted = try await requestAuthorizationIfNeeded(center: center)
        guard granted else {
            throw CheckInReminderError.authorizationDenied
        }

        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])

        let clampedDay = max(1, min(28, day))
        let clampedHour = max(0, min(23, hour))
        let clampedMinute = max(0, min(59, minute))

        var dateComponents = DateComponents()
        dateComponents.calendar = Calendar.current
        dateComponents.timeZone = TimeZone.current
        dateComponents.day = clampedDay
        dateComponents.hour = clampedHour
        dateComponents.minute = clampedMinute

        let content = UNMutableNotificationContent()
        content.title = "Månedlig innsjekk"
        content.body = "Oppdater formuen din i Spor økonomi."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            trigger: trigger
        )

        try await addRequest(request, center: center)
    }

    private static func requestAuthorizationIfNeeded(center: UNUserNotificationCenter) async throws -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        @unknown default:
            return false
        }
    }

    private static func addRequest(_ request: UNNotificationRequest, center: UNUserNotificationCenter) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
