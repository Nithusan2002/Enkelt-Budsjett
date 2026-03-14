import Foundation
import Combine

enum InvestmentsSectionFocus: String {
    case development
    case distribution
}

enum SettingsRoute: Hashable {
    case account
    case premium
}

@MainActor
final class AppNavigationState: ObservableObject {
    @Published var selectedTab: AppTab = .overview
    @Published var investmentsFocus: InvestmentsSectionFocus?
    @Published var pendingSettingsRoute: SettingsRoute?
}
