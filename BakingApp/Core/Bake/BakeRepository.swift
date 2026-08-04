import Foundation

protocol BakeRepository {
    func listBakes() async throws -> [Bake]
    func fetchBake(bakeID: UUID) async throws -> Bake
    func createBake(_ input: BakeCreateInput) async throws -> Bake
}
