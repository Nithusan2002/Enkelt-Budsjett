import Foundation
import Combine
import SwiftData

enum OnboardingStep: Int, CaseIterable {
    case intro
    case goals
    case income
    case fixedCosts
    case summary

    static func fromStoredValue(_ rawValue: Int) -> OnboardingStep {
        switch rawValue {
        case intro.rawValue:
            return .intro
        case goals.rawValue:
            return .goals
        case income.rawValue:
            return .income
        case fixedCosts.rawValue:
            return .fixedCosts
        default:
            return .summary
        }
    }
}

enum OnboardingGoalOption: String, CaseIterable, Identifiable {
    case saveMore
    case getOverview
    case keepBudget
    case followInvestments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .saveMore:
            return "Spare mer"
        case .getOverview:
            return "Få oversikt"
        case .keepBudget:
            return "Holde budsjett"
        case .followInvestments:
            return "Følge investeringer"
        }
    }
}

enum OnboardingFixedCostOption: String, CaseIterable, Identifiable {
    case rent
    case food
    case subscriptions
    case transport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rent:
            return "Husleie"
        case .food:
            return "Mat"
        case .subscriptions:
            return "Abonnement"
        case .transport:
            return "Transport"
        }
    }

    var estimatedMonthlyCost: Double {
        switch self {
        case .rent:
            return 3_500
        case .food:
            return 1_500
        case .subscriptions:
            return 800
        case .transport:
            return 900
        }
    }
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep
    @Published var focus: OnboardingFocus
    @Published var tone: AppToneStyle

    @Published var selectedGoals: Set<OnboardingGoalOption> = []
    @Published var monthlyIncomeText = ""
    @Published var selectedFixedCosts: Set<OnboardingFixedCostOption> = []
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

    var showsProgressHeader: Bool {
        currentStep != .intro
    }

    var primaryButtonTitle: String {
        switch currentStep {
        case .intro:
            return "Kom i gang"
        case .goals:
            return "Neste"
        case .income:
            return "Neste"
        case .fixedCosts:
            return "Se resultat"
        case .summary:
            return "Start appen"
        }
    }

    var secondaryButtonTitle: String? {
        switch currentStep {
        case .summary:
            return nil
        case .fixedCosts:
            return "Ikke nå"
        default:
            return "Hopp over"
        }
    }

    var canGoBack: Bool {
        orderedSteps.firstIndex(of: currentStep).map { $0 > 0 } ?? false
    }

    var isPrimaryDisabled: Bool {
        switch currentStep {
        case .income:
            guard let monthlyIncome else { return true }
            return monthlyIncome <= 0
        default:
            return false
        }
    }

    var introTitle: String {
        "Få kontroll på økonomien din"
    }

    var introBodyText: String {
        "Se hvor mye du har igjen hver måned."
    }

    var summaryTitle: String {
        "Du er klar"
    }

    var summaryBadgeText: String {
        "Klar til bruk"
    }

    var summaryConfirmationText: String {
        "Økonomien din er satt opp"
    }

    var summaryHelpText: String {
        "Basert på det du har lagt inn så langt."
    }

    var summaryResultText: String {
        "Du har ca. \(resultAmountText) igjen denne måneden"
    }

    var resultAmount: Double {
        max((monthlyIncome ?? 0) - totalEstimatedFixedCosts, 0)
    }

    var resultAmountText: String {
        formatWholeKroner(resultAmount)
    }

    var selectedGoalsSummary: String? {
        guard !selectedGoals.isEmpty else { return nil }
        let titles = selectedGoals
            .sorted { $0.title < $1.title }
            .map(\.title)
            .joined(separator: " · ")
        return titles
    }

    var fixedCostHelpText: String? {
        guard !selectedFixedCosts.isEmpty else { return nil }
        return "Vi bruker dette til et raskt estimat nå."
    }

    var monthlyIncome: Double? {
        parseDouble(monthlyIncomeText)
    }

    private var totalEstimatedFixedCosts: Double {
        selectedFixedCosts.reduce(0) { $0 + $1.estimatedMonthlyCost }
    }

    func toggleGoal(_ option: OnboardingGoalOption) {
        if selectedGoals.contains(option) {
            selectedGoals.remove(option)
        } else {
            selectedGoals.insert(option)
        }
        focus = resolvedFocus(from: selectedGoals)
    }

    func toggleFixedCost(_ option: OnboardingFixedCostOption) {
        if selectedFixedCosts.contains(option) {
            selectedFixedCosts.remove(option)
        } else {
            selectedFixedCosts.insert(option)
        }
    }

    func markCurrentStepSeen() {
        if !hasLoggedStart {
            logEvent("onboarding_started")
            hasLoggedStart = true
        }

        guard !viewedSteps.contains(currentStep) else { return }
        viewedSteps.insert(currentStep)
        logEvent("onboarding_step_viewed_\(eventName(for: currentStep))")
        if currentStep == .summary {
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

    func primaryAction(preference: UserPreference, context: ModelContext) {
        if currentStep == .summary {
            finish(preference: preference, context: context)
        } else {
            next(preference: preference, context: context)
        }
    }

    func secondaryAction(preference: UserPreference, context: ModelContext) {
        if currentStep == .fixedCosts {
            selectedFixedCosts.removeAll()
            next(preference: preference, context: context)
        } else {
            skipAll(preference: preference, context: context)
        }
    }

    func goBack(preference: UserPreference, context: ModelContext) {
        guard let idx = orderedSteps.firstIndex(of: currentStep), idx > 0 else { return }

        do {
            try saveStepState(preference: preference, context: context)
            let previousStep = orderedSteps[idx - 1]
            preference.onboardingCurrentStep = previousStep.rawValue
            try context.guardedSave(feature: "Onboarding", operation: "save_step_back_transition")
            currentStep = previousStep
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Kunne ikke gå tilbake. Prøv igjen."
            setError(message)
        }
    }

    func skipAll(preference: UserPreference, context: ModelContext) {
        selectedGoals.removeAll()
        selectedFixedCosts.removeAll()
        monthlyIncomeText = ""
        focus = .both
        logEvent("onboarding_abandoned")
        finish(preference: preference, context: context)
    }

    func finish(preference: UserPreference, context: ModelContext) {
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
                budgetCategories: selectedFixedCosts.sorted { $0.title < $1.title }.map(\.title),
                monthlyBudget: nil,
                monthlyIncome: monthlyIncome,
                incomeDayOfMonth: 25,
                budgetTrackOnly: true,
                reminderEnabled: false,
                reminderDay: 5,
                reminderHour: 18,
                reminderMinute: 0,
                faceIDEnabled: false,
                selectedBuckets: ["Fond", "Aksjer", "Krypto", "Kontanter"],
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

    private func resolvedFocus(from goals: Set<OnboardingGoalOption>) -> OnboardingFocus {
        let includesInvestments = goals.contains(.followInvestments)
        let includesBudget = goals.contains(.saveMore) || goals.contains(.getOverview) || goals.contains(.keepBudget)

        switch (includesBudget, includesInvestments) {
        case (true, true):
            return .both
        case (true, false):
            return .budget
        case (false, true):
            return .investments
        case (false, false):
            return .both
        }
    }

    private func eventName(for step: OnboardingStep) -> String {
        switch step {
        case .intro:
            return "intro"
        case .goals:
            return "goals"
        case .income:
            return "income"
        case .fixedCosts:
            return "fixed_costs"
        case .summary:
            return "summary"
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

    private func formatWholeKroner(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        let formatted = rounded.formatted(
            .number
                .locale(Locale(identifier: "nb_NO"))
                .grouping(.automatic)
        )
        return "\(formatted.replacingOccurrences(of: "\u{00A0}", with: " ")) kr"
    }
}
