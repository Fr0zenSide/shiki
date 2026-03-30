import Foundation
import Testing
@testable import ShikkiKit

@Suite("ShikiNode — Unified node model")
struct ShikiNodeTests {

    @Test("GenericNode stores all properties")
    func genericNodeProperties() {
        let node = GenericNode(
            id: "session:maya",
            nodeType: .session,
            title: "maya:spm-wave3",
            subtitle: "working",
            icon: "*",
            parentId: "company:maya",
            relations: ["priority": "high"]
        )
        #expect(node.id == "session:maya")
        #expect(node.nodeType == .session)
        #expect(node.title == "maya:spm-wave3")
        #expect(node.subtitle == "working")
        #expect(node.icon == "*")
        #expect(node.parentId == "company:maya")
        #expect(node.relations["priority"] == "high")
    }

    @Test("GenericNode equality")
    func genericNodeEquality() {
        let date = Date(timeIntervalSince1970: 1000)
        let a = GenericNode(id: "test", nodeType: .task, title: "Task A", createdAt: date)
        let b = GenericNode(id: "test", nodeType: .task, title: "Task A", createdAt: date)
        #expect(a == b)
    }

    @Test("NodeType covers all entity types")
    func nodeTypeCoverage() {
        let allTypes = NodeType.allCases
        #expect(allTypes.count == 12)
        #expect(allTypes.contains(.session))
        #expect(allTypes.contains(.command))
        #expect(allTypes.contains(.branch))
    }

    @Test("PaletteResult from ShikiNode preserves data")
    func paletteResultFromNode() {
        let node = GenericNode(
            id: "feature:auth",
            nodeType: .feature,
            title: "auth-flow",
            subtitle: "Authentication specification",
            icon: "#"
        )
        let result = PaletteResult(node: node, score: 5)
        #expect(result.id == "feature:auth")
        #expect(result.title == "auth-flow")
        #expect(result.subtitle == "Authentication specification")
        #expect(result.category == "feature")
        #expect(result.icon == "#")
        #expect(result.score == 5)
    }

    @Test("NodeType raw values are stable for Codable")
    func nodeTypeRawValues() {
        #expect(NodeType.session.rawValue == "session")
        #expect(NodeType.decision.rawValue == "decision")
        #expect(NodeType.pr.rawValue == "pr")
        #expect(NodeType.memory.rawValue == "memory")
    }
}
