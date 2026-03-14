import Combine
import SwiftUI

@MainActor
final class AIInsightSheetViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded(AIInsightResponse)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let service: AIInsightsService?
    private let summary: AIInsightRequestSummary
    private var hasLoaded = false

    init(summary: AIInsightRequestSummary, service: AIInsightsService? = nil) {
        self.summary = summary
        self.service = service ?? (try? AIInsightsService())
    }

    var isLoading: Bool {
        if case .loading = state {
            return true
        }
        return false
    }

    func loadIfNeeded() async {
        await load(forceRefresh: false)
    }

    func refresh() async {
        await load(forceRefresh: true)
    }

    private func load(forceRefresh: Bool) async {
        guard forceRefresh || !hasLoaded else { return }
        hasLoaded = true
        state = .loading

#if DEBUG
        state = .loaded(Self.debugResponse(for: summary))
        return
#else
        guard let service else {
            state = .failed("AI-hjelperen er ikke konfigurert ennå.")
            return
        }

        do {
            let response = try await service.fetchInsight(summary: summary)
            state = .loaded(response)
        } catch {
            state = .failed(error.localizedDescription)
        }
#endif
    }

    static func debugResponse(for summary: AIInsightRequestSummary) -> AIInsightResponse {
        let biggestCategory = summary.topCategories.first?.title.lowercased() ?? "utgiftene"
        let remaining = Int(summary.remaining.rounded())
        let spent = Int(summary.spent.rounded())
        let fixedItems = Int(summary.fixedItemsTotal.rounded())

        return AIInsightResponse(
            summary: "Debug-modus: Du har brukt \(spent) kr så langt, og har \(remaining) kr igjen denne måneden.",
            keyDriver: "Debug-modus: \(biggestCategory.capitalized) og faste poster på \(fixedItems) kr preger oversikten mest akkurat nå.",
            nextStep: "Debug-modus: Verifiser at teksten ser riktig ut, uten at appen bruker ekte AI-kall."
        )
    }
}

struct AIInsightSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AIInsightSheetViewModel

    init(summary: AIInsightRequestSummary) {
        _viewModel = StateObject(wrappedValue: AIInsightSheetViewModel(summary: summary))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(AppTheme.background)
            .navigationTitle("AI-hjelper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Lukk") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await viewModel.refresh()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.body.weight(.semibold))
                    }
                    .disabled(viewModel.isLoading)
                    .accessibilityLabel("Oppdater AI-oppsummering")
                }
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            VStack(alignment: .leading, spacing: 14) {
                ProgressView()
                    .tint(AppTheme.primary)
                Text("Ser på måneden din")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Jeg lager en kort oppsummering av tallene dine.")
                    .appBodyStyle()
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)

        case .loaded(let response):
            VStack(alignment: .leading, spacing: 18) {
                Text("Her er en kort oppsummering")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                insightBlock(title: "Oppsummering", text: response.summary)
                insightBlock(title: "Påvirker måneden mest", text: response.keyDriver)
                insightBlock(title: "Neste steg", text: response.nextStep)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 14) {
                Text("Jeg fikk ikke hentet hjelp akkurat nå")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(message)
                    .appBodyStyle()
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        }
    }

    private func insightBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            Text(text)
                .appBodyStyle()
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTheme.divider, lineWidth: 1)
        )
    }
}
