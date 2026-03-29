import BrainyCore
import Testing

@Suite("DownloadError")
struct DownloadErrorTests {

    @Test("Region-locked error with country provides guidance")
    func regionLockedWithCountry() {
        let error = DownloadError.regionLocked(country: "Japan")
        #expect(error.userMessage.contains("region-locked"))
        #expect(error.userMessage.contains("Japan"))
        #expect(error.userMessage.contains("Settings"))
    }

    @Test("Region-locked error without country provides generic guidance")
    func regionLockedWithoutCountry() {
        let error = DownloadError.regionLocked(country: nil)
        #expect(error.userMessage.contains("region-locked"))
        #expect(error.userMessage.contains("Settings"))
    }

    @Test("Format unavailable error includes format name")
    func formatUnavailableIncludesFormat() {
        let error = DownloadError.formatUnavailable("1080p AV1")
        #expect(error.userMessage.contains("1080p AV1"))
    }

    @Test("yt-dlp not found error suggests installation")
    func ytdlpNotFoundSuggestsInstall() {
        let error = DownloadError.ytdlpNotFound
        #expect(error.userMessage.contains("brew install yt-dlp"))
    }

    @Test("Network error includes message")
    func networkErrorIncludesMessage() {
        let error = DownloadError.networkError("Connection timed out")
        #expect(error.userMessage.contains("Connection timed out"))
    }
}
