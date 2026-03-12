import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    let preference: UserPreference
    @StateObject private var viewModel: OnboardingViewModel
    @FocusState private var focusedField: OnboardingInputField?
    @State private var animatedResultAmount = 0

    private enum OnboardingInputField {
        case income
    }

    init(preference: UserPreference) {
        self.preference = preference
        _viewModel = StateObject(wrappedValue: OnboardingViewModel(preference: preference))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    backgroundLayer

                    VStack(spacing: 12) {
                        topBar

                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 14) {
                                ZStack {
                                    stepContent
                                        .id(viewModel.currentStep)
                                        .transition(
                                            .asymmetric(
                                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                                removal: .opacity.combined(with: .move(edge: .leading))
                                            )
                                        )
                                }
                                .frame(maxWidth: .infinity, alignment: .center)

                                footerButtons
                            }
                            .frame(minHeight: geometry.size.height - 132, alignment: .top)
                            .padding(.horizontal)
                            .padding(.top, 2)
                            .padding(.bottom, max(18, geometry.safeAreaInsets.bottom + 8))
                            .frame(maxWidth: 560, alignment: .center)
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .navigationTitle(viewModel.showsProgressHeader ? "Kom i gang" : "")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Ferdig") {
                        focusedField = nil
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            .animation(.easeInOut(duration: 0.24), value: viewModel.currentStep)
            .onAppear {
                viewModel.markCurrentStepSeen()
                updateFocus(for: viewModel.currentStep)
                updateAnimatedResult(for: viewModel.currentStep)
            }
            .onChange(of: viewModel.currentStep) { _, newStep in
                viewModel.markCurrentStepSeen()
                updateFocus(for: newStep)
                updateAnimatedResult(for: newStep)
            }
            .onChange(of: viewModel.monthlyIncomeText) { _, _ in
                if viewModel.currentStep == .summary {
                    updateAnimatedResult(for: .summary)
                }
            }
            .onChange(of: viewModel.selectedFixedCosts) { _, _ in
                if viewModel.currentStep == .summary {
                    updateAnimatedResult(for: .summary)
                }
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

    private var backgroundLayer: some View {
        ZStack(alignment: .top) {
            AppTheme.background
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    AppTheme.primary.opacity(viewModel.currentStep == .intro ? 0.20 : 0.10),
                    AppTheme.primary.opacity(0.05),
                    AppTheme.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxHeight: 360, alignment: .top)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
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
                    Color.clear.frame(width: 36, height: 36)
                }

                if viewModel.showsProgressHeader {
                    Text(viewModel.progressText)
                        .appSecondaryStyle()
                        .frame(maxWidth: .infinity, alignment: .center)
                    Color.clear.frame(width: 36, height: 36)
                } else {
                    Text("Spor økonomi")
                        .font(.footnote.weight(.semibold))
                        .tracking(0.4)
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            if viewModel.showsProgressHeader {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppTheme.surfaceElevated)
                        Capsule()
                            .fill(AppTheme.primary)
                            .frame(width: max(28, geometry.size.width * viewModel.progressFraction))
                    }
                }
                .frame(height: 8)
                .frame(maxWidth: 220)
                .frame(maxWidth: .infinity, alignment: .center)
                .animation(.easeInOut(duration: 0.25), value: viewModel.progressFraction)
            }
        }
        .padding(.horizontal)
        .padding(.top, viewModel.showsProgressHeader ? 0 : 28)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .intro:
            introStep
        case .goals:
            goalsStep
        case .income:
            incomeStep
        case .fixedCosts:
            fixedCostsStep
        case .summary:
            summaryStep
        }
    }

    private var introStep: some View {
        VStack(spacing: 22) {
            introPreviewCard

            VStack(spacing: 8) {
                Text(viewModel.introTitle)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(viewModel.introBodyText)
                    .appBodyStyle()
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 10)
    }

    private var goalsStep: some View {
        VStack(spacing: 16) {
            headerBlock(
                title: "Hva vil du oppnå?",
                body: "Velg det som passer best for deg."
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(OnboardingGoalOption.allCases) { option in
                    selectionCard(
                        title: option.title,
                        subtitle: nil,
                        isSelected: viewModel.selectedGoals.contains(option)
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            viewModel.toggleGoal(option)
                        }
                    }
                }
            }

            if let summary = viewModel.selectedGoalsSummary {
                Text(summary)
                    .appSecondaryStyle()
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 460, alignment: .center)
        .padding(.top, 12)
    }

    private var incomeStep: some View {
        VStack(spacing: 16) {
            headerBlock(
                title: "Hva tjener du per måned?",
                body: "Et grovt tall holder."
            )

            VStack(spacing: 12) {
                currencyField(
                    label: "Månedlig inntekt",
                    placeholder: "f.eks. 12 000",
                    text: $viewModel.monthlyIncomeText,
                    field: .income
                )

                Text("Dette brukes til å vise hva du har igjen.")
                    .appSecondaryStyle()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(AppTheme.divider, lineWidth: 1)
            )
        }
        .frame(maxWidth: 460, alignment: .center)
        .padding(.top, 12)
    }

    private var fixedCostsStep: some View {
        VStack(spacing: 16) {
            headerBlock(
                title: "Har du faste utgifter?",
                body: viewModel.fixedCostsBodyText
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(OnboardingFixedCostOption.allCases) { option in
                    selectionCard(
                        title: option.title,
                        subtitle: nil,
                        isSelected: viewModel.selectedFixedCosts.contains(option)
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            viewModel.toggleFixedCost(option)
                        }
                    }
                }
            }

            if let help = viewModel.fixedCostHelpText {
                VStack(spacing: 4) {
                    Text(help)
                        .appSecondaryStyle()
                    Text(viewModel.fixedCostsSupportText)
                        .appSecondaryStyle()
                }
                .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 460, alignment: .center)
        .padding(.top, 12)
    }

    private var summaryStep: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppTheme.surface)
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
            }

            VStack(spacing: 8) {
                Text(viewModel.summaryTitle)
                    .appCardTitleStyle()
                    .multilineTextAlignment(.center)

                Text(viewModel.summaryBadgeText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)

                Text(viewModel.summaryConfirmationText)
                    .appBodyStyle()
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Text("Du har ca.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)

                Text("\(formattedAnimatedResult) igjen denne måneden")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text(viewModel.summaryHelpText)
                    .appSecondaryStyle()
                    .multilineTextAlignment(.center)
            }
            .padding(18)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(AppTheme.divider, lineWidth: 1)
            )
            .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 10)
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
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel(secondary)
            }
        }
        .frame(maxWidth: 420, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var introPreviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(viewModel.introPreviewEyebrow, systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .tracking(0.3)
                    .foregroundStyle(AppTheme.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.primary.opacity(0.10))
                    .clipShape(Capsule())

                Spacer()

                Text("Preview")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Text(viewModel.introPreviewTitle)
                .font(.caption.weight(.semibold))
                .tracking(0.3)
                .foregroundStyle(AppTheme.textSecondary)

            Text("6 200 kr")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary.opacity(0.92))
                .monospacedDigit()

            Text("igjen denne måneden")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary.opacity(0.92))

            VStack(spacing: 8) {
                previewRow(label: "Inntekt", value: "12 000 kr")
                previewRow(label: "Faste utgifter", value: "5 800 kr")
            }

            Capsule()
                .fill(AppTheme.primary.opacity(0.18))
                .frame(height: 10)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.primary)
                        .frame(width: 168)
                }

            Text(viewModel.introPreviewFootnote)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: 460, alignment: .leading)
        .padding(18)
        .background(AppTheme.surface.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(AppTheme.divider, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 18, y: 10)
    }

    private func headerBlock(title: String, body: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .appCardTitleStyle()
            Text(body)
                .appBodyStyle()
        }
        .multilineTextAlignment(.center)
    }

    private func selectionCard(title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer(minLength: 8)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isSelected ? AppTheme.primary : AppTheme.textSecondary)
                }

                if let subtitle {
                    Text(subtitle)
                        .appSecondaryStyle()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .background(isSelected ? AppTheme.primary.opacity(0.08) : AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? AppTheme.primary : AppTheme.divider, lineWidth: isSelected ? 2 : 1)
            )
            .scaleEffect(isSelected ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private func previewRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .appSecondaryStyle()
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .monospacedDigit()
        }
    }

    private func currencyField(label: String, placeholder: String, text: Binding<String>, field: OnboardingInputField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .appBodyStyle()

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("kr")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)

                TextField(placeholder, text: monetaryBinding(text))
                    .keyboardType(.numberPad)
                    .textContentType(.none)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused($focusedField, equals: field)
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

    private func updateFocus(for step: OnboardingStep) {
        switch step {
        case .income:
            focusedField = .income
        default:
            focusedField = nil
        }
    }

    private func updateAnimatedResult(for step: OnboardingStep) {
        guard step == .summary else { return }
        animatedResultAmount = 0
        withAnimation(.easeOut(duration: 0.8)) {
            animatedResultAmount = Int(viewModel.resultAmount.rounded())
        }
    }

    private var formattedAnimatedResult: String {
        "\(animatedResultAmount.formatted(.number.grouping(.automatic))) kr"
    }
}

#Preview {
    OnboardingView(preference: OnboardingPreviewData.preference)
        .modelContainer(OnboardingPreviewData.container)
        .environmentObject(SessionStore())
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
