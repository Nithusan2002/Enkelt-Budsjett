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
            if viewModel.currentStep != .welcome {
                Button("Hopp over") {
                    viewModel.skipCurrent(preference: preference, context: modelContext)
                }
                .appSecondaryStyle()
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .welcome:
            welcomeStep
        case .focus:
            focusStep
        case .goal:
            goalStep
        case .snapshot:
            snapshotStep
        case .budget:
            budgetStep
        case .habits:
            habitsStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Få oversikt over penger og investeringer på under ett minutt")
                .appCardTitleStyle()
            Text("Du kan hoppe over tall nå og fylle inn senere.")
                .appBodyStyle()
            Text("Velg tone")
                .appCardTitleStyle()
            ForEach(AppToneStyle.allCases, id: \.rawValue) { tone in
                Button {
                    viewModel.tone = tone
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.titleForTone(tone))
                            .appBodyStyle()
                        Text(viewModel.subtitleForTone(tone))
                            .appSecondaryStyle()
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
            Text("Sveip for å se hvordan Oversikt ser ut med eksempeldata.")
                .appSecondaryStyle()
        }
    }

    private var focusStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hva vil du starte med?")
                .appCardTitleStyle()
            Text("Valget styrer rekkefølgen. Du får tilgang til alt uansett.")
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
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.primary)
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

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vil du sette et formue-mål?")
                .appCardTitleStyle()
            Text("Et grovt mål gjør utviklingen lettere å følge.")
                .appBodyStyle()
            currencyField(
                label: "Målbeløp (valgfritt)",
                placeholder: "f.eks. 300 000",
                text: $viewModel.goalAmountText
            )
            DatePicker("Måldato (valgfritt)", selection: $viewModel.goalDate, displayedComponents: .date)
            Text("Forslag: 24 måneder fra i dag.")
                .appSecondaryStyle()
        }
    }

    private var snapshotStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Første investeringsstatus")
                .appCardTitleStyle()
            Text("Runde tall holder. Du kan justere senere.")
                .appBodyStyle()
            snapshotField("Fond")
            snapshotField("Aksjer")
            snapshotField("IPS")
            snapshotField("Krypto")
            currencyField(
                label: "Jeg satte inn/ut denne måneden (valgfritt)",
                placeholder: "f.eks. +1 000 eller -500",
                text: $viewModel.monthlyFlowText,
                allowSign: true
            )
            Text("Lar du alt stå tomt, kan du oppdatere fra Oversikt.")
                .appSecondaryStyle()
        }
    }

    private var budgetStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Budsjett, enkelt først")
                .appCardTitleStyle()
            Text("Velg kategorier nå. Finjustering kan vente.")
                .appBodyStyle()
            ForEach(viewModel.budgetCategories.keys.sorted(), id: \.self) { key in
                Toggle(key, isOn: Binding(
                    get: { viewModel.budgetCategories[key] ?? false },
                    set: { viewModel.budgetCategories[key] = $0 }
                ))
            }
            currencyField(
                label: "Månedsbudsjett (valgfritt)",
                placeholder: "f.eks. 12 000",
                text: $viewModel.monthlyBudgetText
            )
            Toggle("Jeg sporer bare (uten budsjettgrenser nå)", isOn: $viewModel.budgetTrackOnly)
        }
    }

    private var habitsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trygghet og gode vaner")
                .appCardTitleStyle()
            Text("Velg det som passer rytmen din.")
                .appBodyStyle()
            Toggle("Månedlig insjekk-påminnelse", isOn: $viewModel.reminderEnabled)
            if viewModel.reminderEnabled {
                Stepper("Dag i måneden: \(viewModel.reminderDay)", value: $viewModel.reminderDay, in: 1...28)
            }
            Toggle("Lås appen med Face ID (valgfritt)", isOn: $viewModel.faceIDEnabled)
            Text("Du kan endre alt senere i Innstillinger.")
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

            Button(secondaryButtonTitle) {
                handleSecondaryAction()
            }
            .appSecondaryStyle()
        }
    }

    private var primaryButtonTitle: String {
        switch viewModel.currentStep {
        case .welcome: return "Kom i gang"
        case .focus: return "Neste"
        case .goal: return "Lagre og fortsett"
        case .snapshot: return "Lagre snapshot"
        case .budget: return "Lagre budsjett"
        case .habits: return "Gå til Oversikt"
        }
    }

    private var secondaryButtonTitle: String {
        switch viewModel.currentStep {
        case .welcome: return "Hopp over onboarding"
        case .habits: return "Fullfør uten påminnelse"
        default: return "Hopp over"
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

    private func snapshotField(_ name: String) -> some View {
        currencyField(
            label: "\(name) (valgfritt)",
            placeholder: "f.eks. 200 000",
            text: Binding(
                get: { viewModel.snapshotText[name] ?? "" },
                set: { viewModel.snapshotText[name] = $0 }
            )
        )
    }

    private func currencyField(label: String, placeholder: String, text: Binding<String>, allowSign: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .appBodyStyle()
            HStack {
                Text("kr")
                    .appSecondaryStyle()
                TextField(placeholder, text: monetaryBinding(text, allowSign: allowSign))
                    .keyboardType(.numbersAndPunctuation)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.divider, lineWidth: 1))
        }
    }

    private func monetaryBinding(_ source: Binding<String>, allowSign: Bool = false) -> Binding<String> {
        Binding(
            get: { source.wrappedValue },
            set: { newValue in
                source.wrappedValue = formatMonetaryInput(newValue, allowSign: allowSign)
            }
        )
    }

    private func formatMonetaryInput(_ raw: String, allowSign: Bool) -> String {
        var text = raw.replacingOccurrences(of: " ", with: "")
        var sign = ""

        if allowSign, let first = text.first, first == "+" || first == "-" {
            sign = String(first)
            text.removeFirst()
        }

        let digits = String(text.filter(\.isNumber))
        guard !digits.isEmpty else { return sign }
        return sign + groupedThousands(digits)
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
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    previewCard(title: "Mål", text: "42 % nådd · 34 måneder igjen")
                    previewCard(title: "Portefølje", text: "Fond 61 % · Aksjer 23 % · IPS 12 %")
                    previewCard(title: "Utvikling", text: "I år: +kr 12 400")
                }
                .padding()
            }
            .navigationTitle("Demo-preview")
        }
    }

    private func previewCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).appCardTitleStyle()
            Text(text).appBodyStyle()
            Text("Eksempeldata").appSecondaryStyle()
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
