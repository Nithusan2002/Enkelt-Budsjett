import Foundation
import Combine
import SwiftData
import SwiftUI
import LocalAuthentication

@MainActor
final class AppRootViewModel: ObservableObject {
    @Published var bootstrapErrorMessage: String?
    @Published var isLocked = false
    @Published var isAuthenticating = false
    @Published var lockErrorMessage: String?

    private var lockEnabled = false

    func bootstrap(context: ModelContext) {
        do {
            try BootstrapService.ensurePreference(context: context)
            if ProcessInfo.processInfo.arguments.contains("UITEST_SKIP_ONBOARDING") {
                var descriptor = FetchDescriptor<UserPreference>()
                descriptor.fetchLimit = 1
                if let preference = try context.fetch(descriptor).first, !preference.onboardingCompleted {
                    preference.onboardingCompleted = true
                    preference.onboardingCurrentStep = 0
                    try context.save()
                }
            }
            try BootstrapService.ensureCurrentBudgetMonthAndRecurring(context: context)
            bootstrapErrorMessage = nil
        } catch {
            bootstrapErrorMessage = "Kunne ikke laste lokale data."
        }
    }

    func configureLock(enabled: Bool) {
        lockEnabled = enabled
        if !enabled {
            isLocked = false
            isAuthenticating = false
            lockErrorMessage = nil
            return
        }

        if !isLocked {
            isLocked = true
            authenticate()
        }
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        guard lockEnabled else { return }
        if phase == .background || phase == .inactive {
            isLocked = true
            lockErrorMessage = nil
        } else if phase == .active, isLocked {
            authenticate()
        }
    }

    func retryUnlock() {
        authenticate()
    }

    private func authenticate() {
        guard lockEnabled else { return }
        guard !isAuthenticating else { return }
        isAuthenticating = true
        lockErrorMessage = nil

        let context = LAContext()
        context.localizedCancelTitle = "Ikke nå"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isAuthenticating = false
            lockErrorMessage = "Kan ikke bruke Face ID eller kode på denne enheten."
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Lås opp budsjettet ditt"
        ) { [weak self] success, evaluateError in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isAuthenticating = false
                if success {
                    self.isLocked = false
                    self.lockErrorMessage = nil
                } else {
                    self.isLocked = true
                    self.lockErrorMessage = evaluateError?.localizedDescription ?? "Kunne ikke bekrefte identitet."
                }
            }
        }
    }
}
