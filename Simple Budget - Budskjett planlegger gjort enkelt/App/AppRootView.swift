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
    @Environment(\.scenePhase) private var scenePhase
    @Query private var preferences: [UserPreference]
    @StateObject private var viewModel = AppRootViewModel()
    @StateObject private var navigationState = AppNavigationState()
    @State private var bootstrapAttempted = false

    private var preference: UserPreference? { preferences.first }
    private var shouldUseFaceIDLock: Bool {
        preference?.faceIDLockEnabled ?? false
    }

    var body: some View {
        ZStack {
            Group {
                if preference != nil {
                    TabView(selection: $navigationState.selectedTab) {
                        NavigationStack { BudgetView() }
                            .tabItem { Label("Budsjett", systemImage: "list.bullet.rectangle") }
                            .tag(AppTab.budget)

                        NavigationStack { InvestmentsView() }
                            .tabItem { Label("Investeringer", systemImage: "chart.line.uptrend.xyaxis") }
                            .tag(AppTab.investments)

                        NavigationStack { OverviewView() }
                            .tabItem { Label("Oversikt", systemImage: "chart.pie.fill") }
                            .tag(AppTab.overview)

                        NavigationStack { ChallengesView() }
                            .tabItem { Label("Utfordringer", systemImage: "flag.pattern.checkered") }
                            .tag(AppTab.challenges)

                        NavigationStack { SettingsView() }
                            .tabItem { Label("Innstillinger", systemImage: "gear") }
                            .tag(AppTab.settings)
                    }
                    .environmentObject(navigationState)
                } else {
                    VStack(spacing: 12) {
                        ProgressView("Klargjør appen...")
                        if let message = viewModel.bootstrapErrorMessage {
                            Text(message)
                                .appSecondaryStyle()
                        }
                        if bootstrapAttempted {
                            Button("Prøv igjen") {
                                viewModel.bootstrap(context: modelContext)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if shouldUseFaceIDLock && viewModel.isLocked {
                lockOverlay
                    .transition(.opacity)
                    .zIndex(5)
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
        .onAppear {
            viewModel.configureLock(enabled: shouldUseFaceIDLock)
        }
        .onChange(of: shouldUseFaceIDLock) { _, newValue in
            viewModel.configureLock(enabled: newValue)
        }
        .onChange(of: scenePhase) { _, newValue in
            viewModel.handleScenePhaseChange(newValue)
        }
    }

    private var lockOverlay: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "faceid")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                Text("Face ID-lås")
                    .font(.title3.weight(.semibold))
                Text("Lås opp for å fortsette")
                    .appSecondaryStyle()
                if viewModel.isAuthenticating {
                    ProgressView()
                }
                if let lockError = viewModel.lockErrorMessage {
                    Text(lockError)
                        .appSecondaryStyle()
                        .multilineTextAlignment(.center)
                }
                Button("Prøv igjen") {
                    viewModel.retryUnlock()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
            }
            .padding(24)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
            .padding(24)
        }
    }
}
