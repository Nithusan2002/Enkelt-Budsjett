import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreference]
    @StateObject private var viewModel = SettingsViewModel()

    private var pref: UserPreference { viewModel.preference(from: preferences, context: modelContext) }

    var body: some View {
        Form {
            Section("Spart hittil") {
                Picker("Definisjon", selection: binding(\.savingsDefinition)) {
                    Text("Inntekt minus utgifter")
                        .appBodyStyle()
                        .tag(SavingsDefinition.incomeMinusExpense)
                    Text("Kun sparingskategori")
                        .appBodyStyle()
                        .tag(SavingsDefinition.savingsCategoryOnly)
                }
            }
            Section("Insjekk-påminnelse") {
                Toggle("Aktiver påminnelse", isOn: binding(\.checkInReminderEnabled))
                    .appBodyStyle()
                Stepper("Dag i måned: \(pref.checkInReminderDay)", value: binding(\.checkInReminderDay), in: 1...28)
                    .appBodyStyle()
            }
            Section("Graf") {
                Picker("Standardvisning", selection: binding(\.defaultGraphView)) {
                    Text("I år")
                        .appBodyStyle()
                        .tag(GraphViewRange.yearToDate)
                    Text("Siste 12 mnd")
                        .appBodyStyle()
                        .tag(GraphViewRange.last12Months)
                }
            }
            Section("Sikkerhet") {
                Toggle("Face ID-lås", isOn: binding(\.faceIDLockEnabled))
                    .appBodyStyle()
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Innstillinger")
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<UserPreference, T>) -> Binding<T> {
        Binding(
            get: { pref[keyPath: keyPath] },
            set: {
                pref[keyPath: keyPath] = $0
                viewModel.save(context: modelContext)
            }
        )
    }
}
