import Foundation
import Supabase

final class SupabaseStarterRepository: StarterRepository {
    private let client: SupabaseClient
    private let supabaseURL: URL
    private let anonKey: String
    private let session: URLSession

    init(
        supabaseURL: URL,
        anonKey: String,
        session: URLSession = .shared
    ) {
        self.client = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: anonKey)
        self.supabaseURL = supabaseURL
        self.anonKey = anonKey
        self.session = session
    }

    func listStarters() async throws -> [Starter] {
        do {
            let response = try await client
                .from("starters")
                .select()
                .order("active", ascending: false)
                .order("created_at", ascending: false)
                .execute()
            return try decode([Starter].self, from: response.data)
        } catch {
            throw mapRepositoryError(error, operation: "load starters")
        }
    }

    func createStarter(name: String, hydrationPreference: Double?, active: Bool) async throws -> Starter {
        let validatedName = try StarterValidation.validateStarterName(name)
        let validatedHydration = try StarterValidation.validateHydration(hydrationPreference)
        let userID = try await currentUserID()
        do {
            return try await Self.createStarterWithActivation(
                active: active,
                insert: { [self] in
                    let response = try await client
                        .from("starters")
                        .insert(StarterInsert(
                            userID: userID,
                            name: validatedName,
                            hydrationPreference: validatedHydration,
                            active: active
                        ))
                        .select()
                        .single()
                        .execute()
                    return try decode(Starter.self, from: response.data)
                },
                deactivateOthers: { [self] newStarterID in
                    try await deactivateAllStarters(for: userID, excluding: newStarterID)
                }
            )
        } catch {
            throw mapRepositoryError(error, operation: "create starter")
        }
    }

    func setActiveStarter(starterID: UUID) async throws {
        let userID = try await currentUserID()
        do {
            _ = try await client
                .from("starters")
                .update(["active": true])
                .eq("id", value: starterID.uuidString.lowercased())
                .eq("user_id", value: userID.uuidString.lowercased())
                .execute()
            try await deactivateAllStarters(for: userID, excluding: starterID)
        } catch {
            throw mapRepositoryError(error, operation: "set active starter")
        }
    }

    func fetchStarter(starterID: UUID) async throws -> Starter {
        do {
            let response = try await client
                .from("starters")
                .select()
                .eq("id", value: starterID.uuidString.lowercased())
                .single()
                .execute()
            return try decode(Starter.self, from: response.data)
        } catch {
            throw mapRepositoryError(error, operation: "load starter details")
        }
    }

    func fetchStarterState(starterID: UUID) async throws -> StarterState? {
        do {
            let response = try await client
                .from("starter_states")
                .select()
                .eq("starter_id", value: starterID.uuidString.lowercased())
                .limit(1)
                .execute()
            let decoded = try decode([StarterState].self, from: response.data)
            return decoded.first
        } catch {
            throw mapRepositoryError(error, operation: "load starter state")
        }
    }

    func createFeedingLog(
        starterID: UUID,
        loggedAt: Date,
        roomTempC: Double,
        flourG: Int?,
        waterG: Int?,
        starterG: Int?,
        notes: String?
    ) async throws -> FeedingLog {
        try StarterValidation.validateFeedingLog(roomTempC: roomTempC, flourG: flourG, waterG: waterG, starterG: starterG)
        let userID = try await currentUserID()
        do {
            let response = try await client
                .from("feeding_logs")
                .insert(
                    FeedingLogInsert(
                        userID: userID,
                        starterID: starterID,
                        loggedAt: loggedAt,
                        roomTempC: roomTempC,
                        flourG: flourG,
                        waterG: waterG,
                        starterG: starterG,
                        notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
                .select()
                .single()
                .execute()
            return try decode(FeedingLog.self, from: response.data)
        } catch {
            throw mapRepositoryError(error, operation: "save feeding log")
        }
    }

    func listFeedingLogs(starterID: UUID) async throws -> [FeedingLog] {
        do {
            let response = try await client
                .from("feeding_logs")
                .select()
                .eq("starter_id", value: starterID.uuidString.lowercased())
                .order("logged_at", ascending: false)
                .execute()
            return try decode([FeedingLog].self, from: response.data)
        } catch {
            throw mapRepositoryError(error, operation: "load feeding history")
        }
    }

    func uploadStarterImage(data: Data, userID: UUID, starterID: UUID, date: Date) async throws -> String {
        let path = Self.makeStoragePath(userID: userID, starterID: starterID, date: date, imageID: UUID())
        do {
            try await client.storage
                .from("starter-images")
                .upload(
                    path,
                    data: data,
                    options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: false)
                )
            return path
        } catch {
            throw mapRepositoryError(error, operation: "upload starter image")
        }
    }

    func analyzeStarter(starterID: UUID, imagePath: String, promptVersion: String = "v1") async throws -> StarterAnalyzeResult {
        let authSession = try await client.auth.session
        let payload = AnalyzeStarterPayload(starterID: starterID, imagePath: imagePath, promptVersion: promptVersion)

        let endpoint = supabaseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent("analyze-starter")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(authSession.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw mapRepositoryError(AppError.analysisFailed, operation: "analyze starter image")
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw mapRepositoryError(AppError.analysisFailed, operation: "analyze starter image")
        }
        do {
            return try StarterAnalyzeResponseParser.decode(data)
        } catch {
            throw mapRepositoryError(error, operation: "decode starter analysis response")
        }
    }

    func persistStarterAnalysis(
        starterID: UUID,
        imagePath: String,
        qualityScore: Double?,
        qualityIssue: String?,
        model: String,
        promptVersion: String,
        response: StarterAIResponse
    ) async throws -> PersistedStarterAnalysisIDs {
        let authSession = try await client.auth.session
        let endpoint = supabaseURL
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent("rpc")
            .appendingPathComponent("persist_starter_analysis")

        let body = PersistStarterAnalysisPayload(
            starterID: starterID,
            storagePath: imagePath,
            qualityScore: qualityScore,
            qualityIssue: qualityIssue,
            model: model,
            promptVersion: promptVersion,
            confidence: response.confidence,
            analysisJSON: response,
            renderedExplanation: response.humanExplanation,
            stateLabel: response.starterState,
            recommendation: response.nextSteps[0].instruction,
            dueHours: response.nextSteps[0].timeWindowHours
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(authSession.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw mapRepositoryError(AppError.unknown("Invalid response"), operation: "save analysis")
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw mapRepositoryError(AppError.analysisFailed, operation: "save analysis")
        }
        do {
            return try decode(PersistedStarterAnalysisIDs.self, from: data)
        } catch {
            if let decodedArray = try? decode([PersistedStarterAnalysisIDs].self, from: data), let first = decodedArray.first {
                return first
            }
            throw mapRepositoryError(error, operation: "decode persisted analysis response")
        }
    }

    func listTimeline(starterID: UUID) async throws -> [StarterTimelineItem] {
        do {
            let response = try await client
                .from("scans")
                .select("*, ai_analyses(*), recommendations(*)")
                .eq("starter_id", value: starterID.uuidString.lowercased())
                .eq("scan_type", value: "starter")
                .order("created_at", ascending: false)
                .execute()
            let rows = try decode([TimelineRow].self, from: response.data)
            return rows.map { row in
                StarterTimelineItem(
                    id: row.id,
                    scan: row.scan,
                    analysis: row.analyses.first,
                    recommendation: row.recommendations.first
                )
            }
        } catch {
            throw mapRepositoryError(error, operation: "load starter timeline")
        }
    }

    func updateRecommendationOutcome(recommendationID: UUID, outcome: RecommendationOutcome) async throws -> Recommendation {
        do {
            let response = try await client
                .from("recommendations")
                .update(RecommendationOutcomeUpdate(
                    outcome: outcome.rawValue,
                    completedAt: ISO8601DateFormatter().string(from: Date())
                ))
                .eq("id", value: recommendationID.uuidString.lowercased())
                .select()
                .single()
                .execute()
            return try decode(Recommendation.self, from: response.data)
        } catch {
            throw mapRepositoryError(error, operation: "update recommendation outcome")
        }
    }

    func signedImageURL(path: String, expiresIn: TimeInterval = 1800) async throws -> URL {
        try await client.storage
            .from("starter-images")
            .createSignedURL(path: path, expiresIn: Int(expiresIn))
    }

    static func makeStoragePath(userID: UUID, starterID: UUID, date: Date, imageID: UUID) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let year = String(calendar.component(.year, from: date))
        let month = String(format: "%02d", calendar.component(.month, from: date))
        return "\(userID.uuidString.lowercased())/\(starterID.uuidString.lowercased())/\(year)/\(month)/\(imageID.uuidString.lowercased()).jpg"
    }

    private func currentUserID() async throws -> UUID {
        do {
            let authSession = try await client.auth.session
            return authSession.user.id
        } catch {
            throw mapRepositoryError(error, operation: "load authenticated user")
        }
    }

    private func deactivateAllStarters(for userID: UUID, excluding starterID: UUID) async throws {
        _ = try await client
            .from("starters")
            .update(["active": false])
            .eq("user_id", value: userID.uuidString.lowercased())
            .neq("id", value: starterID.uuidString.lowercased())
            .execute()
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    private func mapRepositoryError(_ error: Error, operation: String) -> AppError {
        RepositoryErrorMapper.map(error, operation: operation)
    }

    static func createStarterWithActivation(
        active: Bool,
        insert: () async throws -> Starter,
        deactivateOthers: (UUID) async throws -> Void
    ) async throws -> Starter {
        let starter = try await insert()
        guard active else { return starter }
        try await deactivateOthers(starter.id)
        return starter
    }
}

struct StarterInsert: Codable {
    let userID: UUID
    let name: String
    let hydrationPreference: Double?
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case name
        case hydrationPreference = "hydration_preference"
        case active
    }
}

struct FeedingLogInsert: Codable {
    let userID: UUID
    let starterID: UUID
    let loggedAt: Date
    let roomTempC: Double
    let flourG: Int?
    let waterG: Int?
    let starterG: Int?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case starterID = "starter_id"
        case loggedAt = "logged_at"
        case roomTempC = "room_temp_c"
        case flourG = "flour_g"
        case waterG = "water_g"
        case starterG = "starter_g"
        case notes
    }
}

private struct PersistStarterAnalysisPayload: Codable {
    let starterID: UUID
    let storagePath: String
    let qualityScore: Double?
    let qualityIssue: String?
    let model: String
    let promptVersion: String
    let confidence: Double
    let analysisJSON: StarterAIResponse
    let renderedExplanation: String
    let stateLabel: String
    let recommendation: String
    let dueHours: Int

    enum CodingKeys: String, CodingKey {
        case starterID = "p_starter_id"
        case storagePath = "p_storage_path"
        case qualityScore = "p_quality_score"
        case qualityIssue = "p_quality_issue"
        case model = "p_model"
        case promptVersion = "p_prompt_version"
        case confidence = "p_confidence"
        case analysisJSON = "p_analysis_json"
        case renderedExplanation = "p_rendered_explanation"
        case stateLabel = "p_state_label"
        case recommendation = "p_recommendation"
        case dueHours = "p_due_hours"
    }
}

private struct TimelineRow: Decodable {
    let id: UUID
    let scan: StarterScan
    let analyses: [StarterAnalysis]
    let recommendations: [Recommendation]

    enum CodingKeys: String, CodingKey {
        case id
        case analyses = "ai_analyses"
        case recommendations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        analyses = try container.decodeIfPresent([StarterAnalysis].self, forKey: .analyses) ?? []
        recommendations = try container.decodeIfPresent([Recommendation].self, forKey: .recommendations) ?? []
        scan = try StarterScan(from: decoder)
    }
}

enum StarterAnalyzeResponseParser {
    static func decode(_ data: Data) throws -> StarterAnalyzeResult {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let root = json as? [String: Any] else {
            throw AppError.malformedResponse
        }
        guard let model = root["model"] as? String else {
            throw AppError.malformedResponse
        }
        guard let promptVersion = root["prompt_version"] as? String else {
            throw AppError.malformedResponse
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.malformedResponse
        }
        guard !promptVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.malformedResponse
        }
        guard let analysisObject = root["analysis"] else {
            throw AppError.malformedResponse
        }
        let analysisData = try JSONSerialization.data(withJSONObject: analysisObject)
        let analysis = try StarterAIContractValidator.decodeStrict(analysisData)
        return StarterAnalyzeResult(
            model: model,
            promptVersion: promptVersion,
            analysis: analysis
        )
    }
}

private struct RecommendationOutcomeUpdate: Encodable {
    let outcome: String
    let completedAt: String

    enum CodingKeys: String, CodingKey {
        case outcome
        case completedAt = "completed_at"
    }
}

enum RepositoryErrorMapper {
    static func map(_ error: Error, operation: String) -> AppError {
        debugLog(error, operation: operation)

        if let appError = error as? AppError {
            return appError
        }
        if let authError = error as? AuthError, authError == .sessionMissing {
            return .unknown("Your session has expired. Please sign in again.")
        }
        if let postgrestError = error as? PostgrestError {
            let code = postgrestError.code ?? ""
            let message = postgrestError.message.lowercased()
            if code == "42501" || message.contains("row-level security") || message.contains("permission denied") {
                return .unknown("You don't have permission to perform this action.")
            }
            if code == "23502" || code == "23514" || code == "22P02" {
                return .unknown("Some values are invalid. Please review the form and try again.")
            }
            return .unknown("Something went wrong while trying to \(operation). Please try again.")
        }
        if error is DecodingError {
            return .unknown("We received an unexpected response from the server. Please try again.")
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost:
                return .unknown("Network issue detected. Check your connection and try again.")
            default:
                return .unknown("Network request failed. Please try again.")
            }
        }
        return .unknown("Something went wrong while trying to \(operation). Please try again.")
    }

    private static func debugLog(_ error: Error, operation: String) {
        #if DEBUG
        print("[StarterRepository] \(operation) failed: \(String(describing: error))")
        #endif
    }
}

