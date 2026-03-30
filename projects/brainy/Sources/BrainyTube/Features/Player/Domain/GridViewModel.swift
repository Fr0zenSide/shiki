import AppKit
import BrainyCore
import Foundation

// MARK: - Player Slot

/// A slot in the video grid. Holds a cached thumbnail instead of a live AVPlayer.
public struct PlayerSlot: Identifiable, Sendable {
    public let id: Int
    public var video: Video?
    public var thumbnailImage: NSImage?

    public init(id: Int, video: Video? = nil, thumbnailImage: NSImage? = nil) {
        self.id = id
        self.video = video
        self.thumbnailImage = thumbnailImage
    }
}

// MARK: - Grid View Model

/// Manages the thumbnail grid and a single expanded AVPlayer.
///
/// Architecture: the grid displays static JPEG thumbnails. Only when a cell is
/// tapped/expanded does a single `PlayerViewModel` get created. This eliminates
/// the prior bug where 9 concurrent AVPlayer instances competed for GPU decode
/// bandwidth, causing pixelated rendering.
///
/// Memory impact:
/// - Before: 9 AVPlayers = ~450-720 MB GPU/RAM
/// - After: 9 JPEG thumbnails (~50 KB each) + 1 AVPlayer = ~80 MB
@Observable
@MainActor
public final class GridViewModel {

    // MARK: - State

    public var slots: [PlayerSlot] = []
    public var expandedSlotIndex: Int?
    public var expandedPlayerVM: PlayerViewModel?
    public var columns: Int = 3

    // MARK: - Init

    public init(columns: Int = 3) {
        self.columns = columns
    }

    // MARK: - Slot Management

    /// Assign videos to grid slots, loading cached thumbnails.
    public func assign(videos: [Video], videosDirectory: URL) {
        slots = videos.enumerated().map { index, video in
            var slot = PlayerSlot(id: index, video: video)

            // Load cached thumbnail from disk
            if let thumbPath = video.thumbnailPath {
                let url = videosDirectory.appendingPathComponent(thumbPath)
                slot.thumbnailImage = NSImage(contentsOf: url)
            }

            return slot
        }
    }

    /// Update the thumbnail for a specific slot after extraction completes.
    public func updateThumbnail(at index: Int, image: NSImage) {
        guard index >= 0, index < slots.count else { return }
        slots[index].thumbnailImage = image
    }

    // MARK: - Expand / Collapse

    /// Expand a slot: create a single AVPlayer for the selected video.
    public func expandSlot(at index: Int) {
        guard index >= 0, index < slots.count,
              let video = slots[index].video
        else { return }

        // Destroy previous expanded player if any
        collapseExpanded()

        expandedSlotIndex = index
        let vm = PlayerViewModel()
        vm.load(video: video)
        expandedPlayerVM = vm
    }

    /// Collapse the expanded player, destroying its AVPlayer.
    public func collapseExpanded() {
        expandedPlayerVM?.teardown()
        expandedPlayerVM = nil
        expandedSlotIndex = nil
    }

    /// Total number of cells in the grid.
    public var cellCount: Int {
        slots.count
    }
}
