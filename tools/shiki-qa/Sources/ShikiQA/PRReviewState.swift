import Foundation

// MARK: - Verdict

public enum SectionVerdict: String, Codable, Sendable {
    case approved
    case comment
    case requestChanges
}

// MARK: - Persistent State

public struct PRReviewState: Codable, Sendable {
    public var verdicts: [Int: SectionVerdict]
    public var comments: [Int: String]
    public var currentSectionIndex: Int
    public var startedAt: Date
    public var lastUpdatedAt: Date

    public init(sectionCount: Int) {
        self.verdicts = [:]
        self.comments = [:]
        self.currentSectionIndex = 0
        self.startedAt = Date()
        self.lastUpdatedAt = Date()
    }

    // MARK: - Persistence

    public static func load(from path: String) -> PRReviewState? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(PRReviewState.self, from: data)
    }

    public func save(to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - Queries

    public var reviewedCount: Int { verdicts.count }

    public func verdictCounts() -> (approved: Int, comment: Int, requestChanges: Int) {
        var a = 0, c = 0, r = 0
        for v in verdicts.values {
            switch v {
            case .approved: a += 1
            case .comment: c += 1
            case .requestChanges: r += 1
            }
        }
        return (a, c, r)
    }
}
