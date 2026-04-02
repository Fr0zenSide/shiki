import Foundation

// MARK: - JSONDecoder

extension JSONDecoder {
    /// Pre-configured decoder for the Shiki backend's snake_case JSON.
    static let snakeCase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// Shared ISO 8601 decoder used across ShikkiKit.
    ///
    /// Replaces the repeated `let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601`
    /// pattern that appeared in 30+ call sites.
    public static let shikki: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

// MARK: - JSONEncoder

extension JSONEncoder {
    /// Shared ISO 8601 encoder used across ShikkiKit.
    ///
    /// Replaces the repeated `let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601`
    /// pattern that appeared in 30+ call sites. Uses `sortedKeys` for deterministic output.
    public static let shikki: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
