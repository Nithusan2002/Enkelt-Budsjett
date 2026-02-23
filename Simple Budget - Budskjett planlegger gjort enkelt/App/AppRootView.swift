import SwiftUI
import SwiftData

enum AppTab {
    case overview
    case budget
    case investments
    case challenges
    case settings
}

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreference]
    @StateObject private var viewModel = AppRootViewModel()
    @State private var selectedTab: AppTab = .overview
    @State private var bootstrapAttempted = false

    private var preference: UserPreference? { preferences.first }

    var body: some View {
        Group {
            if let preference, preference.onboardingCompleted {
                TabView(selection: $selectedTab) {
                    NavigationStack { OverviewView() }
                        .tabItem { Label("Oversikt", systemImage: "rectangle.grid.2x2") }
                        .tag(AppTab.overview)

                    NavigationStack { BudgetView() }
                        .tabItem { Label("Budsjett", systemImage: "list.bullet.rectangle") }
                        .tag(AppTab.budget)

                    NavigationStack { InvestmentsView() }
                        .tabItem { Label("Investeringer", systemImage: "chart.pie") }
                        .tag(AppTab.investments)

                    NavigationStack { ChallengesView() }
                        .tabItem { Label("Utfordringer", systemImage: "flag.pattern.checkered") }
                        .tag(AppTab.challenges)

                    NavigationStack { SettingsView() }
                        .tabItem { Label("Innstillinger", systemImage: "gear") }
                        .tag(AppTab.settings)
                }
            } else if let preference {
                OnboardingView(preference: preference)
            } else {
                VStack(spacing: 12) {
                    ProgressView("Klargjør appen...")
                    if bootstrapAttempted {
                        Button("Prøv igjen") {
                            viewModel.bootstrap(context: modelContext)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .tint(AppTheme.primary)
        .background(AppTheme.background.ignoresSafeArea())
        .foregroundStyle(AppTheme.textPrimary)
        .task {
            guard !bootstrapAttempted else { return }
            bootstrapAttempted = true
            viewModel.bootstrap(context: modelContext)
        }
    }
}
