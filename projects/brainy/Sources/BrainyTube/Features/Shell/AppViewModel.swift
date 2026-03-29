import BrainyCore
import Foundation

// MARK: - View Mode

public enum ViewMode: Equatable, Sendable {
    case single
    case grid
}

// MARK: - App View Model

/// Top-level view model coordinating the player, grid, key router, and settings.
@Observable
@MainActor
public final class AppViewModel {

    // MARK: - State

    public var viewMode: ViewMode = .single
    public var currentVideo: Video?
    public var errorMessage: String?

    // MARK: - Child View Models

    public let gridVM: GridViewModel
    public let keyRouter: KeyRouter
    public let settingsVM: SettingsViewModel

    // MARK: - Single Player

    public var singlePlayerVM: PlayerViewModel?

    // MARK: - Init

    public init() {
        self.gridVM = GridViewModel()
        self.keyRouter = KeyRouter()
        self.settingsVM = SettingsViewModel()

        wireKeyRouter()
    }

    // MARK: - Mode Switching

    public func switchToSingle() {
        gridVM.collapseExpanded()
        viewMode = .single
        keyRouter.mode = .single
    }

    public func switchToGrid() {
        singlePlayerVM?.player.pause()
        viewMode = .grid
        keyRouter.mode = .grid(selectedCell: nil)
        keyRouter.gridSelectedCell = nil
        keyRouter.gridCellCount = gridVM.cellCount
        keyRouter.gridColumns = gridVM.columns
    }

    // MARK: - Region-Lock Error Handling

    /// Handle a download error, providing user-facing guidance for region-locked content.
    public func handleDownloadError(_ error: DownloadError) {
        errorMessage = error.userMessage
    }

    /// Clear the error message.
    public func clearError() {
        errorMessage = nil
    }

    // MARK: - Key Router Wiring

    private func wireKeyRouter() {
        keyRouter.onSeek = { [weak self] seconds in
            self?.activePlayerVM?.seek(by: seconds)
        }

        keyRouter.onVolumeChange = { [weak self] delta in
            self?.activePlayerVM?.adjustVolume(by: delta)
        }

        keyRouter.onTogglePlayPause = { [weak self] in
            self?.activePlayerVM?.togglePlayPause()
        }

        keyRouter.onGridCellSelect = { [weak self] index in
            self?.keyRouter.gridSelectedCell = index
        }

        keyRouter.onExpand = { [weak self] index in
            self?.gridVM.expandSlot(at: index)
            self?.keyRouter.mode = .focused
        }

        keyRouter.onCollapse = { [weak self] in
            self?.gridVM.collapseExpanded()
        }
    }

    // MARK: - Active Player

    /// The currently active player VM (either single or expanded grid cell).
    public var activePlayerVM: PlayerViewModel? {
        switch viewMode {
        case .single:
            return singlePlayerVM
        case .grid:
            return gridVM.expandedPlayerVM
        }
    }
}
