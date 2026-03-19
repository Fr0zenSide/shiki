//
//  Spacing.swift
//  DesignKit
//
//  Extracted from WabiSabi Design System.
//

import SwiftUI

// MARK: - Spacing Scale

/// Spacing tokens following a geometric progression (base 8, with 4 as half-step).
/// Use these for all padding, margins, and gaps to maintain visual rhythm.
@frozen
public enum SpacingScale: CGFloat, Sendable, CaseIterable {

    /// 4pt -- tight spacing for inline elements, icon padding.
    case xs = 4

    /// 8pt -- compact spacing for list items, small gaps.
    case sm = 8

    /// 16pt -- standard spacing for content padding, section gaps.
    case md = 16

    /// 32pt -- generous spacing for section separators, grouped content.
    case lg = 32

    /// 64pt -- large spacing for page-level breathing room.
    case xl = 64

    /// 96pt -- extra-large spacing for hero sections, onboarding.
    case xxl = 96
}

// MARK: - Corner Radius

/// Corner radius tokens for consistent rounding across the app.
@frozen
public enum CornerRadiusScale: CGFloat, Sendable, CaseIterable {

    /// 4pt -- subtle rounding for small elements (badges, chips).
    case small = 4

    /// 6pt -- mild rounding for buttons and input fields.
    case medium = 6

    /// 12pt -- card-level rounding for content containers.
    case card = 12

    /// 20pt -- pill shape for badges and tags.
    case badge = 20
}

// MARK: - Shadow Definitions

/// Shadow token for card elevation -- subtle, color-scheme-aware.
public struct CardShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public func body(content: Content) -> some View {
        content.shadow(
            color: colorScheme == .dark
                ? Color.black.opacity(0.4)
                : Color.gray.opacity(0.15),
            radius: 8,
            x: 0,
            y: 4
        )
    }
}

/// Shadow token for interactive elements (buttons) -- tighter, more focused.
public struct ButtonShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public func body(content: Content) -> some View {
        content.shadow(
            color: colorScheme == .dark
                ? Color.black.opacity(0.3)
                : Color.gray.opacity(0.12),
            radius: 4,
            x: 0,
            y: 2
        )
    }
}

/// Shadow token for elevated overlays (modals, popovers).
public struct ElevatedShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public func body(content: Content) -> some View {
        content.shadow(
            color: colorScheme == .dark
                ? Color.black.opacity(0.5)
                : Color.gray.opacity(0.2),
            radius: 16,
            x: 0,
            y: 8
        )
    }
}

// MARK: - View Extensions

extension View {

    /// Applies a subtle card-level shadow.
    public func shadowCard() -> some View {
        modifier(CardShadow())
    }

    /// Applies a focused button-level shadow.
    public func shadowButton() -> some View {
        modifier(ButtonShadow())
    }

    /// Applies an elevated overlay shadow for modals and popovers.
    public func shadowElevated() -> some View {
        modifier(ElevatedShadow())
    }

    /// Applies standard card styling: surface background, card radius, card shadow.
    /// - Parameters:
    ///   - backgroundColor: The card background color. Defaults to system secondary background.
    ///   - cornerRadius: The corner radius. Defaults to `.card` (12pt).
    /// - Returns: A styled view.
    public func cardStyle(
        backgroundColor: Color = DefaultColors.defaultSurface,
        cornerRadius: CornerRadiusScale = .card
    ) -> some View {
        self
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius.rawValue))
            .shadowCard()
    }

    /// Applies page-level horizontal padding using the standard spacing token.
    public func pagePadding() -> some View {
        self.padding(.horizontal, SpacingScale.md.rawValue)
    }
}
