//
//  ThemeTests.swift
//  DesignKit
//

import Testing
import SwiftUI
@testable import DesignKit

@Suite("Theme Tests")
struct ThemeTests {

    @Test("DefaultTheme conforms to AppTheme and provides all tokens")
    func defaultThemeConformance() {
        let theme = DefaultTheme.shared

        // Colors
        _ = theme.colors.background
        _ = theme.colors.surface
        _ = theme.colors.surfaceAlt
        _ = theme.colors.textPrimary
        _ = theme.colors.textSecondary
        _ = theme.colors.textMuted
        _ = theme.colors.accent
        _ = theme.colors.accentPressed
        _ = theme.colors.border
        _ = theme.colors.error
        _ = theme.colors.success

        // Typography
        _ = theme.typography.displayFont
        _ = theme.typography.titleFont
        _ = theme.typography.title3Font
        _ = theme.typography.bodyFont
        _ = theme.typography.captionFont
        _ = theme.typography.labelFont

        // Spacing
        #expect(theme.spacing.xs == 4)
        #expect(theme.spacing.sm == 8)
        #expect(theme.spacing.md == 16)
        #expect(theme.spacing.lg == 32)
        #expect(theme.spacing.xl == 64)
        #expect(theme.spacing.xxl == 96)
    }

    @Test("DefaultTheme.shared is a singleton value")
    func defaultThemeSingleton() {
        let a = DefaultTheme.shared
        let b = DefaultTheme.shared
        #expect(a.spacing.md == b.spacing.md)
    }

    @Test("Custom theme can conform to AppTheme")
    func customThemeConformance() {
        struct TestColors: ThemeColors, Sendable {
            let background = Color.white
            let surface = Color.white
            let surfaceAlt = Color.gray
            let textPrimary = Color.black
            let textSecondary = Color.gray
            let textMuted = Color.gray
            let accent = Color.blue
            let accentPressed = Color.blue
            let border = Color.gray
            let error = Color.red
            let success = Color.green
        }

        struct TestTypography: ThemeTypography, Sendable {
            let displayFont = Font.largeTitle
            let titleFont = Font.title
            let title3Font = Font.title3
            let bodyFont = Font.body
            let captionFont = Font.caption
            let labelFont = Font.caption2
        }

        struct TestSpacing: ThemeSpacing, Sendable {
            let xs: CGFloat = 2
            let sm: CGFloat = 4
            let md: CGFloat = 8
            let lg: CGFloat = 16
            let xl: CGFloat = 32
            let xxl: CGFloat = 48
            let cornerSmall: CGFloat = 2
            let cornerMedium: CGFloat = 4
            let cornerCard: CGFloat = 8
            let cornerBadge: CGFloat = 16
        }

        struct TestTheme: AppTheme, Sendable {
            let colors = TestColors()
            let typography = TestTypography()
            let spacing = TestSpacing()
        }

        let theme = TestTheme()
        #expect(theme.spacing.md == 8)
        #expect(theme.spacing.xs == 2)
    }

    @MainActor
    @Test("ThemeManager holds and updates theme")
    func themeManagerBasics() {
        let manager = ThemeManager(theme: DefaultTheme.shared)
        #expect(manager.currentTheme.spacing.md == 16)
        #expect(manager.isTransitioning == false)

        let custom = DefaultTheme(spacing: DefaultSpacing(md: 24))
        manager.setTheme(custom)
        #expect(manager.currentTheme.spacing.md == 24)
        #expect(manager.isTransitioning == false)
    }

    @MainActor
    @Test("ThemeManager animated transition sets flag")
    func themeManagerAnimatedTransition() {
        let manager = ThemeManager(theme: DefaultTheme.shared)
        let custom = DefaultTheme(spacing: DefaultSpacing(md: 24))
        manager.setTheme(custom, animated: true)
        #expect(manager.isTransitioning == true)
    }
}
