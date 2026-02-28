import Foundation
import Combine
import SwiftData
import SwiftUI
import LocalAuthentication

enum BootstrapPhase: Equatable {
    case idle
    case loadingProfile
    case applyingStartupRules
    case warmingLocalData
    case ready
    case failed

    var progress: Double {
        switch self {
        case .idle:
            return 0.05
        case .loadingProfile:
            return 0.25
        case .applyingStartupRules:
            return 0.45
        case .warmingLocalData:
            return 0.75
        case .ready:
            return 1.0
        case .failed:
            return 0.45
        }
    }

    var title: String {
        switch self {
        case .idle:
            return "Starter appen"
        case .loadingProfile:
            return "Laster innstillinger"
        case .applyingStartupRules:
            return "Klargjør oppstart"
        case .warmingLocalData:
            return "Forbereder data"
        case .ready:
            return "Klar"
        case .failed:
            return "Noe gikk galt"
        }
    }
}

@MainActor
final class AppRootViewModel: ObservableObject {
    @Published var bootstrapErrorMessage: String?
    @Published var bootstrapPhase: BootstrapPhase = .idle
    @Published var isLocked = false
    @Published var isAuthenticating = false
    @Published var lockErrorMessage: String?

    private var lockEnabled = false
    private var bootstrapTask: Task<Void, Never>?

    func bootstrap(context: ModelContext) {
        bootstrapTask?.cancel()
        do {
            bootstrapPhase = .loadingProfile
            try BootstrapService.ensurePreference(context: context)

            bootstrapPhase = .applyingStartupRules
            if ProcessInfo.processInfo.arguments.contains("UITEST_SKIP_ONBOARDING") {
                var descriptor = FetchDescriptor<UserPreference>()
                descriptor.fetchLimit = 1
                if let preference = try context.fetch(descriptor).first, !preference.onboardingCompleted {
                    preference.onboardingCompleted = true
                    preference.onboardingCurrentStep = 0
                    try context.save()
                }
            }

            bootstrapPhase = .warmingLocalData
            bootstrapTask = Task { @MainActor [weak self] in
                guard let self else { return }
                guard !Task.isCancelled else { return }
                do {
                    try BootstrapService.ensureCurrentBudgetMonthAndRecurring(context: context)
                    guard !Task.isCancelled else { return }
                    self.bootstrapErrorMessage = nil
                    self.bootstrapPhase = .ready
                } catch {
                    guard !Task.isCancelled else { return }
                    self.bootstrapErrorMessage = "Kunne ikke forberede lokale data."
                    self.bootstrapPhase = .failed
                }
            }
            bootstrapErrorMessage = nil
        } catch {
            bootstrapErrorMessage = "Kunne ikke laste lokale data."
            bootstrapPhase = .failed
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
