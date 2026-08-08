import Foundation
import Supabase

final class SupabaseLoafAnalysisRepository: LoafAnalysisRepository {
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

    func uploadImage(_ data: Data, userID: UUID) async throws -> String {
        let path = Self.makeStoragePath(userID: userID, date: Date(), imageID: UUID())
        do {
            try await client.storage
                .from("loaf-images")
                .upload(
                    path,
                    data: data,
                    options: FileOptions(
                        cacheControl: "3600",
                        contentType: "image/jpeg",
                        upsert: false
                    )
                )
            return path
        } catch {
            throw AppError.uploadFailed
        }
    }

    func analyzeLoaf(imagePath: String, promptVersion: String = "v1") async throws -> LoafAnalyzeResult {
        let authSession = try await client.auth.session
        let payload = AnalyzeLoafPayload(imagePath: imagePath, promptVersion: promptVersion)

        let endpoint = supabaseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent("analyze-loaf")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(authSession.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.analysisFailed
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw AppError.analysisFailed
        }
        do {
            return try LoafAnalyzeResponseParser.decode(data)
        } catch {
            throw AppError.malformedResponse
        }
    }

    func persistLoafAnalysis(
        bakeID: UUID,
        imagePath: String,
        result: LoafAnalyzeResult,
        qualityScore: Double? = nil,
        qualityIssue: String? = nil
    ) async throws -> PersistedLoafAnalysisIDs {
        if let existing = try await reconcilePersistedIDs(imagePath: imagePath) {
            return existing
        }

        let authSession = try await client.auth.session
        let endpoint = supabaseURL
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent("rpc")
            .appendingPathComponent("persist_loaf_analysis")

        let body = PersistLoafAnalysisPayload(
            bakeID: bakeID,
            storagePath: imagePath,
            model: result.model,
            promptVersion: result.promptVersion,
            confidence: result.analysis.confidence,
            analysisJSON: result.analysis,
            renderedExplanation: result.analysis.summary,
            qualityScore: qualityScore,
            qualityIssue: qualityIssue
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
            throw AppError.unknown("Could not save loaf analysis.")
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            if let reconciled = try await reconcilePersistedIDs(imagePath: imagePath) {
                return reconciled
            }
            throw AppError.unknown("Could not save loaf analysis.")
        }
        do {
            return try PersistLoafAnalysisResponseDecoder.decodeIDs(data)
        } catch {
            if let reconciled = try await reconcilePersistedIDs(imagePath: imagePath) {
                return reconciled
            }
            throw AppError.malformedResponse
        }
    }

    func fetchHistory() async throws -> [LoafScan] {
        // Legacy Phase B table — keep readable; Phase C does not write here.
        do {
            let response = try await client
                .from("loaf_scans")
                .select()
                .order("created_at", ascending: false)
                .execute()
            return try SupabaseJSONDecoder.make().decode([LoafScan].self, from: response.data)
        } catch {
            throw AppError.unknown("Could not load analysis history.")
        }
    }

    func fetchLoafAnalyses(forBakeID bakeID: UUID) async throws -> [CanonicalLoafAnalysis] {
        do {
            let response = try await client
                .from("scans")
                .select("id, bake_id, storage_path, created_at, ai_analyses(id, model, prompt_version, confidence, analysis_json, rendered_explanation, created_at)")
                .eq("bake_id", value: bakeID.uuidString.lowercased())
                .eq("scan_type", value: "loaf")
                .order("created_at", ascending: false)
                .execute()
            let rows = try SupabaseJSONDecoder.make().decode([CanonicalLoafScanRow].self, from: response.data)
            return rows.compactMap { $0.asCanonical() }
        } catch {
            throw AppError.unknown("Could not load loaf analyses for bake.")
        }
    }

    func signedImageURL(path: String, expiresIn: TimeInterval = 1800) async throws -> URL {
        let signedURL = try await client.storage
            .from("loaf-images")
            .createSignedURL(path: path, expiresIn: Int(expiresIn))
        return signedURL
    }

    static func makeStoragePath(userID: UUID, date: Date, imageID: UUID) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let year = String(calendar.component(.year, from: date))
        let month = String(format: "%02d", calendar.component(.month, from: date))
        return "\(userID.uuidString.lowercased())/\(year)/\(month)/\(imageID.uuidString.lowercased()).jpg"
    }

    private func reconcilePersistedIDs(imagePath: String) async throws -> PersistedLoafAnalysisIDs? {
        let response = try await client
            .from("scans")
            .select("id, ai_analyses(id)")
            .eq("storage_path", value: imagePath)
            .eq("scan_type", value: "loaf")
            .order("created_at", ascending: true)
            .limit(1)
            .execute()
        let rows = try SupabaseJSONDecoder.make().decode([PersistedLoafLookupRow].self, from: response.data)
        guard let row = rows.first, let analysisID = row.analyses.first?.id else {
            return nil
        }
        return PersistedLoafAnalysisIDs(scanID: row.id, analysisID: analysisID)
    }
}

private struct PersistedLoafLookupRow: Decodable {
    let id: UUID
    let analyses: [IDOnly]

    enum CodingKeys: String, CodingKey {
        case id
        case analyses = "ai_analyses"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        analyses = try PostgrestRelationDecoder.decodeManyOrOne(
            IDOnly.self,
            from: container,
            forKey: .analyses
        )
    }

    struct IDOnly: Decodable {
        let id: UUID
    }
}

private struct CanonicalLoafScanRow: Decodable {
    let id: UUID
    let bakeID: UUID?
    let storagePath: String
    let createdAt: Date
    let analyses: [AnalysisRow]

    enum CodingKeys: String, CodingKey {
        case id
        case bakeID = "bake_id"
        case storagePath = "storage_path"
        case createdAt = "created_at"
        case analyses = "ai_analyses"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        bakeID = try container.decodeIfPresent(UUID.self, forKey: .bakeID)
        storagePath = try container.decode(String.self, forKey: .storagePath)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        analyses = try PostgrestRelationDecoder.decodeManyOrOne(
            AnalysisRow.self,
            from: container,
            forKey: .analyses
        )
    }

    func asCanonical() -> CanonicalLoafAnalysis? {
        guard let analysis = analyses.first else { return nil }
        return CanonicalLoafAnalysis(
            scanID: id,
            analysisID: analysis.id,
            bakeID: bakeID,
            storagePath: storagePath,
            model: analysis.model,
            promptVersion: analysis.promptVersion,
            confidence: analysis.confidence,
            analysis: analysis.analysisJSON,
            renderedExplanation: analysis.renderedExplanation,
            createdAt: analysis.createdAt
        )
    }

    struct AnalysisRow: Decodable {
        let id: UUID
        let model: String
        let promptVersion: String
        let confidence: Double
        let analysisJSON: LoafAIAnalysis
        let renderedExplanation: String
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case model
            case promptVersion = "prompt_version"
            case confidence
            case analysisJSON = "analysis_json"
            case renderedExplanation = "rendered_explanation"
            case createdAt = "created_at"
        }
    }
}
