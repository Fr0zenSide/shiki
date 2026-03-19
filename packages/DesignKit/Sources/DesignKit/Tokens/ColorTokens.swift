//
//  ColorTokens.swift
//  DesignKit
//
//  Extracted from WabiSabi Design System.
//

import SwiftUI

// MARK: - Hex Color Initializer

/// Programmatic approach chosen over asset catalogs for several reasons:
/// 1. Single source of truth -- tokens defined in code, auditable in PRs
/// 2. Easier to generate dark-mode variants algorithmically
/// 3. No xcassets merge conflicts across branches
/// 4. Design tokens can be shared with other platforms (watchOS, macOS) trivially
extension Color {

    /// Creates a `Color` from a hex string (e.g. "#F5F0E8" or "F5F0E8").
    /// Supports 6-character (RGB) and 8-character (ARGB) hex strings.
    /// Returns `.clear` if the string is malformed.
    public init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        var rgbValue: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&rgbValue)

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        switch sanitized.count {
        case 6:
            red = Double((rgbValue >> 16) & 0xFF) / 255.0
            green = Double((rgbValue >> 8) & 0xFF) / 255.0
            blue = Double(rgbValue & 0xFF) / 255.0
            alpha = 1.0
        case 8:
            alpha = Double((rgbValue >> 24) & 0xFF) / 255.0
            red = Double((rgbValue >> 16) & 0xFF) / 255.0
            green = Double((rgbValue >> 8) & 0xFF) / 255.0
            blue = Double(rgbValue & 0xFF) / 255.0
        default:
            red = 0
            green = 0
            blue = 0
            alpha = 0
        }

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

// MARK: - Adaptive Color Helper

#if canImport(UIKit)
import UIKit

extension Color {

    /// Creates a color that adapts between light and dark mode.
    /// - Parameters:
    ///   - light: The color to use in light mode.
    ///   - dark: The color to use in dark mode.
    /// - Returns: A dynamic color that resolves based on the current color scheme.
    public init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }
}
#endif

#if canImport(AppKit) && !canImport(UIKit)
import AppKit

extension Color {

    /// Creates a color that adapts between light and dark mode (macOS).
    /// - Parameters:
    ///   - light: The color to use in light (aqua) appearance.
    ///   - dark: The color to use in dark appearance.
    /// - Returns: A dynamic color that resolves based on the current appearance.
    public init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        })
    }
}
#endif
