import SwiftUI
import SwiftData

struct ChallengesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Challenge.startDate, order: .reverse) private var challenges: [Challenge]
    @Query private var transactions: [Transaction]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var preferences: [UserPreference]
    @StateObject private var viewModel = ChallengesViewModel()

    var body: some View {
        List {
            ForEach(challenges) { challenge in
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.title(for: challenge.type))
                        .appCardTitleStyle()
                    Text(ChallengeService.progressText(challenge))
                        .appSecondaryStyle()
                    ProgressView(value: challenge.progress)
                        .tint(AppTheme.primary)
                    HStack {
                        if challenge.status == .active {
                            Button("Pause") {
                                viewModel.pause(challenge, context: modelContext)
                            }
                            .appCTAStyle()
                        } else if challenge.status == .paused {
                            Button("Fortsett") {
                                viewModel.resume(challenge, context: modelContext)
                            }
                            .appCTAStyle()
                        }
                        Spacer()
                        if challenge.status != .completed {
                            Button("Fullfør") {
                                viewModel.complete(challenge, context: modelContext)
                            }
                            .appCTAStyle()
                        }
                    }
                    Button("Oppdater progresjon") {
                        viewModel.recalculate(
                            challenge,
                            transactions: transactions,
                            categories: categories,
                            preference: preferences.first,
                            context: modelContext
                        )
                    }
                    .appSecondaryStyle()
                }
                .padding(.vertical, 6)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Utfordringer")
    }
}
