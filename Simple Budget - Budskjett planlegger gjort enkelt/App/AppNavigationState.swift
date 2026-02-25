import Foundation
import Combine

enum InvestmentsSectionFocus: String {
    case development
    case distribution
}

@MainActor
final class AppNavigationState: ObservableObject {
    @Published var selectedTab: AppTab = .overview
    @Published var investmentsFocus: InvestmentsSectionFocus?
}
