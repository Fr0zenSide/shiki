//
//  Typography.swift
//  DesignKit
//
//  Extracted from WabiSabi Design System.
//

import SwiftUI

// MARK: - Type Scale

/// Standard type scale levels for a design system.
///
/// Sizes follow a harmonic progression anchored at 17pt body (iOS default).
/// Apps can override sizes via `TypographyProvider`.
///
/// | Level   | Default Size | Weight   | Use Case                          |
/// |---------|-------------|----------|-----------------------------------|
/// | display | 34pt        | Light    | Hero text, onboarding headlines   |
/// | title   | 28pt        | Regular  | Screen titles, section headers    |
/// | title3  | 20pt        | Medium   | Card titles, sub-headers          |
/// | body    | 17pt        | Regular  | Primary content text              |
/// | caption | 13pt        | Regular  | Timestamps, metadata, hints       |
/// | label   | 11pt        | Medium   | Badges, tags, uppercase labels    |
@frozen
public enum TypeScale: Sendable, CaseIterable {
    case display
    case title
    case title3
    case body
    case caption
    case label

    /// The default point size for this type scale level.
    public var defaultSize: CGFloat {
        switch self {
        case .display: 34
        case .title:   28
        case .title3:  20
        case .body:    17
        case .caption: 13
        case .label:   11
        }
    }

    /// The default font weight for this type scale level.
    public var defaultWeight: Font.Weight {
        switch self {
        case .display: .light
        case .title:   .regular
        case .title3:  .medium
        case .body:    .regular
        case .caption: .regular
        case .label:   .medium
        }
    }

    /// Whether this level should typically be rendered in uppercase.
    public var isUppercased: Bool {
        self == .label
    }
}

// MARK: - Typography Provider Protocol

/// Protocol for apps to supply their own font configuration.
///
/// Conform to this protocol to define custom fonts for each type scale level.
/// Use the default implementation for system fonts.
///
/// ```swift
/// struct MyAppTypography: TypographyProvider {
///     func font(for scale: TypeScale) -> Font {
///         switch scale {
///         case .display, .title, .title3:
///             return .custom("MySerifFont", size: scale.defaultSize)
///                 .weight(scale.defaultWeight)
///         case .body, .caption, .label:
///             return .custom("MySansFont", size: scale.defaultSize)
///                 .weight(scale.defaultWeight)
///         }
///     }
/// }
/// ```
public protocol TypographyProvider: Sendable {

    /// Returns the font for a given type scale level.
    /// - Parameter scale: The desired type scale.
    /// - Returns: A configured `Font` instance.
    func font(for scale: TypeScale) -> Font
}

// MARK: - Default Typography Provider

/// Default typography provider using system fonts.
///
/// Headings use serif design, body uses the system default.
public struct SystemTypographyProvider: TypographyProvider, Sendable {

    public init() {}

    public func font(for scale: TypeScale) -> Font {
        switch scale {
        case .display, .title, .title3:
            .system(size: scale.defaultSize, weight: scale.defaultWeight, design: .serif)
        case .body, .caption, .label:
            .system(size: scale.defaultSize, weight: scale.defaultWeight, design: .default)
        }
    }
}

// MARK: - Typography View Modifier

/// Applies typography styling to a view, including font, color, and case transform.
public struct TypographyModifier: ViewModifier {

    public let scale: TypeScale
    public let color: Color
    public let provider: any TypographyProvider

    public init(scale: TypeScale, color: Color, provider: any TypographyProvider = SystemTypographyProvider()) {
        self.scale = scale
        self.color = color
        self.provider = provider
    }

    public func body(content: Content) -> some View {
        if scale.isUppercased {
            content
                .font(provider.font(for: scale))
                .foregroundStyle(color)
                .textCase(.uppercase)
                .tracking(1.2)
        } else {
            content
                .font(provider.font(for: scale))
                .foregroundStyle(color)
        }
    }
}

// MARK: - View Extension

extension View {

    /// Applies design system typography at the given scale.
    /// - Parameters:
    ///   - scale: The type scale level to apply.
    ///   - color: Text color. Defaults to primary label.
    ///   - provider: Typography provider for font resolution. Defaults to system fonts.
    /// - Returns: A styled view.
    public func typography(
        _ scale: TypeScale,
        color: Color = DefaultColors.defaultTextPrimary,
        provider: any TypographyProvider = SystemTypographyProvider()
    ) -> some View {
        modifier(TypographyModifier(scale: scale, color: color, provider: provider))
    }
}
