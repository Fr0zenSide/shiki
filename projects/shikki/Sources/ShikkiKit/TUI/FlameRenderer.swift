import Foundation

// MARK: - FlameColorPalette

/// ANSI color palettes for each flame emotion.
/// Uses 24-bit (truecolor) ANSI sequences for rich gradients.
public struct FlameColorPalette: Sendable, Equatable {
    /// Core color — the brightest part of the flame.
    public let core: String
    /// Inner color — surrounding the core.
    public let inner: String
    /// Outer color — the flame's edge.
    public let outer: String
    /// Spark color — for accents (* and similar).
    public let spark: String
    /// Base color — the pedestal/platform.
    public let base: String

    public init(core: String, inner: String, outer: String, spark: String, base: String) {
        self.core = core
        self.inner = inner
        self.outer = outer
        self.spark = spark
        self.base = base
    }

    // MARK: - Predefined Palettes

    /// Calm: cool blue tones, gentle.
    public static let calm = FlameColorPalette(
        core:  "\u{1B}[38;2;120;180;255m",  // soft blue
        inner: "\u{1B}[38;2;80;140;220m",   // medium blue
        outer: "\u{1B}[38;2;50;100;180m",   // deep blue
        spark: "\u{1B}[38;2;160;200;255m",  // light blue
        base:  "\u{1B}[38;2;100;120;160m"   // steel blue
    )

    /// Focused: warm blue with white-hot core.
    public static let focused = FlameColorPalette(
        core:  "\u{1B}[38;2;220;240;255m",  // near-white blue
        inner: "\u{1B}[38;2;100;160;255m",  // bright blue
        outer: "\u{1B}[38;2;60;120;220m",   // standard blue
        spark: "\u{1B}[38;2;180;220;255m",  // ice blue
        base:  "\u{1B}[38;2;120;140;180m"   // cool gray-blue
    )

    /// Excited: electric blue with cyan sparks.
    public static let excited = FlameColorPalette(
        core:  "\u{1B}[38;2;255;255;255m",  // pure white
        inner: "\u{1B}[38;2;80;200;255m",   // electric blue
        outer: "\u{1B}[38;2;0;160;255m",    // vivid blue
        spark: "\u{1B}[38;2;0;255;255m",    // cyan
        base:  "\u{1B}[38;2;140;160;200m"   // bright steel
    )

    /// Alarmed: blue shifting to red, unstable.
    public static let alarmed = FlameColorPalette(
        core:  "\u{1B}[38;2;255;100;80m",   // hot red
        inner: "\u{1B}[38;2;200;80;120m",   // red-purple
        outer: "\u{1B}[38;2;120;60;180m",   // blue-purple
        spark: "\u{1B}[38;2;255;60;60m",    // bright red
        base:  "\u{1B}[38;2;140;100;120m"   // muted rose
    )

    /// Celebrating: full spectrum blue + gold accents.
    public static let celebrating = FlameColorPalette(
        core:  "\u{1B}[38;2;255;215;0m",    // gold
        inner: "\u{1B}[38;2;100;180;255m",  // bright blue
        outer: "\u{1B}[38;2;60;140;255m",   // royal blue
        spark: "\u{1B}[38;2;255;255;100m",  // yellow sparks
        base:  "\u{1B}[38;2;200;180;100m"   // warm gold
    )

    /// Lookup palette by emotion.
    public static func palette(for emotion: FlameEmotion) -> FlameColorPalette {
        switch emotion {
        case .calm: return .calm
        case .focused: return .focused
        case .excited: return .excited
        case .alarmed: return .alarmed
        case .celebrating: return .celebrating
        }
    }
}

// MARK: - FlameRenderer

/// Renders the Blue Flame mascot as colored ASCII art strings.
/// All output is returned as strings (never prints directly) for testability.
public enum FlameRenderer: Sendable {

    // MARK: - Public API

    /// Render a single frame of the flame at the given size, emotion, and frame index.
    /// Returns an array of ANSI-colored lines.
    public static func render(
        size: FlameSize,
        emotion: FlameEmotion,
        frame: Int
    ) -> [String] {
        switch size {
        case .mini:
            return renderMini(emotion: emotion, frame: frame)
        case .medium:
            return renderMedium(emotion: emotion, frame: frame)
        case .large:
            return renderLarge(emotion: emotion, frame: frame)
        }
    }

    /// Render to a single string (lines joined with newline).
    public static func renderToString(
        size: FlameSize,
        emotion: FlameEmotion,
        frame: Int
    ) -> String {
        render(size: size, emotion: emotion, frame: frame)
            .joined(separator: "\n")
    }

    /// Total frame count for a given size and emotion.
    public static func frameCount(size: FlameSize, emotion: FlameEmotion) -> Int {
        switch size {
        case .mini:
            return FlameArt.miniFrames[emotion]?.count ?? 1
        case .medium:
            return FlameArt.mediumFrames[emotion]?.count ?? 1
        case .large:
            return FlameArt.largeFrames[emotion]?.count ?? 1
        }
    }

    // MARK: - Mini Rendering

    private static func renderMini(emotion: FlameEmotion, frame: Int) -> [String] {
        guard let frames = FlameArt.miniFrames[emotion], !frames.isEmpty else {
            return ["."]
        }
        let idx = frame % frames.count
        let palette = FlameColorPalette.palette(for: emotion)
        let glyph = frames[idx]
        return ["\(palette.core)\(glyph)\(ANSI.reset)"]
    }

    // MARK: - Medium Rendering

    private static func renderMedium(emotion: FlameEmotion, frame: Int) -> [String] {
        guard let frames = FlameArt.mediumFrames[emotion], !frames.isEmpty else {
            return ["(.)"]
        }
        let idx = frame % frames.count
        let rawLines = frames[idx]
        let palette = FlameColorPalette.palette(for: emotion)
        return colorizeLines(rawLines, palette: palette)
    }

    // MARK: - Large Rendering

    private static func renderLarge(emotion: FlameEmotion, frame: Int) -> [String] {
        guard let frames = FlameArt.largeFrames[emotion], !frames.isEmpty else {
            return ["(.)"]
        }
        let idx = frame % frames.count
        let rawLines = frames[idx]
        let palette = FlameColorPalette.palette(for: emotion)
        return colorizeLines(rawLines, palette: palette)
    }

    // MARK: - Colorization

    /// Apply gradient coloring to flame lines.
    /// Top lines get spark/outer colors, middle lines get inner, core chars get core color.
    /// Base line (___ or |  |) gets base color.
    static func colorizeLines(_ lines: [String], palette: FlameColorPalette) -> [String] {
        guard !lines.isEmpty else { return [] }

        let total = lines.count
        return lines.enumerated().map { index, line in
            colorizeLine(line, lineIndex: index, totalLines: total, palette: palette)
        }
    }

    /// Colorize a single line based on its vertical position and character content.
    static func colorizeLine(
        _ line: String,
        lineIndex: Int,
        totalLines: Int,
        palette: FlameColorPalette
    ) -> String {
        // Base lines (last 2) — pedestal
        if lineIndex >= totalLines - 2 {
            return "\(palette.base)\(line)\(ANSI.reset)"
        }

        // Apply per-character coloring for flame body
        let chars = Array(line)
        var result = ""
        for char in chars {
            let color = colorForChar(
                char,
                lineIndex: lineIndex,
                totalLines: totalLines,
                palette: palette
            )
            result += "\(color)\(char)"
        }
        result += ANSI.reset
        return result
    }

    /// Determine color for a single character based on its role in the flame.
    private static func colorForChar(
        _ char: Character,
        lineIndex: Int,
        totalLines: Int,
        palette: FlameColorPalette
    ) -> String {
        switch char {
        // Sparks and accents
        case "*", "@", "#":
            return palette.spark

        // Core/center characters
        case "|", "!":
            return palette.core

        // Inner flame
        case ".", ":":
            return palette.inner

        // Outer flame structure
        case "/", "\\", "-", "'", "(", ")":
            // Top third: outer, bottom: inner, to create gradient
            let ratio = Double(lineIndex) / Double(max(totalLines - 2, 1))
            if ratio < 0.33 {
                return palette.outer
            } else if ratio < 0.66 {
                return palette.inner
            } else {
                return palette.outer
            }

        // Flame tip
        case "^":
            return palette.spark

        // Equals signs (celebration base)
        case "=":
            return palette.core

        // Space — no color needed
        case " ":
            return ""

        default:
            return palette.outer
        }
    }
}
