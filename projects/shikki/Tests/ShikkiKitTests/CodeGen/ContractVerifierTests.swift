import Foundation
import Testing
@testable import ShikkiKit

@Suite("ContractVerifier")
struct ContractVerifierTests {

    let verifier = ContractVerifier()

    // MARK: - Valid Contracts

    @Test("valid protocol layer passes verification")
    func validLayer() {
        let layer = ProtocolLayer(
            featureName: "Test",
            protocols: [
                ProtocolSpec(name: "FooProvider", methods: ["func doStuff() async throws"])
            ],
            types: [
                TypeSpec(name: "FooResult", kind: .struct, fields: [
                    FieldSpec(name: "value", type: "String")
                ], conformances: ["Sendable"])
            ]
        )
        let result = verifier.verify(layer)
        #expect(result.isValid)
        #expect(result.issues.isEmpty)
    }

    @Test("empty layer is valid")
    func emptyLayer() {
        let layer = ProtocolLayer()
        let result = verifier.verify(layer)
        #expect(result.isValid)
    }

    // MARK: - Duplicate Detection

    @Test("detects duplicate protocol names")
    func duplicateProtocols() {
        let layer = ProtocolLayer(
            protocols: [
                ProtocolSpec(name: "Foo"),
                ProtocolSpec(name: "Foo"),
            ]
        )
        let result = verifier.verify(layer)
        #expect(!result.isValid)
        #expect(result.issues.contains { $0.contains("Duplicate") && $0.contains("Foo") })
    }

    @Test("detects protocol-type name collision")
    func protoTypeCollision() {
        let layer = ProtocolLayer(
            protocols: [ProtocolSpec(name: "Widget")],
            types: [TypeSpec(name: "Widget")]
        )
        let result = verifier.verify(layer)
        #expect(!result.isValid)
    }

    // MARK: - Warnings

    @Test("warns about empty protocols")
    func emptyProtocolWarning() {
        let layer = ProtocolLayer(
            protocols: [ProtocolSpec(name: "Marker")]
        )
        let result = verifier.verify(layer)
        #expect(result.isValid) // Warning, not error
        #expect(result.warnings.contains { $0.contains("Marker") && $0.contains("no methods") })
    }

    @Test("warns about unknown conformances")
    func unknownConformance() {
        let layer = ProtocolLayer(
            types: [
                TypeSpec(name: "Foo", conformances: ["CustomWidget"])
            ]
        )
        let result = verifier.verify(layer)
        #expect(result.isValid)
        #expect(result.warnings.contains { $0.contains("CustomWidget") })
    }

    @Test("does not warn about well-known protocols")
    func wellKnownProtocols() {
        let layer = ProtocolLayer(
            types: [
                TypeSpec(name: "Foo", conformances: ["Sendable", "Codable", "Hashable"])
            ]
        )
        let result = verifier.verify(layer)
        let conformanceWarnings = result.warnings.filter { $0.contains("conforms to") }
        #expect(conformanceWarnings.isEmpty)
    }

    @Test("warns about types with no fields except enums")
    func noFieldsWarning() {
        let layer = ProtocolLayer(
            types: [
                TypeSpec(name: "EmptyStruct", kind: .struct),
                TypeSpec(name: "StatusEnum", kind: .enum),
            ]
        )
        let result = verifier.verify(layer)
        #expect(result.warnings.contains { $0.contains("EmptyStruct") && $0.contains("no fields") })
        #expect(!result.warnings.contains { $0.contains("StatusEnum") && $0.contains("no fields") })
    }

    @Test("warns about missing target files")
    func missingTargetFiles() {
        let layer = ProtocolLayer(
            protocols: [ProtocolSpec(name: "Foo", targetFile: "")],
            types: [TypeSpec(name: "Bar", targetFile: "")]
        )
        let result = verifier.verify(layer)
        #expect(result.warnings.contains { $0.contains("Foo") && $0.contains("no target file") })
        #expect(result.warnings.contains { $0.contains("Bar") && $0.contains("no target file") })
    }

    // MARK: - Cache Verification

    @Test("detects name collision with existing project types")
    func cacheCollision() {
        let layer = ProtocolLayer(
            types: [TypeSpec(name: "Company")]
        )
        let cache = ArchitectureCache(
            projectId: "test",
            projectPath: "/tmp/test",
            gitHash: "abc",
            builtAt: Date(),
            packageInfo: PackageInfo(),
            protocols: [],
            types: [TypeDescriptor(name: "Company", kind: .struct)],
            dependencyGraph: [:],
            patterns: [],
            testInfo: TestInfo()
        )
        let result = verifier.verifyAgainstCache(layer, cache: cache)
        #expect(result.warnings.contains { $0.contains("Company") && $0.contains("already exists") })
    }

    @Test("detects protocol-type conflict with existing project")
    func cacheProtocolTypeConflict() {
        let layer = ProtocolLayer(
            protocols: [ProtocolSpec(name: "Engine")]
        )
        let cache = ArchitectureCache(
            projectId: "test",
            projectPath: "/tmp/test",
            gitHash: "abc",
            builtAt: Date(),
            packageInfo: PackageInfo(),
            protocols: [],
            types: [TypeDescriptor(name: "Engine", kind: .class)],
            dependencyGraph: [:],
            patterns: [],
            testInfo: TestInfo()
        )
        let result = verifier.verifyAgainstCache(layer, cache: cache)
        #expect(!result.isValid)
        #expect(result.issues.contains { $0.contains("Engine") && $0.contains("conflicts") })
    }

    @Test("warns when target module not in project")
    func missingModule() {
        let layer = ProtocolLayer(targetModule: "NewModule")
        let cache = ArchitectureCache(
            projectId: "test",
            projectPath: "/tmp/test",
            gitHash: "abc",
            builtAt: Date(),
            packageInfo: PackageInfo(targets: [
                TargetInfo(name: "ExistingModule", type: .library)
            ]),
            protocols: [],
            types: [],
            dependencyGraph: [:],
            patterns: [],
            testInfo: TestInfo()
        )
        let result = verifier.verifyAgainstCache(layer, cache: cache)
        #expect(result.warnings.contains { $0.contains("NewModule") && $0.contains("not found") })
    }

    // MARK: - Source Generation

    @Test("generates compilable source for protocol layer")
    func sourceGeneration() {
        let layer = ProtocolLayer(
            featureName: "Test",
            protocols: [
                ProtocolSpec(
                    name: "Foo",
                    methods: ["func bar() async throws -> String"],
                    inherits: ["Sendable"]
                )
            ],
            types: [
                TypeSpec(
                    name: "Result",
                    kind: .struct,
                    fields: [
                        FieldSpec(name: "value", type: "String"),
                        FieldSpec(name: "error", type: "Error", isOptional: true),
                    ],
                    conformances: ["Sendable"]
                )
            ]
        )

        let source = verifier.generateSource(layer)
        #expect(source.contains("protocol Foo: Sendable"))
        #expect(source.contains("func bar() async throws -> String"))
        #expect(source.contains("struct Result: Sendable"))
        #expect(source.contains("let value: String"))
        #expect(source.contains("let error: Error?"))
    }

    @Test("verification duration is measured")
    func durationTracking() {
        let layer = ProtocolLayer(
            protocols: [ProtocolSpec(name: "Foo", methods: ["func bar()"])]
        )
        let result = verifier.verify(layer)
        #expect(result.durationMs >= 0)
    }
}
