import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    let preference: UserPreference
    @StateObject private var viewModel: OnboardingViewModel
    @FocusState private var focusedField: OnboardingInputField?

    private enum OnboardingInputField {
        case income
        case goalAmount
    }

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
                updateFocus(for: viewModel.currentStep)
            }
            .onChange(of: viewModel.currentStep) { _, newStep in
                viewModel.markCurrentStepSeen()
                updateFocus(for: newStep)
            }
            .onChange(of: viewModel.wantsGoal) { _, _ in
                updateFocus(for: viewModel.currentStep)
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
            HStack {
                if viewModel.canGoBack {
                    Button {
                        viewModel.goBack(preference: preference, context: modelContext)
                    } label: {
                        Label("Tilbake", systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(AppTheme.surface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Gå tilbake")
                } else {
                    Color.clear
                        .frame(width: 36, height: 36)
                }

                Text(viewModel.progressText)
                    .appSecondaryStyle()
                    .frame(maxWidth: .infinity, alignment: .center)

                Color.clear
                    .frame(width: 36, height: 36)
            }

            ProgressView(value: viewModel.progressFraction)
                .tint(AppTheme.primary)
                .frame(maxWidth: 220)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .intro:
            introStep
        case .income:
            incomeStep
        case .goal:
            goalStep
        case .summary:
            summaryStep
        }
    }

    private var introStep: some View {
        VStack(spacing: 18) {
            heroIcon(systemName: "eye")

            VStack(spacing: 8) {
                Text("Få roligere oversikt")
                    .appCardTitleStyle()
                Text("Spor økonomi hjelper deg å se hva du har igjen denne måneden, uten komplisert oppsett.")
                    .appBodyStyle()
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 36)
    }

    private var incomeStep: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("Hva får du inn i måneden?")
                    .appCardTitleStyle()
                Text("Et grovt beløp er nok. Du kan endre det senere.")
                    .appBodyStyle()
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                currencyField(
                    label: "Månedlig inntekt",
                    placeholder: "f.eks. 32 000",
                    text: $viewModel.monthlyIncomeText,
                    field: .income
                )
                .padding(12)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.divider, lineWidth: 1))

                if let preview = viewModel.incomePreviewText {
                    Text(preview)
                        .appSecondaryStyle()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: 460, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 24)
    }

    private var goalStep: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("Vil du spare mot et mål?")
                    .appCardTitleStyle()
                Text("Du kan legge det til nå eller vente til senere.")
                    .appBodyStyle()
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    goalOptionButton(title: "Ja", isSelected: viewModel.wantsGoal) {
                        viewModel.wantsGoal = true
                    }

                    goalOptionButton(title: "Ikke nå", isSelected: !viewModel.wantsGoal) {
                        viewModel.wantsGoal = false
                    }
                }

                if viewModel.wantsGoal {
                    currencyField(
                        label: "Målbeløp",
                        placeholder: "f.eks. 250 000",
                        text: $viewModel.goalAmountText,
                        field: .goalAmount
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Måldato")
                            .appBodyStyle()
                        DatePicker(
                            "Måldato",
                            selection: $viewModel.goalDate,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appInputShellStyle()
                    }

                    if let preview = viewModel.goalMonthlyPreviewText {
                        Text(preview)
                            .appSecondaryStyle()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(12)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.divider, lineWidth: 1))
            .frame(maxWidth: 460, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 24)
    }

    private var summaryStep: some View {
        VStack(spacing: 18) {
            heroIcon(systemName: "checkmark.circle")

            VStack(spacing: 8) {
                Text(viewModel.summaryTitle)
                    .appCardTitleStyle()
                Text(viewModel.summaryBodyText)
                    .appBodyStyle()
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 10) {
                if let amountLabel = viewModel.summaryPreviewAmountLabel {
                    Text(amountLabel)
                        .font(.system(size: 28, weight: .semibold, design: .default))
                        .foregroundStyle(AppTheme.textPrimary)
                        .monospacedDigit()
                }

                if let goalContext = viewModel.summaryGoalContextText {
                    summaryRow("Sparing", value: goalContext)
                }

                Text(viewModel.summaryHelpText)
                    .appSecondaryStyle()
            }
            .padding(12)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.divider, lineWidth: 1))
            .frame(maxWidth: 460, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 24)
    }

    private var footerButtons: some View {
        VStack(spacing: 8) {
            Button(viewModel.primaryButtonTitle) {
                viewModel.primaryAction(preference: preference, context: modelContext)
            }
            .frame(maxWidth: .infinity)
            .appProminentCTAStyle()
            .disabled(viewModel.isPrimaryDisabled)
            .accessibilityLabel(viewModel.primaryButtonTitle)

            if let secondary = viewModel.secondaryButtonTitle {
                Button(secondary) {
                    viewModel.secondaryAction(preference: preference, context: modelContext)
                }
                .appSecondaryStyle()
                .accessibilityLabel(secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: 420, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
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

    private func currencyField(label: String, placeholder: String, text: Binding<String>, field: OnboardingInputField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .appBodyStyle()
            HStack {
                Text("kr")
                    .appSecondaryStyle()
                TextField(placeholder, text: monetaryBinding(text))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused($focusedField, equals: field)
            }
            .appInputShellStyle()
        }
    }

    private func goalOptionButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? AppTheme.onPrimary : AppTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? AppTheme.primary : AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? AppTheme.primary : AppTheme.divider, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
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

    private func updateFocus(for step: OnboardingStep) {
        switch step {
        case .income:
            focusedField = .income
        case .goal:
            focusedField = viewModel.wantsGoal ? .goalAmount : nil
        default:
            focusedField = nil
        }
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
            FixedItem.self,
            FixedItemSkip.self,
            Goal.self,
            Challenge.self,
            UserPreference.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else {
            fatalError("Kunne ikke opprette preview-container for OnboardingView")
        }
        return container
    }()

    static let preference: UserPreference = {
        let pref = UserPreference(onboardingCompleted: false)
        container.mainContext.insert(pref)
        try? container.mainContext.save()
        return pref
    }()
}
