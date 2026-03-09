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
    private var demoProtectionTask: Task<Void, Never>?
    private var phaseStartedAt = Date()

    func bootstrap(context: ModelContext) {
        let bootstrapStartedAt = Date()
        bootstrapTask?.cancel()
        demoProtectionTask?.cancel()
        do {
            transition(to: .loadingProfile)
            try BootstrapService.removeDemoDataIfPresent(context: context)
            try BootstrapService.ensurePreference(context: context)

            transition(to: .applyingStartupRules)
            if ProcessInfo.processInfo.arguments.contains("UITEST_SKIP_ONBOARDING") {
                var descriptor = FetchDescriptor<UserPreference>()
                descriptor.fetchLimit = 1
                if let preference = try context.fetch(descriptor).first, !preference.onboardingCompleted {
                    preference.onboardingCompleted = true
                    preference.onboardingCurrentStep = 0
                    try context.guardedSave(
                        feature: "Bootstrap",
                        operation: "uitest_skip_onboarding",
                        enforceReadOnly: false
                    )
                }
            }

            transition(to: .warmingLocalData)
            bootstrapTask = Task { @MainActor [weak self] in
                guard let self else { return }
                guard !Task.isCancelled else { return }
                do {
                    try BootstrapService.ensureCurrentBudgetMonthAndRecurring(context: context)
                    guard !Task.isCancelled else { return }
                    self.bootstrapErrorMessage = nil
                    self.transition(to: .ready)
                    self.scheduleDemoProtection(context: context)
                    let total = Date().timeIntervalSince(bootstrapStartedAt)
                    PersistenceGate.recordInfo(
                        feature: "Bootstrap",
                        operation: "complete",
                        message: "total_seconds=\(String(format: "%.3f", total))"
                    )
                } catch {
                    guard !Task.isCancelled else { return }
                    self.bootstrapErrorMessage = "Kunne ikke forberede lokale data."
                    self.transition(to: .failed)
                    PersistenceGate.recordError(feature: "Bootstrap", operation: "warm_local_data_failed", error: error)
                }
            }
            bootstrapErrorMessage = nil
        } catch {
            bootstrapErrorMessage = "Kunne ikke laste lokale data."
            transition(to: .failed)
            PersistenceGate.recordError(feature: "Bootstrap", operation: "startup_failed", error: error)
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

    func refreshDemoProtection(context: ModelContext) {
        do {
            if try BootstrapService.removeDemoDataIfPresent(context: context) {
                bootstrap(context: context)
                return
            }
            scheduleDemoProtection(context: context)
        } catch {
            PersistenceGate.recordError(feature: "Bootstrap", operation: "remove_demo_data_failed", error: error)
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

    private func scheduleDemoProtection(context: ModelContext) {
        demoProtectionTask?.cancel()
        demoProtectionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<10 {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                do {
                    if try BootstrapService.removeDemoDataIfPresent(context: context) {
                        self.bootstrap(context: context)
                        return
                    }
                } catch {
                    PersistenceGate.recordError(feature: "Bootstrap", operation: "scheduled_demo_data_check_failed", error: error)
                    return
                }
            }
        }
    }

    private func transition(to newPhase: BootstrapPhase) {
        let now = Date()
        let duration = now.timeIntervalSince(phaseStartedAt)
        if bootstrapPhase != newPhase {
            PersistenceGate.recordInfo(
                feature: "Bootstrap",
                operation: "phase_\(bootstrapPhase)_duration",
                message: "seconds=\(String(format: "%.3f", duration))"
            )
        }
        bootstrapPhase = newPhase
        phaseStartedAt = now
    }
}
