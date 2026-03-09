//
//  ThemeEnvironment.swift
//  DesignKit
//
//  Extracted from WabiSabi Design System.
//

import SwiftUI

// MARK: - Environment Key

/// Environment key for injecting a `DefaultTheme` into the SwiftUI hierarchy.
///
/// For custom app themes, define your own `EnvironmentKey` and `EnvironmentValues`
/// extension in your app target following this same pattern.
///
/// ```swift
/// // In your app:
/// extension EnvironmentValues {
///     @Entry public var myAppTheme = MyAppTheme.light
/// }
/// ```
extension EnvironmentValues {

    /// The current design theme (using the built-in `DefaultTheme`).
    @Entry public var designTheme = DefaultTheme.shared
}

// MARK: - View Extension

extension View {

    /// Injects the given design theme into the environment.
    /// - Parameter theme: The theme to apply. Defaults to `.shared`.
    /// - Returns: A view with the theme injected.
    public func designTheme(_ theme: DefaultTheme = .shared) -> some View {
        self.environment(\.designTheme, theme)
    }
}
