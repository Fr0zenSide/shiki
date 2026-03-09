//
//  DIEnvironment.swift
//  CoreKit
//
//  Extracted from WabiSabi — Created by Jeoffrey Thirot on 22/02/2026.
//

import Foundation

// MARK: - DI Environment

/// Defines the two dependency injection environments.
///
/// The backend host (dev/preprod/prod) is orthogonal — handled by your app's `Env` enum.
/// `DIEnvironment` only determines whether the app uses real or fake implementations.
public enum DIEnvironment: String, Sendable {
    /// Real implementations. Backend host determined by your app's environment config.
    case production
    /// Fake data for SwiftUI previews, development without backend, and tests.
    case mock
}
