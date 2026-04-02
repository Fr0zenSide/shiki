import Foundation
import Testing
@testable import ShikkiKit

// MARK: - SecurityPatternDetectorTests

@Suite("SecurityPatternDetector — anomaly detection engine")
struct SecurityPatternDetectorTests {

    // MARK: - Helpers

    /// Build N records for a single user with timestamps spread over the last `spanSeconds`.
    private func makeRecords(
        count: Int,
        userId: String = "user-1",
        toolName: String = "memory_search",
        projectSlug: String? = "project-a",
        isMemoryRead: Bool = false,
        spanSeconds: TimeInterval = 60
    ) -> [SecurityEventRecord] {
        let now = Date()
        return (0..<count).map { i in
            SecurityEventRecord(
                userId: userId,
                toolName: toolName,
                projectSlug: projectSlug,
                timestamp: now.addingTimeInterval(-spanSeconds + Double(i)),
                isMemoryRead: isMemoryRead
            )
        }
    }

    /// Record a batch into the detector.
    private func ingest(_ records: [SecurityEventRecord], into detector: SecurityPatternDetector) async {
        for record in records {
            await detector.record(record)
        }
    }

    // MARK: - Recording & Window

    @Test("record appends events to the window")
    func record_appendsToWindow() async {
        let detector = SecurityPatternDetector(config: .testing)
        let records = makeRecords(count: 3)
        await ingest(records, into: detector)
        let size = await detector.windowSize()
        #expect(size == 3)
    }

    @Test("window trims to maxWindowSize")
    func window_trimsToMax() async {
        let config = SecurityDetectorConfig(maxWindowSize: 5)
        let detector = SecurityPatternDetector(config: config)
        let records = makeRecords(count: 10)
        await ingest(records, into: detector)
        let size = await detector.windowSize()
        #expect(size == 5)
    }

    @Test("reset clears window and incidents")
    func reset_clearsEverything() async {
        let detector = SecurityPatternDetector(config: .testing)
        await ingest(makeRecords(count: 6), into: detector)
        _ = await detector.detect()
        let incidentsBefore = await detector.allIncidents()
        #expect(!incidentsBefore.isEmpty)

        await detector.reset()
        let sizeAfter = await detector.windowSize()
        let incidentsAfter = await detector.allIncidents()
        #expect(sizeAfter == 0)
        #expect(incidentsAfter.isEmpty)
    }

    // MARK: - Bulk Extraction

    @Test("detects bulk extraction when threshold exceeded")
    func detectBulkExtraction_triggersAboveThreshold() async {
        let config = SecurityDetectorConfig.testing // threshold = 5
        let detector = SecurityPatternDetector(config: config)
        let records = makeRecords(count: 6, userId: "alice", spanSeconds: 60)
        await ingest(records, into: detector)

        let incidents = await detector.detect()
        let bulkIncidents = incidents.filter { $0.anomaly == .bulkExtraction }
        #expect(bulkIncidents.count == 1)
        #expect(bulkIncidents.first?.userId == "alice")
        #expect(bulkIncidents.first?.action == .blockAndAlert)
    }

    @Test("no bulk extraction below threshold")
    func detectBulkExtraction_doesNotTriggerBelowThreshold() async {
        let config = SecurityDetectorConfig.testing // threshold = 5
        let detector = SecurityPatternDetector(config: config)
        let records = makeRecords(count: 4, userId: "alice", spanSeconds: 60)
        await ingest(records, into: detector)

        let incidents = await detector.detect()
        let bulkIncidents = incidents.filter { $0.anomaly == .bulkExtraction }
        #expect(bulkIncidents.isEmpty)
    }

    @Test("bulk extraction deduplicates within same window")
    func detectBulkExtraction_noDuplicateWithinWindow() async {
        let config = SecurityDetectorConfig.testing
        let detector = SecurityPatternDetector(config: config)
        let records = makeRecords(count: 6, userId: "alice", spanSeconds: 60)
        await ingest(records, into: detector)

        _ = await detector.detect()
        // Add more records and detect again — should not duplicate
        await ingest(makeRecords(count: 3, userId: "alice", spanSeconds: 10), into: detector)
        let second = await detector.detect()
        let bulkInSecond = second.filter { $0.anomaly == .bulkExtraction && $0.userId == "alice" }
        #expect(bulkInSecond.isEmpty)
    }

    @Test("bulk extraction description includes count and threshold")
    func detectBulkExtraction_descriptionContainsCounts() async {
        let config = SecurityDetectorConfig.testing
        let detector = SecurityPatternDetector(config: config)
        await ingest(makeRecords(count: 7, userId: "bob", spanSeconds: 60), into: detector)

        let incidents = await detector.detect()
        let desc = incidents.first { $0.anomaly == .bulkExtraction }?.description ?? ""
        #expect(desc.contains("7"))
        #expect(desc.contains("5"))
    }

    // MARK: - Cross-Project Scan

    @Test("detects cross-project scan when accessing many projects")
    func detectCrossProjectScan_triggersAboveThreshold() async {
        let config = SecurityDetectorConfig.testing // threshold = 3
        let detector = SecurityPatternDetector(config: config)
        let now = Date()
        for i in 0..<4 {
            await detector.record(SecurityEventRecord(
                userId: "eve",
                toolName: "search",
                projectSlug: "project-\(i)",
                timestamp: now.addingTimeInterval(Double(-i))
            ))
        }

        let incidents = await detector.detect()
        let crossProject = incidents.filter { $0.anomaly == .crossProjectScan }
        #expect(crossProject.count == 1)
        #expect(crossProject.first?.userId == "eve")
        #expect(crossProject.first?.action == .alertAndLog)
    }

    @Test("no cross-project scan when below threshold")
    func detectCrossProjectScan_noTriggerBelowThreshold() async {
        let config = SecurityDetectorConfig.testing // threshold = 3
        let detector = SecurityPatternDetector(config: config)
        let now = Date()
        for i in 0..<2 {
            await detector.record(SecurityEventRecord(
                userId: "eve",
                toolName: "search",
                projectSlug: "project-\(i)",
                timestamp: now
            ))
        }

        let incidents = await detector.detect()
        let crossProject = incidents.filter { $0.anomaly == .crossProjectScan }
        #expect(crossProject.isEmpty)
    }

    @Test("cross-project scan description lists project slugs")
    func detectCrossProjectScan_descriptionListsProjects() async {
        let config = SecurityDetectorConfig.testing
        let detector = SecurityPatternDetector(config: config)
        let now = Date()
        for slug in ["alpha", "bravo", "charlie"] {
            await detector.record(SecurityEventRecord(
                userId: "eve",
                toolName: "search",
                projectSlug: slug,
                timestamp: now
            ))
        }

        let incidents = await detector.detect()
        let desc = incidents.first { $0.anomaly == .crossProjectScan }?.description ?? ""
        #expect(desc.contains("alpha"))
        #expect(desc.contains("bravo"))
        #expect(desc.contains("charlie"))
    }

    // MARK: - Off-Hours Access

    @Test("detects off-hours access outside working window")
    func detectOffHoursAccess_triggersOutsideHours() async {
        let config = SecurityDetectorConfig(workingHoursStart: 9, workingHoursEnd: 18)
        let detector = SecurityPatternDetector(config: config)

        // Create a timestamp at 3 AM today
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 3
        components.minute = 0
        let offHoursDate = calendar.date(from: components)!

        await detector.record(SecurityEventRecord(
            userId: "nightowl",
            toolName: "search",
            projectSlug: "proj",
            timestamp: offHoursDate
        ))

        let incidents = await detector.detect()
        let offHours = incidents.filter { $0.anomaly == .offHoursAccess }
        #expect(offHours.count == 1)
        #expect(offHours.first?.userId == "nightowl")
        #expect(offHours.first?.action == .logOnly)
    }

    @Test("no off-hours detection during working hours")
    func detectOffHoursAccess_noTriggerDuringWorkingHours() async {
        let config = SecurityDetectorConfig(workingHoursStart: 9, workingHoursEnd: 18)
        let detector = SecurityPatternDetector(config: config)

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 12
        components.minute = 0
        let workingHoursDate = calendar.date(from: components)!

        await detector.record(SecurityEventRecord(
            userId: "daytime",
            toolName: "search",
            projectSlug: "proj",
            timestamp: workingHoursDate
        ))

        let incidents = await detector.detect()
        let offHours = incidents.filter { $0.anomaly == .offHoursAccess }
        #expect(offHours.isEmpty)
    }

    @Test("off-hours deduplicates per user per day")
    func detectOffHoursAccess_deduplicatesPerUserPerDay() async {
        let config = SecurityDetectorConfig(workingHoursStart: 9, workingHoursEnd: 18)
        let detector = SecurityPatternDetector(config: config)

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 2
        let ts1 = calendar.date(from: components)!
        components.hour = 4
        let ts2 = calendar.date(from: components)!

        await detector.record(SecurityEventRecord(userId: "owl", toolName: "search", timestamp: ts1))
        await detector.record(SecurityEventRecord(userId: "owl", toolName: "search", timestamp: ts2))

        let incidents = await detector.detect()
        let offHours = incidents.filter { $0.anomaly == .offHoursAccess && $0.userId == "owl" }
        #expect(offHours.count == 1)
    }

    // MARK: - Export Pattern

    @Test("detects export pattern with many memory reads")
    func detectExportPattern_triggersAboveThreshold() async {
        let config = SecurityDetectorConfig.testing // threshold = 5
        let detector = SecurityPatternDetector(config: config)
        let records = makeRecords(
            count: 6,
            userId: "exporter",
            projectSlug: "secret-project",
            isMemoryRead: true,
            spanSeconds: 60
        )
        await ingest(records, into: detector)

        let incidents = await detector.detect()
        let exports = incidents.filter { $0.anomaly == .exportPattern }
        #expect(exports.count == 1)
        #expect(exports.first?.action == .throttleAndAlert)
    }

    @Test("no export pattern for non-memory reads")
    func detectExportPattern_ignoresNonMemoryReads() async {
        let config = SecurityDetectorConfig.testing
        let detector = SecurityPatternDetector(config: config)
        let records = makeRecords(
            count: 10,
            userId: "exporter",
            projectSlug: "project",
            isMemoryRead: false,
            spanSeconds: 60
        )
        await ingest(records, into: detector)

        let incidents = await detector.detect()
        let exports = incidents.filter { $0.anomaly == .exportPattern }
        #expect(exports.isEmpty)
    }

    @Test("no export pattern below threshold")
    func detectExportPattern_noTriggerBelowThreshold() async {
        let config = SecurityDetectorConfig.testing // threshold = 5
        let detector = SecurityPatternDetector(config: config)
        let records = makeRecords(
            count: 3,
            userId: "reader",
            projectSlug: "project",
            isMemoryRead: true,
            spanSeconds: 60
        )
        await ingest(records, into: detector)

        let incidents = await detector.detect()
        let exports = incidents.filter { $0.anomaly == .exportPattern }
        #expect(exports.isEmpty)
    }

    // MARK: - Burnout Signal

    @Test("detects burnout signal for long continuous sessions")
    func detectBurnoutSignal_triggersAboveThreshold() async {
        let config = SecurityDetectorConfig.testing // threshold = 3600 (1h)
        let detector = SecurityPatternDetector(config: config)
        let now = Date()

        // Two events 2 hours apart
        await detector.record(SecurityEventRecord(
            userId: "workaholic",
            toolName: "search",
            timestamp: now.addingTimeInterval(-7200) // 2h ago
        ))
        await detector.record(SecurityEventRecord(
            userId: "workaholic",
            toolName: "search",
            timestamp: now
        ))

        let incidents = await detector.detect()
        let burnout = incidents.filter { $0.anomaly == .burnoutSignal }
        #expect(burnout.count == 1)
        #expect(burnout.first?.userId == "workaholic")
        #expect(burnout.first?.action == .logOnly)
    }

    @Test("no burnout signal for short sessions")
    func detectBurnoutSignal_noTriggerForShortSession() async {
        let config = SecurityDetectorConfig.testing // threshold = 3600 (1h)
        let detector = SecurityPatternDetector(config: config)
        let now = Date()

        // Two events 30 minutes apart — below 1h threshold
        await detector.record(SecurityEventRecord(
            userId: "normal",
            toolName: "search",
            timestamp: now.addingTimeInterval(-1800)
        ))
        await detector.record(SecurityEventRecord(
            userId: "normal",
            toolName: "search",
            timestamp: now
        ))

        let incidents = await detector.detect()
        let burnout = incidents.filter { $0.anomaly == .burnoutSignal }
        #expect(burnout.isEmpty)
    }

    @Test("burnout description includes hours and threshold")
    func detectBurnoutSignal_descriptionIncludesHours() async {
        let config = SecurityDetectorConfig.testing
        let detector = SecurityPatternDetector(config: config)
        let now = Date()

        await detector.record(SecurityEventRecord(userId: "worker", toolName: "t", timestamp: now.addingTimeInterval(-7200)))
        await detector.record(SecurityEventRecord(userId: "worker", toolName: "t", timestamp: now))

        let incidents = await detector.detect()
        let desc = incidents.first { $0.anomaly == .burnoutSignal }?.description ?? ""
        #expect(desc.contains("2h"))
        #expect(desc.contains("1h"))
    }

    // MARK: - Knowledge Hoarding

    @Test("detects knowledge hoarding when single user dominates")
    func detectKnowledgeHoarding_triggersOnDominantUser() async {
        let config = SecurityDetectorConfig.testing // ratio 0.8, minQueries 5
        let detector = SecurityPatternDetector(config: config)
        let now = Date()

        // "hoarder" makes 9 queries, "other" makes 1 → 90% ratio
        for i in 0..<9 {
            await detector.record(SecurityEventRecord(
                userId: "hoarder",
                toolName: "search",
                projectSlug: "shared-proj",
                timestamp: now.addingTimeInterval(Double(-i))
            ))
        }
        await detector.record(SecurityEventRecord(
            userId: "other",
            toolName: "search",
            projectSlug: "shared-proj",
            timestamp: now
        ))

        let incidents = await detector.detect()
        let hoarding = incidents.filter { $0.anomaly == .knowledgeHoarding }
        #expect(hoarding.count == 1)
        #expect(hoarding.first?.userId == "hoarder")
        #expect(hoarding.first?.action == .alertAndLog)
    }

    @Test("no knowledge hoarding when queries evenly distributed")
    func detectKnowledgeHoarding_noTriggerWhenBalanced() async {
        let config = SecurityDetectorConfig.testing
        let detector = SecurityPatternDetector(config: config)
        let now = Date()

        // 3 users, 3 queries each → 33% each, below 80% threshold
        for user in ["a", "b", "c"] {
            for i in 0..<3 {
                await detector.record(SecurityEventRecord(
                    userId: user,
                    toolName: "search",
                    projectSlug: "team-proj",
                    timestamp: now.addingTimeInterval(Double(-i))
                ))
            }
        }

        let incidents = await detector.detect()
        let hoarding = incidents.filter { $0.anomaly == .knowledgeHoarding }
        #expect(hoarding.isEmpty)
    }

    @Test("no knowledge hoarding below minimum queries")
    func detectKnowledgeHoarding_noTriggerBelowMinQueries() async {
        let config = SecurityDetectorConfig.testing // minQueries = 5
        let detector = SecurityPatternDetector(config: config)
        let now = Date()

        // Only 3 total queries from one user — below minQueries=5
        for i in 0..<3 {
            await detector.record(SecurityEventRecord(
                userId: "solo",
                toolName: "search",
                projectSlug: "tiny-proj",
                timestamp: now.addingTimeInterval(Double(-i))
            ))
        }

        let incidents = await detector.detect()
        let hoarding = incidents.filter { $0.anomaly == .knowledgeHoarding }
        #expect(hoarding.isEmpty)
    }

    // MARK: - Safe Code / No False Positives

    @Test("normal activity produces zero incidents")
    func normalActivity_producesNoIncidents() async {
        let config = SecurityDetectorConfig.testing
        let detector = SecurityPatternDetector(config: config)

        // Build a "normal" working day: few queries, one project, working hours
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 14

        for i in 0..<3 {
            components.minute = i * 15
            let ts = calendar.date(from: components)!
            await detector.record(SecurityEventRecord(
                userId: "normal-user",
                toolName: "search",
                projectSlug: "my-project",
                timestamp: ts
            ))
        }

        let incidents = await detector.detect()
        #expect(incidents.isEmpty)
    }

    @Test("multiple users in separate projects produce no cross-project scan")
    func multipleUsers_separateProjects_noIncidents() async {
        let config = SecurityDetectorConfig.testing
        let detector = SecurityPatternDetector(config: config)
        let now = Date()

        // Different users in different projects — no single user hits threshold
        await detector.record(SecurityEventRecord(userId: "alice", toolName: "search", projectSlug: "proj-a", timestamp: now))
        await detector.record(SecurityEventRecord(userId: "bob", toolName: "search", projectSlug: "proj-b", timestamp: now))
        await detector.record(SecurityEventRecord(userId: "charlie", toolName: "search", projectSlug: "proj-c", timestamp: now))

        let incidents = await detector.detect()
        let crossProject = incidents.filter { $0.anomaly == .crossProjectScan }
        #expect(crossProject.isEmpty)
    }

    // MARK: - Callback

    @Test("onIncidentDetected callback fires for each new incident")
    func callback_firesOnDetection() async {
        let config = SecurityDetectorConfig.testing
        let detector = SecurityPatternDetector(config: config)

        nonisolated(unsafe) var callbackIncidents: [SecurityIncident] = []
        await detector.setOnIncidentDetected { incident in
            callbackIncidents.append(incident)
        }

        await ingest(makeRecords(count: 6, userId: "alice"), into: detector)
        _ = await detector.detect()

        #expect(!callbackIncidents.isEmpty)
        #expect(callbackIncidents.first?.anomaly == .bulkExtraction)
    }

    // MARK: - SecurityPolicyMap

    @Test("policy map returns correct actions for each anomaly")
    func policyMap_correctActions() {
        #expect(SecurityPolicyMap.action(for: .bulkExtraction) == .blockAndAlert)
        #expect(SecurityPolicyMap.action(for: .crossProjectScan) == .alertAndLog)
        #expect(SecurityPolicyMap.action(for: .offHoursAccess) == .logOnly)
        #expect(SecurityPolicyMap.action(for: .exportPattern) == .throttleAndAlert)
        #expect(SecurityPolicyMap.action(for: .burnoutSignal) == .logOnly)
        #expect(SecurityPolicyMap.action(for: .knowledgeHoarding) == .alertAndLog)
    }

    // MARK: - SecurityDetectorConfig

    @Test("default config has production thresholds")
    func defaultConfig_hasProductionValues() {
        let config = SecurityDetectorConfig.default
        #expect(config.maxWindowSize == 1000)
        #expect(config.bulkExtractionThreshold == 100)
        #expect(config.crossProjectThreshold == 5)
        #expect(config.burnoutThresholdSeconds == 57600)
    }

    @Test("testing config has lower thresholds")
    func testingConfig_hasLowerValues() {
        let config = SecurityDetectorConfig.testing
        #expect(config.maxWindowSize == 100)
        #expect(config.bulkExtractionThreshold == 5)
        #expect(config.crossProjectThreshold == 3)
        #expect(config.burnoutThresholdSeconds == 3600)
    }

    // MARK: - allIncidents persistence

    @Test("allIncidents accumulates across multiple detect() calls")
    func allIncidents_accumulatesAcrossCalls() async {
        let config = SecurityDetectorConfig.testing
        let detector = SecurityPatternDetector(config: config)

        // First detection: bulk extraction
        await ingest(makeRecords(count: 6, userId: "alice"), into: detector)
        _ = await detector.detect()

        // Second detection: burnout (different pattern)
        let now = Date()
        await detector.record(SecurityEventRecord(
            userId: "bob",
            toolName: "search",
            timestamp: now.addingTimeInterval(-7200)
        ))
        await detector.record(SecurityEventRecord(
            userId: "bob",
            toolName: "search",
            timestamp: now
        ))
        _ = await detector.detect()

        let all = await detector.allIncidents()
        let anomalyTypes = Set(all.map(\.anomaly))
        #expect(anomalyTypes.contains(.bulkExtraction))
        #expect(anomalyTypes.contains(.burnoutSignal))
    }

    // MARK: - SecurityEventRecord

    @Test("SecurityEventRecord defaults are correct")
    func eventRecord_defaults() {
        let record = SecurityEventRecord(userId: "test", toolName: "search")
        #expect(record.userId == "test")
        #expect(record.toolName == "search")
        #expect(record.projectSlug == nil)
        #expect(record.isMemoryRead == false)
    }
}
