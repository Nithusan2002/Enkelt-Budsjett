import Foundation
import Combine
import SwiftData

enum OnboardingStep: Int, CaseIterable {
    case goal
    case minimumData
    case template
    case summary
    case firstAction
}

enum BudgetStarterPackage: String, CaseIterable {
    case simple
    case family
    case student
    case none
}

enum OnboardingGoalChoice: String, CaseIterable {
    case getOverview
    case reduceSpending
    case trackInvestments
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep
    @Published var focus: OnboardingFocus
    @Published var tone: AppToneStyle

    @Published var selectedGoal: OnboardingGoalChoice
    @Published var monthlyIncomeText = ""
    @Published var payday = 25
    @Published var monthlyBudgetText = ""
    @Published var budgetPackage: BudgetStarterPackage = .simple

    @Published var errorMessage: String?

    private var hasLoggedStart = false
    private var viewedSteps = Set<OnboardingStep>()

    init(preference: UserPreference) {
        self.focus = preference.onboardingFocus
        self.tone = preference.toneStyle
        self.currentStep = OnboardingStep(rawValue: preference.onboardingCurrentStep) ?? .goal

        switch preference.onboardingFocus {
        case .budget:
            self.selectedGoal = .reduceSpending
        case .investments:
            self.selectedGoal = .trackInvestments
        case .both:
            self.selectedGoal = .getOverview
        }
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
        case .goal, .minimumData, .template:
            return "Fortsett"
        case .summary:
            return "Fullfør oppsett"
        case .firstAction:
            return firstActionPrimaryButtonTitle
        }
    }

    var backButtonTitle: String? {
        canGoBack ? "Tilbake" : nil
    }

    var secondaryButtonTitle: String? {
        switch currentStep {
        case .goal:
            return "Hopp over"
        case .firstAction:
            return "Gå til oversikt"
        default:
            return nil
        }
    }

    var canGoBack: Bool {
        guard let idx = orderedSteps.firstIndex(of: currentStep) else { return false }
        return idx > 0
    }

    var isPrimaryDisabled: Bool {
        switch currentStep {
        case .minimumData:
            return isMonthlyIncomeRequired && parseDouble(monthlyIncomeText) == nil
        default:
            return false
        }
    }

    var isMonthlyIncomeRequired: Bool {
        selectedGoal != .trackInvestments
    }

    var monthlyIncomeLabel: String {
        isMonthlyIncomeRequired ? "Månedlig inntekt" : "Månedlig inntekt (valgfritt)"
    }

    var minimumDataHelpText: String {
        if isMonthlyIncomeRequired {
            return "Kun inntekt og lønnsdato er nødvendig nå."
        }
        return "Lønnsdato er nødvendig nå. Inntekt er valgfritt for investeringsmål."
    }

    var firstActionPrimaryButtonTitle: String {
        selectedGoal == .trackInvestments ? "Legg til første investering" : "Legg til første utgift"
    }

    func selectGoal(_ goal: OnboardingGoalChoice) {
        selectedGoal = goal
        switch goal {
        case .getOverview:
            focus = .both
        case .reduceSpending:
            focus = .budget
        case .trackInvestments:
            focus = .investments
        }
    }

    func selectTemplate(_ template: BudgetStarterPackage) {
        budgetPackage = template
    }

    func markCurrentStepSeen() {
        if !hasLoggedStart {
            logEvent("onboarding_started")
            hasLoggedStart = true
        }

        guard !viewedSteps.contains(currentStep) else { return }
        viewedSteps.insert(currentStep)
        logEvent("onboarding_step_viewed_\(eventName(for: currentStep))")

        if currentStep == .firstAction {
            logEvent("onboarding_aha_seen")
        }
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

    func back(preference: UserPreference, context: ModelContext) {
        do {
            try saveStepState(preference: preference, context: context)
            guard let idx = orderedSteps.firstIndex(of: currentStep), idx > 0 else { return }
            let previousStep = orderedSteps[idx - 1]
            preference.onboardingCurrentStep = previousStep.rawValue
            try context.guardedSave(feature: "Onboarding", operation: "save_step_transition")
            currentStep = previousStep
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Kunne ikke gå tilbake. Prøv igjen."
            setError(message)
        }
    }

    func primaryAction(preference: UserPreference, context: ModelContext) {
        if currentStep == .firstAction {
            finish(preference: preference, context: context)
        } else {
            next(preference: preference, context: context)
        }
    }

    func secondaryAction(preference: UserPreference, context: ModelContext) {
        switch currentStep {
        case .goal:
            skipAll(preference: preference, context: context)
        case .firstAction:
            finish(preference: preference, context: context)
        default:
            break
        }
    }

    func skipAll(preference: UserPreference, context: ModelContext) {
        monthlyIncomeText = ""
        monthlyBudgetText = ""
        budgetPackage = .none
        logEvent("onboarding_abandoned")
        finish(preference: preference, context: context)
    }

    func finish(preference: UserPreference, context: ModelContext) {
        let monthlyBudget = parseDouble(monthlyBudgetText)
        let monthlyIncome = parseDouble(monthlyIncomeText)
        let selectedBudgetCategories = categories(for: budgetPackage)

        do {
            try OnboardingService.complete(
                context: context,
                preference: preference,
                firstName: "",
                focus: focus,
                tone: tone,
                firstWealthTotal: nil,
                goalAmount: nil,
                goalDate: nil,
                snapshotValues: [:],
                snapshotInputProvided: false,
                budgetCategories: selectedBudgetCategories,
                monthlyBudget: monthlyBudget,
                monthlyIncome: monthlyIncome,
                incomeDayOfMonth: payday,
                budgetTrackOnly: budgetPackage == .none,
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

    func titleForFocus(_ value: OnboardingFocus) -> String {
        switch value {
        case .budget: return "Budsjett"
        case .investments: return "Investeringer"
        case .both: return "Begge"
        }
    }

    func title(for package: BudgetStarterPackage) -> String {
        switch package {
        case .simple: return "Enkel"
        case .family: return "Familie"
        case .student: return "Student"
        case .none: return "Ingen mal nå"
        }
    }

    func subtitle(for package: BudgetStarterPackage) -> String {
        switch package {
        case .simple: return "Mat, Bolig, Transport, Fritid, Sparing"
        case .family: return "Mat, Bolig, Transport, Barn, Sparing"
        case .student: return "Mat, Transport, Abonnement, Uteliv, Sparing"
        case .none: return "Opprett kategorier manuelt senere"
        }
    }

    func title(for goal: OnboardingGoalChoice) -> String {
        switch goal {
        case .getOverview:
            return "Få oversikt"
        case .reduceSpending:
            return "Redusere forbruk"
        case .trackInvestments:
            return "Følge investeringer"
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

    private func categories(for package: BudgetStarterPackage) -> [String] {
        switch package {
        case .simple:
            return ["Mat", "Bolig", "Transport", "Fritid", "Sparing"]
        case .family:
            return ["Mat", "Bolig", "Transport", "Barnehage", "Sparing"]
        case .student:
            return ["Mat", "Transport", "Abonnement", "Uteliv", "Sparing"]
        case .none:
            return []
        }
    }

    private func eventName(for step: OnboardingStep) -> String {
        switch step {
        case .goal: return "goal"
        case .minimumData: return "minimum_data"
        case .template: return "template"
        case .summary: return "summary"
        case .firstAction: return "first_action"
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
