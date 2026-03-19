//
//  AppTheme.swift
//  DesignKit
//
//  Extracted from WabiSabi Design System.
//

import SwiftUI

// MARK: - Theme Protocols

/// Semantic color roles that every theme must provide.
///
/// Apps conform to this protocol with their own palette values.
/// DesignKit provides the mechanism; apps provide the colors.
public protocol ThemeColors: Sendable {

    /// Primary page background.
    var background: Color { get }
    /// Card and content surface.
    var surface: Color { get }
    /// Alternate surface for visual rhythm.
    var surfaceAlt: Color { get }
    /// Primary text color.
    var textPrimary: Color { get }
    /// Secondary text color.
    var textSecondary: Color { get }
    /// Muted text for metadata.
    var textMuted: Color { get }
    /// Primary interactive accent.
    var accent: Color { get }
    /// Accent pressed/active state.
    var accentPressed: Color { get }
    /// Border and divider color.
    var border: Color { get }
    /// Error state color.
    var error: Color { get }
    /// Success state color.
    var success: Color { get }
}

/// Typography configuration that every theme must provide.
///
/// Apps conform with their own font families and type scales.
public protocol ThemeTypography: Sendable {

    /// Large display font for hero text.
    var displayFont: Font { get }
    /// Screen title font.
    var titleFont: Font { get }
    /// Sub-header / card title font.
    var title3Font: Font { get }
    /// Primary body text font.
    var bodyFont: Font { get }
    /// Small caption font for metadata.
    var captionFont: Font { get }
    /// Tiny label font for badges/tags.
    var labelFont: Font { get }
}

/// Spacing and layout tokens that every theme must provide.
public protocol ThemeSpacing: Sendable {

    /// Extra-small spacing (e.g. 4pt).
    var xs: CGFloat { get }
    /// Small spacing (e.g. 8pt).
    var sm: CGFloat { get }
    /// Medium spacing (e.g. 16pt).
    var md: CGFloat { get }
    /// Large spacing (e.g. 32pt).
    var lg: CGFloat { get }
    /// Extra-large spacing (e.g. 64pt).
    var xl: CGFloat { get }
    /// Extra-extra-large spacing (e.g. 96pt).
    var xxl: CGFloat { get }

    /// Small corner radius.
    var cornerSmall: CGFloat { get }
    /// Medium corner radius.
    var cornerMedium: CGFloat { get }
    /// Card corner radius.
    var cornerCard: CGFloat { get }
    /// Badge/pill corner radius.
    var cornerBadge: CGFloat { get }
}

/// A complete design theme that bundles colors, typography, and spacing.
///
/// Apps define concrete types conforming to `AppTheme` to supply
/// their own branded design tokens while sharing the same theme engine.
public protocol AppTheme: Sendable {

    associatedtype Colors: ThemeColors
    associatedtype Typography: ThemeTypography
    associatedtype Spacing: ThemeSpacing

    /// Color tokens for the current theme.
    var colors: Colors { get }
    /// Typography configuration for the current theme.
    var typography: Typography { get }
    /// Spacing and layout tokens for the current theme.
    var spacing: Spacing { get }
}

// MARK: - Default Theme

/// A minimal default theme providing sensible fallback values.
///
/// Apps can use `DefaultTheme` as a starting point or fallback
/// while developing their own branded theme.
public struct DefaultTheme: AppTheme, Sendable {

    public let colors: DefaultColors
    public let typography: DefaultTypography
    public let spacing: DefaultSpacing

    public init(
        colors: DefaultColors = DefaultColors(),
        typography: DefaultTypography = DefaultTypography(),
        spacing: DefaultSpacing = DefaultSpacing()
    ) {
        self.colors = colors
        self.typography = typography
        self.spacing = spacing
    }

    /// The shared default theme instance.
    public static let shared = DefaultTheme()
}

// MARK: - Default Colors

/// Neutral color palette that works in both light and dark mode.
public struct DefaultColors: ThemeColors, Sendable {

    public let background: Color
    public let surface: Color
    public let surfaceAlt: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let textMuted: Color
    public let accent: Color
    public let accentPressed: Color
    public let border: Color
    public let error: Color
    public let success: Color

    // MARK: - Platform-Agnostic Default Colors

    /// Default background using hex values that work on all platforms.
    public static let defaultBackground = Color(hex: "F2F2F7")
    /// Default surface color.
    public static let defaultSurface = Color(hex: "FFFFFF")
    /// Default alternate surface color.
    public static let defaultSurfaceAlt = Color(hex: "E5E5EA")
    /// Default primary text color.
    public static let defaultTextPrimary = Color(hex: "000000")
    /// Default secondary text color.
    public static let defaultTextSecondary = Color(hex: "3C3C43")
    /// Default muted text color.
    public static let defaultTextMuted = Color(hex: "8E8E93")
    /// Default border/separator color.
    public static let defaultBorder = Color(hex: "C6C6C8")

    public init(
        background: Color = DefaultColors.defaultBackground,
        surface: Color = DefaultColors.defaultSurface,
        surfaceAlt: Color = DefaultColors.defaultSurfaceAlt,
        textPrimary: Color = DefaultColors.defaultTextPrimary,
        textSecondary: Color = DefaultColors.defaultTextSecondary,
        textMuted: Color = DefaultColors.defaultTextMuted,
        accent: Color = .accentColor,
        accentPressed: Color = .accentColor.opacity(0.8),
        border: Color = DefaultColors.defaultBorder,
        error: Color = .red,
        success: Color = .green
    ) {
        self.background = background
        self.surface = surface
        self.surfaceAlt = surfaceAlt
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textMuted = textMuted
        self.accent = accent
        self.accentPressed = accentPressed
        self.border = border
        self.error = error
        self.success = success
    }
}

// MARK: - Default Typography

/// System font-based typography using the iOS type scale.
public struct DefaultTypography: ThemeTypography, Sendable {

    public let displayFont: Font
    public let titleFont: Font
    public let title3Font: Font
    public let bodyFont: Font
    public let captionFont: Font
    public let labelFont: Font

    public init(
        displayFont: Font = .system(size: 34, weight: .light, design: .serif),
        titleFont: Font = .system(size: 28, weight: .regular, design: .serif),
        title3Font: Font = .system(size: 20, weight: .medium, design: .serif),
        bodyFont: Font = .system(size: 17, weight: .regular, design: .default),
        captionFont: Font = .system(size: 13, weight: .regular, design: .default),
        labelFont: Font = .system(size: 11, weight: .medium, design: .default)
    ) {
        self.displayFont = displayFont
        self.titleFont = titleFont
        self.title3Font = title3Font
        self.bodyFont = bodyFont
        self.captionFont = captionFont
        self.labelFont = labelFont
    }
}

// MARK: - Default Spacing

/// Standard 4/8-based spacing scale with corner radii.
public struct DefaultSpacing: ThemeSpacing, Sendable {

    public let xs: CGFloat
    public let sm: CGFloat
    public let md: CGFloat
    public let lg: CGFloat
    public let xl: CGFloat
    public let xxl: CGFloat
    public let cornerSmall: CGFloat
    public let cornerMedium: CGFloat
    public let cornerCard: CGFloat
    public let cornerBadge: CGFloat

    public init(
        xs: CGFloat = 4,
        sm: CGFloat = 8,
        md: CGFloat = 16,
        lg: CGFloat = 32,
        xl: CGFloat = 64,
        xxl: CGFloat = 96,
        cornerSmall: CGFloat = 4,
        cornerMedium: CGFloat = 6,
        cornerCard: CGFloat = 12,
        cornerBadge: CGFloat = 20
    ) {
        self.xs = xs
        self.sm = sm
        self.md = md
        self.lg = lg
        self.xl = xl
        self.xxl = xxl
        self.cornerSmall = cornerSmall
        self.cornerMedium = cornerMedium
        self.cornerCard = cornerCard
        self.cornerBadge = cornerBadge
    }
}
