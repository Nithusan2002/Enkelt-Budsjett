import SwiftUI
import SwiftData

struct GoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let goal: Goal?
    @StateObject private var viewModel = GoalEditorViewModel()
    private var isReadOnlyMode: Bool { PersistenceGate.isReadOnlyMode }
    private var screenTitle: String { goal == nil ? "Lag mål" : "Rediger mål" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if goal == nil {
                        Text("Velg målbeløp og datoen du vil nå det innen.")
                            .appSecondaryStyle()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Målbeløp")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)

                            HStack(spacing: 12) {
                                TextField("250 000", text: $viewModel.targetAmountText)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.appInput)
                                    .multilineTextAlignment(.leading)
                                    .monospacedDigit()
                                    .onChange(of: viewModel.targetAmountText) { _, newValue in
                                        let formatted = AppAmountInput.formatLive(newValue)
                                        if formatted != newValue {
                                            viewModel.targetAmountText = formatted
                                        }
                                    }

                                Text("kr")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Måldato")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)

                            DatePicker(
                                "",
                                selection: $viewModel.targetDate,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .environment(\.locale, Locale(identifier: "nb_NO"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AppTheme.divider, lineWidth: 1)
                            )
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(AppTheme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(AppTheme.divider.opacity(0.8), lineWidth: 1)
                    )
                }
                .padding(16)
            }
            .background(AppTheme.background)
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                        .foregroundStyle(AppTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        if viewModel.save(goal: goal, context: modelContext) {
                            dismiss()
                        }
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(viewModel.canSave && !isReadOnlyMode ? AppTheme.primary : AppTheme.textSecondary)
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
