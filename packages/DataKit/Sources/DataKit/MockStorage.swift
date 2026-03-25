import Foundation

public final class MockStorage: StorageProtocol, @unchecked Sendable {
    private var tables: [String: [String: Data]] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Call Tracking

    public private(set) var getCallCount = 0
    public private(set) var getAllCallCount = 0
    public private(set) var insertCallCount = 0
    public private(set) var updateCallCount = 0
    public private(set) var deleteCallCount = 0
    public private(set) var countCallCount = 0
    public private(set) var executeCallCount = 0
    public private(set) var queryCallCount = 0

    public init() {}

    public func reset() {
        tables = [:]
        getCallCount = 0
        getAllCallCount = 0
        insertCallCount = 0
        updateCallCount = 0
        deleteCallCount = 0
        countCallCount = 0
        executeCallCount = 0
        queryCallCount = 0
    }

    // MARK: - StorageProtocol

    public func get<T: Codable & Sendable>(id: String, from table: String) async throws -> T {
        getCallCount += 1
        guard let data = tables[table]?[id] else {
            throw StorageError.notFound(table: table, id: id)
        }
        return try decoder.decode(T.self, from: data)
    }

    public func getAll<T: Codable & Sendable>(from table: String, filter: StorageFilter?) async throws -> [T] {
        getAllCallCount += 1
        guard let rows = tables[table] else { return [] }
        return try rows.values.map { try decoder.decode(T.self, from: $0) }
    }

    public func insert<T: Codable & Sendable>(_ item: T, into table: String) async throws {
        insertCallCount += 1
        let data = try encoder.encode(item)
        let id = try extractID(from: item)
        if tables[table] == nil {
            tables[table] = [:]
        }
        tables[table]?[id] = data
    }

    public func update<T: Codable & Sendable>(id: String, _ item: T, in table: String) async throws {
        updateCallCount += 1
        let data = try encoder.encode(item)
        if tables[table] == nil {
            tables[table] = [:]
        }
        tables[table]?[id] = data
    }

    public func delete(id: String, from table: String) async throws {
        deleteCallCount += 1
        tables[table]?[id] = nil
    }

    public func count(in table: String, filter: StorageFilter?) async throws -> Int {
        countCallCount += 1
        return tables[table]?.count ?? 0
    }

    public func execute(sql: String, params: [String]) async throws {
        executeCallCount += 1
        // No-op for mock
    }

    public func query<T: Codable & Sendable>(sql: String, params: [String]) async throws -> [T] {
        queryCallCount += 1
        return []
    }

    // MARK: - Helpers

    private func extractID(from item: some Encodable) throws -> String {
        let data = try encoder.encode(item)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = dict["id"] else {
            throw StorageError.insertFailed("Item must have an 'id' field")
        }
        return "\(id)"
    }
}
