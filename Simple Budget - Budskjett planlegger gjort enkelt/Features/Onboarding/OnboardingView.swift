import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    let preference: UserPreference
    @StateObject private var viewModel = OnboardingViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Velkommen") {
                    Text("Sett opp appen raskt. Du kan alltid endre dette senere.")
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Section("Inntekt (valgfritt)") {
                    Toggle("Legg inn inntekt nå", isOn: $viewModel.includeIncome)
                    if viewModel.includeIncome {
                        TextField("Månedlig inntekt", value: $viewModel.monthlyIncome, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Investeringsbøtter") {
                    ForEach(viewModel.bucketToggles.keys.sorted(), id: \.self) { key in
                        Toggle(key, isOn: Binding(
                            get: { viewModel.bucketToggles[key] ?? false },
                            set: { viewModel.bucketToggles[key] = $0 }
                        ))
                    }
                    TextField("Egen bøtte (valgfritt)", text: $viewModel.customBucketName)
                }

                Section {
                    Button("Fullfør onboarding") {
                        viewModel.complete(context: modelContext, preference: preference)
                    }
                    .font(.headline.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Kom i gang")
        }
    }
}
