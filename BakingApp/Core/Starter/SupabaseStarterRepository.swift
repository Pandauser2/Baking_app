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
        do {
            let payload = CreateStarterProfilePayload(
                name: validatedName,
                hydrationPreference: validatedHydration,
                active: active
            )
            return try await performStarterRPC(
                name: "create_starter_profile",
                payload: payload
            )
        } catch {
            throw mapRepositoryError(error, operation: "create starter")
        }
    }

    func setActiveStarter(starterID: UUID) async throws {
        do {
            let payload = SetActiveStarterPayload(starterID: starterID)
            _ = try await performStarterRPC(
                name: "set_active_starter",
                payload: payload
            )
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
            let mappedError = StarterAnalyzeHTTPErrorMapper.map(statusCode: httpResponse.statusCode, data: data)
            #if DEBUG
            StarterAnalyzeHTTPErrorMapper.debugLog(statusCode: httpResponse.statusCode, data: data)
            #endif
            throw mapRepositoryError(mappedError, operation: "analyze starter image")
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
        let requestID = UUID().uuidString.lowercased()
        if let existing = try await reconcilePersistedAnalysisIDs(
            starterID: starterID,
            imagePath: imagePath
        ) {
            return existing
        }
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
            throw mapRepositoryError(
                PersistStarterAnalysisHTTPErrorMapper.mapInvalidResponse(requestID: requestID),
                operation: "save analysis"
            )
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let mapped = PersistStarterAnalysisHTTPErrorMapper.map(
                statusCode: httpResponse.statusCode,
                data: data,
                requestID: requestID
            )
            if mapped.errorCode == "PERSIST_CONFLICT" || mapped.errorCode == "PERSIST_RESPONSE_INVALID" {
                if let reconciled = try await reconcilePersistedAnalysisIDs(
                    starterID: starterID,
                    imagePath: imagePath
                ) {
                    return reconciled
                }
            }
            #if DEBUG
            PersistStarterAnalysisHTTPErrorMapper.debugLog(
                requestID: requestID,
                statusCode: httpResponse.statusCode,
                errorCode: mapped.errorCode
            )
            #endif
            throw mapRepositoryError(mapped, operation: "save analysis")
        }
        do {
            return try PersistStarterAnalysisResponseDecoder.decodeIDs(data)
        } catch {
            if let reconciled = try await reconcilePersistedAnalysisIDs(
                starterID: starterID,
                imagePath: imagePath
            ) {
                return reconciled
            }
            let mapped = PersistStarterAnalysisHTTPErrorMapper.mapResponseInvalid(requestID: requestID)
            #if DEBUG
            PersistStarterAnalysisHTTPErrorMapper.debugLog(
                requestID: requestID,
                statusCode: httpResponse.statusCode,
                errorCode: mapped.errorCode
            )
            #endif
            throw mapRepositoryError(mapped, operation: "decode persisted analysis response")
        }
    }

    func fetchRecommendation(recommendationID: UUID) async throws -> Recommendation {
        do {
            let response = try await client
                .from("recommendations")
                .select()
                .eq("id", value: recommendationID.uuidString.lowercased())
                .single()
                .execute()
            return try decode(Recommendation.self, from: response.data)
        } catch {
            throw mapRepositoryError(error, operation: "load recommendation")
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
            let rows = try TimelineRowDecoder.decodeRows(response.data)
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

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try SupabaseJSONDecoder.make().decode(type, from: data)
    }

    private func mapRepositoryError(_ error: Error, operation: String) -> AppError {
        RepositoryErrorMapper.map(error, operation: operation)
    }

    private func performStarterRPC<Payload: Encodable>(
        name: String,
        payload: Payload
    ) async throws -> Starter {
        let authSession = try await client.auth.session
        let endpoint = supabaseURL
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent("rpc")
            .appendingPathComponent(name)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(authSession.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.unknown("Invalid response")
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw AppError.unknown("Starter mutation failed")
        }
        return try StarterRPCResponseDecoder.decodeSingleStarter(data)
    }

    private func reconcilePersistedAnalysisIDs(starterID: UUID, imagePath: String) async throws -> PersistedStarterAnalysisIDs? {
        let response = try await client
            .from("scans")
            .select("id, ai_analyses(id), recommendations(id)")
            .eq("starter_id", value: starterID.uuidString.lowercased())
            .eq("storage_path", value: imagePath)
            .eq("scan_type", value: "starter")
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
        let rows = try decode([PersistedScanLookupRow].self, from: response.data)
        guard
            let row = rows.first,
            let analysisID = row.analyses.first?.id,
            let recommendationID = row.recommendations.first?.id
        else {
            return nil
        }
        return PersistedStarterAnalysisIDs(
            scanID: row.id,
            analysisID: analysisID,
            recommendationID: recommendationID
        )
    }
}

struct StarterInsert: Codable {
    let name: String
    let hydrationPreference: Double?
    let active: Bool

    enum CodingKeys: String, CodingKey {
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

struct PersistStarterAnalysisPayload: Codable {
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(starterID, forKey: .starterID)
        try container.encode(storagePath, forKey: .storagePath)
        if let qualityScore {
            try container.encode(qualityScore, forKey: .qualityScore)
        } else {
            try container.encodeNil(forKey: .qualityScore)
        }
        if let qualityIssue {
            try container.encode(qualityIssue, forKey: .qualityIssue)
        } else {
            try container.encodeNil(forKey: .qualityIssue)
        }
        try container.encode(model, forKey: .model)
        try container.encode(promptVersion, forKey: .promptVersion)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(analysisJSON, forKey: .analysisJSON)
        try container.encode(renderedExplanation, forKey: .renderedExplanation)
        try container.encode(stateLabel, forKey: .stateLabel)
        try container.encode(recommendation, forKey: .recommendation)
        try container.encode(dueHours, forKey: .dueHours)
    }
}

struct TimelineRow: Decodable {
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
        analyses = try PostgrestRelationDecoder.decodeManyOrOne(StarterAnalysis.self, from: container, forKey: .analyses)
        recommendations = try PostgrestRelationDecoder.decodeManyOrOne(Recommendation.self, from: container, forKey: .recommendations)
        scan = try StarterScan(from: decoder)
    }
}

enum TimelineRowDecoder {
    static func decodeRows(_ data: Data) throws -> [TimelineRow] {
        try SupabaseJSONDecoder.make().decode([TimelineRow].self, from: data)
    }
}

private struct PersistedScanLookupRow: Decodable {
    struct AnalysisRow: Decodable {
        let id: UUID
    }

    struct RecommendationRow: Decodable {
        let id: UUID
    }

    let id: UUID
    let analyses: [AnalysisRow]
    let recommendations: [RecommendationRow]

    enum CodingKeys: String, CodingKey {
        case id
        case analyses = "ai_analyses"
        case recommendations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        analyses = try PostgrestRelationDecoder.decodeManyOrOne(AnalysisRow.self, from: container, forKey: .analyses)
        recommendations = try PostgrestRelationDecoder.decodeManyOrOne(RecommendationRow.self, from: container, forKey: .recommendations)
    }
}

enum StarterAnalyzeResponseParser {
    static func decode(_ data: Data) throws -> StarterAnalyzeResult {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let root = json as? [String: Any] else {
            throw AppError.malformedResponse
        }
        guard let resultType = root["result_type"] as? String else {
            throw AppError.malformedResponse
        }
        switch resultType {
        case "starter_analysis":
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
                outcome: .starterAnalysis(analysis)
            )
        case "invalid_subject":
            guard let reasonRaw = root["reason"] as? String else {
                throw AppError.malformedResponse
            }
            guard let reason = InvalidSubjectReason(rawValue: reasonRaw) else {
                throw AppError.malformedResponse
            }
            guard let message = root["message"] as? String else {
                throw AppError.malformedResponse
            }
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw AppError.malformedResponse
            }
            return StarterAnalyzeResult(
                model: nil,
                promptVersion: nil,
                outcome: .invalidSubject(reason: reason, message: trimmed)
            )
        default:
            throw AppError.malformedResponse
        }
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

struct CreateStarterProfilePayload: Encodable {
    let name: String
    let hydrationPreference: Double?
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case name = "p_name"
        case hydrationPreference = "p_hydration_preference"
        case active = "p_active"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        if let hydrationPreference {
            try container.encode(hydrationPreference, forKey: .hydrationPreference)
        } else {
            try container.encodeNil(forKey: .hydrationPreference)
        }
        try container.encode(active, forKey: .active)
    }
}

struct SetActiveStarterPayload: Encodable {
    let starterID: UUID

    enum CodingKeys: String, CodingKey {
        case starterID = "p_starter_id"
    }
}

enum StarterRPCResponseDecoder {
    static func decodeSingleStarter(_ data: Data) throws -> Starter {
        let decoder = SupabaseJSONDecoder.make()
        if let decoded = try? decoder.decode(Starter.self, from: data) {
            return decoded
        }
        if let list = try? decoder.decode([Starter].self, from: data),
           let first = list.first {
            return first
        }
        throw AppError.malformedResponse
    }
}

enum RepositoryErrorMapper {
    static func map(_ error: Error, operation: String) -> AppError {
        debugLog(error, operation: operation)

        if let persistError = error as? PersistStarterAnalysisSafeError {
            return .unknown(persistError.message)
        }
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

private struct StarterAnalyzeErrorEnvelope: Decodable {
    let errorCode: String
    let message: String
    let requestID: String

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case message
        case requestID = "request_id"
    }
}

enum StarterAnalyzeHTTPErrorMapper {
    static func map(statusCode: Int, data: Data) -> AppError {
        guard let envelope = decodeEnvelope(data: data) else {
            return .analysisFailed
        }
        switch envelope.errorCode {
        case "AUTH_INVALID":
            return .unknown("Your session is invalid. Please sign in again and retry analysis.")
        case "STARTER_NOT_FOUND":
            return .unknown("Starter not found. Refresh your starters and try again.")
        case "IMAGE_DOWNLOAD_FAILED":
            return .unknown("We couldn't read the uploaded image. Please choose another photo and retry.")
        case "IMAGE_INVALID":
            return .unknown("The uploaded image was rejected. Retake the photo and try again.")
        case "PROVIDER_AUTH":
            return .unknown("Analysis provider authentication failed. Please try again shortly.")
        case "PROVIDER_QUOTA":
            return .unknown("Analysis is temporarily unavailable due to provider quota limits. Please try again later.")
        case "PROVIDER_RATE_LIMIT":
            return .unknown("Analysis is temporarily rate-limited. Please wait a moment and retry.")
        case "PROVIDER_TIMEOUT":
            return .unknown("Analysis timed out. Please retry.")
        case "PROVIDER_RESPONSE_INVALID":
            return .unknown("The analysis provider returned an invalid response. Please retry with another photo.")
        case "INTERNAL_ERROR":
            fallthrough
        default:
            if !envelope.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .unknown(envelope.message)
            }
            if statusCode == 401 || statusCode == 403 {
                return .unknown("Your session is invalid. Please sign in again and retry analysis.")
            }
            return .analysisFailed
        }
    }

    #if DEBUG
    static func debugLog(statusCode: Int, data: Data) {
        let envelope = decodeEnvelope(data: data)
        let requestID = envelope?.requestID ?? "unavailable"
        let errorCode = envelope?.errorCode ?? "unavailable"
        print("[StarterAnalysis] request_id=\(requestID) status=\(statusCode) error_code=\(errorCode)")
    }
    #endif

    private static func decodeEnvelope(data: Data) -> StarterAnalyzeErrorEnvelope? {
        try? JSONDecoder().decode(StarterAnalyzeErrorEnvelope.self, from: data)
    }
}

struct PersistStarterAnalysisSafeError: Error {
    let errorCode: String
    let message: String
    let requestID: String
}

private struct PersistStarterAnalysisErrorEnvelope: Decodable {
    let code: String?
    let message: String
    let details: String?
}

enum PersistStarterAnalysisHTTPErrorMapper {
    static func map(statusCode: Int, data: Data, requestID: String) -> PersistStarterAnalysisSafeError {
        let parsed = parseEnvelope(data)
        let rawCode = parsed?.code?.lowercased() ?? ""
        let combined = [
            parsed?.message.lowercased() ?? "",
            parsed?.details?.lowercased() ?? ""
        ].joined(separator: " ")

        if statusCode == 401 || statusCode == 403 {
            return PersistStarterAnalysisSafeError(
                errorCode: "PERSIST_AUTH_FAILED",
                message: "Your session is invalid. Please sign in again and retry saving.",
                requestID: requestID
            )
        }
        if combined.contains("starter not found") {
            return PersistStarterAnalysisSafeError(
                errorCode: "STARTER_NOT_FOUND",
                message: "Starter not found. Refresh your starters and try saving again.",
                requestID: requestID
            )
        }
        if rawCode == "23505" || statusCode == 409 {
            return PersistStarterAnalysisSafeError(
                errorCode: "PERSIST_CONFLICT",
                message: "This analysis is already saved.",
                requestID: requestID
            )
        }
        if rawCode == "pgrst202" {
            return PersistStarterAnalysisSafeError(
                errorCode: "PERSIST_VALIDATION_FAILED",
                message: "The save request format was invalid.",
                requestID: requestID
            )
        }
        if ["23502", "23514", "22p02", "22023", "p0001"].contains(rawCode) ||
            combined.contains("required") ||
            combined.contains("invalid") ||
            combined.contains("between 0 and 1") {
            return PersistStarterAnalysisSafeError(
                errorCode: "PERSIST_VALIDATION_FAILED",
                message: "The analysis could not be saved because some values were invalid. Please retry.",
                requestID: requestID
            )
        }
        if statusCode >= 500 {
            return PersistStarterAnalysisSafeError(
                errorCode: "PERSIST_DATABASE_ERROR",
                message: "The server could not save your analysis. Please try again.",
                requestID: requestID
            )
        }
        return mapResponseInvalid(requestID: requestID)
    }

    static func mapInvalidResponse(requestID: String) -> PersistStarterAnalysisSafeError {
        PersistStarterAnalysisSafeError(
            errorCode: "PERSIST_RESPONSE_INVALID",
            message: "We received an invalid response while saving. Please try again.",
            requestID: requestID
        )
    }

    static func mapResponseInvalid(requestID: String) -> PersistStarterAnalysisSafeError {
        PersistStarterAnalysisSafeError(
            errorCode: "PERSIST_RESPONSE_INVALID",
            message: "We received an unexpected save response. Please try again.",
            requestID: requestID
        )
    }

    #if DEBUG
    static func debugLog(requestID: String, statusCode: Int, errorCode: String) {
        print("[StarterPersist] request_id=\(requestID) status=\(statusCode) error_code=\(errorCode)")
    }
    #endif

    private static func parseEnvelope(_ data: Data) -> PersistStarterAnalysisErrorEnvelope? {
        try? JSONDecoder().decode(PersistStarterAnalysisErrorEnvelope.self, from: data)
    }
}

enum PersistStarterAnalysisResponseDecoder {
    static func decodeIDs(_ data: Data) throws -> PersistedStarterAnalysisIDs {
        let decoder = SupabaseJSONDecoder.make()
        if let decoded = try? decoder.decode(PersistedStarterAnalysisIDs.self, from: data) {
            return decoded
        }
        if let decoded = try? decoder.decode([PersistedStarterAnalysisIDs].self, from: data),
           let first = decoded.first {
            return first
        }
        throw AppError.malformedResponse
    }
}

