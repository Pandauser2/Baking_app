import Foundation

struct StarterAIResponse: Codable, Equatable {
    let scanType: String
    let observations: [String]
    let diagnosis: [String]
    let confidence: Double
    let nextSteps: [NextStep]
    let humanExplanation: String
    let riskFlags: [String]
    let compareToPrevious: CompareToPrevious
    let starterState: String

    struct NextStep: Codable, Equatable {
        let instruction: String
        let timeWindowHours: Int

        enum CodingKeys: String, CodingKey {
            case instruction
            case timeWindowHours = "time_window_hours"
        }
    }

    struct CompareToPrevious: Codable, Equatable {
        let changed: Bool
        let explanation: String
    }

    enum CodingKeys: String, CodingKey {
        case scanType = "scan_type"
        case observations
        case diagnosis
        case confidence
        case nextSteps = "next_steps"
        case humanExplanation = "human_explanation"
        case riskFlags = "risk_flags"
        case compareToPrevious = "compare_to_previous"
        case starterState = "starter_state"
    }
}

enum StarterAIContractValidator {
    private static let allowedRootKeys: Set<String> = [
        "scan_type",
        "observations",
        "diagnosis",
        "confidence",
        "next_steps",
        "human_explanation",
        "risk_flags",
        "compare_to_previous",
        "starter_state"
    ]

    private static let allowedCompareKeys: Set<String> = ["changed", "explanation"]
    private static let allowedNextStepKeys: Set<String> = ["instruction", "time_window_hours"]

    static func decodeStrict(_ data: Data) throws -> StarterAIResponse {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let root = json as? [String: Any] else {
            throw AppError.malformedResponse
        }
        guard Set(root.keys) == allowedRootKeys else {
            throw AppError.malformedResponse
        }

        if let compare = root["compare_to_previous"] as? [String: Any], Set(compare.keys) != allowedCompareKeys {
            throw AppError.malformedResponse
        }

        if let steps = root["next_steps"] as? [[String: Any]] {
            for step in steps where Set(step.keys) != allowedNextStepKeys {
                throw AppError.malformedResponse
            }
        }

        let response = try JSONDecoder().decode(StarterAIResponse.self, from: data)
        try validate(response)
        return response
    }

    static func validate(_ response: StarterAIResponse) throws {
        guard response.scanType == "starter" else {
            throw AppError.malformedResponse
        }
        guard response.confidence >= 0, response.confidence <= 1 else {
            throw AppError.malformedResponse
        }
        guard !response.humanExplanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.malformedResponse
        }
        guard response.observations.count <= 3 else {
            throw AppError.malformedResponse
        }
        guard response.nextSteps.count == 1 else {
            throw AppError.malformedResponse
        }
        guard let first = response.nextSteps.first else {
            throw AppError.malformedResponse
        }
        guard !first.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.malformedResponse
        }
        guard first.timeWindowHours > 0 else {
            throw AppError.malformedResponse
        }
    }
}

