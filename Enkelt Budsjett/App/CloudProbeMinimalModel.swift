import Foundation
import SwiftData

@Model
final class CloudProbeMinimalModel {
    var createdAt: Date = Date.now

    init(createdAt: Date = Date.now) {
        self.createdAt = createdAt
    }
}
