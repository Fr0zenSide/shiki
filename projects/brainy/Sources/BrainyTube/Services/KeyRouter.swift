import AppKit
import Foundation

// MARK: - Input Mode

/// The active keyboard navigation mode, determining how arrow keys are interpreted.
public enum InputMode: Equatable, Sendable {
    /// Grid browsing: arrows navigate between cells, Enter expands.
    case grid(selectedCell: Int?)
    /// A single cell is expanded: arrows seek/volume, Escape collapses.
    case focused
    /// Single-player view: arrows seek/volume.
    case single
}

// MARK: - Key Router

/// Mode-aware keyboard event router for BrainyTube.
///
/// Routes arrow keys, Enter, Escape, and Space to the correct action based on
/// the current input mode. Eliminates the prior bug where global menu shortcuts
/// intercepted arrow keys meant for grid navigation.
@Observable
@MainActor
public final class KeyRouter {

    // MARK: - State

    public var mode: InputMode = .single

    /// The currently highlighted cell index in grid mode.
    public var gridSelectedCell: Int?

    /// Number of columns in the grid (for row-based arrow navigation).
    public var gridColumns: Int = 3

    /// Total number of cells in the grid.
    public var gridCellCount: Int = 0

    // MARK: - Callbacks

    public var onSeek: ((TimeInterval) -> Void)?
    public var onVolumeChange: ((Float) -> Void)?
    public var onTogglePlayPause: (() -> Void)?
    public var onGridCellSelect: ((Int) -> Void)?
    public var onExpand: ((Int) -> Void)?
    public var onCollapse: (() -> Void)?

    // MARK: - Constants

    private static let seekSmall: TimeInterval = 5
    private static let seekLarge: TimeInterval = 10
    private static let volumeStep: Float = 0.1

    // MARK: - Init

    public init() {}

    // MARK: - Key Handling

    /// Process a keyboard event. Returns `true` if the event was consumed.
    @discardableResult
    public func handleKeyDown(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        switch mode {
        case .grid:
            return handleGridKey(keyCode: keyCode, modifierFlags: modifierFlags)
        case .focused:
            return handleFocusedKey(keyCode: keyCode, modifierFlags: modifierFlags)
        case .single:
            return handleSingleKey(keyCode: keyCode, modifierFlags: modifierFlags)
        }
    }

    // MARK: - Grid Mode

    private func handleGridKey(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        switch keyCode {
        case KeyCode.rightArrow:
            moveGridSelection(by: 1)
            return true
        case KeyCode.leftArrow:
            moveGridSelection(by: -1)
            return true
        case KeyCode.downArrow:
            moveGridSelection(by: gridColumns)
            return true
        case KeyCode.upArrow:
            moveGridSelection(by: -gridColumns)
            return true
        case KeyCode.returnKey, KeyCode.enter:
            if let cell = gridSelectedCell {
                mode = .focused
                onExpand?(cell)
            }
            return true
        case KeyCode.escape:
            gridSelectedCell = nil
            mode = .grid(selectedCell: nil)
            return true
        case KeyCode.space:
            if let cell = gridSelectedCell {
                onExpand?(cell)
                mode = .focused
            }
            return true
        default:
            return false
        }
    }

    // MARK: - Focused Mode

    private func handleFocusedKey(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let hasShift = modifierFlags.contains(.shift)

        switch keyCode {
        case KeyCode.rightArrow:
            onSeek?(hasShift ? Self.seekLarge : Self.seekSmall)
            return true
        case KeyCode.leftArrow:
            onSeek?(hasShift ? -Self.seekLarge : -Self.seekSmall)
            return true
        case KeyCode.upArrow:
            onVolumeChange?(Self.volumeStep)
            return true
        case KeyCode.downArrow:
            onVolumeChange?(-Self.volumeStep)
            return true
        case KeyCode.escape:
            mode = .grid(selectedCell: gridSelectedCell)
            onCollapse?()
            return true
        case KeyCode.space:
            onTogglePlayPause?()
            return true
        default:
            return false
        }
    }

    // MARK: - Single Mode

    private func handleSingleKey(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let hasShift = modifierFlags.contains(.shift)

        switch keyCode {
        case KeyCode.rightArrow:
            onSeek?(hasShift ? Self.seekLarge : Self.seekSmall)
            return true
        case KeyCode.leftArrow:
            onSeek?(hasShift ? -Self.seekLarge : -Self.seekSmall)
            return true
        case KeyCode.upArrow:
            onVolumeChange?(Self.volumeStep)
            return true
        case KeyCode.downArrow:
            onVolumeChange?(-Self.volumeStep)
            return true
        case KeyCode.space:
            onTogglePlayPause?()
            return true
        default:
            return false
        }
    }

    // MARK: - Grid Navigation

    private func moveGridSelection(by offset: Int) {
        guard gridCellCount > 0 else { return }

        let current = gridSelectedCell ?? 0
        let next = current + offset

        guard next >= 0, next < gridCellCount else { return }

        gridSelectedCell = next
        mode = .grid(selectedCell: next)
        onGridCellSelect?(next)
    }
}

// MARK: - Key Codes

/// macOS virtual key codes for keyboard event handling.
public enum KeyCode {
    public static let rightArrow: UInt16 = 124
    public static let leftArrow: UInt16 = 123
    public static let downArrow: UInt16 = 125
    public static let upArrow: UInt16 = 126
    public static let returnKey: UInt16 = 36
    public static let enter: UInt16 = 76
    public static let escape: UInt16 = 53
    public static let space: UInt16 = 49
}
