import SwiftUI
import SwiftData

struct GoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let goal: Goal?
    @StateObject private var viewModel = GoalEditorViewModel()
    private var isReadOnlyMode: Bool { PersistenceGate.isReadOnlyMode }

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
                        if viewModel.save(goal: goal, context: modelContext) {
                            dismiss()
                        }
                    }
                    .appCTAStyle()
                    .disabled(!viewModel.canSave || isReadOnlyMode)
                }
            }
            .appKeyboardDismissToolbar()
            .alert(
                "Kunne ikke lagre",
                isPresented: Binding(
                    get: { viewModel.persistenceErrorMessage != nil },
                    set: { if !$0 { viewModel.clearPersistenceError() } }
                )
            ) {
                Button("OK", role: .cancel) {
                    viewModel.clearPersistenceError()
                }
            } message: {
                Text(viewModel.persistenceErrorMessage ?? "")
            }
            .onAppear {
                viewModel.onAppear(goal: goal)
            }
        }
    }
}
