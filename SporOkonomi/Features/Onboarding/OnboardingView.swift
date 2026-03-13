import SwiftUI
import SwiftData
import UIKit

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    let preference: UserPreference
    @StateObject private var viewModel: OnboardingViewModel
    @FocusState private var focusedField: OnboardingInputField?
    @State private var animatedResultAmount = 0
    @State private var introPage = 0
    @State private var summaryMarkVisible = false

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
        VStack(spacing: 24) {
            TabView(selection: $introPage) {
                ForEach(Array(introSlides.enumerated()), id: \.offset) { index, slide in
                    VStack(spacing: 22) {
                        introIllustration(for: slide.illustration)

                        VStack(spacing: 10) {
                            Text(slide.title)
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.textPrimary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 330)

                            Text(slide.body)
                                .appBodyStyle()
                                .foregroundStyle(AppTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 300)
                        }
                    }
                    .tag(index)
                    .padding(.top, 8)
                    .padding(.horizontal, 6)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 560)

            introPageIndicator
        }
        .frame(maxWidth: 460, alignment: .center)
        .padding(.top, 4)
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

                Text("Du kan endre dette senere.")
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
    }

    private var summaryStep: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(AppTheme.primary.opacity(0.18), lineWidth: 10)
                    .frame(width: 92, height: 92)
                    .scaleEffect(summaryMarkVisible ? 1 : 0.88)

                Circle()
                    .fill(AppTheme.surface)
                    .frame(width: 74, height: 74)
                    .scaleEffect(summaryMarkVisible ? 1 : 0.92)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                    .scaleEffect(summaryMarkVisible ? 1 : 0.82)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: summaryMarkVisible)

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
            .opacity(viewModel.isPrimaryDisabled ? 0.45 : 1)
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

    private var introPageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(Array(introSlides.indices), id: \.self) { index in
                Capsule()
                    .fill(index == introPage ? AppTheme.primary.opacity(0.55) : AppTheme.divider)
                    .frame(width: index == introPage ? 28 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: introPage)
            }
        }
    }

    @ViewBuilder
    private func introIllustration(for style: IntroIllustrationStyle) -> some View {
        ZStack {
            Circle()
                .fill(AppTheme.primary.opacity(0.10))
                .frame(width: 260, height: 260)
                .offset(x: -26, y: 8)

            RoundedRectangle(cornerRadius: 28)
                .fill(AppTheme.primary.opacity(0.08))
                .frame(width: 300, height: 210)
                .offset(y: 34)

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

    private func updateStepAnimations(for step: OnboardingStep) {
        summaryMarkVisible = false

        switch step {
        case .intro:
            break
        case .summary:
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                summaryMarkVisible = true
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        default:
            break
        }
    }

    private var formattedAnimatedResult: String {
        "\(animatedResultAmount.formatted(.number.grouping(.automatic))) kr"
    }
}

private extension OnboardingView {
    var introSlides: [IntroSlide] {
        [
            IntroSlide(
                title: "Se hva du faktisk har igjen hver måned",
                body: "Få en rolig start med enkel oversikt før du går videre.",
                illustration: .lockscreen
            ),
            IntroSlide(
                title: "Fang oversikten på noen sekunder",
                body: "Legg inn inntekt og faste utgifter uten komplisert oppsett.",
                illustration: .overview
            ),
            IntroSlide(
                title: "Følg fremgangen din uten støy",
                body: "Spor økonomi hjelper deg å se utviklingen uten å fylle skjermen med detaljer.",
                illustration: .progress
            )
        ]
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
