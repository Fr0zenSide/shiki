import Foundation

// MARK: - Risk Level

public enum RiskLevel: String, Codable, Sendable, Comparable {
    case high
    case medium
    case low
    case skip

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        let order: [RiskLevel] = [.high, .medium, .low, .skip]
        let lhsIdx = order.firstIndex(of: lhs) ?? 3
        let rhsIdx = order.firstIndex(of: rhs) ?? 3
        return lhsIdx < rhsIdx
    }
}

public struct AssessedFile: Sendable {
    public let file: PRFileEntry
    public let risk: RiskLevel
    public let reasons: [String]

    public init(file: PRFileEntry, risk: RiskLevel, reasons: [String]) {
        self.file = file
        self.risk = risk
        self.reasons = reasons
    }
}

// MARK: - Engine

public enum PRRiskEngine {

    /// Assess risk for a single file given the full file list for context.
    public static func assess(file: PRFileEntry, allFiles: [PRFileEntry]) -> RiskLevel {
        let reasons = assessReasons(file: file, allFiles: allFiles)
        return reasons.risk
    }

    /// Assess all files, return sorted by risk (high first).
    public static func assessAll(files: [PRFileEntry]) -> [AssessedFile] {
        files
            .map { file in
                let result = assessReasons(file: file, allFiles: files)
                return AssessedFile(file: file, risk: result.risk, reasons: result.reasons)
            }
            .sorted { $0.risk < $1.risk } // high < medium < low < skip in our Comparable
    }

    // MARK: - Assessment Logic

    private static func assessReasons(file: PRFileEntry, allFiles: [PRFileEntry]) -> (risk: RiskLevel, reasons: [String]) {
        var reasons: [String] = []

        // Auto-skip categories
        switch file.category {
        case .docs:
            return (.skip, ["Documentation file"])
        case .config:
            return (.skip, ["Configuration file"])
        case .asset:
            return (.skip, ["Asset file"])
        case .generated:
            return (.skip, ["Generated file"])
        case .test:
            return (.low, ["Test file"])
        case .source:
            break
        }

        // Source file heuristics
        let hasMatchingTest = allFiles.contains { testFile in
            testFile.category == .test && testFileMatches(source: file.path, test: testFile.path)
        }

        // Large change
        if file.totalChanges > 100 {
            reasons.append("Large change: +\(file.insertions)/-\(file.deletions)")
        }

        // New file without tests
        if file.isNew && !hasMatchingTest {
            reasons.append("New file without matching test")
        }

        // Large file with no test counterpart
        if !hasMatchingTest && file.totalChanges > 20 {
            reasons.append("No matching test file")
        }

        // Determine risk level
        if file.isNew && !hasMatchingTest && file.totalChanges > 30 {
            return (.high, reasons)
        }

        if file.totalChanges > 100 && !hasMatchingTest {
            return (.high, reasons)
        }

        if !hasMatchingTest && file.totalChanges > 20 {
            return (.medium, reasons)
        }

        if file.totalChanges > 50 {
            return (.medium, reasons)
        }

        if reasons.isEmpty {
            reasons.append("Small change with test coverage")
        }

        return (.low, reasons)
    }

    /// Check if a test file path matches a source file path.
    private static func testFileMatches(source: String, test: String) -> Bool {
        let sourceName = (source as NSString).lastPathComponent
            .replacingOccurrences(of: ".swift", with: "")
            .replacingOccurrences(of: ".ts", with: "")
            .replacingOccurrences(of: ".go", with: "")

        let testName = (test as NSString).lastPathComponent
            .replacingOccurrences(of: ".swift", with: "")
            .replacingOccurrences(of: ".ts", with: "")
            .replacingOccurrences(of: ".go", with: "")
            .replacingOccurrences(of: "Tests", with: "")
            .replacingOccurrences(of: "Test", with: "")
            .replacingOccurrences(of: "_test", with: "")
            .replacingOccurrences(of: ".test", with: "")
            .replacingOccurrences(of: ".spec", with: "")

        return sourceName == testName
    }
}
