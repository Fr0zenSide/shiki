import Testing
import Foundation
@testable import ShikiKit

@Suite("Ingest/Radar/Pipeline DTOs")
struct IngestRadarPipelineDTOTests {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - IngestRequestInput

    @Test("IngestRequestInput round-trips through JSON")
    func test_ingestRequestDTO_roundTrips() throws {
        let input = IngestRequestInput(
            projectId: UUID(),
            sourceType: .githubRepo,
            sourceUri: "https://github.com/example/repo",
            displayName: "Example Repo",
            chunks: [
                IngestChunk(content: "Some content", category: "code", filePath: "src/main.swift"),
                IngestChunk(content: "More content", importance: 5.0, chunkIndex: 1),
            ]
        )

        let data = try Self.encoder.encode(input)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"source_type\""))
        #expect(json.contains("\"source_uri\""))
        #expect(json.contains("\"display_name\""))
        #expect(json.contains("\"file_path\""))
        #expect(json.contains("\"chunk_index\""))
        #expect(json.contains("\"dedup_threshold\""))

        let decoded = try Self.decoder.decode(IngestRequestInput.self, from: data)
        #expect(decoded.sourceType == .githubRepo)
        #expect(decoded.chunks.count == 2)
        #expect(decoded.config.dedupThreshold == 0.92)
    }

    @Test("IngestRequestInput rejects empty chunks")
    func test_ingestRequestInput_rejectsEmptyChunks() {
        let input = IngestRequestInput(
            projectId: UUID(),
            sourceType: .rawText,
            sourceUri: "inline",
            chunks: []
        )
        #expect(throws: ShikiValidationError.self) {
            try input.validate()
        }
    }

    @Test("IngestChunk validates content")
    func test_ingestChunk_validatesContent() {
        let chunk = IngestChunk(content: "")
        #expect(throws: ShikiValidationError.self) {
            try chunk.validate()
        }
    }

    // MARK: - RadarWatchItemDTO

    @Test("RadarWatchItemDTO round-trips through JSON")
    func test_radarWatchItemDTO_roundTrips() throws {
        let item = RadarWatchItemDTO(
            id: UUID(),
            slug: "vapor",
            kind: .dependency,
            name: "Vapor",
            sourceUrl: "https://github.com/vapor/vapor",
            relevance: "Core web framework for ShikiServer",
            tags: ["swift", "server-side"]
        )

        let data = try Self.encoder.encode(item)
        let decoded = try Self.decoder.decode(RadarWatchItemDTO.self, from: data)

        #expect(decoded.slug == "vapor")
        #expect(decoded.kind == .dependency)
        #expect(decoded.tags == ["swift", "server-side"])
        #expect(decoded.enabled == true)
    }

    @Test("RadarWatchItemInput validates required fields")
    func test_radarWatchItemInput_validates() {
        let invalid = RadarWatchItemInput(slug: "", kind: .repo, name: "Test")
        #expect(throws: ShikiValidationError.self) {
            try invalid.validate()
        }
    }

    @Test("RadarScanTriggerInput rejects out-of-range sinceDays")
    func test_radarScanTriggerInput_rejectsOutOfRange() {
        let invalid = RadarScanTriggerInput(sinceDays: 0)
        #expect(throws: ShikiValidationError.self) {
            try invalid.validate()
        }

        let tooHigh = RadarScanTriggerInput(sinceDays: 400)
        #expect(throws: ShikiValidationError.self) {
            try tooHigh.validate()
        }
    }

    // MARK: - PipelineRunDTO

    @Test("PipelineRunDTO round-trips through JSON")
    func test_pipelineRunDTO_roundTrips() throws {
        let run = PipelineRunDTO(
            id: UUID(),
            pipelineType: .mdFeature,
            projectId: UUID(),
            status: .running,
            currentPhase: "synthesis",
            state: ["phase": .int(3)]
        )

        let data = try Self.encoder.encode(run)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"pipeline_type\""))
        #expect(json.contains("\"md-feature\""))
        #expect(json.contains("\"current_phase\""))

        let decoded = try Self.decoder.decode(PipelineRunDTO.self, from: data)
        #expect(decoded.pipelineType == .mdFeature)
        #expect(decoded.status == .running)
        #expect(decoded.currentPhase == "synthesis")
    }

    @Test("PipelineRunCreateInput validates enum values via decode")
    func test_pipelineRunCreate_validatesEnumValues() throws {
        // Valid pipeline type decodes
        let validJSON = """
        {
            "pipeline_type": "pre-pr",
            "config": {},
            "initial_state": {},
            "metadata": {}
        }
        """
        let decoded = try Self.decoder.decode(PipelineRunCreateInput.self, from: Data(validJSON.utf8))
        #expect(decoded.pipelineType == .prePr)

        // Invalid pipeline type fails to decode
        let invalidJSON = """
        { "pipeline_type": "invalid_type", "config": {}, "initial_state": {}, "metadata": {} }
        """
        #expect(throws: DecodingError.self) {
            _ = try Self.decoder.decode(PipelineRunCreateInput.self, from: Data(invalidJSON.utf8))
        }
    }

    // MARK: - PipelineCheckpointInput

    @Test("PipelineCheckpointInput validates phase and phaseIndex")
    func test_pipelineCheckpointInput_validates() {
        let invalidPhase = PipelineCheckpointInput(phase: "", phaseIndex: 0)
        #expect(throws: ShikiValidationError.self) {
            try invalidPhase.validate()
        }

        let invalidIndex = PipelineCheckpointInput(phase: "test", phaseIndex: -1)
        #expect(throws: ShikiValidationError.self) {
            try invalidIndex.validate()
        }
    }

    // MARK: - PipelineRoutingRuleInput

    @Test("PipelineRoutingRuleInput round-trips and validates")
    func test_pipelineRoutingRuleInput_roundTripsAndValidates() throws {
        let rule = PipelineRoutingRuleInput(
            pipelineType: "md-feature",
            sourcePhase: "synthesis",
            condition: .onFailure,
            targetAction: "retry_phase",
            priority: 10
        )

        try rule.validate()

        let data = try Self.encoder.encode(rule)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"on_failure\""))
        #expect(json.contains("\"source_phase\""))
        #expect(json.contains("\"target_action\""))

        let decoded = try Self.decoder.decode(PipelineRoutingRuleInput.self, from: data)
        #expect(decoded.condition == .onFailure)
        #expect(decoded.priority == 10)
    }

    @Test("PipelineRoutingRuleInput rejects invalid priority")
    func test_pipelineRoutingRuleInput_rejectsInvalidPriority() {
        let invalid = PipelineRoutingRuleInput(
            pipelineType: "quick",
            sourcePhase: "test",
            condition: .always,
            targetAction: "skip",
            priority: 101
        )
        #expect(throws: ShikiValidationError.self) {
            try invalid.validate()
        }
    }
}
