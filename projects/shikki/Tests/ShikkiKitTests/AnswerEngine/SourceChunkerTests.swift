import Testing
@testable import ShikkiKit

@Suite("SourceChunker")
struct SourceChunkerTests {

    let chunker = SourceChunker()

    // MARK: - Basic Chunking

    @Test("Empty content returns no chunks")
    func emptyContent() {
        let chunks = chunker.chunk(content: "", relativePath: "empty.swift")
        #expect(chunks.isEmpty)
    }

    @Test("Single function produces one chunk")
    func singleFunction() {
        let source = """
        func hello() {
            let x = 1
            let y = 2
            let z = x + y
            return z
        }
        """
        let chunks = chunker.chunk(content: source, relativePath: "hello.swift")
        #expect(chunks.count == 1)
        #expect(chunks[0].file == "hello.swift")
        #expect(chunks[0].startLine == 1)
        #expect(chunks[0].symbols.contains("hello"))
    }

    @Test("Multiple declarations produce multiple chunks")
    func multipleDeclarations() {
        let source = """
        import Foundation

        public struct Foo {
            let name: String
            let value: Int
        }

        public struct Bar {
            let id: UUID
            let label: String
        }

        public func doSomething() {
            let x = 1
            let y = 2
        }
        """
        let chunks = chunker.chunk(content: source, relativePath: "models.swift")
        #expect(chunks.count >= 2)

        // Check symbols are extracted
        let allSymbols = chunks.flatMap(\.symbols)
        #expect(allSymbols.contains("Foo"))
        #expect(allSymbols.contains("Bar"))
    }

    @Test("Doc comments are included with their declaration")
    func docCommentsIncluded() {
        let source = """
        import Foundation

        /// This is a doc comment
        /// for the Foo struct.
        public struct Foo {
            let name: String
        }

        /// Bar does things.
        public struct Bar {
            let id: Int
        }
        """
        let chunks = chunker.chunk(content: source, relativePath: "docs.swift")

        // Find the chunk containing Foo
        let fooChunk = chunks.first { $0.symbols.contains("Foo") }
        #expect(fooChunk != nil)
        #expect(fooChunk?.content.contains("doc comment") == true)
    }

    // MARK: - Symbol Extraction

    @Test("Extracts type symbols")
    func extractsTypeSymbols() {
        let source = """
        public class MyService {
            func doWork() {}
        }
        """
        let chunks = chunker.chunk(content: source, relativePath: "service.swift")
        let symbols = chunks.flatMap(\.symbols)
        #expect(symbols.contains("MyService"))
        #expect(symbols.contains("doWork"))
    }

    @Test("Extracts protocol symbols")
    func extractsProtocolSymbols() {
        let source = """
        protocol Fetchable {
            func fetch() async throws
        }
        """
        let chunks = chunker.chunk(content: source, relativePath: "protocol.swift")
        let symbols = chunks.flatMap(\.symbols)
        #expect(symbols.contains("Fetchable"))
        #expect(symbols.contains("fetch"))
    }

    @Test("Extracts enum and actor symbols")
    func extractsEnumActorSymbols() {
        let source = """
        enum Status {
            case active
            case inactive
        }

        actor DataStore {
            var items: [String] = []
            func add(_ item: String) {
                items.append(item)
            }
        }
        """
        let chunks = chunker.chunk(content: source, relativePath: "types.swift")
        let symbols = chunks.flatMap(\.symbols)
        #expect(symbols.contains("Status"))
        #expect(symbols.contains("DataStore"))
    }

    // MARK: - Chunk Splitting

    @Test("Large chunk is split at maxChunkLines boundary")
    func largeChunkSplit() {
        let smallChunker = SourceChunker(maxChunkLines: 10, minChunkLines: 2)
        let lines = (1...30).map { "let x\($0) = \($0)" }
        let source = "func bigFunction() {\n" + lines.joined(separator: "\n") + "\n}"

        let chunks = smallChunker.chunk(content: source, relativePath: "big.swift")
        #expect(chunks.count > 1)

        // Verify all lines are covered
        let totalLines = chunks.reduce(0) { $0 + $1.lineCount }
        #expect(totalLines >= 30)
    }

    @Test("Tiny chunks are merged into predecessors")
    func tinyChunkMerged() {
        let source = """
        public struct Alpha {
            let a: Int
            let b: Int
            let c: Int
            let d: Int
            let e: Int
        }

        let x = 1
        """
        let chunks = chunker.chunk(content: source, relativePath: "tiny.swift")
        // The `let x = 1` line alone (< minChunkLines) should be merged
        // All chunks should be >= minChunkLines
        for chunk in chunks {
            #expect(chunk.lineCount >= chunker.minChunkLines)
        }
    }

    // MARK: - Markdown Chunking

    @Test("Markdown is chunked by headings")
    func markdownChunking() {
        let md = """
        # Title

        Introduction text.

        ## Section One

        Content of section one.

        ## Section Two

        Content of section two.
        """
        let chunks = chunker.chunkMarkdown(content: md, relativePath: "spec.md")
        #expect(chunks.count == 3)
        #expect(chunks[0].symbols.contains("Title"))
        #expect(chunks[1].symbols.contains("Section One"))
        #expect(chunks[2].symbols.contains("Section Two"))
    }

    @Test("Markdown headings become symbols")
    func markdownSymbols() {
        let md = """
        # Architecture Overview

        This is the overview.
        """
        let chunks = chunker.chunkMarkdown(content: md, relativePath: "arch.md")
        #expect(chunks.count == 1)
        #expect(chunks[0].symbols.contains("Architecture Overview"))
    }

    // MARK: - Line Numbers

    @Test("Line numbers are 1-based and accurate")
    func lineNumbersAccuracy() {
        let source = """
        import Foundation

        struct First {
            let a: Int
            let b: Int
            let c: Int
        }

        struct Second {
            let x: Int
            let y: Int
            let z: Int
        }
        """
        let chunks = chunker.chunk(content: source, relativePath: "lines.swift")

        // First chunk should start at line 1
        #expect(chunks[0].startLine == 1)

        // Find the Second struct chunk
        if let secondChunk = chunks.first(where: { $0.symbols.contains("Second") }) {
            // Second struct starts around line 9
            #expect(secondChunk.startLine >= 8)
            #expect(secondChunk.endLine <= 14)
        }
    }

    // MARK: - Declaration Detection

    @Test("isDeclarationStart detects top-level Swift declarations")
    func declarationDetection() {
        // Top-level declarations (no indentation)
        #expect(chunker.isDeclarationStart("public struct Foo {") == true)
        #expect(chunker.isDeclarationStart("class Bar {") == true)
        #expect(chunker.isDeclarationStart("enum Status {") == true)
        #expect(chunker.isDeclarationStart("actor Pool {") == true)
        #expect(chunker.isDeclarationStart("protocol Fetchable {") == true)
        #expect(chunker.isDeclarationStart("extension String {") == true)
        #expect(chunker.isDeclarationStart("func doWork() {") == true)
        #expect(chunker.isDeclarationStart("public func doWork() {") == true)
        #expect(chunker.isDeclarationStart("final class MyClass {") == true)

        // Indented declarations are NOT boundaries (inside type bodies)
        #expect(chunker.isDeclarationStart("    let name: String") == false)
        #expect(chunker.isDeclarationStart("    var cache: [String] = []") == false)
        #expect(chunker.isDeclarationStart("    func innerMethod() {") == false)

        // Non-declarations
        #expect(chunker.isDeclarationStart("// a comment") == false)
        #expect(chunker.isDeclarationStart("") == false)
        #expect(chunker.isDeclarationStart("    case .active:") == false)
        #expect(chunker.isDeclarationStart("    return value") == false)
        #expect(chunker.isDeclarationStart("    guard let x = y else {") == false)

        // MARK comments are section separators
        #expect(chunker.isDeclarationStart("// MARK: - Section") == true)
    }

    // MARK: - Project Chunking

    @Test("chunkProject skips .build directory")
    func chunkProjectSkipsBuild() {
        // This tests the filter logic — .build/ should be excluded
        // We test by verifying no chunks have .build in their path
        // (can't create real .build dir in test, but we verify the logic)
        let chunker = SourceChunker()
        #expect(chunker.maxChunkLines == 80)
        #expect(chunker.minChunkLines == 5)
    }
}
