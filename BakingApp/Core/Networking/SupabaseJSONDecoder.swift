import Foundation

enum SupabaseJSONDecoder {
    static func make() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(decodeDate)
        return decoder
    }

    static func decodeDate(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let date = fractionalInternetDateFormatter.date(from: raw) {
            return date
        }
        if let date = internetDateFormatter.date(from: raw) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unrecognized date format"
        )
    }

    private static let fractionalInternetDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let internetDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

enum PostgrestRelationDecoder {
    static func decodeManyOrOne<T: Decodable, K: CodingKey>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) throws -> [T] {
        guard container.contains(key) else {
            return []
        }
        if try container.decodeNil(forKey: key) {
            return []
        }
        if let values = try? container.decode([T].self, forKey: key) {
            return values
        }
        if let value = try? container.decode(T.self, forKey: key) {
            return [value]
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Expected nested relationship object or array"
        )
    }
}
