import Foundation

enum ProjectType: String, CaseIterable, Identifiable, Codable {
    case timeHistory = "Time History"
    case floorVibration = "Floor Vibration"
    var id: String { rawValue }
}

enum BuildingType: String, CaseIterable, Identifiable, Codable {
    case office = "Office"
    case residential = "Residential"
    case industrial = "Industrial"
    var id: String { rawValue }
}

enum ConstructionMaterial: String, CaseIterable, Identifiable, Codable {
    case concrete = "Concrete"
    case steel = "Steel"
    case wood = "Wood"
    var id: String { rawValue }
}

struct Project: Identifiable, Codable {
    let id: UUID = UUID()
    var name: String
    var description: String
    var type: ProjectType
    var buildingType: BuildingType?
    var constructionMaterial: ConstructionMaterial?
    var subjectiveResponses: [String: String]? = nil
    var measurements: [Measurement] = []
}
