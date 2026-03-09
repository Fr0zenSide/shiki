//
//  AuthPersistenceError.swift
//  SecurityKit
//
//  Extracted from WabiSabi — Created by Jeoffrey Thirot on 17/02/2026.
//

import Foundation

/// Errors thrown by ``AuthPersistenceManager`` operations.
public enum AuthPersistenceError: Error, Sendable {
    case noTokensAvailable
}
