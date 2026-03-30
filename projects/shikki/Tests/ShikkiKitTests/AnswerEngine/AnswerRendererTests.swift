import Testing
@testable import ShikkiKit

@Suite("AnswerRenderer")
struct AnswerRendererTests {

    // MARK: - Rendering

    @Test("Render produces non-empty output")
    func renderNonEmpty() {
        let result = makeResult()
        let output = AnswerRenderer.render(result: result, query: "test query")
        #expect(!output.isEmpty)
    }

    @Test("Render includes answer text")
    func renderIncludesAnswer() {
        let result = makeResult()
        let output = AnswerRenderer.render(result: result, query: "test", plain: true)
        #expect(output.contains("EventBus dispatches"))
    }

    @Test("Render includes citation locations")
    func renderIncludesCitations() {
        let result = makeResult()
        let output = AnswerRenderer.render(result: result, query: "test", plain: true)
        #expect(output.contains("EventBus.swift"))
        #expect(output.contains("lines 1-30"))
    }

    @Test("Render includes confidence and latency")
    func renderIncludesMetrics() {
        let result = makeResult()
        let output = AnswerRenderer.render(result: result, query: "test", plain: true)
        #expect(output.contains("confidence: 85%"))
        #expect(output.contains("latency:"))
        #expect(output.contains("2 source(s)"))
    }

    @Test("Plain mode strips ANSI codes")
    func plainModeNoANSI() {
        let result = makeResult()
        let output = AnswerRenderer.render(result: result, query: "test", plain: true)
        #expect(!output.contains("\u{1B}["))
    }

    @Test("Styled mode includes ANSI codes")
    func styledModeHasANSI() {
        let result = makeResult()
        let output = AnswerRenderer.render(result: result, query: "test", plain: false)
        #expect(output.contains("\u{1B}["))
    }

    @Test("Sources cited section lists all citations")
    func sourcesCitedSection() {
        let result = makeResult()
        let output = AnswerRenderer.render(result: result, query: "test", plain: true)
        #expect(output.contains("Sources cited:"))
        #expect(output.contains("> EventBus.swift"))
        #expect(output.contains("# spec.md"))
    }

    // MARK: - Title Extraction

    @Test("Title extracted from colon-separated first line")
    func titleFromColon() {
        let result = AnswerResult(
            answer: "EventBus: dispatches events to subscribers",
            citations: [],
            confidence: 0.5,
            latency: 0.01
        )
        let title = AnswerRenderer.extractTitle(from: result)
        #expect(title == "EventBus")
    }

    @Test("Long first line is truncated")
    func titleTruncated() {
        let longLine = String(repeating: "a", count: 100)
        let result = AnswerResult(
            answer: longLine,
            citations: [],
            confidence: 0.5,
            latency: 0.01
        )
        let title = AnswerRenderer.extractTitle(from: result)
        #expect(title.count == 60)
        #expect(title.hasSuffix("..."))
    }

    @Test("Short first line used as-is")
    func titleShort() {
        let result = AnswerResult(
            answer: "Short answer",
            citations: [],
            confidence: 0.5,
            latency: 0.01
        )
        let title = AnswerRenderer.extractTitle(from: result)
        #expect(title == "Short answer")
    }

    // MARK: - Citation Icons

    @Test("Citation icons map correctly")
    func citationIcons() {
        #expect(AnswerRenderer.citationIcon(for: .sourceCode) == ">")
        #expect(AnswerRenderer.citationIcon(for: .specDocument) == "#")
        #expect(AnswerRenderer.citationIcon(for: .architectureCache) == "@")
        #expect(AnswerRenderer.citationIcon(for: .database) == "~")
    }

    // MARK: - Citation Location

    @Test("Citation location with line range")
    func citationLocationRange() {
        let citation = Citation(sourceType: .sourceCode, file: "Foo.swift",
                               startLine: 10, endLine: 20)
        #expect(citation.location == "Foo.swift (lines 10-20)")
    }

    @Test("Citation location with single line")
    func citationLocationSingleLine() {
        let citation = Citation(sourceType: .sourceCode, file: "Foo.swift",
                               startLine: 42, endLine: nil)
        #expect(citation.location == "Foo.swift (line 42)")
    }

    @Test("Citation location without lines")
    func citationLocationNoLines() {
        let citation = Citation(sourceType: .architectureCache, file: "Foo.swift")
        #expect(citation.location == "Foo.swift")
    }

    // MARK: - Empty Results

    @Test("Render with no citations shows no Sources cited section")
    func renderNoCitations() {
        let result = AnswerResult(
            answer: "Some answer text",
            citations: [],
            confidence: 0.5,
            latency: 0.05
        )
        let output = AnswerRenderer.render(result: result, query: "test", plain: true)
        #expect(!output.contains("Sources cited:"))
        #expect(output.contains("0 source(s)"))
    }

    // MARK: - Helpers

    func makeResult() -> AnswerResult {
        AnswerResult(
            answer: "EventBus dispatches events to typed subscribers via AsyncStream.",
            citations: [
                Citation(sourceType: .sourceCode, file: "EventBus.swift",
                        startLine: 1, endLine: 30, snippet: "InProcessEventBus"),
                Citation(sourceType: .specDocument, file: "spec.md",
                        startLine: 5, endLine: 15, snippet: "Event Bus Design"),
            ],
            confidence: 0.85,
            latency: 0.042
        )
    }
}
