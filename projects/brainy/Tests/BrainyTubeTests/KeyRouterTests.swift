import AppKit
@testable import BrainyTubeKit
import Testing

@Suite("KeyRouter")
@MainActor
struct KeyRouterTests {

    // MARK: - Grid Mode

    @Test("Grid mode: right arrow moves to next cell")
    func gridModeArrowRightMovesCell() {
        let router = KeyRouter()
        router.mode = .grid(selectedCell: 0)
        router.gridSelectedCell = 0
        router.gridCellCount = 9
        router.gridColumns = 3

        var selectedCell: Int?
        router.onGridCellSelect = { cell in selectedCell = cell }

        let handled = router.handleKeyDown(keyCode: KeyCode.rightArrow, modifierFlags: [])

        #expect(handled == true)
        #expect(router.gridSelectedCell == 1)
        #expect(selectedCell == 1)
    }

    @Test("Grid mode: left arrow moves to previous cell")
    func gridModeArrowLeftMovesCell() {
        let router = KeyRouter()
        router.mode = .grid(selectedCell: 2)
        router.gridSelectedCell = 2
        router.gridCellCount = 9
        router.gridColumns = 3

        let handled = router.handleKeyDown(keyCode: KeyCode.leftArrow, modifierFlags: [])

        #expect(handled == true)
        #expect(router.gridSelectedCell == 1)
    }

    @Test("Grid mode: down arrow moves to next row")
    func gridModeArrowDownMovesToNextRow() {
        let router = KeyRouter()
        router.mode = .grid(selectedCell: 1)
        router.gridSelectedCell = 1
        router.gridCellCount = 9
        router.gridColumns = 3

        let handled = router.handleKeyDown(keyCode: KeyCode.downArrow, modifierFlags: [])

        #expect(handled == true)
        #expect(router.gridSelectedCell == 4) // 1 + 3 columns
    }

    @Test("Grid mode: up arrow moves to previous row")
    func gridModeArrowUpMovesToPreviousRow() {
        let router = KeyRouter()
        router.mode = .grid(selectedCell: 4)
        router.gridSelectedCell = 4
        router.gridCellCount = 9
        router.gridColumns = 3

        let handled = router.handleKeyDown(keyCode: KeyCode.upArrow, modifierFlags: [])

        #expect(handled == true)
        #expect(router.gridSelectedCell == 1) // 4 - 3 columns
    }

    @Test("Grid mode: Enter expands cell and transitions to focused")
    func gridModeEnterExpandsCell() {
        let router = KeyRouter()
        router.mode = .grid(selectedCell: 2)
        router.gridSelectedCell = 2
        router.gridCellCount = 9
        router.gridColumns = 3

        var expandedIndex: Int?
        router.onExpand = { index in expandedIndex = index }

        let handled = router.handleKeyDown(keyCode: KeyCode.returnKey, modifierFlags: [])

        #expect(handled == true)
        #expect(router.mode == .focused)
        #expect(expandedIndex == 2)
    }

    @Test("Grid mode: Escape deselects cell")
    func gridModeEscapeDeselectsCell() {
        let router = KeyRouter()
        router.mode = .grid(selectedCell: 3)
        router.gridSelectedCell = 3
        router.gridCellCount = 9
        router.gridColumns = 3

        let handled = router.handleKeyDown(keyCode: KeyCode.escape, modifierFlags: [])

        #expect(handled == true)
        #expect(router.gridSelectedCell == nil)
        #expect(router.mode == .grid(selectedCell: nil))
    }

    @Test("Grid mode: does not move past last cell")
    func gridModeDoesNotMovePastEnd() {
        let router = KeyRouter()
        router.mode = .grid(selectedCell: 8)
        router.gridSelectedCell = 8
        router.gridCellCount = 9
        router.gridColumns = 3

        let handled = router.handleKeyDown(keyCode: KeyCode.rightArrow, modifierFlags: [])

        #expect(handled == true)
        #expect(router.gridSelectedCell == 8) // unchanged
    }

    @Test("Grid mode: does not move before first cell")
    func gridModeDoesNotMoveBeforeStart() {
        let router = KeyRouter()
        router.mode = .grid(selectedCell: 0)
        router.gridSelectedCell = 0
        router.gridCellCount = 9
        router.gridColumns = 3

        let handled = router.handleKeyDown(keyCode: KeyCode.leftArrow, modifierFlags: [])

        #expect(handled == true)
        #expect(router.gridSelectedCell == 0) // unchanged
    }

    // MARK: - Focused Mode

    @Test("Focused mode: right arrow seeks +5s")
    func focusedModeArrowRightSeeks() {
        let router = KeyRouter()
        router.mode = .focused

        var seekAmount: TimeInterval?
        router.onSeek = { amount in seekAmount = amount }

        let handled = router.handleKeyDown(keyCode: KeyCode.rightArrow, modifierFlags: [])

        #expect(handled == true)
        #expect(seekAmount == 5)
    }

    @Test("Focused mode: Shift+right arrow seeks +10s")
    func focusedModeShiftRightSeeksMore() {
        let router = KeyRouter()
        router.mode = .focused

        var seekAmount: TimeInterval?
        router.onSeek = { amount in seekAmount = amount }

        let handled = router.handleKeyDown(keyCode: KeyCode.rightArrow, modifierFlags: .shift)

        #expect(handled == true)
        #expect(seekAmount == 10)
    }

    @Test("Focused mode: left arrow seeks -5s")
    func focusedModeArrowLeftSeeksBack() {
        let router = KeyRouter()
        router.mode = .focused

        var seekAmount: TimeInterval?
        router.onSeek = { amount in seekAmount = amount }

        let handled = router.handleKeyDown(keyCode: KeyCode.leftArrow, modifierFlags: [])

        #expect(handled == true)
        #expect(seekAmount == -5)
    }

    @Test("Focused mode: up arrow increases volume")
    func focusedModeUpArrowIncreasesVolume() {
        let router = KeyRouter()
        router.mode = .focused

        var volumeDelta: Float?
        router.onVolumeChange = { delta in volumeDelta = delta }

        let handled = router.handleKeyDown(keyCode: KeyCode.upArrow, modifierFlags: [])

        #expect(handled == true)
        #expect(volumeDelta == 0.1)
    }

    @Test("Focused mode: down arrow decreases volume")
    func focusedModeDownArrowDecreasesVolume() {
        let router = KeyRouter()
        router.mode = .focused

        var volumeDelta: Float?
        router.onVolumeChange = { delta in volumeDelta = delta }

        let handled = router.handleKeyDown(keyCode: KeyCode.downArrow, modifierFlags: [])

        #expect(handled == true)
        #expect(volumeDelta == -0.1)
    }

    @Test("Focused mode: Escape collapses to grid")
    func focusedModeEscapeCollapsesToGrid() {
        let router = KeyRouter()
        router.mode = .focused
        router.gridSelectedCell = 2

        var collapsed = false
        router.onCollapse = { collapsed = true }

        let handled = router.handleKeyDown(keyCode: KeyCode.escape, modifierFlags: [])

        #expect(handled == true)
        #expect(router.mode == .grid(selectedCell: 2))
        #expect(collapsed == true)
    }

    @Test("Focused mode: Space toggles play/pause")
    func focusedModeSpaceTogglesPlayPause() {
        let router = KeyRouter()
        router.mode = .focused

        var toggled = false
        router.onTogglePlayPause = { toggled = true }

        let handled = router.handleKeyDown(keyCode: KeyCode.space, modifierFlags: [])

        #expect(handled == true)
        #expect(toggled == true)
    }

    // MARK: - Single Mode

    @Test("Single mode: right arrow seeks +5s")
    func singleModeArrowRightSeeks() {
        let router = KeyRouter()
        router.mode = .single

        var seekAmount: TimeInterval?
        router.onSeek = { amount in seekAmount = amount }

        let handled = router.handleKeyDown(keyCode: KeyCode.rightArrow, modifierFlags: [])

        #expect(handled == true)
        #expect(seekAmount == 5)
    }

    @Test("Single mode: Space toggles play/pause")
    func singleModeSpaceTogglesPlayPause() {
        let router = KeyRouter()
        router.mode = .single

        var toggled = false
        router.onTogglePlayPause = { toggled = true }

        let handled = router.handleKeyDown(keyCode: KeyCode.space, modifierFlags: [])

        #expect(handled == true)
        #expect(toggled == true)
    }

    @Test("Unhandled key returns false")
    func unhandledKeyReturnsFalse() {
        let router = KeyRouter()
        router.mode = .single

        // Key code 0 = 'a' — not handled
        let handled = router.handleKeyDown(keyCode: 0, modifierFlags: [])

        #expect(handled == false)
    }
}
