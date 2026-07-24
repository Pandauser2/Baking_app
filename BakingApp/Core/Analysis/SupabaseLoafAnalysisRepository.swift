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
                    path: path,
                    file: data,
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

    func analyzeLoaf(imagePath: String, promptVersion: String = "v1") async throws -> LoafScan {
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
            return try LoafScanParser.decodeScanResponse(data)
        } catch {
            throw AppError.malformedResponse
        }
    }

    func fetchHistory() async throws -> [LoafScan] {
        do {
            let response = try await client
                .from("loaf_scans")
                .select()
                .order("created_at", ascending: false)
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([LoafScan].self, from: response.data)
        } catch {
            throw AppError.unknown("Could not load analysis history.")
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
}

