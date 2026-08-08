import Foundation

enum FermentationTemperatureSource: String, Codable, CaseIterable, Equatable {
    case room
    case dough
}

enum BakeMixingMethod: String, CaseIterable, Equatable {
    case hand = "Hand mix"
    case standMixer = "Stand mixer"
    case stretchAndFoldOnly = "Stretch and fold only"
}

enum BakeShapingMethod: String, CaseIterable, Equatable {
    case boule = "Boule"
    case batard = "Batard"
    case freeForm = "Free-form"
    case panLoaf = "Pan loaf"
}

struct Bake: Codable, Equatable, Identifiable {
    let id: UUID
    let userID: UUID
    let starterID: UUID
    var bakedAt: Date
    var name: String
    var doughHydrationPercent: Double
    var bulkFermentationMinutes: Int
    var finalProofMinutes: Int
    var mixingMethod: String
    var shapingMethod: String
    var ovenTemperatureCelsius: Double
    var bakingTimeMinutes: Int
    var resultRating: Int
    var fermentationTemperatureCelsius: Double?
    var fermentationTemperatureSource: FermentationTemperatureSource?
    var retardationMinutes: Int?
    var numberOfFolds: Int?
    var steamingMethod: String?
    var flourNotes: String?
    var notes: String?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case starterID = "starter_id"
        case bakedAt = "baked_at"
        case name
        case doughHydrationPercent = "dough_hydration_percent"
        case bulkFermentationMinutes = "bulk_fermentation_minutes"
        case finalProofMinutes = "final_proof_minutes"
        case mixingMethod = "mixing_method"
        case shapingMethod = "shaping_method"
        case ovenTemperatureCelsius = "oven_temperature_c"
        case bakingTimeMinutes = "baking_time_minutes"
        case resultRating = "result_rating"
        case fermentationTemperatureCelsius = "fermentation_temperature_c"
        case fermentationTemperatureSource = "fermentation_temperature_source"
        case retardationMinutes = "retardation_minutes"
        case numberOfFolds = "number_of_folds"
        case steamingMethod = "steaming_method"
        case flourNotes = "flour_notes"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct BakeCreateInput: Equatable {
    var starterID: UUID
    var bakedAt: Date
    var name: String
    var doughHydrationPercent: Double
    var bulkFermentationMinutes: Int
    var finalProofMinutes: Int
    var mixingMethod: String
    var shapingMethod: String
    var ovenTemperatureCelsius: Double
    var bakingTimeMinutes: Int
    var resultRating: Int
    var fermentationTemperatureCelsius: Double?
    var fermentationTemperatureSource: FermentationTemperatureSource?
    var retardationMinutes: Int?
    var numberOfFolds: Int?
    var steamingMethod: String?
    var flourNotes: String?
    var notes: String?
}

struct BakeInsert: Codable, Equatable {
    let userID: UUID
    let starterID: UUID
    let bakedAt: Date
    let name: String
    let doughHydrationPercent: Double
    let bulkFermentationMinutes: Int
    let finalProofMinutes: Int
    let mixingMethod: String
    let shapingMethod: String
    let ovenTemperatureCelsius: Double
    let bakingTimeMinutes: Int
    let resultRating: Int
    let fermentationTemperatureCelsius: Double?
    let fermentationTemperatureSource: String?
    let retardationMinutes: Int?
    let numberOfFolds: Int?
    let steamingMethod: String?
    let flourNotes: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case starterID = "starter_id"
        case bakedAt = "baked_at"
        case name
        case doughHydrationPercent = "dough_hydration_percent"
        case bulkFermentationMinutes = "bulk_fermentation_minutes"
        case finalProofMinutes = "final_proof_minutes"
        case mixingMethod = "mixing_method"
        case shapingMethod = "shaping_method"
        case ovenTemperatureCelsius = "oven_temperature_c"
        case bakingTimeMinutes = "baking_time_minutes"
        case resultRating = "result_rating"
        case fermentationTemperatureCelsius = "fermentation_temperature_c"
        case fermentationTemperatureSource = "fermentation_temperature_source"
        case retardationMinutes = "retardation_minutes"
        case numberOfFolds = "number_of_folds"
        case steamingMethod = "steaming_method"
        case flourNotes = "flour_notes"
        case notes
    }
}
