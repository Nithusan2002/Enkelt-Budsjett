import Foundation
import Combine
import SwiftData

enum OnboardingStep: Int, CaseIterable {
    case intro
    case income
    case summary

    static func fromStoredValue(_ rawValue: Int) -> OnboardingStep {
        switch rawValue {
        case intro.rawValue:
            return .intro
        case income.rawValue:
            return .income
        default:
            return .summary
        }
    }
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep
    @Published var focus: OnboardingFocus
    @Published var tone: AppToneStyle

    @Published var monthlyIncomeText = ""

    @Published var errorMessage: String?

    private var hasLoggedStart = false
    private var viewedSteps = Set<OnboardingStep>()

    init(preference: UserPreference) {
        self.focus = preference.onboardingFocus
        self.tone = preference.toneStyle
        self.currentStep = OnboardingStep.fromStoredValue(preference.onboardingCurrentStep)
    }

    var orderedSteps: [OnboardingStep] {
        OnboardingStep.allCases
    }

    var currentStepIndex: Int {
        (orderedSteps.firstIndex(of: currentStep) ?? 0) + 1
    }

    var totalSteps: Int {
        orderedSteps.count
    }

    var progressFraction: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(currentStepIndex) / Double(totalSteps)
    }

    var progressText: String {
        "Steg \(currentStepIndex) av \(totalSteps)"
    }

    var primaryButtonTitle: String {
        switch currentStep {
        case .intro:
            return "Kom i gang"
        case .income:
            return "Fortsett"
        case .summary:
            return "Gå til oversikt"
        }
    }

    var secondaryButtonTitle: String? {
        "Hopp over"
    }

    var isPrimaryDisabled: Bool {
        switch currentStep {
        case .income:
            let trimmed = monthlyIncomeText.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && parseDouble(trimmed) == nil
        default:
            return false
        }
    }

    var summaryTitle: String {
        "Slik starter oversikten din"
    }

    var summaryBodyText: String {
        hasMonthlyIncome
            ? "Du har nå et enkelt utgangspunkt for denne måneden."
            : "Du kan fortsatt komme i gang uten oppsett."
    }

    var summaryHelpText: String {
        hasMonthlyIncome
            ? "Legg til utgifter underveis, så blir oversikten mer presis."
            : "Legg til inntekt eller utgifter når du vil, så bygger oversikten seg opp."
    }

    var summaryAmountLabel: String? {
        guard hasMonthlyIncome, let monthlyIncome else { return nil }
        return formatNOK(monthlyIncome)
    }

    var hasMonthlyIncome: Bool {
        monthlyIncome != nil
    }

    private var monthlyIncome: Double? {
        parseDouble(monthlyIncomeText)
    }

    func markCurrentStepSeen() {
        if !hasLoggedStart {
            logEvent("onboarding_started")
            hasLoggedStart = true
        }

        guard !viewedSteps.contains(currentStep) else { return }
        viewedSteps.insert(currentStep)
        logEvent("onboarding_step_viewed_\(eventName(for: currentStep))")
        if currentStep == .summary { logEvent("onboarding_aha_seen") }
    }

    func next(preference: UserPreference, context: ModelContext) {
        do {
            try saveStepState(preference: preference, context: context)
            guard let idx = orderedSteps.firstIndex(of: currentStep), idx < orderedSteps.count - 1 else { return }
            let nextStep = orderedSteps[idx + 1]
            preference.onboardingCurrentStep = nextStep.rawValue
            try context.guardedSave(feature: "Onboarding", operation: "save_step_transition")
            currentStep = nextStep
            markCurrentStepSeen()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Kunne ikke lagre fremdrift. Prøv igjen."
            setError(message)
        }
    }

    func primaryAction(preference: UserPreference, context: ModelContext) {
        if currentStep == .summary {
            finish(preference: preference, context: context)
        } else {
            next(preference: preference, context: context)
        }
    }

    func secondaryAction(preference: UserPreference, context: ModelContext) {
        skipAll(preference: preference, context: context)
    }

    func skipAll(preference: UserPreference, context: ModelContext) {
        monthlyIncomeText = ""
        logEvent("onboarding_abandoned")
        finish(preference: preference, context: context)
    }

    func finish(preference: UserPreference, context: ModelContext) {
        do {
            try OnboardingService.complete(
                context: context,
                preference: preference,
                firstName: "",
                focus: .both,
                tone: tone,
                firstWealthTotal: nil,
                goalAmount: nil,
                goalDate: nil,
                snapshotValues: [:],
                snapshotInputProvided: false,
                budgetCategories: [],
                monthlyBudget: nil,
                monthlyIncome: monthlyIncome,
                incomeDayOfMonth: 25,
                budgetTrackOnly: true,
                reminderEnabled: false,
                reminderDay: 5,
                reminderHour: 18,
                reminderMinute: 0,
                faceIDEnabled: false,
                selectedBuckets: ["Fond", "Aksjer", "BSU", "Buffer"],
                customBucketName: nil
            )
            logEvent("onboarding_completed")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Kunne ikke fullføre onboarding. Prøv igjen."
            setError(message)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func saveStepState(preference: UserPreference, context: ModelContext) throws {
        preference.onboardingFocus = focus
        preference.toneStyle = tone
        preference.onboardingCurrentStep = currentStep.rawValue
        preference.checkInReminderEnabled = false
        preference.faceIDLockEnabled = false
        try context.guardedSave(feature: "Onboarding", operation: "save_step_state")
    }

    private func eventName(for step: OnboardingStep) -> String {
        switch step {
        case .intro: return "intro"
        case .income: return "income"
        case .summary: return "summary"
        }
    }

    private func parseDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func logEvent(_ event: String) {
        OnboardingEventLogger.log(event)
    }

    private func setError(_ message: String) {
        errorMessage = message
        logEvent("onboarding_error")
    }
}
