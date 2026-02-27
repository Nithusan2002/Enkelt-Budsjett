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
                    TextField("Jeg vil ha en formue på", text: $viewModel.targetAmountText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.appInput)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                    DatePicker("Måldato", selection: $viewModel.targetDate, displayedComponents: .date)
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
                    .disabled(!viewModel.canSave)
                }
            }
            .appKeyboardDismissToolbar()
            .onAppear {
                viewModel.onAppear(goal: goal)
            }
        }
    }
}
