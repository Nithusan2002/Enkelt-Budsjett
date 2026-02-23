import Foundation
import Combine
import SwiftData

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case focus
    case goal
    case snapshot
    case budget
    case habits
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep
    @Published var focus: OnboardingFocus
    @Published var tone: AppToneStyle
    @Published var showDemo = false

    @Published var includeIncome = false
    @Published var monthlyIncomeText = ""

    @Published var goalAmountText = ""
    @Published var goalDate = Calendar.current.date(byAdding: .month, value: 24, to: .now) ?? .now

    @Published var snapshotText: [String: String] = [
        "Fond": "",
        "Aksjer": "",
        "IPS": "",
        "Krypto": ""
    ]
    @Published var monthlyFlowText = ""

    @Published var budgetCategories: [String: Bool] = [
        "Mat": true,
        "Bolig": true,
        "Transport": true,
        "Fritid": true,
        "Sparing": true
    ]
    @Published var monthlyBudgetText = ""
    @Published var budgetTrackOnly = false

    @Published var reminderEnabled = true
    @Published var reminderDay = 5
    @Published var faceIDEnabled = false

    init(preference: UserPreference) {
        self.focus = preference.onboardingFocus
        self.tone = preference.toneStyle
        self.currentStep = OnboardingStep(rawValue: preference.onboardingCurrentStep) ?? .welcome
        self.reminderEnabled = preference.checkInReminderEnabled
        self.reminderDay = preference.checkInReminderDay
        self.faceIDEnabled = preference.faceIDLockEnabled
    }

    var orderedSteps: [OnboardingStep] {
        switch focus {
        case .budget:
            return [.welcome, .focus, .goal, .budget, .snapshot, .habits]
        case .investments:
            return [.welcome, .focus, .goal, .snapshot, .budget, .habits]
        case .both:
            return [.welcome, .focus, .goal, .snapshot, .budget, .habits]
        }
    }

    var progressText: String {
        guard let idx = orderedSteps.firstIndex(of: currentStep) else { return "1 av 6" }
        return "\(idx + 1) av 6"
    }

    func next(preference: UserPreference, context: ModelContext) {
        saveStepState(preference: preference, context: context)
        guard let idx = orderedSteps.firstIndex(of: currentStep), idx < orderedSteps.count - 1 else { return }
        currentStep = orderedSteps[idx + 1]
        preference.onboardingCurrentStep = currentStep.rawValue
        try? context.save()
        logEvent("onboarding_step_advanced")
    }

    func skipCurrent(preference: UserPreference, context: ModelContext) {
        if currentStep == .welcome {
            finish(preference: preference, context: context, forceReminderOff: true)
            logEvent("onboarding_skipped_from_welcome")
            return
        }
        if currentStep == .habits {
            finish(preference: preference, context: context, forceReminderOff: true)
            logEvent("onboarding_completed_without_reminder")
            return
        }
        next(preference: preference, context: context)
        logEvent("onboarding_step_skipped")
    }

    func finish(preference: UserPreference, context: ModelContext, forceReminderOff: Bool = false) {
        let selectedBuckets = ["Fond", "Aksjer", "IPS", "Krypto"]
        let goalAmount = parseDouble(goalAmountText)
        let income = parseDouble(monthlyIncomeText)
        let flow = parseDouble(monthlyFlowText)
        let selectedBudgetCategories = budgetCategories.filter(\.value).map(\.key)
        let monthlyBudget = parseDouble(monthlyBudgetText)
        let snapshotValues = snapshotText.reduce(into: [String: Double]()) { partialResult, entry in
            partialResult[entry.key] = parseDouble(entry.value) ?? 0
        }
        let snapshotInputProvided = snapshotText.values.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        try? OnboardingService.complete(
            context: context,
            preference: preference,
            focus: focus,
            tone: tone,
            includeIncome: includeIncome,
            monthlyIncome: includeIncome ? income : nil,
            goalAmount: goalAmount,
            goalDate: goalAmount != nil ? goalDate : nil,
            snapshotValues: snapshotValues,
            snapshotInputProvided: snapshotInputProvided,
            monthlyFlow: flow,
            budgetCategories: selectedBudgetCategories.isEmpty ? ["Mat", "Bolig", "Transport", "Fritid", "Sparing"] : selectedBudgetCategories,
            monthlyBudget: budgetTrackOnly ? nil : monthlyBudget,
            budgetTrackOnly: budgetTrackOnly,
            reminderEnabled: forceReminderOff ? false : reminderEnabled,
            reminderDay: reminderEnabled ? reminderDay : 5,
            faceIDEnabled: faceIDEnabled,
            selectedBuckets: selectedBuckets,
            customBucketName: nil
        )
        logEvent("onboarding_completed")
    }

    func titleForFocus(_ value: OnboardingFocus) -> String {
        switch value {
        case .budget: return "Budsjett"
        case .investments: return "Investeringer"
        case .both: return "Begge"
        }
    }

    func titleForTone(_ value: AppToneStyle) -> String {
        switch value {
        case .calm: return "Rolig og nøktern"
        case .warm: return "Varm motivasjon"
        case .nudges: return "Korte nudges"
        }
    }

    func subtitleForTone(_ value: AppToneStyle) -> String {
        switch value {
        case .calm: return "Klar og rolig tekst uten ekstra dytt."
        case .warm: return "Vennlig energi med fokus på små steg."
        case .nudges: return "Ekstra korte påminnelser og raske tips."
        }
    }

    private func saveStepState(preference: UserPreference, context: ModelContext) {
        preference.onboardingFocus = focus
        preference.toneStyle = tone
        preference.onboardingCurrentStep = currentStep.rawValue
        preference.checkInReminderEnabled = reminderEnabled
        preference.checkInReminderDay = max(1, min(28, reminderDay))
        preference.faceIDLockEnabled = faceIDEnabled
        try? context.save()
    }

    private func parseDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    private func logEvent(_ event: String) {
        print("[onboarding_event] \(event)")
    }
}
