import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID
    var name: String
    var description: String
    var type: String
    var measurements: [Measurement]

    init(id: UUID = UUID(), name: String, description: String, type: String) {
        self.id = id
        self.name = name
        self.description = description
        self.type = type
        self.measurements = []
    }
}
