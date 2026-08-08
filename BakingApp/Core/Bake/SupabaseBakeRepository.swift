import Foundation
import Supabase

final class SupabaseBakeRepository: BakeRepository {
    private let client: SupabaseClient

    init(supabaseURL: URL, anonKey: String) {
        self.client = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: anonKey)
    }

    func listBakes() async throws -> [Bake] {
        do {
            let response = try await client
                .from("bakes")
                .select()
                .order("baked_at", ascending: false)
                .execute()
            return try decode([Bake].self, from: response.data)
        } catch {
            throw RepositoryErrorMapper.map(error, operation: "load bake journal")
        }
    }

    func fetchBake(bakeID: UUID) async throws -> Bake {
        do {
            let response = try await client
                .from("bakes")
                .select()
                .eq("id", value: bakeID.uuidString.lowercased())
                .single()
                .execute()
            return try decode(Bake.self, from: response.data)
        } catch {
            throw RepositoryErrorMapper.map(error, operation: "load bake details")
        }
    }

    func createBake(_ input: BakeCreateInput) async throws -> Bake {
        let validated = try BakeValidation.validate(input)
        do {
            let userID = try await currentUserID()
            let insert = BakeInsert(
                userID: userID,
                starterID: validated.starterID,
                bakedAt: validated.bakedAt,
                name: validated.name,
                doughHydrationPercent: validated.doughHydrationPercent,
                bulkFermentationMinutes: validated.bulkFermentationMinutes,
                finalProofMinutes: validated.finalProofMinutes,
                mixingMethod: validated.mixingMethod,
                shapingMethod: validated.shapingMethod,
                ovenTemperatureCelsius: validated.ovenTemperatureCelsius,
                bakingTimeMinutes: validated.bakingTimeMinutes,
                resultRating: validated.resultRating,
                fermentationTemperatureCelsius: validated.fermentationTemperatureCelsius,
                fermentationTemperatureSource: validated.fermentationTemperatureSource?.rawValue,
                retardationMinutes: validated.retardationMinutes,
                numberOfFolds: validated.numberOfFolds,
                steamingMethod: validated.steamingMethod,
                flourNotes: validated.flourNotes,
                notes: validated.notes
            )
            let response = try await client
                .from("bakes")
                .insert(insert)
                .select()
                .single()
                .execute()
            return try decode(Bake.self, from: response.data)
        } catch let validation as BakeValidationError {
            throw AppError.unknown(validation.errorDescription ?? "Invalid bake")
        } catch {
            throw RepositoryErrorMapper.map(error, operation: "save bake")
        }
    }

    private func currentUserID() async throws -> UUID {
        do {
            let authSession = try await client.auth.session
            return authSession.user.id
        } catch {
            throw RepositoryErrorMapper.map(error, operation: "load authenticated user")
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try SupabaseJSONDecoder.make().decode(type, from: data)
    }
}
