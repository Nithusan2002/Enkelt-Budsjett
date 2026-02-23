import SwiftUI
import SwiftData

struct GoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let goal: Goal?
    @StateObject private var viewModel = GoalEditorViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Formue-mål") {
                    TextField("Målbeløp", value: $viewModel.targetAmount, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .appBigNumberStyle()
                    DatePicker("Måldato", selection: $viewModel.targetDate, displayedComponents: .date)
                        .appBodyStyle()
                    Toggle("Inkluder konti i formue", isOn: $viewModel.includeAccounts)
                        .appBodyStyle()
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Mål")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                        .appBodyStyle()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        viewModel.save(goal: goal, context: modelContext)
                        dismiss()
                    }
                    .appCTAStyle()
                }
            }
            .onAppear {
                viewModel.onAppear(goal: goal)
            }
        }
    }
}
