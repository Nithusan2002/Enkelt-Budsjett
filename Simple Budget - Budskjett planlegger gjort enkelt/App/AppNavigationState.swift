import Foundation
import Combine

@MainActor
final class AppNavigationState: ObservableObject {
    @Published var selectedTab: AppTab = .overview
}
