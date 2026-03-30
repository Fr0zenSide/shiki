import AVFoundation
import AVKit
import BrainyCore
import SwiftUI

/// A single video player cell wrapping AVPlayer in a SwiftUI view.
///
/// Used only for the expanded/focused cell in grid mode or in single-player mode.
/// Never instantiated per-cell in the grid — that caused the pixelation bug.
struct VideoPlayerCell: View {
    let playerVM: PlayerViewModel

    var body: some View {
        ZStack {
            VideoPlayer(player: playerVM.player)
                .aspectRatio(16 / 9, contentMode: .fit)

            if playerVM.isBuffering {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.3))
            }

            if let error = playerVM.errorMessage {
                errorOverlay(message: error)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func errorOverlay(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.7))
    }
}
