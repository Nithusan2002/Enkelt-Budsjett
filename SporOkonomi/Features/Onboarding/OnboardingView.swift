import SwiftUI
import SwiftData
import UIKit

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    let preference: UserPreference
    @StateObject private var viewModel: OnboardingViewModel
    @FocusState private var focusedField: OnboardingInputField?
    @State private var introPage = 0
    @State private var showCustomInvestmentTypeSheet = false
    @State private var customInvestmentTypeDraft = ""

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
                updateStepAnimations(for: viewModel.currentStep)
            }
            .onChange(of: viewModel.currentStep) { _, newStep in
                viewModel.markCurrentStepSeen()
                updateFocus(for: newStep)
                updateAnimatedResult(for: newStep)
                updateStepAnimations(for: newStep)
            }
            .onChange(of: viewModel.monthlyIncomeText) { _, _ in
            }
            .onChange(of: viewModel.selectedFixedCosts) { _, _ in
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
                    viewModel.currentStep == .intro ? Color.white.opacity(0.18) : AppTheme.primary.opacity(0.14),
                    viewModel.currentStep == .intro ? AppTheme.primary.opacity(0.10) : AppTheme.primary.opacity(0.07),
                    AppTheme.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxHeight: viewModel.currentStep == .intro ? 430 : 340, alignment: .top)
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
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
            }
            .overlay {
                if !viewModel.showsProgressHeader {
                    Text("Spor økonomi")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
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
        case .investmentTypes:
            investmentTypesStep
        }
    }

    private var introStep: some View {
        VStack(spacing: 24) {
            TabView(selection: $introPage) {
                ForEach(Array(introSlides.enumerated()), id: \.offset) { index, slide in
                    VStack(spacing: 30) {
                        introIllustration(for: slide.illustration)

                        VStack(spacing: 12) {
                            Text(slide.title)
                                .font(.system(size: 37, weight: .bold, design: .rounded))
                                .lineSpacing(2)
                                .foregroundStyle(AppTheme.textPrimary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 330)

                            Text(slide.body)
                                .appBodyStyle()
                                .foregroundStyle(AppTheme.textSecondary.opacity(0.82))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 300)
                        }
                    }
                    .tag(index)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
                    .padding(.horizontal, 6)
                    .clipped()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 560)
            .clipped()

            introPageIndicator
        }
        .frame(maxWidth: 460, alignment: .center)
        .padding(.top, 4)
        .accessibilityIdentifier("onboarding.step.intro")
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
        .accessibilityIdentifier("onboarding.step.goals")
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
        .accessibilityIdentifier("onboarding.step.income")
    }

    private var fixedCostsStep: some View {
        VStack(spacing: 16) {
            headerBlock(
                title: "Har du faste utgifter",
                body: viewModel.fixedCostsBodyText
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                ForEach(OnboardingFixedCostOption.allCases) { option in
                    selectionChip(
                        title: option.title,
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
        .accessibilityIdentifier("onboarding.step.fixed_costs")
    }

    private var investmentTypesStep: some View {
        VStack(spacing: 16) {
            headerBlock(
                title: viewModel.investmentTypesTitle,
                body: viewModel.investmentTypesBodyText
            )

            VStack(spacing: 10) {
                ForEach(viewModel.orderedInvestmentTypeOptions) { option in
                    selectionCard(
                        title: option.title,
                        subtitle: nil,
                        isSelected: viewModel.selectedInvestmentTypes.contains(option)
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            viewModel.toggleInvestmentType(option)
                        }
                    }
                }

                if viewModel.hasCustomInvestmentType {
                    selectionCard(
                        title: viewModel.customInvestmentTypeName,
                        subtitle: "Egen type",
                        isSelected: viewModel.isCustomInvestmentTypeSelected
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            viewModel.toggleCustomInvestmentTypeSelection()
                        }
                    }

                    Button("Fjern egen type") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            viewModel.removeCustomInvestmentType()
                        }
                    }
                    .appSecondaryStyle()
                }
            }

            Button(viewModel.hasCustomInvestmentType ? "Endre egen type" : "Legg til egen type") {
                customInvestmentTypeDraft = viewModel.customInvestmentTypeName
                showCustomInvestmentTypeSheet = true
            }
            .buttonStyle(.bordered)
            .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: 460, alignment: .center)
        .padding(.top, 12)
        .accessibilityIdentifier("onboarding.step.investment_types")
        .sheet(isPresented: $showCustomInvestmentTypeSheet) {
            AddCustomInvestmentTypeSheet(
                name: $customInvestmentTypeDraft,
                onSave: {
                    viewModel.customInvestmentTypeName = customInvestmentTypeDraft
                    if viewModel.saveCustomInvestmentType() {
                        showCustomInvestmentTypeSheet = false
                    }
                },
                onCancel: {
                    viewModel.clearError()
                }
            )
        }
    }

    private var footerButtons: some View {
        VStack(spacing: 8) {
            Button(viewModel.primaryButtonTitle) {
                viewModel.primaryAction(preference: preference, context: modelContext)
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: "#1F6F5C"),
                        Color(hex: "#2E8B73")
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
            .buttonStyle(.plain)
            .disabled(viewModel.isPrimaryDisabled)
            .opacity(viewModel.isPrimaryDisabled ? 0.45 : 1)
            .accessibilityLabel(viewModel.primaryButtonTitle)
            .accessibilityIdentifier("onboarding.primary_cta")

            if let secondary = viewModel.secondaryButtonTitle {
                Button(secondary) {
                    viewModel.secondaryAction(preference: preference, context: modelContext)
                }
                .appSecondaryStyle()
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel(secondary)
                .accessibilityIdentifier("onboarding.secondary_cta")
            }
        }
        .frame(maxWidth: 420, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var introPageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(Array(introSlides.indices), id: \.self) { index in
                Capsule()
                    .fill(index == introPage ? AppTheme.primary.opacity(0.62) : AppTheme.textSecondary.opacity(0.32))
                    .frame(width: index == introPage ? 30 : 9, height: 9)
                    .overlay {
                        Capsule()
                            .stroke(index == introPage ? Color.white.opacity(0.35) : Color.clear, lineWidth: 0.5)
                    }
                    .scaleEffect(index == introPage ? 1 : 0.92)
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: introPage)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func introIllustration(for style: IntroIllustrationStyle) -> some View {
        ZStack {
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#2E8B73").opacity(0.22),
                            Color(hex: "#1F6F5C").opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 290, height: 248)
                .blur(radius: 4)
                .offset(x: -18, y: 12)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "#2E8B73").opacity(0.18),
                            Color(hex: "#2E8B73").opacity(0.05)
                        ],
                        center: .center,
                        startRadius: 30,
                        endRadius: 140
                    )
                )
                .frame(width: 270, height: 270)
                .offset(x: -30, y: 2)

            RoundedRectangle(cornerRadius: 28)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#1F6F5C").opacity(0.16),
                            Color(hex: "#2E8B73").opacity(0.07)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 304, height: 214)
                .offset(y: 30)

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.32), lineWidth: 1)
                )
                .shadow(color: Color(hex: "#1F6F5C").opacity(0.10), radius: 22, y: 10)
                .frame(width: 318, height: 226)
                .offset(y: 24)

            switch style {
            case .lockscreen:
                lockscreenIllustration
            case .overview:
                overviewIllustration
            case .progress:
                progressIllustration
            }
        }
        .frame(height: 340)
    }

    private var lockscreenIllustration: some View {
        HStack(spacing: 20) {
            VStack(spacing: 12) {
                Circle()
                    .fill(AppTheme.surface)
                    .frame(width: 70, height: 70)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(AppTheme.primary)
                    )

                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.primary.opacity(0.16))
                    .frame(width: 88, height: 14)
            }

            RoundedRectangle(cornerRadius: 28)
                .fill(AppTheme.textPrimary)
                .frame(width: 132, height: 220)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 0.55, green: 0.88, blue: 0.66))
                        .padding(12)
                        .overlay {
                            VStack(spacing: 16) {
                                Circle()
                                    .fill(AppTheme.surface)
                                    .frame(width: 42, height: 42)
                                    .overlay(
                                        Image(systemName: "person.crop.circle.fill")
                                            .font(.system(size: 24))
                                            .foregroundStyle(AppTheme.textPrimary.opacity(0.85))
                                    )

                                Image(systemName: "lock.fill")
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundStyle(AppTheme.surface)

                                RoundedRectangle(cornerRadius: 12)
                                    .fill(AppTheme.surface.opacity(0.88))
                                    .frame(width: 76, height: 68)
                                    .overlay(
                                        Image(systemName: "key.fill")
                                            .font(.system(size: 28, weight: .bold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                    )
                            }
                        }
                }
        }
    }

    private var overviewIllustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(AppTheme.surface)
                .frame(width: 220, height: 150)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(AppTheme.textPrimary.opacity(0.15), lineWidth: 1)
                )

            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Circle()
                        .stroke(AppTheme.textPrimary, lineWidth: 4)
                        .frame(width: 46, height: 46)
                    Capsule()
                        .fill(Color(red: 0.55, green: 0.88, blue: 0.66))
                        .frame(width: 90, height: 14)
                    Circle()
                        .stroke(AppTheme.textPrimary, lineWidth: 4)
                        .frame(width: 46, height: 46)
                }

                VStack(spacing: 9) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.primary.opacity(0.18))
                            .frame(width: 150, height: 10)
                    }
                }
            }

            HStack {
                magnifyingGlass(offset: CGSize(width: -110, height: 56))
                Spacer()
                magnifyingGlass(offset: CGSize(width: 112, height: -28))
            }
            .frame(width: 280)
        }
    }

    private var progressIllustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(AppTheme.surface)
                .frame(width: 210, height: 150)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(AppTheme.primary.opacity(0.18), lineWidth: 1)
                )

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(red: 0.55, green: 0.88, blue: 0.66))
                            .frame(width: 20, height: 8)
                    }
                }

                ForEach(0..<5, id: \.self) { _ in
                    HStack(spacing: 8) {
                        ForEach(0..<7, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(AppTheme.primary.opacity(0.10))
                                .frame(width: 20, height: 14)
                        }
                    }
                }
            }

            Path { path in
                path.move(to: CGPoint(x: 70, y: 212))
                path.addLine(to: CGPoint(x: 140, y: 156))
                path.addLine(to: CGPoint(x: 210, y: 178))
                path.addLine(to: CGPoint(x: 290, y: 110))
            }
            .stroke(AppTheme.textPrimary, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

            ForEach(Array([CGPoint(x: 140, y: 156), CGPoint(x: 210, y: 178), CGPoint(x: 290, y: 110)].enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(AppTheme.textPrimary)
                    .frame(width: 12, height: 12)
                    .position(point)
            }

            Image(systemName: "arrow.up.left")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color(red: 0.55, green: 0.88, blue: 0.66))
                .position(x: 80, y: 156)
        }
    }

    private func magnifyingGlass(offset: CGSize) -> some View {
        ZStack {
            Circle()
                .stroke(AppTheme.textPrimary, lineWidth: 3)
                .frame(width: 44, height: 44)
            Rectangle()
                .fill(AppTheme.textPrimary)
                .frame(width: 4, height: 20)
                .rotationEffect(.degrees(45))
                .offset(x: 14, y: 16)
        }
        .offset(offset)
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
        .accessibilityIdentifier("onboarding.option.\(normalizedIdentifier(title))")
    }

    private func selectionChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? AppTheme.primary : AppTheme.textPrimary)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.primary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(isSelected ? AppTheme.primary.opacity(0.10) : AppTheme.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? AppTheme.primary.opacity(0.55) : AppTheme.divider, lineWidth: 1)
            )
            .scaleEffect(isSelected ? 0.98 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.option.\(normalizedIdentifier(title))")
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
                .accessibilityIdentifier(field == .income ? "onboarding.income_input" : "onboarding.input")
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

    private func normalizedIdentifier(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: "å", with: "a")
            .replacingOccurrences(of: "ø", with: "o")
            .replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: " ", with: "_")
    }

    private func updateFocus(for step: OnboardingStep) {
        switch step {
        case .income:
            focusedField = .income
        default:
            focusedField = nil
        }
    }

    private func updateAnimatedResult(for step: OnboardingStep) {}

    private func updateStepAnimations(for step: OnboardingStep) {}
}

private extension OnboardingView {
    var introSlides: [IntroSlide] {
        [
            IntroSlide(
                title: "Fang oversikten på sekunder",
                body: "Legg inn inntekt og faste utgifter – resten skjer automatisk.",
                illustration: .lockscreen
            ),
            IntroSlide(
                title: "Følg fremgangen uten stress",
                body: "Se tydelig hva du har igjen hver måned.",
                illustration: .overview
            ),
            IntroSlide(
                title: "Full kontroll – helt enkelt",
                body: "Spor økonomi gir deg ro og oversikt fra dag én.",
                illustration: .progress
            )
        ]
    }
}

private struct AddCustomInvestmentTypeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var name: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Legg til typen du vil følge.")
                    .appSecondaryStyle()

                TextField("F.eks. Eiendom", text: $name)
                    .textFieldStyle(.appInput)

                Spacer()
            }
            .padding()
            .background(AppTheme.background)
            .navigationTitle("Egen type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        onSave()
                    }
                    .appCTAStyle()
                }
            }
        }
    }
}

private struct IntroSlide {
    let title: String
    let body: String
    let illustration: IntroIllustrationStyle
}

private enum IntroIllustrationStyle {
    case lockscreen
    case overview
    case progress
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
