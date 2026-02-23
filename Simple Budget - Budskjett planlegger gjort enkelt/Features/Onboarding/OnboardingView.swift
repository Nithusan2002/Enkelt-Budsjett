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
            VStack(spacing: 16) {
                topBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        stepContent
                    }
                    .padding(.horizontal)
                }

                footerButtons
            }
            .padding(.vertical)
            .background(AppTheme.background)
            .navigationTitle("Kom i gang")
            .sheet(isPresented: $viewModel.showDemo) {
                DemoPreviewSheet()
            }
        }
    }

    private var topBar: some View {
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
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image("BrandLogoTransparent")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 110)
                    .accessibilityHidden(true)
                Spacer()
            }
            .padding(10)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))

            Text("Få oversikt på under ett minutt")
                .appCardTitleStyle()
            Text("Se hvordan budsjett og formue henger sammen. Tall kan legges inn senere.")
                .appBodyStyle()

            Text("Velg tone")
                .appCardTitleStyle()

            ForEach(AppToneStyle.allCases, id: \.rawValue) { tone in
                Button {
                    viewModel.tone = tone
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.titleForTone(tone))
                                .appBodyStyle()
                            Text(viewModel.subtitleForTone(tone))
                                .appSecondaryStyle()
                        }
                        Spacer()
                        if viewModel.tone == tone {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(viewModel.tone == tone ? AppTheme.primary.opacity(0.12) : AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.divider, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

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

            Button(viewModel.showBucketBreakdown ? "Skjul fordeling" : "Fordel i bøtter") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.showBucketBreakdown.toggle()
                }
            }
            .font(.footnote.weight(.semibold))

            if viewModel.showBucketBreakdown {
                snapshotField("Fond")
                snapshotField("Aksjer")
                snapshotField("IPS")
                snapshotField("Krypto")
            }

            Text("Grovt tall holder. Du kan finjustere senere.")
                .appSecondaryStyle()
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

            Toggle("Månedlig insjekk", isOn: $viewModel.reminderEnabled)
            if viewModel.reminderEnabled {
                Stepper("Dag i måneden: \(viewModel.reminderDay)", value: $viewModel.reminderDay, in: 1...28)
                DatePicker("Klokkeslett", selection: $viewModel.reminderTime, displayedComponents: .hourAndMinute)
            }

            Toggle("Face ID-lås", isOn: $viewModel.faceIDEnabled)
            Text("Du kan endre dette senere i Innstillinger.")
                .appSecondaryStyle()
        }
    }

    private var footerButtons: some View {
        VStack(spacing: 8) {
            Button(primaryButtonTitle) {
                handlePrimaryAction()
            }
            .frame(maxWidth: .infinity)
            .appCTAStyle()
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)

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
        case .habits: return "Gå til Oversikt"
        }
    }

    private var secondaryButtonTitle: String? {
        switch viewModel.currentStep {
        case .welcome: return "Hopp over onboarding"
        case .firstWealth: return "Legg inn senere"
        case .goal: return "Ikke nå"
        case .habits: return "Fullfør uten påminnelse"
        case .focus, .budget: return nil
        }
    }

    private func handlePrimaryAction() {
        if viewModel.currentStep == .habits {
            viewModel.finish(preference: preference, context: modelContext)
        } else {
            viewModel.next(preference: preference, context: modelContext)
        }
    }

    private func handleSecondaryAction() {
        viewModel.skipCurrent(preference: preference, context: modelContext)
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
    var body: some View {
        NavigationStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image("BrandStory")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        Text("Slik ser dashboardet ut i praksis.")
                            .appSecondaryStyle()
                    }
                    .frame(width: 280, alignment: .topLeading)

                    previewCard(
                        title: "Total formue",
                        text: "NOK 124 000",
                        detail: "+NOK 2 300 siden forrige insjekk"
                    )
                    previewCard(
                        title: "Målprogresjon",
                        text: "42 % nådd",
                        detail: "24 måneder igjen"
                    )
                    previewCard(
                        title: "Utvikling",
                        text: "I år: +NOK 12 400",
                        detail: "Fond 58 % av porteføljen"
                    )
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .navigationTitle("Demo-preview")
        }
    }

    private func previewCard(title: String, text: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .appCardTitleStyle()
            Text(text)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(detail)
                .appSecondaryStyle()
        }
        .frame(width: 280, height: 170, alignment: .topLeading)
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
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
            Transaction.self,
            Account.self,
            InvestmentBucket.self,
            InvestmentSnapshot.self,
            InvestmentSnapshotValue.self,
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
