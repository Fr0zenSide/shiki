import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("PRCacheBuilder")
struct PRCacheBuilderTests {

    static let sampleDiff = """
    diff --git a/Sources/Services/ProcessCleanup.swift b/Sources/Services/ProcessCleanup.swift
    index abc1234..def5678 100644
    --- a/Sources/Services/ProcessCleanup.swift
    +++ b/Sources/Services/ProcessCleanup.swift
    @@ -10,6 +10,15 @@ public struct ProcessCleanup {
         func cleanupSession(session: String) -> CleanupStats {
             let pids = collectSessionPIDs(session: session)
    +        // Kill task windows individually
    +        for pid in pids {
    +            killProcessTree(pid: pid)
    +        }
    +        return CleanupStats(killed: pids.count)
    +    }
    +
    +    func killProcessTree(pid: pid_t) {
    +        kill(pid, SIGTERM)
         }
     }
    diff --git a/Tests/ProcessCleanupTests.swift b/Tests/ProcessCleanupTests.swift
    new file mode 100644
    index 0000000..abc1234
    --- /dev/null
    +++ b/Tests/ProcessCleanupTests.swift
    @@ -0,0 +1,20 @@
    +import Testing
    +@testable import ShikiCtlKit
    +
    +@Suite("ProcessCleanup")
    +struct ProcessCleanupTests {
    +    @Test("cleanup kills PIDs")
    +    func cleanupKillsPIDs() {
    +        // test body
    +    }
    +}
    diff --git a/README.md b/README.md
    index 111..222 100644
    --- a/README.md
    +++ b/README.md
    @@ -1,3 +1,3 @@
    -# Old Title
    +# New Title

     Some content.
    """

    @Test("Parses file entries from git diff")
    func parsesFileEntries() {
        let files = PRCacheBuilder.parseFilesFromDiff(Self.sampleDiff)
        #expect(files.count == 3)
        #expect(files[0].path == "Sources/Services/ProcessCleanup.swift")
        #expect(files[1].path == "Tests/ProcessCleanupTests.swift")
        #expect(files[2].path == "README.md")
    }

    @Test("Counts insertions and deletions per file")
    func countsChanges() {
        let files = PRCacheBuilder.parseFilesFromDiff(Self.sampleDiff)
        let cleanup = files.first { $0.path.contains("ProcessCleanup.swift") }!
        #expect(cleanup.insertions > 0)
        #expect(cleanup.deletions == 0) // only additions in this hunk
    }

    @Test("Detects new files")
    func detectsNewFiles() {
        let files = PRCacheBuilder.parseFilesFromDiff(Self.sampleDiff)
        let testFile = files.first { $0.path.contains("Tests/") }!
        #expect(testFile.isNew == true)
    }

    @Test("Categorizes files by path")
    func categorizesFiles() {
        let files = PRCacheBuilder.parseFilesFromDiff(Self.sampleDiff)
        let cleanup = files.first { $0.path.contains("ProcessCleanup") }!
        #expect(cleanup.category == .source)

        let test = files.first { $0.path.contains("Tests/") }!
        #expect(test.category == .test)

        let readme = files.first { $0.path == "README.md" }!
        #expect(readme.category == .docs)
    }

    @Test("Empty diff produces empty file list")
    func emptyDiff() {
        let files = PRCacheBuilder.parseFilesFromDiff("")
        #expect(files.isEmpty)
    }
}
