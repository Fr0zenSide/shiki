import Testing
import Foundation
@testable import ShikkiKit

@Suite("SpecParser")
struct SpecParserTests {

    let parser = SpecParser()

    // MARK: - Feature Name Extraction

    @Test("extracts feature name from first heading")
    func featureName() throws {
        let spec = """
        # Payment System

        A new payment processing feature.
        """
        let layer = try parser.parse(content: spec)
        #expect(layer.featureName == "Payment System")
    }

    @Test("defaults to Unknown Feature when no heading")
    func featureNameMissing() throws {
        let spec = "Just some text without a heading."
        let layer = try parser.parse(content: spec)
        #expect(layer.featureName == "Unknown Feature")
    }

    // MARK: - Target Module

    @Test("extracts target module from metadata")
    func targetModule() throws {
        let spec = """
        # Feature
        module: BrainyCore
        """
        let layer = try parser.parse(content: spec)
        #expect(layer.targetModule == "BrainyCore")
    }

    @Test("extracts target module case-insensitive")
    func targetModuleCaseInsensitive() throws {
        let spec = """
        # Feature
        Target: ShikkiKit
        """
        let layer = try parser.parse(content: spec)
        #expect(layer.targetModule == "ShikkiKit")
    }

    // MARK: - Protocol Extraction from Code Blocks

    @Test("extracts protocol from swift code block")
    func protocolExtraction() throws {
        let spec = """
        # Translation Feature

        ## Contracts

        ```swift
        public protocol TranslationProvider: Sendable {
            func translate(text: String) async throws -> String
            func detectLanguage(text: String) async -> String
        }
        ```
        """
        let layer = try parser.parse(content: spec)
        #expect(layer.protocols.count == 1)
        #expect(layer.protocols[0].name == "TranslationProvider")
        #expect(layer.protocols[0].methods.count == 2)
        #expect(layer.protocols[0].inherits.contains("Sendable"))
    }

    @Test("extracts multiple protocols from one code block")
    func multipleProtocols() throws {
        let spec = """
        # Feature

        ```swift
        protocol StorageProvider {
            func save(data: Data) async throws
        }

        protocol CacheProvider {
            func get(key: String) -> Data?
        }
        ```
        """
        let layer = try parser.parse(content: spec)
        #expect(layer.protocols.count == 2)
        #expect(layer.protocols[0].name == "StorageProvider")
        #expect(layer.protocols[1].name == "CacheProvider")
    }

    @Test("extracts protocols from multiple code blocks")
    func protocolsAcrossBlocks() throws {
        let spec = """
        # Feature

        ## Core Protocol

        ```swift
        protocol Engine {
            func start() async throws
        }
        ```

        ## Extension Protocol

        ```swift
        protocol EnginePlugin: Sendable {
            func attach(to engine: Engine) async
        }
        ```
        """
        let layer = try parser.parse(content: spec)
        #expect(layer.protocols.count == 2)
    }

    @Test("extracts associated types from protocol")
    func associatedTypes() throws {
        let spec = """
        # Feature

        ```swift
        protocol Repository {
            associatedtype Entity
            associatedtype ID
            func find(id: ID) async throws -> Entity?
        }
        ```
        """
        let layer = try parser.parse(content: spec)
        #expect(layer.protocols[0].associatedTypes == ["Entity", "ID"])
    }

    // MARK: - Type Extraction from Code Blocks

    @Test("extracts struct from code block")
    func structExtraction() throws {
        let spec = """
        # Feature

        ```swift
        public struct TranslationPage: Sendable, Codable {
            public let id: String
            public let sourceText: String
            public let translatedText: String?
            public let progress: Double
        }
        ```
        """
        let layer = try parser.parse(content: spec)
        #expect(layer.types.count == 1)
        #expect(layer.types[0].name == "TranslationPage")
        #expect(layer.types[0].kind == .struct)
        #expect(layer.types[0].conformances.contains("Sendable"))
        #expect(layer.types[0].conformances.contains("Codable"))
        #expect(layer.types[0].fields.count == 4)
        #expect(layer.types[0].fields[0].name == "id")
        #expect(layer.types[0].fields[0].type == "String")
    }

    @Test("extracts enum from code block")
    func enumExtraction() throws {
        let spec = """
        # Feature

        ```swift
        public enum TranslationStatus: String, Codable {
            case pending
            case inProgress
            case completed
            case failed
        }
        ```
        """
        let layer = try parser.parse(content: spec)
        #expect(layer.types.count == 1)
        #expect(layer.types[0].name == "TranslationStatus")
        #expect(layer.types[0].kind == .enum)
    }

    @Test("extracts class from code block")
    func classExtraction() throws {
        let spec = """
        # Feature

        ```swift
        public final class TranslationEngine {
            public let provider: TranslationProvider
            public var cache: CacheProvider?
        }
        ```
        """
        let layer = try parser.parse(content: spec)
        #expect(layer.types.count == 1)
        #expect(layer.types[0].name == "TranslationEngine")
        #expect(layer.types[0].kind == .class)
        #expect(layer.types[0].fields.count == 2)
    }

    @Test("extracts optional field types")
    func optionalFields() throws {
        let spec = """
        # Feature

        ```swift
        struct Config {
            let apiKey: String
            let timeout: Int?
            let retryCount: Int
        }
        ```
        """
        let layer = try parser.parse(content: spec)
        #expect(layer.types[0].fields[1].isOptional == true)
        #expect(layer.types[0].fields[0].isOptional == false)
    }

    // MARK: - File Spec Extraction

    @Test("extracts file specs from TDDP listing")
    func fileSpecs() throws {
        let spec = """
        # Feature

        ## Files

        - Sources/BrainyCore/Translation/TranslationProvider.swift — protocol for translation
        - Sources/BrainyCore/Translation/TranslationPage.swift — core model
        - Tests/TranslationTests.swift — unit tests
        """
        let layer = try parser.parse(content: spec)
        #expect(layer.fileSpecs.count == 3)
        #expect(layer.fileSpecs[0].path == "Sources/BrainyCore/Translation/TranslationProvider.swift")
        #expect(layer.fileSpecs[0].description == "protocol for translation")
        #expect(layer.fileSpecs[2].role == .test)
    }

    @Test("extracts file specs with arrow prefix")
    func fileSpecsArrow() throws {
        let spec = """
        # Feature

        → Sources/Module/File.swift — implementation
        → Tests/FileTests.swift — tests
        """
        let layer = try parser.parse(content: spec)
        #expect(layer.fileSpecs.count == 2)
    }

    @Test("infers file roles correctly")
    func fileRoleInference() throws {
        let spec = """
        # Feature

        - Sources/Protocols/FooProtocol.swift
        - Sources/Models/FooModel.swift
        - Tests/FooTests.swift
        - Sources/Mocks/MockFoo.swift
        - Sources/Services/FooService.swift
        """
        let layer = try parser.parse(content: spec)
        #expect(layer.fileSpecs.count == 5)

        let roleMap = Dictionary(uniqueKeysWithValues: layer.fileSpecs.map { ($0.path, $0.role) })
        #expect(roleMap["Sources/Protocols/FooProtocol.swift"] == .protocol)
        #expect(roleMap["Sources/Models/FooModel.swift"] == .model)
        #expect(roleMap["Tests/FooTests.swift"] == .test)
        #expect(roleMap["Sources/Mocks/MockFoo.swift"] == .mock)
        #expect(roleMap["Sources/Services/FooService.swift"] == .implementation)
    }

    // MARK: - Target File Inference

    @Test("infers target files for protocols without explicit paths")
    func targetFileInference() throws {
        let spec = """
        # Feature
        module: BrainyCore

        ```swift
        protocol Foo {
            func bar()
        }
        ```
        """
        let layer = try parser.parse(content: spec)
        #expect(layer.protocols[0].targetFile == "Sources/BrainyCore/Protocols/Foo.swift")
    }

    @Test("infers target files for types without explicit paths")
    func targetFileInferenceTypes() throws {
        let spec = """
        # Feature
        module: BrainyCore

        ```swift
        struct Bar {
            let name: String
        }
        ```
        """
        let layer = try parser.parse(content: spec)
        #expect(layer.types[0].targetFile == "Sources/BrainyCore/Models/Bar.swift")
    }

    // MARK: - Mixed Spec (protocols + types + files)

    @Test("parses full TDDP spec with everything")
    func fullSpec() throws {
        let spec = """
        # Translation Pipeline
        module: BrainyCore

        ## Contracts

        ```swift
        public protocol TranslationProvider: Sendable {
            func translate(text: String, from: String, to: String) async throws -> String
        }

        public protocol OCRProvider: Sendable {
            func extractText(from imageData: Data) async throws -> [TextRegion]
        }
        ```

        ## Models

        ```swift
        public struct TextRegion: Sendable, Codable {
            public let text: String
            public let boundingBox: CGRect
            public let confidence: Double
        }

        public enum TranslationError: Error {
            case unsupportedLanguage(String)
            case networkUnavailable
            case quotaExceeded
        }
        ```

        ## Files

        - Sources/BrainyCore/Translation/TranslationProvider.swift — main protocol
        - Sources/BrainyCore/Translation/OCRProvider.swift — OCR protocol
        - Sources/BrainyCore/Translation/TextRegion.swift — region model
        - Sources/BrainyCore/Translation/TranslationError.swift — error types
        - Sources/BrainyCore/Translation/AppleTranslation.swift — Apple Translation impl
        - Sources/BrainyCore/Translation/AppleVisionOCR.swift — Vision framework impl
        - Tests/TranslationTests/TranslationProviderTests.swift — protocol tests
        - Tests/TranslationTests/OCRProviderTests.swift — OCR tests
        - Sources/BrainyCore/Mocks/MockTranslationProvider.swift — mock
        """
        let layer = try parser.parse(content: spec)

        #expect(layer.featureName == "Translation Pipeline")
        #expect(layer.targetModule == "BrainyCore")
        #expect(layer.protocols.count == 2)
        #expect(layer.types.count == 2)
        #expect(layer.fileSpecs.count == 9)
        #expect(layer.protocols[0].name == "TranslationProvider")
        #expect(layer.protocols[1].name == "OCRProvider")
        #expect(layer.types[0].name == "TextRegion")
        #expect(layer.types[1].name == "TranslationError")
    }

    // MARK: - Edge Cases

    @Test("empty spec returns empty layer")
    func emptySpec() throws {
        let layer = try parser.parse(content: "")
        #expect(layer.protocols.isEmpty)
        #expect(layer.types.isEmpty)
    }

    @Test("spec with no code blocks still parses file specs")
    func noCodeBlocks() throws {
        let spec = """
        # Feature

        ## Files

        - Sources/Module/File.swift — implementation
        """
        let layer = try parser.parse(content: spec)
        #expect(layer.protocols.isEmpty)
        #expect(layer.fileSpecs.count == 1)
    }

    @Test("non-swift code blocks are ignored")
    func nonSwiftCodeBlocks() throws {
        let spec = """
        # Feature

        ```python
        class Foo:
            pass
        ```

        ```swift
        protocol Bar {
            func baz()
        }
        ```
        """
        let layer = try parser.parse(content: spec)
        #expect(layer.protocols.count == 1)
        #expect(layer.protocols[0].name == "Bar")
    }
}
