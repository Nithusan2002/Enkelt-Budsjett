import Foundation
import Combine
import SwiftData

enum OnboardingStep: Int, CaseIterable {
    case intro
    case goals
    case income
    case fixedCosts
    case investmentTypes

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
        case investmentTypes.rawValue:
            return .investmentTypes
        default:
            return .fixedCosts
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
    case electricity
    case subscriptions
    case transport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rent:
            return "Husleie"
        case .electricity:
            return "Strøm"
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
        case .electricity:
            return 600
        case .subscriptions:
            return 800
        case .transport:
            return 900
        }
    }
}

enum OnboardingInvestmentTypeOption: String, CaseIterable, Identifiable {
    case funds
    case stocks
    case crypto
    case cash
    case bsu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .funds:
            return "Fond"
        case .stocks:
            return "Aksjer"
        case .crypto:
            return "Krypto"
        case .cash:
            return "Kontanter"
        case .bsu:
            return "BSU"
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
    @Published var selectedInvestmentTypes: Set<OnboardingInvestmentTypeOption> = []
    @Published var customInvestmentTypeName = ""
    @Published var isCustomInvestmentTypeSelected = false
    @Published var errorMessage: String?

    private var hasLoggedStart = false
    private var viewedSteps = Set<OnboardingStep>()

    init(preference: UserPreference) {
        self.focus = preference.onboardingFocus
        self.tone = preference.toneStyle
        self.currentStep = OnboardingStep.fromStoredValue(preference.onboardingCurrentStep)
    }

    var orderedSteps: [OnboardingStep] {
        var steps: [OnboardingStep] = [.intro, .goals, .income, .fixedCosts]
        if shouldShowInvestmentTypesStep {
            steps.append(.investmentTypes)
        }
        return steps
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
            return shouldShowInvestmentTypesStep ? "Neste" : "Ferdig"
        case .investmentTypes:
            return "Fortsett"
        }
    }

    var secondaryButtonTitle: String? {
        switch currentStep {
        case .intro:
            return "Hopp over intro"
        case .goals:
            return "Ikke nå"
        case .income:
            return "Ikke nå"
        case .fixedCosts:
            return "Ikke nå"
        case .investmentTypes:
            return nil
        }
    }

    var canGoBack: Bool {
        orderedSteps.firstIndex(of: currentStep).map { $0 > 0 } ?? false
    }

    var isPrimaryDisabled: Bool {
        switch currentStep {
        case .income:
            let trimmed = monthlyIncomeText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            guard let monthlyIncome else { return true }
            return monthlyIncome <= 0
        default:
            return false
        }
    }

    var introTitle: String {
        "Se hvor mye du faktisk har igjen hver måned"
    }

    var introBodyText: String {
        "Få roligere oversikt uten komplisert oppsett."
    }

    var introPreviewEyebrow: String {
        "Eksempel"
    }

    var introPreviewTitle: String {
        "6 200 kr igjen denne måneden"
    }

    var introPreviewFootnote: String {
        "Tallene her er bare et eksempel."
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
        return "Brukes bare for et raskt anslag."
    }

    var fixedCostsBodyText: String {
        "Velg det som passer."
    }

    var fixedCostsSupportText: String {
        "Du kan justere dette senere."
    }

    var shouldShowInvestmentTypesStep: Bool {
        selectedGoals.contains(.followInvestments) || focus == .investments || currentStep == .investmentTypes
    }

    var investmentTypesTitle: String {
        "Hvilke investeringer vil du følge?"
    }

    var investmentTypesBodyText: String {
        "Velg typene som passer for deg. Du kan endre dette senere."
    }

    var orderedInvestmentTypeOptions: [OnboardingInvestmentTypeOption] {
        OnboardingInvestmentTypeOption.allCases
    }

    var hasCustomInvestmentType: Bool {
        !customInvestmentTypeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedInvestmentTypeNames: [String] {
        let suggested = orderedInvestmentTypeOptions
            .filter { selectedInvestmentTypes.contains($0) }
            .map(\.title)

        let trimmedCustom = customInvestmentTypeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCustomInvestmentTypeSelected && !trimmedCustom.isEmpty {
            return suggested + [trimmedCustom]
        }
        return suggested
    }

    var resolvedInvestmentTypeNamesForCompletion: [String] {
        guard shouldShowInvestmentTypesStep else { return [] }
        return selectedInvestmentTypeNames
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

    func toggleInvestmentType(_ option: OnboardingInvestmentTypeOption) {
        if selectedInvestmentTypes.contains(option) {
            selectedInvestmentTypes.remove(option)
        } else {
            selectedInvestmentTypes.insert(option)
        }
    }

    func saveCustomInvestmentType() -> Bool {
        let trimmed = customInvestmentTypeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setError("Skriv inn et navn på investeringstypen.")
            return false
        }

        let suggestedNames = Set(orderedInvestmentTypeOptions.map { $0.title.lowercased() })
        if suggestedNames.contains(trimmed.lowercased()) {
            setError("Denne investeringstypen finnes allerede i forslagene.")
            return false
        }

        customInvestmentTypeName = trimmed
        isCustomInvestmentTypeSelected = true
        clearError()
        return true
    }

    func removeCustomInvestmentType() {
        customInvestmentTypeName = ""
        isCustomInvestmentTypeSelected = false
    }

    func toggleCustomInvestmentTypeSelection() {
        guard hasCustomInvestmentType else { return }
        isCustomInvestmentTypeSelected.toggle()
    }

    func markCurrentStepSeen() {
        if !hasLoggedStart {
            logEvent("onboarding_started")
            hasLoggedStart = true
        }

        guard !viewedSteps.contains(currentStep) else { return }
        viewedSteps.insert(currentStep)
        logEvent("onboarding_step_viewed_\(eventName(for: currentStep))")
        if currentStep == .fixedCosts && !shouldShowInvestmentTypesStep {
            logEvent("onboarding_aha_seen")
        } else if currentStep == .investmentTypes {
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
        if currentStep == .investmentTypes || (currentStep == .fixedCosts && !shouldShowInvestmentTypesStep) {
            finish(preference: preference, context: context)
        } else {
            next(preference: preference, context: context)
        }
    }

    func secondaryAction(preference: UserPreference, context: ModelContext) {
        switch currentStep {
        case .goals:
            selectedGoals.removeAll()
            focus = .both
            next(preference: preference, context: context)
        case .income:
            monthlyIncomeText = ""
            next(preference: preference, context: context)
        case .fixedCosts:
            selectedFixedCosts.removeAll()
            if shouldShowInvestmentTypesStep {
                next(preference: preference, context: context)
            } else {
                finish(preference: preference, context: context)
            }
        case .investmentTypes:
            finish(preference: preference, context: context)
        case .intro:
            next(preference: preference, context: context)
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
                selectedBuckets: resolvedInvestmentTypeNamesForCompletion,
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
        case .investmentTypes:
            return "investment_types"
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
