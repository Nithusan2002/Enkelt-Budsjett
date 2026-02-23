import Foundation
import Combine
import SwiftData

@MainActor
final class SettingsViewModel: ObservableObject {
    func preference(from preferences: [UserPreference], context: ModelContext) -> UserPreference {
        if let existing = preferences.first {
            return existing
        }
        let newPref = UserPreference()
        context.insert(newPref)
        try? context.save()
        return newPref
    }

    func save(context: ModelContext) {
        try? context.save()
    }
}
