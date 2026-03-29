import AppKit
import AVFoundation
import SwiftUI

/// Thumbnail preview popup shown when dragging the seek bar slider.
///
/// Uses `AVAssetImageGenerator` to extract a frame at the cursor position,
/// displayed as a floating preview above the seek bar.
struct SeekBarThumbnailPreview: View {
    let videoURL: URL?
    let fraction: Double
    let isVisible: Bool

    @State private var previewImage: NSImage?
    @State private var generationTask: Task<Void, Never>?

    private static let previewSize = CGSize(width: 160, height: 90)

    var body: some View {
        Group {
            if isVisible {
                VStack(spacing: 4) {
                    thumbnailImage
                        .frame(width: Self.previewSize.width, height: Self.previewSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(radius: 8)

                    Text(formattedTime)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isVisible)
        .onChange(of: fraction) { _, newFraction in
            requestThumbnail(at: newFraction)
        }
    }

    // MARK: - Thumbnail Image

    @ViewBuilder
    private var thumbnailImage: some View {
        if let image = previewImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.4))
                .overlay {
                    ProgressView()
                        .scaleEffect(0.6)
                }
        }
    }

    // MARK: - Time Display

    private var formattedTime: String {
        // This is a placeholder — the parent should provide the actual duration
        // For now, display the fraction as a percentage
        let percent = Int(fraction * 100)
        return "\(percent)%"
    }

    // MARK: - Thumbnail Generation

    private func requestThumbnail(at position: Double) {
        generationTask?.cancel()

        guard let url = videoURL else { return }

        generationTask = Task {
            do {
                let image = try await ThumbnailExtractor.extractThumbnail(
                    from: url,
                    at: position,
                    maxSize: Self.previewSize
                )
                guard !Task.isCancelled else { return }
                previewImage = image
            } catch {
                // Preview generation is best-effort — keep the last known image
            }
        }
    }
}

// MARK: - Enhanced Seek Bar with Thumbnail Preview

/// A seek bar that shows a thumbnail preview popup during drag.
struct SeekBarWithPreview: View {
    let playerVM: PlayerViewModel
    let videoURL: URL?
    let onSeek: (Double) -> Void

    @State private var isSeeking = false
    @State private var seekFraction: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail preview (floating above the seek bar)
            SeekBarThumbnailPreview(
                videoURL: videoURL,
                fraction: seekFraction,
                isVisible: isSeeking
            )
            .offset(y: -8)

            // Seek bar track
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 4)

                    // Progress fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(
                            width: geometry.size.width * currentFraction,
                            height: 4
                        )

                    // Drag handle
                    if isSeeking {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 14, height: 14)
                            .offset(x: geometry.size.width * seekFraction - 7)
                    }
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isSeeking = true
                            seekFraction = max(0, min(1, value.location.x / geometry.size.width))
                        }
                        .onEnded { _ in
                            isSeeking = false
                            onSeek(seekFraction)
                        }
                )
            }
            .frame(height: 20)
        }
        .padding(.horizontal, 12)
    }

    private var currentFraction: Double {
        guard playerVM.duration > 0 else { return 0 }
        if isSeeking { return seekFraction }
        return playerVM.currentTime / playerVM.duration
    }
}
