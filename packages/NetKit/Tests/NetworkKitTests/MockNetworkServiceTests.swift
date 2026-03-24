//
//  MockNetworkServiceTests.swift
//  NetworkKitTests
//

import Combine
import Foundation
import Testing
@testable import NetKit

// MARK: - Test Model

private struct User: Codable, Equatable, Sendable {
    let id: Int
    let name: String
}

private struct MockEndPoint: EndPoint, @unchecked Sendable {
    var host: String = "api.example.com"
    var path: String = "/users/1"
    var method: RequestMethod = .GET
    var header: [String: String]? = nil
    var body: [String: Any]? = nil
    var queryParams: [String: Any]? = nil
}

// MARK: - Tests

@Suite("MockNetworkService Tests")
struct MockNetworkServiceTests {

    @Test("Returns decoded model from configured data")
    func returnsDecodedModel() async throws {
        let mock = MockNetworkService()
        let expectedUser = User(id: 1, name: "Alice")
        mock.resultData = try JSONEncoder().encode(expectedUser)

        let result: User = try await mock.sendRequest(endpoint: MockEndPoint())

        #expect(result == expectedUser)
        #expect(mock.capturedRequests.count == 1)
    }

    @Test("Throws configured error")
    func throwsConfiguredError() async {
        let mock = MockNetworkService()
        mock.resultError = .invalidData

        do {
            let _: User = try await mock.sendRequest(endpoint: MockEndPoint())
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as NetworkError {
            #expect(error.description == "Invalid data")
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test("Throws unexpectedStatusCode for non-2xx/3xx")
    func throwsForBadStatusCode() async {
        let mock = MockNetworkService()
        mock.statusCode = 500
        mock.resultData = try? JSONEncoder().encode(User(id: 1, name: "Alice"))

        do {
            let _: User = try await mock.sendRequest(endpoint: MockEndPoint())
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as NetworkError {
            #expect(error.description == "Invalid status code: 500")
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test("Throws invalidData when no data configured")
    func throwsInvalidDataWhenNoData() async {
        let mock = MockNetworkService()

        do {
            let _: User = try await mock.sendRequest(endpoint: MockEndPoint())
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as NetworkError {
            #expect(error.description == "Invalid data")
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test("Callback variant returns success")
    func callbackSuccess() async {
        let mock = MockNetworkService()
        let expectedUser = User(id: 2, name: "Bob")
        mock.resultData = try? JSONEncoder().encode(expectedUser)

        await withCheckedContinuation { continuation in
            mock.sendRequest(endpoint: MockEndPoint()) { (result: Result<User, NetworkError>) in
                switch result {
                case .success(let user):
                    #expect(user == expectedUser)
                case .failure(let error):
                    #expect(Bool(false), "Unexpected failure: \(error)")
                }
                continuation.resume()
            }
        }
    }

    @Test("Callback variant returns failure")
    func callbackFailure() async {
        let mock = MockNetworkService()
        mock.resultError = .requestFailed(description: "network down")

        await withCheckedContinuation { continuation in
            mock.sendRequest(endpoint: MockEndPoint()) { (result: Result<User, NetworkError>) in
                switch result {
                case .success:
                    #expect(Bool(false), "Expected failure")
                case .failure(let error):
                    #expect(error.description == "Request failed: network down")
                }
                continuation.resume()
            }
        }
    }

    @Test("Captures multiple requests")
    func capturesMultipleRequests() async throws {
        let mock = MockNetworkService()
        let user = User(id: 1, name: "Test")
        mock.resultData = try JSONEncoder().encode(user)

        let _: User = try await mock.sendRequest(endpoint: MockEndPoint())
        let _: User = try await mock.sendRequest(endpoint: MockEndPoint())

        #expect(mock.capturedRequests.count == 2)
    }
}
