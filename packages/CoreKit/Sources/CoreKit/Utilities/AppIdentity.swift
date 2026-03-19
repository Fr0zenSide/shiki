//
//  AppIdentity.swift
//  CoreKit
//
//  Extracted from WabiSabi — Created by Jeoffrey Thirot on 22/02/2026.
//

import Foundation

/// Configurable app identity constants.
///
/// Uses a stored property instead of `Bundle.main.bundleIdentifier`
/// to avoid `@MainActor` inference under Swift 6 strict concurrency.
///
/// **Setup:** Each app must set the bundle ID at launch:
/// ```swift
/// AppIdentity.bundleId = "com.example.MyApp"
/// ```
public enum AppIdentity: Sendable {
    /// Main app bundle identifier — must be set by the host app at launch.
    /// Defaults to the main bundle identifier if available, otherwise "CoreKit".
    nonisolated(unsafe) public static var bundleId: String = Bundle.main.bundleIdentifier ?? "CoreKit"
}
