import Testing
@testable import ShikkiKit

// MARK: - FlameRendererTests

@Suite("FlameRenderer — ASCII flame rendering at all sizes and emotions")
struct FlameRendererTests {

    // MARK: Mini Rendering

    @Test("mini render returns single-line array")
    func miniRendersSingleLine() {
        let lines = FlameRenderer.render(size: .mini, emotion: .calm, frame: 0)
        #expect(lines.count == 1)
    }

    @Test("mini render contains non-empty content")
    func miniRendersContent() {
        let lines = FlameRenderer.render(size: .mini, emotion: .focused, frame: 0)
        let stripped = stripANSI(lines[0])
        #expect(!stripped.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @Test("mini cycles through frames")
    func miniCyclesFrames() {
        let frame0 = FlameRenderer.renderToString(size: .mini, emotion: .calm, frame: 0)
        let frame1 = FlameRenderer.renderToString(size: .mini, emotion: .calm, frame: 1)
        // Calm mini has 4 frames — 0 and 1 should differ
        #expect(frame0 != frame1)
    }

    @Test("mini frame wraps around when exceeding count")
    func miniFrameWraps() {
        let count = FlameRenderer.frameCount(size: .mini, emotion: .calm)
        let frame0 = FlameRenderer.renderToString(size: .mini, emotion: .calm, frame: 0)
        let frameWrapped = FlameRenderer.renderToString(size: .mini, emotion: .calm, frame: count)
        #expect(frame0 == frameWrapped)
    }

    // MARK: Medium Rendering

    @Test("medium render returns multiple lines")
    func mediumRendersMultipleLines() {
        let lines = FlameRenderer.render(size: .medium, emotion: .calm, frame: 0)
        #expect(lines.count == 8)
    }

    @Test("medium render includes ANSI escape codes")
    func mediumIncludesANSI() {
        let output = FlameRenderer.renderToString(size: .medium, emotion: .focused, frame: 0)
        #expect(output.contains("\u{1B}["))
    }

    @Test("medium render stripped of ANSI matches raw art line count")
    func mediumStrippedMatchesRaw() {
        for emotion in FlameEmotion.allCases {
            guard let frames = FlameArt.mediumFrames[emotion] else { continue }
            let rendered = FlameRenderer.render(size: .medium, emotion: emotion, frame: 0)
            #expect(rendered.count == frames[0].count, "Line count mismatch for \(emotion)")
        }
    }

    // MARK: Large Rendering

    @Test("large render returns 16 lines")
    func largeRendersCorrectHeight() {
        let lines = FlameRenderer.render(size: .large, emotion: .calm, frame: 0)
        #expect(lines.count == 16)
    }

    @Test("large render for all emotions produces output")
    func largeRendersAllEmotions() {
        for emotion in FlameEmotion.allCases {
            let lines = FlameRenderer.render(size: .large, emotion: emotion, frame: 0)
            #expect(!lines.isEmpty, "Large render empty for \(emotion)")
        }
    }

    // MARK: Frame Counting

    @Test("frame count for mini calm is 4")
    func miniCalmFrameCount() {
        #expect(FlameRenderer.frameCount(size: .mini, emotion: .calm) == 4)
    }

    @Test("frame count for medium alarmed is 3")
    func mediumAlarmedFrameCount() {
        #expect(FlameRenderer.frameCount(size: .medium, emotion: .alarmed) == 3)
    }

    @Test("frame count for large celebrating is 2")
    func largeCelebratingFrameCount() {
        #expect(FlameRenderer.frameCount(size: .large, emotion: .celebrating) == 2)
    }

    @Test("all emotion-size combinations have at least 1 frame")
    func allCombinationsHaveFrames() {
        for size in FlameSize.allCases {
            for emotion in FlameEmotion.allCases {
                let count = FlameRenderer.frameCount(size: size, emotion: emotion)
                #expect(count >= 1, "No frames for \(size) \(emotion)")
            }
        }
    }

    // MARK: renderToString

    @Test("renderToString joins lines with newlines")
    func renderToStringJoinsLines() {
        let lines = FlameRenderer.render(size: .medium, emotion: .calm, frame: 0)
        let string = FlameRenderer.renderToString(size: .medium, emotion: .calm, frame: 0)
        #expect(string == lines.joined(separator: "\n"))
    }

    // MARK: Color Palettes

    @Test("each emotion has a distinct color palette")
    func distinctPalettes() {
        let palettes = FlameEmotion.allCases.map { FlameColorPalette.palette(for: $0) }
        // Check cores are different
        let cores = Set(palettes.map(\.core))
        #expect(cores.count == FlameEmotion.allCases.count)
    }

    @Test("calm palette uses blue tones")
    func calmPaletteIsCoolBlue() {
        let palette = FlameColorPalette.calm
        // RGB values in the escape code should show blue dominance
        #expect(palette.core.contains("120;180;255"))
    }

    @Test("alarmed palette uses red tones for core")
    func alarmedPaletteUsesRed() {
        let palette = FlameColorPalette.alarmed
        #expect(palette.core.contains("255;100;80"))
    }

    @Test("celebrating palette uses gold for core")
    func celebratingPaletteUsesGold() {
        let palette = FlameColorPalette.celebrating
        #expect(palette.core.contains("255;215;0"))
    }

    // MARK: Colorization Details

    @Test("base lines use base color")
    func baseLinesUseBaseColor() {
        let palette = FlameColorPalette.calm
        let lines = [
            "  test  ",
            "  body  ",
            " '___'  ",
            "  ___   ",
        ]
        let colored = FlameRenderer.colorizeLines(lines, palette: palette)
        // Last 2 lines should start with base color
        #expect(colored[2].hasPrefix(palette.base))
        #expect(colored[3].hasPrefix(palette.base))
    }

    @Test("spark characters get spark color")
    func sparkCharsGetSparkColor() {
        let palette = FlameColorPalette.excited
        let line = FlameRenderer.colorizeLine(
            " * ",
            lineIndex: 0,
            totalLines: 8,
            palette: palette
        )
        #expect(line.contains(palette.spark))
    }

    @Test("pipe characters get core color")
    func pipeCharsGetCoreColor() {
        let palette = FlameColorPalette.focused
        let line = FlameRenderer.colorizeLine(
            " ||| ",
            lineIndex: 3,
            totalLines: 8,
            palette: palette
        )
        #expect(line.contains(palette.core))
    }
}

// MARK: - FlameArt Consistency Tests

@Suite("FlameArt — art data integrity")
struct FlameArtTests {

    @Test("all emotions have mini frames")
    func allEmotionsHaveMiniFrames() {
        for emotion in FlameEmotion.allCases {
            let frames = FlameArt.miniFrames[emotion]
            #expect(frames != nil, "Missing mini frames for \(emotion)")
            #expect(frames?.isEmpty == false, "Empty mini frames for \(emotion)")
        }
    }

    @Test("all emotions have medium frames")
    func allEmotionsHaveMediumFrames() {
        for emotion in FlameEmotion.allCases {
            let frames = FlameArt.mediumFrames[emotion]
            #expect(frames != nil, "Missing medium frames for \(emotion)")
            #expect(frames?.isEmpty == false, "Empty medium frames for \(emotion)")
        }
    }

    @Test("all emotions have large frames")
    func allEmotionsHaveLargeFrames() {
        for emotion in FlameEmotion.allCases {
            let frames = FlameArt.largeFrames[emotion]
            #expect(frames != nil, "Missing large frames for \(emotion)")
            #expect(frames?.isEmpty == false, "Empty large frames for \(emotion)")
        }
    }

    @Test("medium frames have consistent line counts per emotion")
    func mediumFramesConsistentLineCount() {
        for emotion in FlameEmotion.allCases {
            guard let frames = FlameArt.mediumFrames[emotion] else { continue }
            let expectedCount = frames[0].count
            for (i, frame) in frames.enumerated() {
                #expect(
                    frame.count == expectedCount,
                    "\(emotion) medium frame \(i) has \(frame.count) lines, expected \(expectedCount)"
                )
            }
        }
    }

    @Test("large frames have consistent line counts per emotion")
    func largeFramesConsistentLineCount() {
        for emotion in FlameEmotion.allCases {
            guard let frames = FlameArt.largeFrames[emotion] else { continue }
            let expectedCount = frames[0].count
            for (i, frame) in frames.enumerated() {
                #expect(
                    frame.count == expectedCount,
                    "\(emotion) large frame \(i) has \(frame.count) lines, expected \(expectedCount)"
                )
            }
        }
    }

    @Test("medium frames are 8 lines tall")
    func mediumFramesAre8Lines() {
        for emotion in FlameEmotion.allCases {
            guard let frames = FlameArt.mediumFrames[emotion] else { continue }
            for frame in frames {
                #expect(frame.count == 8, "\(emotion) medium frame has \(frame.count) lines, expected 8")
            }
        }
    }

    @Test("large frames are 16 lines tall")
    func largeFramesAre16Lines() {
        for emotion in FlameEmotion.allCases {
            guard let frames = FlameArt.largeFrames[emotion] else { continue }
            for frame in frames {
                #expect(frame.count == 16, "\(emotion) large frame has \(frame.count) lines, expected 16")
            }
        }
    }
}
