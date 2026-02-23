import SwiftUI
import SwiftData

struct InvestmentsView: View {
    @Query(sort: \InvestmentBucket.sortOrder) private var buckets: [InvestmentBucket]
    @Query(sort: \InvestmentSnapshot.periodKey) private var snapshots: [InvestmentSnapshot]
    @StateObject private var viewModel = InvestmentsViewModel()

    private var latest: InvestmentSnapshot? { viewModel.latestSnapshot(snapshots) }
    private var previous: InvestmentSnapshot? { viewModel.previousSnapshot(snapshots) }

    var body: some View {
        List {
            Section("Total") {
                Text(formatNOK(latest?.totalValue ?? 0))
                    .appBigNumberStyle()
                    .foregroundStyle(AppTheme.textPrimary)

                let change = viewModel.monthChange(current: latest, previous: previous)
                Text(change.pct != nil
                     ? "Siden forrige måned: \(formatNOK(change.kr)) (\(formatPercent(change.pct ?? 0)))"
                     : "Siden forrige måned: \(formatNOK(change.kr))")
                    .appSecondaryStyle()
            }

            Section("Beholdning") {
                ForEach(buckets.filter(\.isActive)) { bucket in
                    HStack {
                        Text(bucket.name)
                            .appBodyStyle()
                        Spacer()
                        Text(formatNOK(viewModel.value(for: bucket.id, latest: latest)))
                            .appSecondaryStyle()
                    }
                }
            }

            Section("Historikk") {
                ForEach(viewModel.history(snapshots), id: \.periodKey) { snapshot in
                    HStack {
                        Text(snapshot.periodKey)
                            .appBodyStyle()
                        Spacer()
                        Text(formatNOK(snapshot.totalValue))
                            .monospacedDigit()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Investeringer")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Oppdater verdier") {
                    viewModel.showCheckIn = true
                }
                .appCTAStyle()
            }
        }
        .sheet(isPresented: $viewModel.showCheckIn) {
            InvestmentCheckInView(buckets: buckets, latestSnapshot: latest)
        }
    }
}

struct InvestmentCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let buckets: [InvestmentBucket]
    let latestSnapshot: InvestmentSnapshot?
    @StateObject private var viewModel = InvestmentCheckInViewModel()

    private var periodKey: String { viewModel.periodKey() }
    private var total: Double { viewModel.total() }

    var body: some View {
        NavigationStack {
            Form {
                Section("Månedlig insjekk (\(periodKey))") {
                    ForEach(buckets.filter(\.isActive)) { bucket in
                        HStack {
                            Text(bucket.name)
                                .appBodyStyle()
                            Spacer()
                            TextField(
                                "0",
                                value: binding(for: bucket.id),
                                format: .number.precision(.fractionLength(0...2))
                            )
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 120)
                        }
                    }
                }

                Section("Oppsummering") {
                    row("Ny total", total)
                    row("Forrige total", latestSnapshot?.totalValue ?? 0)
                    row("Endring", total - (latestSnapshot?.totalValue ?? 0))
                }
            }
            .navigationTitle("Oppdater verdier")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        saveSnapshot()
                        dismiss()
                    }
                    .appCTAStyle()
                }
            }
            .onAppear {
                viewModel.prepareValues(buckets: buckets, latestSnapshot: latestSnapshot)
            }
        }
    }

    private func row(_ title: String, _ value: Double) -> some View {
        HStack {
            Text(title)
                .appBodyStyle()
            Spacer()
            Text(formatNOK(value))
                .monospacedDigit()
        }
    }

    private func binding(for bucketID: String) -> Binding<Double> {
        Binding(
            get: { viewModel.binding(for: bucketID) },
            set: { viewModel.setBinding($0, for: bucketID) }
        )
    }

    private func saveSnapshot() {
        viewModel.saveSnapshot(context: modelContext, periodKey: periodKey, total: total)
    }
}
