import BrainyCore
import SwiftUI

/// Transport controls overlay for the video player.
///
/// Includes a codec-aware quality selector that shows H.264/HEVC/AV1 labels
/// alongside resolution and estimated file size, replacing the previous
/// codec-blind "best/1080p/720p" menu.
struct PlayerControlsView: View {
    let playerVM: PlayerViewModel
    let availableFormats: [VideoFormatInfo]
    let codecPreference: VideoCodecPreference
    let onQualitySelected: (VideoFormatInfo) -> Void
    let onSeek: (Double) -> Void

    @State private var isSeeking = false
    @State private var seekFraction: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            Spacer()

            // Seek bar with thumbnail preview position
            seekBar

            // Transport controls row
            HStack(spacing: 16) {
                playPauseButton
                timeLabel
                Spacer()
                codecBadge
                qualityMenu
                volumeSlider
                speedMenu
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(controlsGradient)
    }

    // MARK: - Seek Bar

    private var seekBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track background
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

                // Seek position indicator (shown during drag)
                if isSeeking {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 12, height: 12)
                        .offset(x: geometry.size.width * seekFraction - 6)
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
        .padding(.horizontal, 12)
    }

    // MARK: - Controls

    private var playPauseButton: some View {
        Button(action: { playerVM.togglePlayPause() }) {
            Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                .font(.title3)
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
    }

    private var timeLabel: some View {
        Text("\(formatTime(playerVM.currentTime)) / \(formatTime(playerVM.duration))")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.8))
            .monospacedDigit()
    }

    /// Badge showing the detected codec of the currently playing video.
    @ViewBuilder
    private var codecBadge: some View {
        if let codec = playerVM.detectedCodec {
            Text(codecDisplayName(codec))
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(codecBadgeColor(codec).opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.white)
        }
    }

    /// Codec-aware quality selector showing resolution + codec + estimated size.
    private var qualityMenu: some View {
        Menu {
            if availableFormats.isEmpty {
                // Fallback to generic quality presets
                ForEach(VideoQuality.allCases, id: \.self) { quality in
                    Button(quality.rawValue) {
                        // Handled by parent via preset quality selection
                    }
                }
            } else {
                ForEach(availableFormats, id: \.formatId) { format in
                    Button(action: { onQualitySelected(format) }) {
                        HStack {
                            Text(format.displayLabel)
                            if isVP9(format.codec), codecPreference == .native {
                                Text("(software decode)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(isVP9(format.codec) && codecPreference == .native)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gear")
                Text("Quality")
                    .font(.caption)
            }
            .foregroundStyle(.white)
        }
        .menuStyle(.borderlessButton)
    }

    private var volumeSlider: some View {
        HStack(spacing: 4) {
            Image(systemName: volumeIcon)
                .font(.caption)
                .foregroundStyle(.white)
            Slider(
                value: Binding(
                    get: { Double(playerVM.volume) },
                    set: { playerVM.volume = Float($0); playerVM.player.volume = Float($0) }
                ),
                in: 0...1
            )
            .frame(width: 80)
        }
    }

    private var speedMenu: some View {
        Menu {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                Button("\(rate, specifier: "%.2g")x") {
                    playerVM.setRate(Float(rate))
                }
            }
        } label: {
            Text("\(playerVM.playbackRate, specifier: "%.2g")x")
                .font(.caption)
                .foregroundStyle(.white)
        }
        .menuStyle(.borderlessButton)
    }

    private var controlsGradient: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.7)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Helpers

    private var currentFraction: Double {
        guard playerVM.duration > 0 else { return 0 }
        if isSeeking { return seekFraction }
        return playerVM.currentTime / playerVM.duration
    }

    private var volumeIcon: String {
        if playerVM.volume <= 0 {
            return "speaker.slash.fill"
        } else if playerVM.volume < 0.5 {
            return "speaker.wave.1.fill"
        } else {
            return "speaker.wave.2.fill"
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private func codecDisplayName(_ codec: String) -> String {
        let lower = codec.lowercased().trimmingCharacters(in: .whitespaces)
        switch lower {
        case "avc1", "h264": return "H.264"
        case "hvc1", "hev1", "hevc": return "HEVC"
        case "av01", "av1": return "AV1"
        case "vp9", "vp09": return "VP9"
        default: return codec.uppercased()
        }
    }

    private func codecBadgeColor(_ codec: String) -> Color {
        let lower = codec.lowercased().trimmingCharacters(in: .whitespaces)
        switch lower {
        case "av01", "av1": return .green
        case "avc1", "h264": return .blue
        case "hvc1", "hev1", "hevc": return .purple
        case "vp9", "vp09": return .orange
        default: return .gray
        }
    }

    private func isVP9(_ codec: String) -> Bool {
        let lower = codec.lowercased()
        return lower.contains("vp9") || lower.contains("vp09")
    }
}
