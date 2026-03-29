import Foundation
import Testing
@testable import ShikkiMCP

@Suite("ToolResult Helpers")
struct ToolResultTests {

    @Test("success result has correct structure")
    func successStructure() {
        let result = ToolResult.success("Operation completed")
        let content = result["content"]?.arrayValue
        #expect(content?.count == 1)
        #expect(content?.first?["type"]?.stringValue == "text")
        #expect(content?.first?["text"]?.stringValue == "Operation completed")
        #expect(result["isError"] == nil)
    }

    @Test("success result with data includes JSON")
    func successWithData() {
        let data: JSONValue = .object(["id": .string("abc-123")])
        let result = ToolResult.success("Saved", data: data)
        let text = result["content"]?.arrayValue?.first?["text"]?.stringValue ?? ""
        #expect(text.contains("Saved"))
        #expect(text.contains("abc-123"))
    }

    @Test("error result has isError flag")
    func errorStructure() {
        let result = ToolResult.error("Something went wrong")
        let content = result["content"]?.arrayValue
        #expect(content?.count == 1)
        #expect(content?.first?["text"]?.stringValue == "Something went wrong")
        #expect(result["isError"] == .bool(true))
    }

    @Test("success result without data has no extra newline")
    func successNoDataNoNewline() {
        let result = ToolResult.success("Done")
        let text = result["content"]?.arrayValue?.first?["text"]?.stringValue ?? ""
        #expect(text == "Done")
    }
}
