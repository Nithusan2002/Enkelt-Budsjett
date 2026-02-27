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
                }
            }
            .padding(.vertical)
            .background(AppTheme.background)
            .navigationTitle("Kom i gang")
            .sheet(isPresented: $viewModel.showDemo) {
                DemoPreviewSheet()
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
                Text(viewModel.progressText)
                    .appSecondaryStyle()
                Spacer()
                if let trailing = trailingSkipTitle {
                    Button(trailing) {
                        viewModel.skipCurrent(preference: preference, context: modelContext)
                    }
                    .appSecondaryStyle()
                }
            }
            ProgressView(value: viewModel.progressFraction)
                .tint(AppTheme.primary)
        }
        .padding(.horizontal)
    }

    private var trailingSkipTitle: String? {
        switch viewModel.currentStep {
        case .focus, .budget:
            return "Hopp over"
        default:
            return nil
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .welcome:
            welcomeStep
        case .focus:
            focusStep
        case .firstWealth:
            firstWealthStep
        case .budget:
            budgetStep
        case .goal:
            goalStep
        case .habits:
            habitsStep
        case .summary:
            summaryStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Få oversikt på under ett minutt")
                .appCardTitleStyle()
            Text("Se hvordan budsjett og formue henger sammen. Tall kan legges inn senere.")
                .appBodyStyle()

            Button("Se demo (10 sek)") {
                viewModel.showDemo = true
            }
            .appCTAStyle()
            .buttonStyle(.bordered)
            .tint(AppTheme.primary)
        }
    }

    private var focusStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hva vil du starte med?")
                .appCardTitleStyle()
            Text("Valget styrer bare rekkefølgen nå. Du får tilgang til begge deler uansett.")
                .appBodyStyle()

            ForEach(OnboardingFocus.allCases, id: \.rawValue) { focus in
                Button {
                    viewModel.focus = focus
                    autoAdvance(from: .focus)
                } label: {
                    HStack {
                        Text(viewModel.titleForFocus(focus))
                            .appBodyStyle()
                        Spacer()
                        if viewModel.focus == focus {
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
            }
        }
    }

    private var firstWealthStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Første formue")
                .appCardTitleStyle()
            Text("Ett tall først, fordel senere.")
                .appBodyStyle()

            Text("Summen av investeringer + kontoer markert som formue. Gjeld er ikke med.")
                .appSecondaryStyle()

            currencyField(
                label: "Total formue (valgfritt)",
                placeholder: "f.eks. 120 000",
                text: $viewModel.firstWealthTotalText
            )

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.showBucketBreakdown.toggle()
                    }
                } label: {
                    HStack {
                        Text("Fordel i bøtter")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .rotationEffect(.degrees(viewModel.showBucketBreakdown ? 180 : 0))
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)

                if viewModel.showBucketBreakdown {
                    Button("Fordel automatisk") {
                        viewModel.autoDistributeBuckets()
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(AppTheme.primary)
                    .disabled(viewModel.firstWealthTotalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    snapshotField("Fond")
                    snapshotField("Aksjer")
                    snapshotField("BSU")
                    snapshotField("Buffer")
                    snapshotField("Krypto")
                    Text("Grovt tall holder. Du kan finjustere senere.")
                        .appSecondaryStyle()
                }
            }
            .padding(12)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.divider, lineWidth: 1))
        }
    }

    private var budgetStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Velg budsjett-startpakke")
                .appCardTitleStyle()
            Text("Start enkelt nå. Du kan tilpasse kategorier senere.")
                .appBodyStyle()

            ForEach(BudgetStarterPackage.allCases, id: \.rawValue) { package in
                Button {
                    viewModel.budgetPackage = package
                    autoAdvance(from: .budget)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.title(for: package))
                                .appBodyStyle()
                            Text(viewModel.subtitle(for: package))
                                .appSecondaryStyle()
                        }
                        Spacer()
                        if viewModel.budgetPackage == package {
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
            }

            currencyField(
                label: "Månedsbudsjett (valgfritt)",
                placeholder: "f.eks. 12 000",
                text: $viewModel.monthlyBudgetText
            )
        }
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vil du ha et mål å styre etter?")
                .appCardTitleStyle()
            Text("Mål er valgfritt. Det gjør fremdriften tydeligere på Oversikt.")
                .appBodyStyle()

            HStack(spacing: 8) {
                quickGoalChip("50 000")
                quickGoalChip("100 000")
                quickGoalChip("300 000")
            }

            currencyField(
                label: "Målbeløp (valgfritt)",
                placeholder: "f.eks. 150 000",
                text: $viewModel.goalAmountText
            )

            DatePicker("Måldato", selection: $viewModel.goalDate, displayedComponents: .date)
            Text("Forslag: ca. 24 måneder frem.")
                .appSecondaryStyle()
        }
    }

    private var habitsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trygghet og vaner")
                .appCardTitleStyle()
            Text("Et lite dytt hver måned holder oversikten levende.")
                .appBodyStyle()

            Toggle("Månedlig innsjekk", isOn: $viewModel.reminderEnabled)
            if viewModel.reminderEnabled {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(AppTheme.primary)
                    Text("Når du fortsetter, kommer iOS-spørsmål om varslingstillatelse for månedlig innsjekk.")
                        .appSecondaryStyle()
                }
                .padding(10)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.divider, lineWidth: 1))

                Stepper("Dag i måneden: \(viewModel.reminderDay)", value: $viewModel.reminderDay, in: 1...28)
                DatePicker("Klokkeslett", selection: $viewModel.reminderTime, displayedComponents: .hourAndMinute)
            }

            Toggle("Face ID-lås", isOn: $viewModel.faceIDEnabled)
            Text("Du kan endre dette senere i Innstillinger.")
                .appSecondaryStyle()
        }
    }

    private var summaryStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dette blir satt opp")
                .appCardTitleStyle()
            Text("Sjekk at alt ser riktig ut før du fullfører.")
                .appBodyStyle()

            VStack(alignment: .leading, spacing: 10) {
                summaryRow("Startfokus", value: viewModel.titleForFocus(viewModel.focus))
                summaryRow("Første formue", value: firstWealthSummary)
                summaryRow("Budsjettpakke", value: viewModel.title(for: viewModel.budgetPackage))
                if !viewModel.monthlyBudgetText.isEmpty {
                    summaryRow("Månedsbudsjett", value: "kr \(viewModel.monthlyBudgetText)")
                }
                summaryRow("Mål", value: goalSummary)
                summaryRow("Månedlig innsjekk", value: reminderSummary)
                summaryRow("Face ID-lås", value: viewModel.faceIDEnabled ? "På" : "Av")
            }
            .padding(12)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.divider, lineWidth: 1))
        }
    }

    private var footerButtons: some View {
        VStack(spacing: 8) {
            if isAutoAdvanceStep {
                Text("Valg går videre automatisk. Du kan også trykke Neste.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)

                Button("Neste") {
                    handlePrimaryAction()
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(AppTheme.primary)
            } else {
                Button(primaryButtonTitle) {
                    handlePrimaryAction()
                }
                .frame(maxWidth: .infinity)
                .appCTAStyle()
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
            }

            if let secondary = secondaryButtonTitle {
                Button(secondary) {
                    handleSecondaryAction()
                }
                .appSecondaryStyle()
            }
        }
    }

    private var primaryButtonTitle: String {
        switch viewModel.currentStep {
        case .welcome: return "Kom i gang"
        case .focus: return "Neste"
        case .firstWealth: return "Fortsett"
        case .budget: return "Lagre og fortsett"
        case .goal: return "Lagre og fortsett"
        case .habits: return "Fortsett"
        case .summary: return "Gå til Oversikt"
        }
    }

    private var secondaryButtonTitle: String? {
        switch viewModel.currentStep {
        case .welcome: return "Hopp over onboarding"
        case .firstWealth: return "Legg inn senere"
        case .goal: return "Ikke nå"
        case .habits: return "Fortsett uten påminnelse"
        case .focus, .budget, .summary: return nil
        }
    }

    private func handlePrimaryAction() {
        if viewModel.currentStep == .summary {
            viewModel.finish(preference: preference, context: modelContext)
        } else {
            viewModel.next(preference: preference, context: modelContext)
        }
    }

    private func handleSecondaryAction() {
        viewModel.skipCurrent(preference: preference, context: modelContext)
    }

    private var isAutoAdvanceStep: Bool {
        viewModel.currentStep == .focus || viewModel.currentStep == .budget
    }

    private func autoAdvance(from step: OnboardingStep) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard viewModel.currentStep == step else { return }
            viewModel.next(preference: preference, context: modelContext)
        }
    }

    private var firstWealthSummary: String {
        let hasBucketValues = viewModel.snapshotText.values.contains { !$0.isEmpty }
        if hasBucketValues {
            return "Fordelt i bøtter"
        }
        if viewModel.firstWealthTotalText.isEmpty {
            return "Legges inn senere"
        }
        return "kr \(viewModel.firstWealthTotalText)"
    }

    private var goalSummary: String {
        guard !viewModel.goalAmountText.isEmpty else { return "Ikke satt nå" }
        return "kr \(viewModel.goalAmountText) innen \(goalDateLabel)"
    }

    private var reminderSummary: String {
        guard viewModel.reminderEnabled else { return "Av" }
        return "På, dag \(viewModel.reminderDay) kl \(timeLabel(from: viewModel.reminderTime))"
    }

    private var goalDateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: viewModel.goalDate)
    }

    private func timeLabel(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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

    private func quickGoalChip(_ value: String) -> some View {
        Button(value) {
            viewModel.goalAmountText = value
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.surface, in: Capsule())
        .overlay(Capsule().stroke(AppTheme.divider, lineWidth: 1))
    }

    private func snapshotField(_ name: String) -> some View {
        currencyField(
            label: "\(name) (valgfritt)",
            placeholder: "f.eks. 40 000",
            text: Binding(
                get: { viewModel.snapshotText[name] ?? "" },
                set: { viewModel.snapshotText[name] = $0 }
            )
        )
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

private struct DemoPreviewSheet: View {
    @State private var selectedPage = 0

    private let slides: [DemoSlide] = [
        DemoSlide(title: "Enkelt budsjett", text: "Budsjett gjort enkelt", detail: "Slik ser dashboardet ut i praksis.", imageName: "BrandStory"),
        DemoSlide(title: "Total formue", text: "NOK 124 000", detail: "+NOK 2 300 siden forrige innsjekk", imageName: nil),
        DemoSlide(title: "Målprogresjon", text: "42 % nådd", detail: "24 måneder igjen", imageName: nil),
        DemoSlide(title: "Utvikling", text: "I år: +NOK 12 400", detail: "Fond 58 % av porteføljen", imageName: nil)
    ]

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedPage) {
                ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                    previewCard(slide: slide)
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .navigationTitle("Demo-preview")
        }
    }

    private func previewCard(slide: DemoSlide) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let imageName = slide.imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Text(slide.title)
                .appCardTitleStyle()
            Text(slide.text)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(slide.detail)
                .appSecondaryStyle()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: 260, alignment: .topLeading)
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
    }
}

private struct DemoSlide {
    let title: String
    let text: String
    let detail: String
    let imageName: String?
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
