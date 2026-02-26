import SwiftUI
import SwiftData
import UIKit

enum AppTab {
    case overview
    case budget
    case investments
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
        if ProcessInfo.processInfo.arguments.contains("UITEST_DISABLE_FACEID") {
            return false
        }
        return preference?.faceIDLockEnabled ?? false
    }
    private var storeMode: AppStoreMode {
        Simple_Budget___Budskjett_planlegger_gjort_enkeltApp.activeStoreMode
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
        .safeAreaInset(edge: .top) {
            if storeMode != .primary {
                StoreHealthBanner(mode: storeMode)
                    .padding(.horizontal)
                    .padding(.top, 6)
            }
        }
        .tint(AppTheme.primary)
        .background(AppTheme.background.ignoresSafeArea())
        .foregroundStyle(AppTheme.textPrimary)
        .task {
            guard !bootstrapAttempted else { return }
            applyBarAppearance()
            bootstrapAttempted = true
            viewModel.bootstrap(context: modelContext)
        }
        .onAppear {
            applyBarAppearance()
            viewModel.configureLock(enabled: shouldUseFaceIDLock)
        }
        .onChange(of: shouldUseFaceIDLock) { _, newValue in
            viewModel.configureLock(enabled: newValue)
        }
        .onChange(of: scenePhase) { _, newValue in
            viewModel.handleScenePhaseChange(newValue)
        }
    }

    private func applyBarAppearance() {
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(AppTheme.surface)
        tabAppearance.shadowColor = UIColor(AppTheme.divider)

        let normalColor = UIColor(AppTheme.textSecondary)
        let selectedColor = UIColor(AppTheme.primary)
        tabAppearance.stackedLayoutAppearance.normal.iconColor = normalColor
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
        tabAppearance.stackedLayoutAppearance.selected.iconColor = selectedColor
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(AppTheme.textPrimary)]
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor(AppTheme.textPrimary)]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIColor(AppTheme.primary)
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

private struct StoreHealthBanner: View {
    let mode: AppStoreMode

    private var title: String {
        switch mode {
        case .recovery:
            return "Recovery-modus"
        case .memoryOnly:
            return "Midlertidig datamodus"
        case .primary:
            return ""
        }
    }

    private var detail: String {
        switch mode {
        case .recovery:
            return "Primær datalagring feilet. Appen kjører med recovery-lager. Eksporter data i Innstillinger."
        case .memoryOnly:
            return "Appen kjører uten varig lagring. Data kan forsvinne ved omstart."
        case .primary:
            return ""
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.white)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.white)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.95))
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppTheme.negative, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
    }
}
