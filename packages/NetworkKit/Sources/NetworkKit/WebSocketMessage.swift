//
//  WebSocketMessage.swift
//  NetKit
//

import Foundation

// MARK: - WebSocket Message

/// A message received from or sent through a ``WebSocketClient``.
///
/// ```swift
/// let message: WebSocketMessage = .text("{\"event\": \"ping\"}")
/// try await ws.send(message)
/// ```
public enum WebSocketMessage: Sendable {
    case text(String)
    case data(Data)
}

// MARK: - Connection State

/// Represents the lifecycle state of a ``WebSocketClient`` connection.
public enum WebSocketState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
}
