import Testing
@testable import ShikkiKit

@Suite("KeyMode")
struct KeyModeTests {

    @Test("Emacs Ctrl-n maps to next")
    func emacsCtrlN() {
        let action = KeyMode.emacs.mapAction(for: .char("\u{0E}")) // Ctrl-N
        #expect(action == .next)
    }

    @Test("Emacs Ctrl-p maps to prev")
    func emacsCtrlP() {
        let action = KeyMode.emacs.mapAction(for: .char("\u{10}")) // Ctrl-P
        #expect(action == .prev)
    }

    @Test("Emacs Enter maps to select")
    func emacsEnter() {
        let action = KeyMode.emacs.mapAction(for: .enter)
        #expect(action == .select)
    }

    @Test("Emacs Escape maps to back")
    func emacsEscape() {
        let action = KeyMode.emacs.mapAction(for: .escape)
        #expect(action == .back)
    }

    @Test("Vim j maps to next")
    func vimJ() {
        let action = KeyMode.vim.mapAction(for: .char("j"))
        #expect(action == .next)
    }

    @Test("Vim k maps to prev")
    func vimK() {
        let action = KeyMode.vim.mapAction(for: .char("k"))
        #expect(action == .prev)
    }

    @Test("Arrows mode: up maps to prev, down maps to next")
    func arrowsMode() {
        #expect(KeyMode.arrows.mapAction(for: .up) == .prev)
        #expect(KeyMode.arrows.mapAction(for: .down) == .next)
    }

    @Test("All modes: Enter maps to select")
    func enterUniversal() {
        #expect(KeyMode.emacs.mapAction(for: .enter) == .select)
        #expect(KeyMode.vim.mapAction(for: .enter) == .select)
        #expect(KeyMode.arrows.mapAction(for: .enter) == .select)
    }

    @Test("All modes: 'a' verdict maps to approve")
    func approveUniversal() {
        #expect(KeyMode.emacs.mapAction(for: .char("a")) == .approve)
        #expect(KeyMode.vim.mapAction(for: .char("a")) == .approve)
    }

    @Test("Unknown key maps to nil")
    func unknownKey() {
        let action = KeyMode.emacs.mapAction(for: .char("z"))
        #expect(action == nil)
    }

    @Test("Vim g maps to first, G maps to last")
    func vimJumpToEnds() {
        #expect(KeyMode.vim.mapAction(for: .char("g")) == .first)
        #expect(KeyMode.vim.mapAction(for: .char("G")) == .last)
    }
}
