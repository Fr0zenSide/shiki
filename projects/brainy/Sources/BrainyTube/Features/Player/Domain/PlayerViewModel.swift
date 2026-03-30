import AVFoundation
import BrainyCore
import Combine
import Foundation

/// ViewModel for a single AVPlayer instance.
///
/// Manages playback state, seeking, and volume for one video at a time.
/// In grid mode, only one `PlayerViewModel` exists for the expanded/focused cell.
@Observable
@MainActor
public final class PlayerViewModel {

    // MARK: - Published State

    public var isPlaying = false
    public var currentTime: TimeInterval = 0
    public var duration: TimeInterval = 0
    public var volume: Float = 1.0
    public var playbackRate: Float = 1.0
    public var isBuffering = false
    public var errorMessage: String?

    // MARK: - Video Info

    public var video: Video?
    public var detectedCodec: String?

    // MARK: - Player

    public let player: AVPlayer

    // MARK: - Private

    // These observers need to be cleaned up in deinit. Using @ObservationIgnored
    // keeps them outside the Observable macro's tracking, and nonisolated(unsafe)
    // allows deinit access under Swift 6 strict concurrency.
    @ObservationIgnored
    private var timeObserver: Any?
    @ObservationIgnored
    private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored
    private var rateObservation: NSKeyValueObservation?

    // MARK: - Init

    public init() {
        self.player = AVPlayer()
        setupObservers()
    }

    // MARK: - Teardown

    /// Explicit cleanup. Call before discarding the view model.
    /// Required because Swift 6 strict concurrency prevents MainActor property
    /// access in nonisolated deinit.
    public func teardown() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        rateObservation?.invalidate()
        rateObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    // MARK: - Load

    public func load(video: Video) {
        self.video = video
        self.errorMessage = nil

        guard let path = video.videoPath else {
            errorMessage = "No video file available"
            return
        }

        let url = URL(fileURLWithPath: path)
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)

        observeItem(item)
    }

    // MARK: - Playback Controls

    public func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
            player.rate = playbackRate
        }
        isPlaying = !isPlaying
    }

    public func seek(by seconds: TimeInterval) {
        let target = currentTime + seconds
        let clamped = max(0, min(target, duration))
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func seek(to fraction: Double) {
        let target = duration * fraction
        let time = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func adjustVolume(by delta: Float) {
        volume = max(0, min(1, volume + delta))
        player.volume = volume
    }

    public func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player.rate = rate
        }
    }

    // MARK: - Codec Detection

    /// Detect the video codec from the current player item's tracks.
    public func detectCodec() async {
        guard let item = player.currentItem,
              let asset = item.asset as? AVURLAsset
        else { return }

        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return }
            let descriptions = try await track.load(.formatDescriptions)
            guard let desc = descriptions.first else { return }
            let codecType = CMFormatDescriptionGetMediaSubType(desc)
            detectedCodec = fourCCString(from: codecType)
        } catch {
            // Codec detection is best-effort
        }
    }

    // MARK: - Private

    private func setupObservers() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = CMTimeGetSeconds(time)
            }
        }

        rateObservation = player.observe(\.rate) { [weak self] player, _ in
            Task { @MainActor in
                self?.isPlaying = player.rate > 0
            }
        }
    }

    private func observeItem(_ item: AVPlayerItem) {
        statusObservation?.invalidate()
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    self?.duration = CMTimeGetSeconds(item.duration)
                    self?.isBuffering = false
                case .failed:
                    self?.errorMessage = item.error?.localizedDescription ?? "Playback failed"
                    self?.isBuffering = false
                default:
                    self?.isBuffering = true
                }
            }
        }
    }

    private func fourCCString(from code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8(truncatingIfNeeded: (code >> 24) & 0xFF),
            UInt8(truncatingIfNeeded: (code >> 16) & 0xFF),
            UInt8(truncatingIfNeeded: (code >> 8) & 0xFF),
            UInt8(truncatingIfNeeded: code & 0xFF),
        ]
        return String(decoding: bytes, as: UTF8.self)
    }
}
