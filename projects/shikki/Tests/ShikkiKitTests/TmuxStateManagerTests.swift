import Foundation
import Testing
@testable import ShikkiKit

@Suite("TmuxStateManager — Status Bar State Persistence")
struct TmuxStateManagerTests {

    /// Create a temporary file path for isolated test state.
    private func tempStatePath() -> String {
        let tmp = NSTemporaryDirectory()
        let uuid = UUID().uuidString
        return "\(tmp)shikki-test-tmux-\(uuid).json"
    }

    // MARK: - Default State

    @Test("Default state when file doesn't exist")
    func defaultStateNoFile() {
        let path = tempStatePath()
        let manager = TmuxStateManager(statePath: path)
        #expect(manager.isExpanded == false)
        #expect(manager.arrowStyle == .none)
    }

    // MARK: - Toggle

    @Test("Toggle flips isExpanded from false to true")
    func toggleExpandsFromDefault() {
        let path = tempStatePath()
        let manager = TmuxStateManager(statePath: path)
        #expect(manager.isExpanded == false)
        manager.toggle()
        #expect(manager.isExpanded == true)
    }

    @Test("Double toggle returns to original state")
    func doubleToggle() {
        let path = tempStatePath()
        let manager = TmuxStateManager(statePath: path)
        manager.toggle()
        manager.toggle()
        #expect(manager.isExpanded == false)
    }

    // MARK: - Arrow Style

    @Test("setArrowStyle persists the chosen style")
    func setArrowStyle() {
        let path = tempStatePath()
        let manager = TmuxStateManager(statePath: path)
        manager.setArrowStyle(.left)
        #expect(manager.arrowStyle == .left)
    }

    @Test("Arrow style round-trips through save/load")
    func arrowStylePersistence() {
        let path = tempStatePath()
        let manager1 = TmuxStateManager(statePath: path)
        manager1.setArrowStyle(.both)

        // Create a new manager reading from the same path
        let manager2 = TmuxStateManager(statePath: path)
        #expect(manager2.arrowStyle == .both)
    }

    @Test("All ArrowStyle variants are representable")
    func allArrowStyleVariants() {
        let path = tempStatePath()
        let manager = TmuxStateManager(statePath: path)

        for style in [ArrowStyle.none, .left, .right, .both] {
            manager.setArrowStyle(style)
            #expect(manager.arrowStyle == style)
        }
    }

    // MARK: - Save / Load Round-Trip

    @Test("Save state to JSON file and load it back")
    func saveAndLoadRoundTrip() {
        let path = tempStatePath()
        let manager1 = TmuxStateManager(statePath: path)
        manager1.toggle()  // expanded = true
        manager1.setArrowStyle(.right)

        // New instance reads persisted state
        let manager2 = TmuxStateManager(statePath: path)
        #expect(manager2.isExpanded == true)
        #expect(manager2.arrowStyle == .right)
    }

    @Test("Load from valid JSON file")
    func loadFromValidJSON() {
        let path = tempStatePath()
        let json = #"{"expanded":true,"arrowStyle":"left"}"#
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: path, contents: json.data(using: .utf8)
        )

        let manager = TmuxStateManager(statePath: path)
        #expect(manager.isExpanded == true)
        #expect(manager.arrowStyle == .left)
    }

    @Test("Load from malformed JSON falls back to defaults")
    func loadFromMalformedJSON() {
        let path = tempStatePath()
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: path, contents: "not json".data(using: .utf8)
        )

        let manager = TmuxStateManager(statePath: path)
        #expect(manager.isExpanded == false)
        #expect(manager.arrowStyle == .none)
    }

    @Test("isExpanded persists independently of arrowStyle")
    func independentPersistence() {
        let path = tempStatePath()
        let manager1 = TmuxStateManager(statePath: path)
        manager1.toggle()  // expanded = true

        let manager2 = TmuxStateManager(statePath: path)
        #expect(manager2.isExpanded == true)
        #expect(manager2.arrowStyle == .none)  // unchanged

        manager2.setArrowStyle(.right)

        let manager3 = TmuxStateManager(statePath: path)
        #expect(manager3.isExpanded == true)   // preserved
        #expect(manager3.arrowStyle == .right)
    }
}
