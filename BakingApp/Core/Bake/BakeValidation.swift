import Foundation

enum BakeValidationError: LocalizedError, Equatable {
    case blankName
    case missingStarter
    case hydrationOutOfRange
    case negativeDuration(String)
    case bakingTimeInvalid
    case ratingOutOfRange
    case blankMixingMethod
    case blankShapingMethod
    case ovenTemperatureOutOfRange
    case fermentationTemperatureOutOfRange
    case fermentationSourceRequired
    case fermentationTemperatureRequiredForSource

    var errorDescription: String? {
        switch self {
        case .blankName:
            return "Enter a bake name."
        case .missingStarter:
            return "Select the starter used for this bake."
        case .hydrationOutOfRange:
            return "Dough hydration must be between 40% and 120%."
        case .negativeDuration(let field):
            return "\(field) cannot be negative."
        case .bakingTimeInvalid:
            return "Baking time must be greater than 0 minutes."
        case .ratingOutOfRange:
            return "Result rating must be between 1 and 5."
        case .blankMixingMethod:
            return "Select a mixing method."
        case .blankShapingMethod:
            return "Select a shaping method."
        case .ovenTemperatureOutOfRange:
            return "Oven temperature must be between 100°C and 350°C."
        case .fermentationTemperatureOutOfRange:
            return "Fermentation temperature must be between 0°C and 50°C."
        case .fermentationSourceRequired:
            return "Select whether fermentation temperature is room or dough."
        case .fermentationTemperatureRequiredForSource:
            return "Enter a fermentation temperature, or clear the source."
        }
    }
}

enum BakeValidation {
    static func validate(_ input: BakeCreateInput) throws -> BakeCreateInput {
        let trimmedName = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw BakeValidationError.blankName }

        let mixing = input.mixingMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mixing.isEmpty else { throw BakeValidationError.blankMixingMethod }

        let shaping = input.shapingMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !shaping.isEmpty else { throw BakeValidationError.blankShapingMethod }

        guard (40...120).contains(input.doughHydrationPercent) else {
            throw BakeValidationError.hydrationOutOfRange
        }
        guard input.bulkFermentationMinutes >= 0 else {
            throw BakeValidationError.negativeDuration("Bulk fermentation")
        }
        guard input.finalProofMinutes >= 0 else {
            throw BakeValidationError.negativeDuration("Final proof")
        }
        guard input.bakingTimeMinutes > 0 else {
            throw BakeValidationError.bakingTimeInvalid
        }
        guard (1...5).contains(input.resultRating) else {
            throw BakeValidationError.ratingOutOfRange
        }
        guard (100...350).contains(input.ovenTemperatureCelsius) else {
            throw BakeValidationError.ovenTemperatureOutOfRange
        }

        if let retardation = input.retardationMinutes, retardation < 0 {
            throw BakeValidationError.negativeDuration("Retardation")
        }
        if let folds = input.numberOfFolds, folds < 0 {
            throw BakeValidationError.negativeDuration("Number of folds")
        }

        var fermentationTemp = input.fermentationTemperatureCelsius
        var fermentationSource = input.fermentationTemperatureSource
        switch (fermentationTemp, fermentationSource) {
        case (nil, nil):
            break
        case (let temp?, let source?):
            guard (0...50).contains(temp) else {
                throw BakeValidationError.fermentationTemperatureOutOfRange
            }
            fermentationTemp = temp
            fermentationSource = source
        case (_?, nil):
            throw BakeValidationError.fermentationSourceRequired
        case (nil, _?):
            throw BakeValidationError.fermentationTemperatureRequiredForSource
        }

        let steaming = input.steamingMethod?.trimmingCharacters(in: .whitespacesAndNewlines)
        let flourNotes = input.flourNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = input.notes?.trimmingCharacters(in: .whitespacesAndNewlines)

        return BakeCreateInput(
            starterID: input.starterID,
            bakedAt: input.bakedAt,
            name: trimmedName,
            doughHydrationPercent: input.doughHydrationPercent,
            bulkFermentationMinutes: input.bulkFermentationMinutes,
            finalProofMinutes: input.finalProofMinutes,
            mixingMethod: mixing,
            shapingMethod: shaping,
            ovenTemperatureCelsius: input.ovenTemperatureCelsius,
            bakingTimeMinutes: input.bakingTimeMinutes,
            resultRating: input.resultRating,
            fermentationTemperatureCelsius: fermentationTemp,
            fermentationTemperatureSource: fermentationSource,
            retardationMinutes: input.retardationMinutes,
            numberOfFolds: input.numberOfFolds,
            steamingMethod: steaming.flatMap { $0.isEmpty ? nil : $0 },
            flourNotes: flourNotes.flatMap { $0.isEmpty ? nil : $0 },
            notes: notes.flatMap { $0.isEmpty ? nil : $0 }
        )
    }
}
