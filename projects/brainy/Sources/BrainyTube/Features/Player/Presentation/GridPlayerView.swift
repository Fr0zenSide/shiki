import BrainyCore
import SwiftUI

/// Grid view displaying video thumbnails with a single expandable AVPlayer overlay.
///
/// Architecture fix for the pixelation bug: instead of creating 9 live AVPlayer
/// instances that compete for GPU decode bandwidth, the grid renders static JPEG
/// thumbnails. Only the focused/expanded cell gets a real AVPlayer.
struct GridPlayerView: View {
    @Bindable var gridVM: GridViewModel
    let keyRouter: KeyRouter
    let codecPreference: VideoCodecPreference
    let availableFormats: [VideoFormatInfo]
    let onQualitySelected: (VideoFormatInfo) -> Void

    var body: some View {
        ZStack {
            thumbnailGrid
            expandedOverlay
        }
    }

    // MARK: - Thumbnail Grid

    private var thumbnailGrid: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 8),
            count: gridVM.columns
        )

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(gridVM.slots) { slot in
                if let video = slot.video {
                    ThumbnailCell(
                        video: video,
                        thumbnailImage: slot.thumbnailImage,
                        isSelected: keyRouter.gridSelectedCell == slot.id,
                        onTap: {
                            keyRouter.gridSelectedCell = slot.id
                            gridVM.expandSlot(at: slot.id)
                            keyRouter.mode = .focused
                        }
                    )
                } else {
                    emptySlot
                }
            }
        }
        .padding(8)
        .opacity(gridVM.expandedSlotIndex != nil ? 0.3 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: gridVM.expandedSlotIndex)
    }

    // MARK: - Expanded Player Overlay

    @ViewBuilder
    private var expandedOverlay: some View {
        if let playerVM = gridVM.expandedPlayerVM {
            VStack {
                VideoPlayerCell(playerVM: playerVM)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.scale.combined(with: .opacity))

                PlayerControlsView(
                    playerVM: playerVM,
                    availableFormats: availableFormats,
                    codecPreference: codecPreference,
                    onQualitySelected: onQualitySelected,
                    onSeek: { fraction in
                        playerVM.seek(to: fraction)
                    }
                )
            }
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(16)
            .shadow(radius: 20)
        }
    }

    // MARK: - Empty Slot

    private var emptySlot: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.15))
            .aspectRatio(16 / 9, contentMode: .fill)
            .overlay {
                Image(systemName: "plus")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
    }
}
