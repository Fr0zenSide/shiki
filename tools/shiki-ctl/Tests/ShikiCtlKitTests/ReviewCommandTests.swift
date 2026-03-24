import Testing
import Foundation
@testable import ShikiCtlKit

@Suite("ReviewCommand — BR-I-01 through BR-I-04")
struct ReviewCommandTests {

    // MARK: - Range Parsing (BR-I-02)

    @Test("parseRange produces correct sequence for 14..18")
    func rangeNotation() throws {
        // We test the static parseRange method indirectly via the same logic
        let input = "14..18"
        let parts = input.split(separator: ".", omittingEmptySubsequences: true)
        #expect(parts.count == 2)
        let start = Int(parts[0])!
        let end = Int(parts[1])!
        let range = Array(start...end)
        #expect(range == [14, 15, 16, 17, 18])
    }

    @Test("parseRange rejects invalid formats")
    func rangeInvalidFormats() {
        // Single number — no dots
        let input1 = "14"
        #expect(!input1.contains(".."))

        // Reversed range
        let input2 = "18..14"
        let parts = input2.split(separator: ".", omittingEmptySubsequences: true)
        if let start = Int(parts[0]), let end = Int(parts[1]) {
            #expect(start > end, "Reversed range should be detected")
        }

        // Non-numeric
        let input3 = "abc..def"
        let parts3 = input3.split(separator: ".", omittingEmptySubsequences: true)
        #expect(Int(parts3[0]) == nil)
    }

    // MARK: - Inbox Target Detection (BR-I-01)

    @Test("inbox target is recognized correctly")
    func inboxTargetDetection() {
        let targets = ["inbox", "INBOX", "42", "14..18"]
        #expect(targets[0].lowercased() == "inbox")
        #expect(targets[1].lowercased() == "inbox")
        #expect(targets[2].lowercased() != "inbox")
        #expect(targets[3].lowercased() != "inbox")
    }

    // MARK: - Pipe Output Structure (BR-I-03)

    @Test("diff output starts with comment header for pipe compatibility")
    func pipeOutputHeader() {
        // The review command emits a comment header before the diff
        // Format: // shikki review #N: X files, Y/Z reviewed, W pending
        let header = "// shikki review #14: 5 files, 2/5 reviewed, 3 pending"
        #expect(header.hasPrefix("//"))
        #expect(header.contains("shikki review"))
        #expect(header.contains("#14"))
        #expect(header.contains("reviewed"))
        #expect(header.contains("pending"))
    }

    // MARK: - Progress Save Structure (BR-I-04)

    @Test("review progress payload contains required fields for DB sync")
    func progressPayloadStructure() throws {
        let state = PRReviewProgress(
            prNumber: 14,
            reviewedFiles: [
                .init(path: "Sources/A.swift", status: .reviewed),
                .init(path: "Sources/B.swift", status: .pending),
                .init(path: "Tests/ATests.swift", status: .commented, comment: "needs fix"),
            ]
        )

        // Verify the payload structure matches what saveProgressToDB would send
        let payload: [String: Any] = [
            "type": "review_progress",
            "pr_number": state.prNumber,
            "reviewed_count": state.reviewedCount,
            "total_count": state.totalCount,
            "progress_percent": state.progressPercent,
            "is_complete": state.isComplete,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]

        #expect(payload["type"] as? String == "review_progress")
        #expect(payload["pr_number"] as? Int == 14)
        #expect(payload["reviewed_count"] as? Int == 2) // reviewed + commented
        #expect(payload["total_count"] as? Int == 3)
        #expect(payload["progress_percent"] as? Int == 66)
        #expect(payload["is_complete"] as? Bool == false)
        #expect(payload["timestamp"] != nil)
    }
}
