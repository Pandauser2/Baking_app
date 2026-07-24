import Foundation

protocol LoafAnalysisRepository {
    func uploadImage(_ data: Data, userID: UUID) async throws -> String
    func analyzeLoaf(imagePath: String, promptVersion: String) async throws -> LoafScan
    func fetchHistory() async throws -> [LoafScan]
    func signedImageURL(path: String, expiresIn: TimeInterval) async throws -> URL
}

