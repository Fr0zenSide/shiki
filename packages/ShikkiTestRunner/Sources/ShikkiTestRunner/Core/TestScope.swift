// TestScope.swift — Architecture-scoped test group descriptor
// Part of ShikkiTestRunner

import Foundation

/// A test scope derived from architecture analysis (Moto cache).
/// Each scope groups test files that share a dependency subgraph.
public struct TestScope: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let filter: String
    public let testFiles: [String]
    public let expectedTestCount: Int

    public init(
        name: String,
        filter: String,
        testFiles: [String] = [],
        expectedTestCount: Int = 0
    ) {
        self.id = name
        self.name = name
        self.filter = filter
        self.testFiles = testFiles
        self.expectedTestCount = expectedTestCount
    }
}
