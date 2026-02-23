import Foundation
import Combine
import SwiftData

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case focus
    case firstWealth
    case budget
    case goal
    case habits
}

enum BudgetStarterPackage: String, CaseIterable {
    case basic
    case student
    case trackingOnly
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep
    @Published var focus: OnboardingFocus
    @Published var tone: AppToneStyle
    @Published var showDemo = false

    @Published var goalAmountText = ""
    @Published var goalDate = Calendar.current.date(byAdding: .month, value: 24, to: .now) ?? .now

    @Published var firstWealthTotalText = ""
    @Published var showBucketBreakdown = false
    @Published var snapshotText: [String: String] = [
        "Fond": "",
        "Aksjer": "",
        "BSU": "",
        "Buffer": "",
        "Krypto": ""
    ]

    @Published var budgetPackage: BudgetStarterPackage = .basic
    @Published var monthlyBudgetText = ""

    @Published var reminderEnabled = true
    @Published var reminderDay = 5
    @Published var reminderTime = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now
    @Published var faceIDEnabled = false

    init(preference: UserPreference) {
        self.focus = preference.onboardingFocus
        self.tone = preference.toneStyle
        self.currentStep = OnboardingStep(rawValue: preference.onboardingCurrentStep) ?? .welcome
        self.reminderEnabled = preference.checkInReminderEnabled
        self.reminderDay = preference.checkInReminderDay
        self.reminderTime = Calendar.current.date(
            bySettingHour: preference.checkInReminderHour,
            minute: preference.checkInReminderMinute,
            second: 0,
            of: .now
        ) ?? .now
        self.faceIDEnabled = preference.faceIDLockEnabled
    }

    var orderedSteps: [OnboardingStep] {
        switch focus {
        case .budget:
            return [.welcome, .focus, .budget, .firstWealth, .goal, .habits]
        case .investments:
            return [.welcome, .focus, .firstWealth, .budget, .goal, .habits]
        case .both:
            return [.welcome, .focus, .firstWealth, .budget, .goal, .habits]
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
        if currentStep == .goal {
            goalAmountText = ""
            next(preference: preference, context: context)
            logEvent("onboarding_goal_skipped")
            return
        }
        if currentStep == .firstWealth {
            firstWealthTotalText = ""
            showBucketBreakdown = false
            snapshotText = ["Fond": "", "Aksjer": "", "BSU": "", "Buffer": "", "Krypto": ""]
            next(preference: preference, context: context)
            logEvent("onboarding_first_wealth_skipped")
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
        let selectedBuckets = ["Fond", "Aksjer", "BSU", "Buffer", "Krypto"]
        let totalWealth = parseDouble(firstWealthTotalText)
        let goalAmount = parseDouble(goalAmountText)
        let selectedBudgetCategories = categories(for: budgetPackage)
        let monthlyBudget = parseDouble(monthlyBudgetText)
        let snapshotValues = snapshotText.reduce(into: [String: Double]()) { partialResult, entry in
            partialResult[entry.key] = parseDouble(entry.value) ?? 0
        }
        let snapshotInputProvided = totalWealth != nil || snapshotText.values.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let reminderHour = Calendar.current.component(.hour, from: reminderTime)
        let reminderMinute = Calendar.current.component(.minute, from: reminderTime)

        try? OnboardingService.complete(
            context: context,
            preference: preference,
            focus: focus,
            tone: tone,
            firstWealthTotal: totalWealth,
            goalAmount: goalAmount,
            goalDate: goalAmount != nil ? goalDate : nil,
            snapshotValues: snapshotValues,
            snapshotInputProvided: snapshotInputProvided,
            budgetCategories: selectedBudgetCategories,
            monthlyBudget: budgetPackage == .trackingOnly ? nil : monthlyBudget,
            budgetTrackOnly: budgetPackage == .trackingOnly,
            reminderEnabled: forceReminderOff ? false : reminderEnabled,
            reminderDay: reminderEnabled ? reminderDay : 5,
            reminderHour: reminderEnabled ? reminderHour : 18,
            reminderMinute: reminderEnabled ? reminderMinute : 0,
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
        preference.checkInReminderHour = Calendar.current.component(.hour, from: reminderTime)
        preference.checkInReminderMinute = Calendar.current.component(.minute, from: reminderTime)
        preference.faceIDLockEnabled = faceIDEnabled
        try? context.save()
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

    func title(for package: BudgetStarterPackage) -> String {
        switch package {
        case .basic: return "Basic (anbefalt)"
        case .student: return "Student"
        case .trackingOnly: return "Bare sporing"
        }
    }

    func subtitle(for package: BudgetStarterPackage) -> String {
        switch package {
        case .basic: return "Mat, Transport, Fritid, Bolig, Sparing"
        case .student: return "Mat, Transport, Abonnement, Uteliv, Sparing"
        case .trackingOnly: return "Ingen grenser nå"
        }
    }

    private func categories(for package: BudgetStarterPackage) -> [String] {
        switch package {
        case .basic:
            return ["Mat", "Transport", "Fritid", "Bolig", "Sparing"]
        case .student:
            return ["Mat", "Transport", "Abonnement", "Uteliv", "Sparing"]
        case .trackingOnly:
            return []
        }
    }
}
