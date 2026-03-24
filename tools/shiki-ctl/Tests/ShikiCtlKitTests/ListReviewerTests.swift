import Testing
@testable import ShikiCtlKit

@Suite("ListReviewer")
struct ListReviewerTests {

    // MARK: - Helpers

    private let defaultConfig = ListReviewerConfig(
        title: "Test List",
        showProgress: true
    )

    private func sampleItems() -> [ListItem] {
        [
            ListItem(id: "1", title: "PR #27: README overhaul", status: .validated),
            ListItem(id: "2", title: "PR #28: Fix heartbeat", subtitle: "Interval was too short", status: .inReview),
            ListItem(id: "3", title: "PR #29: Add ShikiCore", status: .pending),
            ListItem(id: "4", title: "PR #30: Remove dead code", status: .rejected),
            ListItem(id: "5", title: "PR #31: Unused experiment", status: .killed),
            ListItem(id: "6", title: "PR #32: Correct config path", status: .corrected),
        ]
    }

    // MARK: - Empty List

    @Test("Render with empty list shows 'No items'")
    func renderEmptyList() {
        let output = ListReviewer.renderToString(items: [], config: defaultConfig)
        let plain = stripANSI(output)

        #expect(plain.contains("Test List"))
        #expect(plain.contains("No items."))
        #expect(!plain.contains("reviewed"))
    }

    // MARK: - Item Rendering

    @Test("Render items shows numbered list with status indicators")
    func renderItemList() {
        let items = sampleItems()
        let output = ListReviewer.renderToString(items: items, config: defaultConfig)
        let plain = stripANSI(output)

        // Title present
        #expect(plain.contains("Test List"))

        // Numbered entries
        #expect(plain.contains("[ 1] \u{2713} PR #27: README overhaul (validated)"))
        #expect(plain.contains("[ 2] \u{25D0} PR #28: Fix heartbeat (inReview)"))
        #expect(plain.contains("[ 3] \u{25CB} PR #29: Add ShikiCore (pending)"))
        #expect(plain.contains("[ 4] \u{2717} PR #30: Remove dead code (rejected)"))
        #expect(plain.contains("[ 5] \u{2298} PR #31: Unused experiment (killed)"))
        #expect(plain.contains("[ 6] \u{2713} PR #32: Correct config path (corrected)"))
    }

    @Test("Subtitle is rendered below the item, indented")
    func renderSubtitle() {
        let items = sampleItems()
        let output = ListReviewer.renderToString(items: items, config: defaultConfig)
        let plain = stripANSI(output)

        #expect(plain.contains("      Interval was too short"))
    }

    // MARK: - Status Indicators

    @Test("Each status has the correct indicator")
    func statusIndicators() {
        #expect(ListItem.ItemStatus.pending.indicator == "\u{25CB}")
        #expect(ListItem.ItemStatus.inReview.indicator == "\u{25D0}")
        #expect(ListItem.ItemStatus.validated.indicator == "\u{2713}")
        #expect(ListItem.ItemStatus.corrected.indicator == "\u{2713}")
        #expect(ListItem.ItemStatus.rejected.indicator == "\u{2717}")
        #expect(ListItem.ItemStatus.killed.indicator == "\u{2298}")
    }

    @Test("Reviewed status classification is correct")
    func reviewedStatuses() {
        #expect(!ListItem.ItemStatus.pending.isReviewed)
        #expect(!ListItem.ItemStatus.inReview.isReviewed)
        #expect(ListItem.ItemStatus.validated.isReviewed)
        #expect(ListItem.ItemStatus.corrected.isReviewed)
        #expect(ListItem.ItemStatus.rejected.isReviewed)
        #expect(ListItem.ItemStatus.killed.isReviewed)
    }

    // MARK: - Progress Bar

    @Test("Progress bar with zero total")
    func progressBarZeroTotal() {
        let bar = ListReviewer.progressBar(done: 0, total: 0, width: 10)
        let plain = stripANSI(bar)
        #expect(plain.contains("0 of 0 reviewed"))
    }

    @Test("Progress bar at 50%")
    func progressBarHalf() {
        let bar = ListReviewer.progressBar(done: 4, total: 8, width: 20)
        let plain = stripANSI(bar)
        #expect(plain.contains("4 of 8 reviewed"))
        // 10 filled + 10 empty = 20 chars of bar
        let barChars = plain.prefix(20)
        let filledCount = barChars.filter { $0 == "\u{2588}" }.count
        let emptyCount = barChars.filter { $0 == "\u{2591}" }.count
        #expect(filledCount == 10)
        #expect(emptyCount == 10)
    }

    @Test("Progress bar at 100%")
    func progressBarFull() {
        let bar = ListReviewer.progressBar(done: 5, total: 5, width: 10)
        let plain = stripANSI(bar)
        #expect(plain.contains("5 of 5 reviewed"))
        let barChars = plain.prefix(10)
        let filledCount = barChars.filter { $0 == "\u{2588}" }.count
        #expect(filledCount == 10)
    }

    @Test("Progress bar clamps done to total")
    func progressBarClamp() {
        let bar = ListReviewer.progressBar(done: 15, total: 5, width: 10)
        let plain = stripANSI(bar)
        #expect(plain.contains("5 of 5 reviewed"))
    }

    @Test("Progress bar clamps negative done to zero")
    func progressBarClampNegative() {
        let bar = ListReviewer.progressBar(done: -3, total: 5, width: 10)
        let plain = stripANSI(bar)
        #expect(plain.contains("0 of 5 reviewed"))
    }

    @Test("Render includes progress line when showProgress is true")
    func renderWithProgress() {
        let items = sampleItems()
        let output = ListReviewer.renderToString(items: items, config: defaultConfig)
        let plain = stripANSI(output)

        // 4 reviewed: validated, corrected, rejected, killed
        #expect(plain.contains("4 of 6 reviewed"))
    }

    @Test("Render omits progress line when showProgress is false")
    func renderWithoutProgress() {
        let config = ListReviewerConfig(title: "No Progress", showProgress: false)
        let items = sampleItems()
        let output = ListReviewer.renderToString(items: items, config: config)
        let plain = stripANSI(output)

        #expect(!plain.contains("reviewed"))
    }

    // MARK: - Action Filtering

    @Test("Actions filter correctly by status")
    func actionFilteringByStatus() {
        let config = defaultConfig
        let pendingActions = config.availableActions(for: .pending)
        let validatedActions = config.availableActions(for: .validated)

        // Pending should have: approve, kill, enrich, defer, next, quit
        let pendingKeys = Set(pendingActions.map(\.key))
        #expect(pendingKeys.contains("a"))  // approve
        #expect(pendingKeys.contains("k"))  // kill
        #expect(pendingKeys.contains("e"))  // enrich
        #expect(pendingKeys.contains("d"))  // defer
        #expect(pendingKeys.contains("n"))  // next
        #expect(pendingKeys.contains("q"))  // quit

        // Validated should only have: next, quit (universal actions)
        let validatedKeys = Set(validatedActions.map(\.key))
        #expect(!validatedKeys.contains("a"))
        #expect(!validatedKeys.contains("k"))
        #expect(validatedKeys.contains("n"))
        #expect(validatedKeys.contains("q"))
    }

    @Test("Action legend appears in list render")
    func actionLegendInRender() {
        let items = [ListItem(id: "1", title: "Item", status: .pending)]
        let output = ListReviewer.renderToString(items: items, config: defaultConfig)
        let plain = stripANSI(output)

        #expect(plain.contains("[a]pprove"))
        #expect(plain.contains("[k]ill"))
        #expect(plain.contains("[q]uit"))
    }

    // MARK: - Detail View

    @Test("Detail view renders item header with status")
    func detailViewHeader() {
        let item = ListItem(
            id: "42",
            title: "PR #42: Big feature",
            subtitle: "This adds the new module",
            status: .inReview,
            metadata: ["author": "jeoffrey", "branch": "feature/big"]
        )
        let output = ListReviewer.renderDetailToString(item: item, config: defaultConfig)
        let plain = stripANSI(output)

        #expect(plain.contains("\u{25D0} PR #42: Big feature"))
        #expect(plain.contains("Status: inReview"))
        #expect(plain.contains("This adds the new module"))
        #expect(plain.contains("author: jeoffrey"))
        #expect(plain.contains("branch: feature/big"))
    }

    @Test("Detail view shows only applicable actions")
    func detailViewActions() {
        let validatedItem = ListItem(id: "1", title: "Done item", status: .validated)
        let output = ListReviewer.renderDetailToString(item: validatedItem, config: defaultConfig)
        let plain = stripANSI(output)

        // Validated should not show approve/kill/enrich/defer
        #expect(!plain.contains("[a]pprove"))
        #expect(!plain.contains("[k]ill"))
        #expect(plain.contains("[n]ext"))
        #expect(plain.contains("[q]uit"))
    }

    @Test("Detail view with no metadata skips metadata section")
    func detailViewNoMetadata() {
        let item = ListItem(id: "1", title: "Simple", status: .pending)
        let output = ListReviewer.renderDetailToString(item: item, config: defaultConfig)
        let plain = stripANSI(output)

        // Should have title and status but no stray colons from metadata
        #expect(plain.contains("Simple"))
        #expect(plain.contains("Status: pending"))
    }

    // MARK: - ANSIStyle

    @Test("styled() applies ANSI codes and resets")
    func styledAppliesCodes() {
        let result = styled("hello", .bold, .green)
        #expect(result.hasPrefix(ANSI.bold + ANSI.green))
        #expect(result.hasSuffix(ANSI.reset))
        #expect(result.contains("hello"))
    }

    @Test("styled() with no styles returns plain text")
    func styledNoStyles() {
        let result = styled("plain")
        #expect(result == "plain")
    }

    @Test("stripANSI removes all escape sequences")
    func stripANSITest() {
        let colored = "\u{1B}[1m\u{1B}[32mhello\u{1B}[0m world"
        #expect(stripANSI(colored) == "hello world")
    }

    // MARK: - ListItem Equatable

    @Test("ListItem equality")
    func listItemEquality() {
        let a = ListItem(id: "1", title: "A", status: .pending)
        let b = ListItem(id: "1", title: "A", status: .pending)
        let c = ListItem(id: "2", title: "A", status: .pending)
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - Custom Config

    @Test("Custom actions are rendered in legend")
    func customActions() {
        let config = ListReviewerConfig(
            title: "Custom",
            showProgress: false,
            actions: [
                .init(key: "x", label: "execute", appliesTo: [.pending]),
                .init(key: "s", label: "skip", appliesTo: Set(ListItem.ItemStatus.allCases)),
            ]
        )
        let items = [ListItem(id: "1", title: "Task", status: .pending)]
        let output = ListReviewer.renderToString(items: items, config: config)
        let plain = stripANSI(output)

        #expect(plain.contains("[x]xecute"))
        #expect(plain.contains("[s]kip"))
    }
}
