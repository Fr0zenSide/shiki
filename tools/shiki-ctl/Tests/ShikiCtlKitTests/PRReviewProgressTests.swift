import Testing
import Foundation
@testable import ShikiCtlKit

@Suite("PR Review Progression")
struct PRReviewProgressionTests {

    // MARK: - Helpers

    private func makeSampleState() -> PRReviewProgress {
        PRReviewProgress(
            prNumber: 23,
            reviewedFiles: [
                .init(path: "Sources/Services/StoreKitService.swift"),
                .init(path: "Sources/Services/PricingEngine.swift"),
                .init(path: "Sources/Services/SubscriptionManager.swift"),
                .init(path: "Sources/Models/Product.swift"),
                .init(path: "Tests/StoreKitServiceTests.swift"),
            ],
            lastReviewedCommit: "abc1234"
        )
    }

    // MARK: - Model (5 tests)

    @Test("state file round-trips through JSON correctly")
    func jsonRoundTrip() throws {
        var state = makeSampleState()
        state.markFileReviewed("Sources/Services/StoreKitService.swift", at: Date(timeIntervalSince1970: 1_000_000), commit: "abc1234")
        state.addComment(to: "Sources/Services/PricingEngine.swift", message: "silent error on L42", at: Date(timeIntervalSince1970: 1_000_001), commit: "abc1234")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PRReviewProgress.self, from: data)

        #expect(decoded.prNumber == 23)
        #expect(decoded.reviewedFiles.count == 5)
        #expect(decoded.reviewedFiles[0].status == .reviewed)
        #expect(decoded.reviewedFiles[0].reviewedAt != nil)
        #expect(decoded.reviewedFiles[1].status == .commented)
        #expect(decoded.reviewedFiles[1].comment == "silent error on L42")
        #expect(decoded.lastReviewedCommit == "abc1234")
    }

    @Test("mark file as reviewed persists with timestamp and commit")
    func markFileReviewed() {
        var state = makeSampleState()
        let now = Date()
        state.markFileReviewed("Sources/Services/StoreKitService.swift", at: now, commit: "def5678")

        let file = state.reviewedFiles.first { $0.path == "Sources/Services/StoreKitService.swift" }!
        #expect(file.status == .reviewed)
        #expect(file.reviewedAt == now)
        #expect(file.reviewedAtCommit == "def5678")
        #expect(state.lastReviewedAt == now)
        #expect(state.lastReviewedCommit == "def5678")
    }

    @Test("read --all marks all files with timestamp and commit")
    func markAllReviewed() {
        var state = makeSampleState()
        let now = Date()
        state.markAllReviewed(at: now, commit: "all5678")

        for file in state.reviewedFiles {
            #expect(file.status == .reviewed)
            #expect(file.reviewedAt == now)
            #expect(file.reviewedAtCommit == "all5678")
        }
        #expect(state.lastReviewedCommit == "all5678")
    }

    @Test("read --reset clears all review state")
    func resetReview() {
        var state = makeSampleState()
        state.markAllReviewed(at: Date(), commit: "abc1234")
        state.addComment(to: "Sources/Services/PricingEngine.swift", message: "test", commit: "abc1234")

        state.resetAll()

        for file in state.reviewedFiles {
            #expect(file.status == .pending)
            #expect(file.reviewedAt == nil)
            #expect(file.comment == nil)
            #expect(file.reviewedAtCommit == nil)
        }
        #expect(state.lastReviewedAt == nil)
        #expect(state.lastReviewedCommit == "")
    }

    @Test("comment attaches to file and sets commented status")
    func commentSetsStatus() {
        var state = makeSampleState()
        let now = Date()
        state.addComment(to: "Sources/Services/PricingEngine.swift", message: "silent error on L42", at: now, commit: "cmt1234")

        let file = state.reviewedFiles.first { $0.path == "Sources/Services/PricingEngine.swift" }!
        #expect(file.status == .commented)
        #expect(file.comment == "silent error on L42")
        #expect(file.reviewedAt == now)
        #expect(file.reviewedAtCommit == "cmt1234")
    }

    // MARK: - Delta (4 tests)

    @Test("delta shows only unreviewed files when no commits changed")
    func deltaUnreviewed() {
        var state = makeSampleState()
        state.markFileReviewed("Sources/Services/StoreKitService.swift", commit: "abc1234")
        state.markFileReviewed("Sources/Models/Product.swift", commit: "abc1234")

        let delta = state.deltaFiles
        #expect(delta.count == 3)
        #expect(delta.allSatisfy { $0.status == .pending })
    }

    @Test("delta detects files changed since last review via commit comparison")
    func deltaDetectsChanges() {
        var state = makeSampleState()
        state.markFileReviewed("Sources/Services/StoreKitService.swift", commit: "abc1234")
        state.markFileReviewed("Sources/Services/PricingEngine.swift", commit: "abc1234")

        // Simulate new commits changing one reviewed file
        state.applyDelta(changedPaths: ["Sources/Services/StoreKitService.swift"])

        let changed = state.reviewedFiles.first { $0.path == "Sources/Services/StoreKitService.swift" }!
        #expect(changed.status == .changed)

        // PricingEngine was not in the diff, stays reviewed
        let unchanged = state.reviewedFiles.first { $0.path == "Sources/Services/PricingEngine.swift" }!
        #expect(unchanged.status == .reviewed)

        // Delta should include changed + pending
        let delta = state.deltaFiles
        #expect(delta.count == 4) // 1 changed + 3 pending
    }

    @Test("new commits reset only changed files — pending stays pending")
    func newCommitsResetOnlyReviewed() {
        var state = makeSampleState()
        // Leave SubscriptionManager as pending
        state.markFileReviewed("Sources/Services/StoreKitService.swift", commit: "abc1234")

        // Simulate both changed — but only reviewed ones should flip
        state.applyDelta(changedPaths: [
            "Sources/Services/StoreKitService.swift",
            "Sources/Services/SubscriptionManager.swift",
        ])

        let storeKit = state.reviewedFiles.first { $0.path == "Sources/Services/StoreKitService.swift" }!
        #expect(storeKit.status == .changed)

        let subMgr = state.reviewedFiles.first { $0.path == "Sources/Services/SubscriptionManager.swift" }!
        #expect(subMgr.status == .pending) // stays pending, not changed
    }

    @Test("files removed from PR diff are pruned from state on load")
    func prunedRemovedFiles() {
        var state = makeSampleState()
        #expect(state.reviewedFiles.count == 5)

        // Force-push removed 2 files
        state.prune(currentPaths: [
            "Sources/Services/StoreKitService.swift",
            "Sources/Services/PricingEngine.swift",
            "Sources/Models/Product.swift",
        ])

        #expect(state.reviewedFiles.count == 3)
        #expect(!state.reviewedFiles.contains { $0.path == "Sources/Services/SubscriptionManager.swift" })
        #expect(!state.reviewedFiles.contains { $0.path == "Tests/StoreKitServiceTests.swift" })
    }

    // MARK: - Display (3 tests)

    @Test("progress bar shows correct percentage and fraction")
    func progressBarPercentage() {
        var state = makeSampleState()
        state.markFileReviewed("Sources/Services/StoreKitService.swift", commit: "abc")
        state.markFileReviewed("Sources/Models/Product.swift", commit: "abc")

        #expect(state.reviewedCount == 2)
        #expect(state.totalCount == 5)
        #expect(state.progressPercent == 40)
        #expect(state.progressFraction == "2/5 reviewed (40%)")

        // Bar: 40% of 20 = 8 filled
        let bar = state.progressBar
        #expect(bar.count == 20)
        #expect(bar.hasPrefix("████████"))
    }

    @Test("status indicators render correctly for each ReviewStatus case")
    func statusIndicators() {
        #expect(PRReviewProgress.ReviewStatus.pending.indicator == "[ ]")
        #expect(PRReviewProgress.ReviewStatus.reviewed.indicator == "[✓]")
        #expect(PRReviewProgress.ReviewStatus.commented.indicator == "[✎]")
        #expect(PRReviewProgress.ReviewStatus.changed.indicator == "[!]")
    }

    @Test("progress shows 100% checkmark when all reviewed and no changes")
    func progressComplete() {
        var state = makeSampleState()
        state.markAllReviewed(at: Date(), commit: "done123")

        #expect(state.isComplete)
        #expect(state.progressPercent == 100)
        #expect(state.progressFraction == "5/5 reviewed (100%)")
    }

    // MARK: - File Matching (2 tests)

    @Test("partial file match resolves basename correctly")
    func partialFileMatch() throws {
        let state = makeSampleState()

        // Basename partial match
        let resolved = try state.resolveFile("Product")
        #expect(resolved == "Sources/Models/Product.swift")

        // Suffix match
        let resolved2 = try state.resolveFile("Services/PricingEngine.swift")
        #expect(resolved2 == "Sources/Services/PricingEngine.swift")
    }

    @Test("ambiguous partial match returns error with candidates")
    func ambiguousMatch() {
        let state = makeSampleState()

        // "Service" matches StoreKitService, PricingEngine (no), SubscriptionManager (no)
        // Actually "StoreKit" only matches one. Let's use "Service" which matches 3 files
        do {
            _ = try state.resolveFile("Service")
            #expect(Bool(false), "Should have thrown")
        } catch let error as PRReviewError {
            if case .ambiguousMatch(let query, let candidates) = error {
                #expect(query == "Service")
                #expect(candidates.count >= 2)
            } else {
                #expect(Bool(false), "Wrong error type: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    // MARK: - Comments Filter (2 tests)

    @Test("--comments shows only files with open comments")
    func commentsFilterOpen() {
        var state = makeSampleState()
        state.addComment(to: "Sources/Services/PricingEngine.swift", message: "bug here", commit: "abc")
        state.addComment(to: "Sources/Models/Product.swift", message: "naming?", commit: "abc")

        // Now mark Product as reviewed (resolving the comment)
        state.markFileReviewed("Sources/Models/Product.swift", commit: "abc")

        let open = state.commentedFiles(includeResolved: false)
        #expect(open.count == 1)
        #expect(open[0].path == "Sources/Services/PricingEngine.swift")
    }

    @Test("--comments --all shows all comments including resolved")
    func commentsFilterAll() {
        var state = makeSampleState()
        state.addComment(to: "Sources/Services/PricingEngine.swift", message: "bug here", commit: "abc")
        state.addComment(to: "Sources/Models/Product.swift", message: "naming?", commit: "abc")

        // Resolve one by marking reviewed
        state.markFileReviewed("Sources/Models/Product.swift", commit: "abc")

        let all = state.commentedFiles(includeResolved: true)
        #expect(all.count == 2)
    }

    // MARK: - State Manager (2 tests — file persistence)

    @Test("state manager saves and loads review state")
    func stateManagerRoundTrip() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("shiki-test-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let manager = PRReviewStateManager(cacheDir: tmpDir)
        var state = makeSampleState()
        state.markFileReviewed("Sources/Services/StoreKitService.swift", commit: "abc")

        try manager.save(state)
        let loaded = try manager.load()

        #expect(loaded != nil)
        #expect(loaded!.prNumber == 23)
        #expect(loaded!.reviewedFiles[0].status == .reviewed)
    }

    @Test("state manager creates state from file paths when no existing state")
    func stateManagerCreate() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("shiki-test-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let manager = PRReviewStateManager(cacheDir: tmpDir)
        let state = try manager.loadOrCreate(prNumber: 42, filePaths: ["a.swift", "b.swift"])

        #expect(state.prNumber == 42)
        #expect(state.reviewedFiles.count == 2)
        #expect(state.reviewedFiles.allSatisfy { $0.status == .pending })
    }

    // MARK: - JSON Output Format (PR #29 — shikki pr --json contract)

    @Test("JSON output matches shikki pr --json contract: pr, files, reviewState keys")
    func jsonOutputFormatContract() throws {
        // Simulate the JSON structure built by PRCommand.run() in --json mode:
        //   { "pr": N, "files": [...], "reviewState": { ... } }
        var state = makeSampleState()
        state.markFileReviewed("Sources/Services/StoreKitService.swift", at: Date(timeIntervalSince1970: 1_700_000_000), commit: "abc1234")
        state.addComment(to: "Sources/Services/PricingEngine.swift", message: "needs guard", at: Date(timeIntervalSince1970: 1_700_000_001), commit: "abc1234")

        // Encode reviewState the same way PRCommand does
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let stateData = try encoder.encode(state)
        let stateDict = try JSONSerialization.jsonObject(with: stateData)

        // Build the top-level JSON the same way PRCommand.run() does
        let files: [[String: Any]] = [
            ["path": "Sources/Services/StoreKitService.swift", "insertions": 10, "deletions": 2],
            ["path": "Sources/Services/PricingEngine.swift", "insertions": 5, "deletions": 0],
        ]
        let result: [String: Any] = [
            "pr": 23,
            "files": files,
            "reviewState": stateDict,
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        let parsed = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        // Verify top-level keys
        #expect(parsed["pr"] as? Int == 23)
        #expect((parsed["files"] as? [[String: Any]])?.count == 2)
        #expect(parsed["reviewState"] != nil)

        // Verify reviewState sub-structure
        let rs = parsed["reviewState"] as! [String: Any]
        #expect(rs["prNumber"] as? Int == 23)
        #expect((rs["reviewedFiles"] as? [[String: Any]])?.count == 5)
        #expect(rs["lastReviewedCommit"] as? String == "abc1234")

        // Verify the JSON is valid for piping (no trailing garbage)
        let outputString = String(data: jsonData, encoding: .utf8)!
        #expect(outputString.hasSuffix("\n}"))
    }
}
