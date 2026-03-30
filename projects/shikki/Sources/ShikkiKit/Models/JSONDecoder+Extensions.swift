import Foundation

extension JSONDecoder {
    /// Pre-configured decoder for the Shiki backend's snake_case JSON.
    static let snakeCase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
