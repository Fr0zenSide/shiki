import Testing
import Foundation
@testable import ShikkiKit

@Suite("BacklogCommand — argument parsing and model decoding")
struct BacklogCommandTests {

    @Test("BacklogItem decodes from snake_case JSON")
    func decodeBacklogItem() throws {
        let json = """
        {
            "id": "b1234-5678",
            "company_id": "comp-1",
            "title": "Add animation system",
            "description": "Skeletal animation for Maya",
            "source_type": "manual",
            "source_ref": "session:abc123",
            "status": "raw",
            "priority": 10,
            "sort_order": 0,
            "enrichment_notes": null,
            "kill_reason": null,
            "tags": ["perf", "ux"],
            "parent_id": null,
            "promoted_to_task_id": null,
            "created_at": "2026-03-23T10:00:00Z",
            "updated_at": "2026-03-23T10:00:00Z",
            "metadata": {}
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(BacklogItem.self, from: json)
        #expect(item.id == "b1234-5678")
        #expect(item.companyId == "comp-1")
        #expect(item.title == "Add animation system")
        #expect(item.sourceType == .manual)
        #expect(item.status == .raw)
        #expect(item.priority == 10)
        #expect(item.tags == ["perf", "ux"])
        #expect(item.enrichmentNotes == nil)
        #expect(item.killReason == nil)
    }

    @Test("BacklogItem decodes with nullable company_id and stringified metadata")
    func decodeBacklogItemNullableFields() throws {
        let json = """
        {
            "id": "b-null",
            "company_id": null,
            "title": "Cross-company idea",
            "description": null,
            "source_type": "push",
            "source_ref": null,
            "status": "enriched",
            "priority": 50,
            "sort_order": -1,
            "enrichment_notes": "Added RFC link",
            "kill_reason": null,
            "tags": [],
            "parent_id": null,
            "promoted_to_task_id": null,
            "created_at": "2026-03-23T10:00:00Z",
            "updated_at": "2026-03-23T11:00:00Z",
            "metadata": "{\\"key\\": \\"value\\"}"
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(BacklogItem.self, from: json)
        #expect(item.companyId == nil)
        #expect(item.sourceType == .push)
        #expect(item.status == .enriched)
        #expect(item.sortOrder == -1)
        #expect(item.enrichmentNotes == "Added RFC link")
        #expect(item.metadata["key"]?.description == "value")
    }

    @Test("BacklogItem decodes killed item with kill_reason")
    func decodeKilledItem() throws {
        let json = """
        {
            "id": "b-killed",
            "company_id": "comp-2",
            "title": "Deprecated idea",
            "description": null,
            "source_type": "agent",
            "source_ref": null,
            "status": "killed",
            "priority": 50,
            "sort_order": 0,
            "enrichment_notes": "Was enriched before kill",
            "kill_reason": "Duplicate of #42",
            "tags": ["deprecated"],
            "parent_id": "b-parent",
            "promoted_to_task_id": null,
            "created_at": "2026-03-23T10:00:00Z",
            "updated_at": "2026-03-23T12:00:00Z",
            "metadata": {}
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(BacklogItem.self, from: json)
        #expect(item.status == .killed)
        #expect(item.killReason == "Duplicate of #42")
        #expect(item.parentId == "b-parent")
        #expect(item.sourceType == .agent)
    }
}
