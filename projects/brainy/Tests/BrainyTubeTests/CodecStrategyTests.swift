import BrainyCore
@testable import BrainyTubeKit
import Testing

@Suite("CodecStrategy")
struct CodecStrategyTests {

    @Test("Native mode prefers AV1 then H.264 via sort string")
    func nativeModePrefersAV1ThenH264() {
        let sort = CodecStrategy.sortString(codec: .native)
        #expect(sort == "vcodec:av01,vcodec:avc1")
    }

    @Test("Universal mode has no sort flag")
    func universalModeNoSortFlag() {
        let sort = CodecStrategy.sortString(codec: .universal)
        #expect(sort == nil)
    }

    @Test("Quality cap is respected in format string")
    func qualityCapRespected() {
        let format720 = CodecStrategy.formatString(quality: .hd720, codec: .native, hasFfmpeg: true)
        #expect(format720.contains("height<=720"))

        let format1080 = CodecStrategy.formatString(quality: .hd1080, codec: .native, hasFfmpeg: true)
        #expect(format1080.contains("height<=1080"))
    }

    @Test("Best quality has no height limit")
    func bestQualityNoHeightLimit() {
        let format = CodecStrategy.formatString(quality: .best, codec: .native, hasFfmpeg: true)
        #expect(!format.contains("height<="))
        #expect(format == "bv*+ba/b")
    }

    @Test("No ffmpeg falls back to pre-merged format")
    func noFfmpegFallsBackToPremerged() {
        let format = CodecStrategy.formatString(quality: .best, codec: .native, hasFfmpeg: false)
        #expect(format == "b")
    }

    @Test("Download arguments include sort flag for native codec")
    func downloadArgumentsNativeIncludeSort() {
        let args = CodecStrategy.downloadArguments(quality: .hd1080, codec: .native, hasFfmpeg: true)

        #expect(args.contains("-S"))
        #expect(args.contains("vcodec:av01,vcodec:avc1"))
        #expect(args.contains("-f"))
        #expect(args.contains("--merge-output-format"))
        #expect(args.contains("mp4"))
    }

    @Test("Download arguments omit sort flag for universal codec")
    func downloadArgumentsUniversalOmitSort() {
        let args = CodecStrategy.downloadArguments(quality: .best, codec: .universal, hasFfmpeg: true)

        #expect(!args.contains("-S"))
        #expect(args.contains("-f"))
        #expect(args.contains("bv*+ba/b"))
    }

    @Test("Download arguments omit merge format without ffmpeg")
    func downloadArgumentsNoFfmpegOmitMerge() {
        let args = CodecStrategy.downloadArguments(quality: .best, codec: .native, hasFfmpeg: false)

        #expect(!args.contains("--merge-output-format"))
        #expect(args.contains("-f"))
        #expect(args.contains("b"))
    }
}
