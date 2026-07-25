import Foundation

enum StarterValidation {
    static func validateStarterName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppError.unknown("Starter name is required.")
        }
        guard trimmed.count <= 60 else {
            throw AppError.unknown("Starter name is too long.")
        }
        return trimmed
    }

    static func validateHydration(_ hydration: Double?) throws -> Double? {
        guard let hydration else { return nil }
        guard hydration >= 20 && hydration <= 300 else {
            throw AppError.unknown("Hydration must be between 20 and 300.")
        }
        return hydration
    }

    static func validateFeedingLog(roomTempC: Double, flourG: Int?, waterG: Int?, starterG: Int?) throws {
        guard roomTempC >= -10, roomTempC <= 60 else {
            throw AppError.unknown("Room temperature must be between -10°C and 60°C.")
        }
        for grams in [flourG, waterG, starterG] {
            if let grams, grams < 0 {
                throw AppError.unknown("Ingredient amounts must be non-negative.")
            }
        }
    }
}

