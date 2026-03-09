//
//  KeychainError.swift
//  SecurityKit
//
//  Extracted from WabiSabi — Created by Jeoffrey Thirot on 17/02/2026.
//

import Foundation

/// Errors thrown by ``KeychainManager`` operations.
public enum KeychainError: Error, Sendable {
    case saveFailed
    case deleteFailed
    case itemNotFound
}
