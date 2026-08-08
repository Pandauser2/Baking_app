import Foundation

protocol LoafAnalysisRepository {
    func uploadImage(_ data: Data, userID: UUID) async throws -> String
    /// Stateless edge analysis only — does not persist.
    func analyzeLoaf(imagePath: String, promptVersion: String) async throws -> LoafAnalyzeResult
    /// Authenticated persistence into `scans` + `ai_analyses` for a bake.
    func persistLoafAnalysis(
        bakeID: UUID,
        imagePath: String,
        result: LoafAnalyzeResult,
        qualityScore: Double?,
        qualityIssue: String?
    ) async throws -> PersistedLoafAnalysisIDs
    /// Legacy Phase B history from `loaf_scans` (read-only).
    func fetchHistory() async throws -> [LoafScan]
    /// Canonical Phase C loaf analyses for a bake (`scans` + `ai_analyses`).
    func fetchLoafAnalyses(forBakeID bakeID: UUID) async throws -> [CanonicalLoafAnalysis]
    func signedImageURL(path: String, expiresIn: TimeInterval) async throws -> URL
}
