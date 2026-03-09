//
//  MockNetworkService.swift
//  NetworkKit
//
//  Created for testing convenience.
//

import Combine
import Foundation

/// A mock implementation of `NetworkProtocol` that returns configurable responses.
///
/// Usage:
/// ```swift
/// let mock = MockNetworkService()
/// mock.resultData = try JSONEncoder().encode(myModel)
/// let result: MyModel = try await mock.sendRequest(endpoint: someEndpoint)
/// ```
public final class MockNetworkService: NetworkProtocol, @unchecked Sendable {

    // MARK: - Configurable State

    /// The raw data to return from requests. Encode your expected model into this.
    public var resultData: Data?

    /// An optional error to throw instead of returning data.
    public var resultError: NetworkError?

    /// The HTTP status code the mock pretends to return (default 200).
    public var statusCode: Int = 200

    /// Tracks every `URLRequest` created via `createRequest(endPoint:)`.
    public private(set) var capturedRequests: [URLRequest] = []

    public init() {}

    // MARK: - NetworkProtocol

    public func sendRequest<T: Decodable>(endpoint: EndPoint) async throws -> T {
        let request = createRequest(endPoint: endpoint)
        capturedRequests.append(request)

        if let error = resultError {
            throw error
        }

        guard 200..<400 ~= statusCode else {
            throw NetworkError.unexpectedStatusCode(statusCode)
        }

        guard let data = resultData else {
            throw NetworkError.invalidData
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as DecodingError {
            throw NetworkError.jsonParsingFailed(error)
        } catch {
            throw NetworkError.unknown(error)
        }
    }

    public func sendRequest<T: Decodable>(endpoint: EndPoint, resultHandler: @escaping (Result<T, NetworkError>) -> Void) {
        let request = createRequest(endPoint: endpoint)
        capturedRequests.append(request)

        if let error = resultError {
            resultHandler(.failure(error))
            return
        }

        guard 200..<400 ~= statusCode else {
            resultHandler(.failure(.unexpectedStatusCode(statusCode)))
            return
        }

        guard let data = resultData else {
            resultHandler(.failure(.invalidData))
            return
        }

        do {
            let decoded = try JSONDecoder().decode(T.self, from: data)
            resultHandler(.success(decoded))
        } catch let error as DecodingError {
            resultHandler(.failure(.jsonParsingFailed(error)))
        } catch {
            resultHandler(.failure(.unknown(error)))
        }
    }

    public func sendRequest<T: Decodable>(endpoint: EndPoint, type: T.Type) -> AnyPublisher<T, NetworkError> {
        let request = createRequest(endPoint: endpoint)
        capturedRequests.append(request)

        if let error = resultError {
            return Fail(error: error).eraseToAnyPublisher()
        }

        guard 200..<400 ~= statusCode else {
            return Fail(error: NetworkError.unexpectedStatusCode(statusCode)).eraseToAnyPublisher()
        }

        guard let data = resultData else {
            return Fail(error: NetworkError.invalidData).eraseToAnyPublisher()
        }

        return Just(data)
            .decode(type: T.self, decoder: JSONDecoder())
            .mapError { error -> NetworkError in
                if let error = error as? DecodingError {
                    return .jsonParsingFailed(error)
                }
                return .unknown(error)
            }
            .eraseToAnyPublisher()
    }
}
