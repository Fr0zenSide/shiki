//
//  ThemeManager.swift
//  DesignKit
//
//  Extracted from WabiSabi Design System.
//

import SwiftUI

// MARK: - Theme Manager

/// Generic observable theme manager that holds and transitions between themes.
///
/// `Theme` must conform to `AppTheme`. Apps supply their own concrete theme type.
///
/// ## Usage
/// ```swift
/// // Define your app theme
/// struct MyAppTheme: AppTheme { ... }
///
/// // Create manager
/// let manager = ThemeManager(theme: MyAppTheme.light)
///
/// // Update theme
/// manager.setTheme(MyAppTheme.dark, animated: true)
/// ```
@Observable
@MainActor
public final class ThemeManager<Theme: AppTheme> {

    // MARK: - State

    /// The currently active theme.
    public private(set) var currentTheme: Theme

    /// `true` briefly during an animated theme transition,
    /// giving the UI a chance to animate the color change.
    public private(set) var isTransitioning: Bool = false

    // MARK: - Configuration

    /// How long the transition flag stays active (seconds).
    public let transitionDuration: TimeInterval

    // MARK: - Init

    /// Creates a theme manager with an initial theme.
    /// - Parameters:
    ///   - theme: The initial theme to apply.
    ///   - transitionDuration: Duration for animated transitions. Defaults to 0.3s.
    public init(theme: Theme, transitionDuration: TimeInterval = 0.3) {
        self.currentTheme = theme
        self.transitionDuration = transitionDuration
    }

    // MARK: - Theme Update

    /// Sets a new theme, optionally animating the transition.
    ///
    /// - Parameters:
    ///   - theme: The new theme to apply.
    ///   - animated: Whether to set the `isTransitioning` flag for animation. Defaults to `false`.
    public func setTheme(_ theme: Theme, animated: Bool = false) {
        currentTheme = theme

        if animated {
            isTransitioning = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.transitionDuration))
                self.isTransitioning = false
            }
        }
    }
}
