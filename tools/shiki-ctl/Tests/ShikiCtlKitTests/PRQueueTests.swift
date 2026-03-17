import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("PR Queue")
struct PRQueueTests {

    @Test("Risk level from size — small is LOW")
    func riskLowSmall() {
        let risk = PRRiskLevel.fromSize(additions: 100, deletions: 20, files: 3)
        #expect(risk == .low)
    }

    @Test("Risk level from size — medium PR")
    func riskMedium() {
        let risk = PRRiskLevel.fromSize(additions: 800, deletions: 100, files: 8)
        #expect(risk == .medium)
    }

    @Test("Risk level from size — high PR")
    func riskHigh() {
        let risk = PRRiskLevel.fromSize(additions: 2500, deletions: 200, files: 15)
        #expect(risk == .high)
    }

    @Test("Risk level from size — critical large PR")
    func riskCritical() {
        let risk = PRRiskLevel.fromSize(additions: 10000, deletions: 500, files: 60)
        #expect(risk == .critical)
    }

    @Test("Queue sorts by risk descending, then size")
    func queueSorting() {
        let queue = PRQueue(workspacePath: "/tmp")
        let entries = [
            PRQueueEntry(number: 1, title: "Small fix", branch: "fix/a", baseBranch: "develop",
                         additions: 10, deletions: 5, fileCount: 1, risk: .low,
                         hasPrecomputedReview: false, hasReviewState: false),
            PRQueueEntry(number: 2, title: "Big feature", branch: "feat/b", baseBranch: "develop",
                         additions: 5000, deletions: 200, fileCount: 30, risk: .critical,
                         hasPrecomputedReview: true, hasReviewState: false),
            PRQueueEntry(number: 3, title: "Medium change", branch: "feat/c", baseBranch: "develop",
                         additions: 1000, deletions: 100, fileCount: 12, risk: .high,
                         hasPrecomputedReview: true, hasReviewState: true),
        ]

        let sorted = queue.sorted(entries)
        #expect(sorted[0].number == 2) // critical first
        #expect(sorted[1].number == 3) // high second
        #expect(sorted[2].number == 1) // low last
    }

    @Test("Precomputed review detection")
    func precomputedReviewDetection() {
        let tmpDir = NSTemporaryDirectory() + "shiki-queue-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: "\(tmpDir)/docs", withIntermediateDirectories: true)

        // Create a fake precomputed review
        FileManager.default.createFile(atPath: "\(tmpDir)/docs/pr42-precomputed-review.md", contents: Data("# Review".utf8))

        let queue = PRQueue(workspacePath: tmpDir)
        #expect(queue.hasPrecomputedReview(prNumber: 42))
        #expect(!queue.hasPrecomputedReview(prNumber: 99))

        try? FileManager.default.removeItem(atPath: tmpDir)
    }
}
