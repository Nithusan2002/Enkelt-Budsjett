import Foundation
import Combine
import SwiftData

@MainActor
final class AppRootViewModel: ObservableObject {
    func bootstrap(context: ModelContext) {
        try? BootstrapService.ensurePreference(context: context)
    }
}
