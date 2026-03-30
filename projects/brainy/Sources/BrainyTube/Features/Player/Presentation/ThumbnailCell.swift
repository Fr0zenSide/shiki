import AppKit
import BrainyCore
import SwiftUI

/// A lightweight grid cell that displays a static JPEG thumbnail instead of a live AVPlayer.
///
/// Replaces per-cell AVPlayer instances to eliminate GPU decode contention in grid mode.
/// On tap, the grid expands a single AVPlayer overlay for the selected video.
struct ThumbnailCell: View {
    let video: Video
    let thumbnailImage: NSImage?
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            thumbnailView
            overlay
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(selectionBorder)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(perform: onTap)
        .accessibilityLabel(video.metadata?.title ?? "Video")
        .accessibilityHint("Double-tap to play")
    }

    // MARK: - Subviews

    @ViewBuilder
    private var thumbnailView: some View {
        if let image = thumbnailImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(16 / 9, contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .aspectRatio(16 / 9, contentMode: .fill)
                .overlay {
                    Image(systemName: "film")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var overlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer()
            HStack {
                Text(video.metadata?.title ?? "Untitled")
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundStyle(.white)

                Spacer()

                if let duration = video.metadata?.duration, duration > 0 {
                    Text(formattedDuration(duration))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(6)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    @ViewBuilder
    private var selectionBorder: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: 2)
        } else if isHovered {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
        }
    }

    // MARK: - Helpers

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
