import Foundation

public struct LifecycleCheckpoint: Codable, Sendable {
    public let featureId: String
    public let state: LifecycleState
    public let timestamp: Date
    public let metadata: [String: String]
    public let transitionHistory: [LifecycleTransition]

    public init(
        featureId: String,
        state: LifecycleState,
        timestamp: Date,
        metadata: [String: String],
        transitionHistory: [LifecycleTransition]
    ) {
        self.featureId = featureId
        self.state = state
        self.timestamp = timestamp
        self.metadata = metadata
        self.transitionHistory = transitionHistory
    }

    public func save(to path: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: path))
    }

    public static func load(from path: String) throws -> LifecycleCheckpoint? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LifecycleCheckpoint.self, from: data)
    }
}
