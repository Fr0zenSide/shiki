import Foundation

// MARK: - PRReviewEvents

/// Factory for PR review events — all review actions emit ShikiEvents.
public enum PRReviewEvents {

    /// Cache built for a PR.
    public static func cacheBuilt(prNumber: Int, fileCount: Int) -> ShikiEvent {
        ShikiEvent(
            source: .process(name: "shiki-pr"),
            type: .prCacheBuilt,
            scope: .pr(number: prNumber),
            payload: ["fileCount": .int(fileCount)]
        )
    }

    /// Risk assessment completed.
    public static func riskAssessed(prNumber: Int, highRiskCount: Int, totalFiles: Int) -> ShikiEvent {
        ShikiEvent(
            source: .process(name: "shiki-pr"),
            type: .prRiskAssessed,
            scope: .pr(number: prNumber),
            payload: [
                "highRiskCount": .int(highRiskCount),
                "totalFiles": .int(totalFiles),
            ]
        )
    }

    /// Human set a verdict on a section.
    public static func verdict(prNumber: Int, sectionIndex: Int, verdict: SectionVerdict) -> ShikiEvent {
        ShikiEvent(
            source: .human(id: nil),
            type: .prVerdictSet,
            scope: .pr(number: prNumber),
            payload: [
                "sectionIndex": .int(sectionIndex),
                "verdict": .string(verdict.rawValue),
            ]
        )
    }

    /// Fix agent spawned for a specific file/issue.
    public static func fixSpawned(prNumber: Int, filePath: String, issue: String) -> ShikiEvent {
        ShikiEvent(
            source: .process(name: "shiki-pr"),
            type: .prFixSpawned,
            scope: .pr(number: prNumber),
            payload: [
                "filePath": .string(filePath),
                "issue": .string(issue),
            ]
        )
    }

    /// Fix agent completed.
    public static func fixCompleted(prNumber: Int, filePath: String, success: Bool) -> ShikiEvent {
        ShikiEvent(
            source: .process(name: "shiki-pr"),
            type: .prFixCompleted,
            scope: .pr(number: prNumber),
            payload: [
                "filePath": .string(filePath),
                "success": .bool(success),
            ]
        )
    }
}
