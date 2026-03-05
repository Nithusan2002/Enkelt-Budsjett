import Foundation
import SwiftData
@testable import Simple_Budget___Budskjett_planlegger_gjort_enkelt

enum TestModelContainerFactory {

    @MainActor
    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            BudgetMonth.self,
            Category.self,
            BudgetPlan.self,
            BudgetGroupPlan.self,
            Transaction.self,
            Account.self,
            InvestmentBucket.self,
            InvestmentSnapshot.self,
            FixedItem.self,
            FixedItemSkip.self,
            Goal.self,
            Challenge.self,
            UserPreference.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
