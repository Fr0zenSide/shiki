//
//  NetworkError.swift
//  NetworkKit
//
//  Extracted from WabiSabi — Created by Jeoffrey Thirot on 12/02/2024.
//

import Foundation

public enum NetworkError: Error, CustomStringConvertible, Sendable {
    case requestFailed(description: String)
    case unexpectedStatusCode(_ statusCode: Int, headers: String? = nil)
    case invalidData
    case jsonParsingFailed(_ error: DecodingError)
    case wsError(description: String)
    case unknown(_ error: any Error)

    public var description: String {
        switch self {
        case .requestFailed(let description):           return "Request failed: \(description)"
        case .unexpectedStatusCode(let statusCode, _):  return "Invalid status code: \(statusCode)"
        case .invalidData:                              return "Invalid data"
        case .jsonParsingFailed(let error):             return "Failed to parse JSON: \(error.localizedDescription)"
        case .wsError(let description):                 return "WebSocket error: \(description)"
        case .unknown(let error):                       return "An unknown error occurred \(error.localizedDescription)"
        }
    }
}
