import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    let preference: UserPreference
    @StateObject private var viewModel: OnboardingViewModel

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
            Text(viewModel.progressText)
                .appSecondaryStyle()
                .frame(maxWidth: .infinity, alignment: .center)

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
                    text: $viewModel.monthlyIncomeText
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
                if let amountLabel = viewModel.summaryAmountLabel {
                    summaryRow("Månedlig inntekt", value: amountLabel)
                } else {
                    Text("Du kan legge til inntekt eller utgifter når du trenger det.")
                        .appBodyStyle()
                        .foregroundStyle(AppTheme.textPrimary)
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

    private func currencyField(label: String, placeholder: String, text: Binding<String>) -> some View {
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
