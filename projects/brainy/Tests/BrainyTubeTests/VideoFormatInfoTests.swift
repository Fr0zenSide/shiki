import BrainyCore
import Testing

@Suite("VideoFormatInfo")
struct VideoFormatInfoTests {

    @Test("Display label includes resolution and codec")
    func displayLabelIncludesResolutionAndCodec() {
        let format = VideoFormatInfo(
            resolution: "1080p",
            codec: "av01",
            fileSize: nil,
            formatId: "303"
        )

        #expect(format.displayLabel == "1080p AV01")
    }

    @Test("Display label includes file size when available")
    func displayLabelIncludesFileSize() {
        let format = VideoFormatInfo(
            resolution: "1080p",
            codec: "avc1",
            fileSize: 262_144_000, // ~250 MB
            formatId: "137"
        )

        #expect(format.displayLabel.contains("250 MB"))
        #expect(format.displayLabel.contains("1080p"))
        #expect(format.displayLabel.contains("AVC1"))
    }

    @Test("Display label omits size when nil")
    func displayLabelOmitsSizeWhenNil() {
        let format = VideoFormatInfo(
            resolution: "720p",
            codec: "vp9",
            fileSize: nil,
            formatId: "247"
        )

        #expect(!format.displayLabel.contains("MB"))
        #expect(format.displayLabel == "720p VP9")
    }
}
