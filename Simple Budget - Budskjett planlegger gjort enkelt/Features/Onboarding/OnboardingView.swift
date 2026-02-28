import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    let preference: UserPreference
    @StateObject private var viewModel: OnboardingViewModel
    @State private var showOptionalBudget = false

    init(preference: UserPreference) {
        self.preference = preference
        _viewModel = StateObject(wrappedValue: OnboardingViewModel(preference: preference))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                topBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        stepContent
                        footerButtons
                            .padding(.top, 6)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                    .frame(maxWidth: 560, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.vertical)
            .background(AppTheme.background)
            .navigationTitle("Kom i gang")
            .appKeyboardDismissToolbar()
            .onAppear {
                viewModel.markCurrentStepSeen()
            }
            .onChange(of: viewModel.currentStep) { _, _ in
                viewModel.markCurrentStepSeen()
            }
            .alert(
                "Kunne ikke lagre",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.clearError() } }
                )
            ) {
                Button("OK", role: .cancel) {
                    viewModel.clearError()
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isHeroStep {
                Text(viewModel.progressText)
                    .appSecondaryStyle()
                    .frame(maxWidth: .infinity, alignment: .center)

                ProgressView(value: viewModel.progressFraction)
                    .tint(AppTheme.primary)
                    .frame(maxWidth: 220)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                HStack {
                    Text(viewModel.progressText)
                        .appSecondaryStyle()
                    Spacer()
                }
                ProgressView(value: viewModel.progressFraction)
                    .tint(AppTheme.primary)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .goal:
            goalStep
        case .minimumData:
            minimumDataStep
        case .template:
            templateStep
        case .summary:
            summaryStep
        case .firstAction:
            firstActionStep
        }
    }

    private var goalStep: some View {
        VStack(spacing: 18) {
            heroIcon(systemName: "eye")

            VStack(spacing: 8) {
                Text("Hva vil du oppnå først?")
                    .appCardTitleStyle()
                Text("Vi tilpasser oppstarten. Du kan endre alt senere.")
                    .appBodyStyle()
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(OnboardingGoalChoice.allCases, id: \.rawValue) { goal in
                    Button {
                        viewModel.selectGoal(goal)
                    } label: {
                        HStack {
                            Text(viewModel.title(for: goal))
                                .appBodyStyle()
                            Spacer()
                            if viewModel.selectedGoal == goal {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.primary)
                            }
                        }
                        .padding(12)
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.divider, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(viewModel.title(for: goal))
                }
            }
            .frame(maxWidth: 460, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 24)
    }

    private var minimumDataStep: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("La oss sette et enkelt utgangspunkt")
                    .appCardTitleStyle()
                Text(viewModel.minimumDataHelpText)
                    .appBodyStyle()
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                currencyField(
                    label: viewModel.monthlyIncomeLabel,
                    placeholder: "f.eks. 45 000",
                    text: $viewModel.monthlyIncomeText
                )

                Stepper(value: $viewModel.payday, in: 1...28) {
                    Text("Lønnsdato: \(viewModel.payday)")
                        .appBodyStyle()
                }
                .accessibilityLabel("Lønnsdato")

                DisclosureGroup(
                    isExpanded: $showOptionalBudget,
                    content: {
                        currencyField(
                            label: "Månedsbudsjett (valgfritt)",
                            placeholder: "f.eks. 22 000",
                            text: $viewModel.monthlyBudgetText
                        )
                        .padding(.top, 8)
                    },
                    label: {
                        Text("Legg til månedsbudsjett (valgfritt)")
                            .appBodyStyle()
                    }
                )
                .padding(12)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.divider, lineWidth: 1))
            }
            .frame(maxWidth: 460, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 24)
    }

    private var templateStep: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("Velg en startmal")
                    .appCardTitleStyle()
                Text("Malen oppretter kategorier du kan redigere senere.")
                    .appBodyStyle()
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(BudgetStarterPackage.allCases, id: \.rawValue) { template in
                    Button {
                        viewModel.selectTemplate(template)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(viewModel.title(for: template))
                                    .appBodyStyle()
                                Text(viewModel.subtitle(for: template))
                                    .appSecondaryStyle()
                            }
                            Spacer()
                            if viewModel.budgetPackage == template {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.primary)
                            }
                        }
                        .padding(12)
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.divider, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(viewModel.title(for: template))
                }
            }
            .frame(maxWidth: 460, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 24)
    }

    private var summaryStep: some View {
        VStack(spacing: 18) {
            Text("Slik ser oppsettet ditt ut")
                .appCardTitleStyle()
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 10) {
                summaryRow("Månedlig inntekt", value: monthlyIncomeSummary)
                summaryRow("Lønnsdato", value: "Dag \(viewModel.payday)")
                summaryRow("Valgt mål", value: viewModel.title(for: viewModel.selectedGoal))
                summaryRow("Valgt mal", value: viewModel.title(for: viewModel.budgetPackage))
            }
            .padding(12)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.divider, lineWidth: 1))
            .frame(maxWidth: 460, alignment: .leading)

            Text("Du kan endre alt senere i Innstillinger.")
                .appSecondaryStyle()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 24)
    }

    private var firstActionStep: some View {
        VStack(spacing: 18) {
            heroIcon(systemName: "sparkles")

            Text("Bra start")
                .appCardTitleStyle()
            Text("Ett lite steg nå gir deg bedre oversikt med én gang.")
                .appBodyStyle()
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 36)
    }

    private var monthlyIncomeSummary: String {
        let trimmed = viewModel.monthlyIncomeText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Ikke satt" : "kr \(trimmed)"
    }

    private var footerButtons: some View {
        VStack(spacing: 8) {
            Button(viewModel.primaryButtonTitle) {
                viewModel.primaryAction(preference: preference, context: modelContext)
            }
            .frame(maxWidth: .infinity)
            .appCTAStyle()
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primary)
            .disabled(viewModel.isPrimaryDisabled)
            .accessibilityLabel(viewModel.primaryButtonTitle)

            if let secondary = viewModel.secondaryButtonTitle {
                Button(secondary) {
                    viewModel.secondaryAction(preference: preference, context: modelContext)
                }
                .appSecondaryStyle()
                .accessibilityLabel(secondary)
            }
        }
        .frame(maxWidth: 420, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var isHeroStep: Bool {
        viewModel.currentStep == .goal || viewModel.currentStep == .firstAction
    }

    private func heroIcon(systemName: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(AppTheme.surface)
                .frame(width: 112, height: 112)
            Image(systemName: systemName)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
        }
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .appSecondaryStyle()
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func currencyField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .appBodyStyle()
            HStack {
                Text("kr")
                    .appSecondaryStyle()
                TextField(placeholder, text: monetaryBinding(text))
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }
            .appInputShellStyle()
        }
    }

    private func monetaryBinding(_ source: Binding<String>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue },
            set: { newValue in
                source.wrappedValue = formatMonetaryInput(newValue)
            }
        )
    }

    private func formatMonetaryInput(_ raw: String) -> String {
        let text = raw.replacingOccurrences(of: " ", with: "")
        let digits = String(text.filter(\.isNumber))
        guard !digits.isEmpty else { return "" }
        return groupedThousands(digits)
    }

    private func groupedThousands(_ digits: String) -> String {
        var result = ""
        let reversed = Array(digits.reversed())
        for (index, char) in reversed.enumerated() {
            if index > 0 && index % 3 == 0 {
                result.append(" ")
            }
            result.append(char)
        }
        return String(result.reversed())
    }
}

#Preview {
    OnboardingView(preference: OnboardingPreviewData.preference)
        .modelContainer(OnboardingPreviewData.container)
}

private enum OnboardingPreviewData {
    static let container: ModelContainer = {
        let schema = Schema([
            BudgetMonth.self,
            Category.self,
            BudgetPlan.self,
            BudgetGroupPlan.self,
            Transaction.self,
            Account.self,
            InvestmentBucket.self,
            InvestmentSnapshot.self,
            InvestmentSnapshotValue.self,
            FixedItem.self,
            FixedItemSkip.self,
            Goal.self,
            Challenge.self,
            UserPreference.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    static let preference: UserPreference = {
        let pref = UserPreference(onboardingCompleted: false)
        container.mainContext.insert(pref)
        try? container.mainContext.save()
        return pref
    }()
}
