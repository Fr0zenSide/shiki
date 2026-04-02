import Foundation
import Testing
@testable import ShikkiKit

@Suite("Moto Cache Hardening")
struct MotoCacheHardeningTests {

    // MARK: - 1. Method-level index includes function signatures

    @Test("method-level index includes function signatures")
    func methodIndexIncludesFunctions() throws {
        let cache = makeTestCache()
        let builder = MotoCacheBuilder(builderId: "test@1.0")

        let index = builder.buildMethodIndex(from: cache)

        // AppConfig has a public function "configure()"
        let appConfigMethods = index.entries.filter { $0.typeName == "AppConfig" }
        let signatures = appConfigMethods.map(\.signature)
        #expect(signatures.contains("func configure(apiKey: String)"))
    }

    // MARK: - 2. Method-level index includes computed properties

    @Test("method-level index includes computed properties")
    func methodIndexIncludesComputedProperties() throws {
        let cache = makeTestCache()
        let builder = MotoCacheBuilder(builderId: "test@1.0")

        let index = builder.buildMethodIndex(from: cache)

        let userModelEntries = index.entries.filter { $0.typeName == "UserModel" }
        let signatures = userModelEntries.map(\.signature)
        #expect(signatures.contains("var displayName: String { get }"))
    }

    // MARK: - 3. Utilities manifest lists shared helpers with usage counts

    @Test("utilities manifest lists shared helpers with usage counts")
    func utilitiesManifestWithUsageCounts() throws {
        let cache = makeTestCache()
        let builder = MotoCacheBuilder(builderId: "test@1.0")

        let manifest = builder.buildUtilitiesManifest(from: cache)

        // "formatDate" is used in 3 files
        let formatDate = manifest.utilities.first { $0.name == "formatDate" }
        #expect(formatDate != nil)
        #expect(formatDate?.usageCount == 3)

        // "sanitizeInput" is used in 2 files
        let sanitize = manifest.utilities.first { $0.name == "sanitizeInput" }
        #expect(sanitize != nil)
        #expect(sanitize?.usageCount == 2)
    }

    // MARK: - 4. Duplicate detection finds identical method signatures

    @Test("duplicate detection finds identical method signatures")
    func duplicateDetectionFindsIdenticalSignatures() throws {
        let cache = makeCacheWithDuplicates()
        let builder = MotoCacheBuilder(builderId: "test@1.0")

        let index = builder.buildMethodIndex(from: cache)
        let detector = DuplicateDetector()
        let duplicates = detector.findDuplicates(in: index)

        // "func validate() -> Bool" appears in both ServiceA and ServiceB
        let validateDup = duplicates.first { $0.signature == "func validate() -> Bool" }
        #expect(validateDup != nil)
        #expect(validateDup?.locations.count == 2)
        let typeNames = validateDup?.locations.map(\.typeName) ?? []
        #expect(typeNames.contains("ServiceA"))
        #expect(typeNames.contains("ServiceB"))
    }

    // MARK: - 5. Duplicate detection ignores test files

    @Test("duplicate detection ignores test files")
    func duplicateDetectionIgnoresTestFiles() throws {
        let cache = makeCacheWithTestDuplicates()
        let builder = MotoCacheBuilder(builderId: "test@1.0")

        let index = builder.buildMethodIndex(from: cache)
        let detector = DuplicateDetector()
        let duplicates = detector.findDuplicates(in: index)

        // "func makeFixture() -> Model" appears in both a source file and a test file
        // but the test file entry should be excluded
        let fixtureDup = duplicates.first { $0.signature == "func makeFixture() -> Model" }
        #expect(fixtureDup == nil)
    }

    // MARK: - 6. Incremental rebuild only processes changed files

    @Test("incremental rebuild only processes changed files")
    func incrementalRebuildOnlyChanged() throws {
        let tmpDir = makeTmpDir("incremental")
        defer { cleanup(tmpDir) }

        // Create two source files with known mtimes
        let file1 = tmpDir.appendingPathComponent("FileA.swift")
        let file2 = tmpDir.appendingPathComponent("FileB.swift")
        try "struct FileA {}".write(to: file1, atomically: true, encoding: .utf8)
        try "struct FileB {}".write(to: file2, atomically: true, encoding: .utf8)

        // Build initial state file
        let tracker = CacheInvalidationTracker()
        let initialState = try tracker.snapshot(directory: tmpDir.path)
        #expect(initialState.files.count == 2)

        // "Modify" FileA by touching it with a different mtime
        let futureDate = Date().addingTimeInterval(10)
        try FileManager.default.setAttributes(
            [.modificationDate: futureDate],
            ofItemAtPath: file1.path
        )

        let newState = try tracker.snapshot(directory: tmpDir.path)
        let changed = tracker.changedFiles(old: initialState, new: newState)

        #expect(changed.count == 1)
        #expect(changed.first?.hasSuffix("FileA.swift") == true)
    }

    // MARK: - 7. Force rebuild processes all files

    @Test("force rebuild processes all files")
    func forceRebuildProcessesAll() throws {
        let tmpDir = makeTmpDir("force-rebuild")
        defer { cleanup(tmpDir) }

        let file1 = tmpDir.appendingPathComponent("FileA.swift")
        let file2 = tmpDir.appendingPathComponent("FileB.swift")
        try "struct FileA {}".write(to: file1, atomically: true, encoding: .utf8)
        try "struct FileB {}".write(to: file2, atomically: true, encoding: .utf8)

        let tracker = CacheInvalidationTracker()
        let state = try tracker.snapshot(directory: tmpDir.path)

        // Force rebuild means all files are "changed"
        let allFiles = tracker.allFiles(in: state)
        #expect(allFiles.count == 2)
    }

    // MARK: - 8. Cache round-trip: build -> save -> load -> query returns same results

    @Test("cache round-trip: build -> save -> load -> query returns same results")
    func cacheRoundTrip() throws {
        let tmpDir = makeTmpDir("round-trip")
        defer { cleanup(tmpDir) }

        let cache = makeTestCache()
        let builder = MotoCacheBuilder(builderId: "test@1.0")

        // Build method index and save
        let index = builder.buildMethodIndex(from: cache)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(index)
        let indexPath = tmpDir.appendingPathComponent("methods.json")
        try data.write(to: indexPath, options: .atomic)

        // Load and query
        let loadedData = try Data(contentsOf: indexPath)
        let loadedIndex = try JSONDecoder().decode(MethodIndex.self, from: loadedData)

        #expect(loadedIndex.entries.count == index.entries.count)

        // Query for a specific method
        let configMethods = loadedIndex.entries.filter { $0.typeName == "AppConfig" }
        let originalConfigMethods = index.entries.filter { $0.typeName == "AppConfig" }
        #expect(configMethods.count == originalConfigMethods.count)
        #expect(configMethods.map(\.signature).sorted() == originalConfigMethods.map(\.signature).sorted())
    }

    // MARK: - Helpers

    private func makeTestCache() -> ArchitectureCache {
        ArchitectureCache(
            projectId: "TestProject",
            projectPath: "/tmp/test-project",
            gitHash: "abc123def456",
            builtAt: Date(timeIntervalSince1970: 1_700_000_000),
            packageInfo: PackageInfo(
                name: "TestPackage",
                platforms: ["macOS 14"],
                targets: [
                    TargetInfo(name: "AppModule", type: .library, sourceFiles: 8),
                    TargetInfo(name: "AppModuleTests", type: .test, sourceFiles: 2),
                ],
                dependencies: []
            ),
            protocols: [
                ProtocolDescriptor(
                    name: "Renderable",
                    methods: ["func render()", "var body: String { get }"],
                    module: "AppModule"
                ),
            ],
            types: [
                TypeDescriptor(
                    name: "AppConfig",
                    kind: .struct,
                    file: "Sources/AppModule/AppConfig.swift",
                    module: "AppModule",
                    fields: ["apiKey", "baseURL"],
                    isPublic: true,
                    methods: ["func configure(apiKey: String)"],
                    computedProperties: ["var isConfigured: Bool { get }"]
                ),
                TypeDescriptor(
                    name: "UserModel",
                    kind: .struct,
                    file: "Sources/AppModule/UserModel.swift",
                    module: "AppModule",
                    fields: ["id", "name"],
                    conformances: ["Codable", "Sendable"],
                    isPublic: true,
                    methods: ["func toJSON() -> String"],
                    computedProperties: ["var displayName: String { get }"]
                ),
                TypeDescriptor(
                    name: "InternalHelper",
                    kind: .class,
                    file: "Sources/AppModule/InternalHelper.swift",
                    module: "AppModule",
                    isPublic: false,
                    methods: ["func help()"],
                    computedProperties: []
                ),
            ],
            dependencyGraph: [
                "AppModule": ["Foundation", "Logging"],
            ],
            patterns: [
                CodePattern(
                    name: "error_pattern",
                    description: "Typed error enums",
                    example: "enum AppError: Error { ... }",
                    files: ["Sources/AppModule/Errors.swift"]
                ),
                CodePattern(
                    name: "utility_pattern",
                    description: "Shared utility functions",
                    example: "func formatDate(_ date: Date) -> String",
                    files: [
                        "Sources/AppModule/Utils/Formatters.swift",
                        "Sources/AppModule/Views/DateView.swift",
                        "Sources/AppModule/Services/DataService.swift",
                    ]
                ),
                CodePattern(
                    name: "sanitize_pattern",
                    description: "Input sanitization",
                    example: "func sanitizeInput(_ input: String) -> String",
                    files: [
                        "Sources/AppModule/Validators/InputValidator.swift",
                        "Sources/AppModule/Services/FormService.swift",
                    ]
                ),
            ],
            testInfo: TestInfo(framework: "swift-testing", testFiles: 2, testCount: 15),
            sharedUtilities: [
                SharedUtility(
                    name: "formatDate",
                    signature: "func formatDate(_ date: Date) -> String",
                    file: "Sources/AppModule/Utils/Formatters.swift",
                    usageFiles: [
                        "Sources/AppModule/Views/DateView.swift",
                        "Sources/AppModule/Services/DataService.swift",
                        "Sources/AppModule/Utils/Formatters.swift",
                    ]
                ),
                SharedUtility(
                    name: "sanitizeInput",
                    signature: "func sanitizeInput(_ input: String) -> String",
                    file: "Sources/AppModule/Validators/InputValidator.swift",
                    usageFiles: [
                        "Sources/AppModule/Validators/InputValidator.swift",
                        "Sources/AppModule/Services/FormService.swift",
                    ]
                ),
            ]
        )
    }

    private func makeCacheWithDuplicates() -> ArchitectureCache {
        ArchitectureCache(
            projectId: "DupProject",
            projectPath: "/tmp/dup-project",
            gitHash: "def456",
            builtAt: Date(timeIntervalSince1970: 1_700_000_000),
            packageInfo: PackageInfo(name: "DupPackage"),
            protocols: [],
            types: [
                TypeDescriptor(
                    name: "ServiceA",
                    kind: .struct,
                    file: "Sources/App/ServiceA.swift",
                    module: "App",
                    isPublic: true,
                    methods: ["func validate() -> Bool", "func execute()"],
                    computedProperties: []
                ),
                TypeDescriptor(
                    name: "ServiceB",
                    kind: .struct,
                    file: "Sources/App/ServiceB.swift",
                    module: "App",
                    isPublic: true,
                    methods: ["func validate() -> Bool", "func process()"],
                    computedProperties: []
                ),
            ],
            dependencyGraph: [:],
            patterns: [],
            testInfo: TestInfo()
        )
    }

    private func makeCacheWithTestDuplicates() -> ArchitectureCache {
        ArchitectureCache(
            projectId: "TestDupProject",
            projectPath: "/tmp/testdup-project",
            gitHash: "789abc",
            builtAt: Date(timeIntervalSince1970: 1_700_000_000),
            packageInfo: PackageInfo(name: "TestDupPackage"),
            protocols: [],
            types: [
                TypeDescriptor(
                    name: "ModelFactory",
                    kind: .struct,
                    file: "Sources/App/ModelFactory.swift",
                    module: "App",
                    isPublic: true,
                    methods: ["func makeFixture() -> Model"],
                    computedProperties: []
                ),
                TypeDescriptor(
                    name: "TestHelper",
                    kind: .struct,
                    file: "Tests/AppTests/TestHelper.swift",
                    module: "AppTests",
                    isPublic: false,
                    methods: ["func makeFixture() -> Model"],
                    computedProperties: []
                ),
            ],
            dependencyGraph: [:],
            patterns: [],
            testInfo: TestInfo()
        )
    }

    private func makeTmpDir(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moto-hardening-\(name)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }
}
