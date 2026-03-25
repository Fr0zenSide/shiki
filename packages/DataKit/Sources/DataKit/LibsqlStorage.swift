import Foundation
@preconcurrency import Libsql

public final class LibsqlStorage: StorageProtocol, @unchecked Sendable {
    private let db: Database
    private let conn: Connection

    /// Creates a new LibsqlStorage instance.
    /// - Parameter path: File path for persistent storage, or `":memory:"` for in-memory databases.
    public init(path: String) throws {
        do {
            db = try Database(path)
            conn = try db.connect()
        } catch {
            throw StorageError.connectionFailed(error.localizedDescription)
        }
    }

    // MARK: - StorageProtocol

    public func get<T: Codable & Sendable>(id: String, from table: String) async throws -> T {
        let rows = try conn.query("SELECT data FROM \(table) WHERE id = ?", [id])
        for row in rows {
            let json = try row.getString(0)
            return try decode(json)
        }
        throw StorageError.notFound(table: table, id: id)
    }

    public func getAll<T: Codable & Sendable>(from table: String, filter: StorageFilter?) async throws -> [T] {
        var sql = "SELECT data FROM \(table)"
        var params: [String] = []

        if let filter {
            let (clause, filterParams) = filter.toSQL()
            sql += " WHERE \(clause)"
            params = filterParams
        }

        let rows: Rows
        if params.isEmpty {
            rows = try conn.query(sql)
        } else {
            rows = try conn.query(sql, params)
        }

        var items: [T] = []
        for row in rows {
            let json = try row.getString(0)
            items.append(try decode(json))
        }
        return items
    }

    public func insert<T: Codable & Sendable>(_ item: T, into table: String) async throws {
        let json = try encode(item)
        let id = try extractID(from: item)
        do {
            _ = try conn.execute(
                "INSERT INTO \(table) (id, data) VALUES (?, ?)",
                [id, json]
            )
        } catch {
            throw StorageError.insertFailed(error.localizedDescription)
        }
    }

    public func update<T: Codable & Sendable>(id: String, _ item: T, in table: String) async throws {
        let json = try encode(item)
        _ = try conn.execute(
            "UPDATE \(table) SET data = ? WHERE id = ?",
            [json, id]
        )
    }

    public func delete(id: String, from table: String) async throws {
        _ = try conn.execute("DELETE FROM \(table) WHERE id = ?", [id])
    }

    public func count(in table: String, filter: StorageFilter?) async throws -> Int {
        var sql = "SELECT COUNT(*) FROM \(table)"
        var params: [String] = []

        if let filter {
            let (clause, filterParams) = filter.toSQL()
            sql += " WHERE \(clause)"
            params = filterParams
        }

        let rows: Rows
        if params.isEmpty {
            rows = try conn.query(sql)
        } else {
            rows = try conn.query(sql, params)
        }

        for row in rows {
            return try Int(row.getInt(0))
        }
        return 0
    }

    public func execute(sql: String, params: [String]) async throws {
        do {
            if params.isEmpty {
                _ = try conn.execute(sql)
            } else {
                _ = try conn.execute(sql, params)
            }
        } catch {
            throw StorageError.queryFailed(error.localizedDescription)
        }
    }

    public func query<T: Codable & Sendable>(sql: String, params: [String]) async throws -> [T] {
        let rows: Rows
        do {
            if params.isEmpty {
                rows = try conn.query(sql)
            } else {
                rows = try conn.query(sql, params)
            }
        } catch {
            throw StorageError.queryFailed(error.localizedDescription)
        }

        var items: [T] = []
        for row in rows {
            let json = try row.getString(0)
            items.append(try decode(json))
        }
        return items
    }

    // MARK: - JSON Helpers

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func encode<T: Encodable>(_ item: T) throws -> String {
        let data = try encoder.encode(item)
        guard let string = String(data: data, encoding: .utf8) else {
            throw StorageError.insertFailed("Failed to encode item to JSON string")
        }
        return string
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw StorageError.queryFailed("Failed to decode JSON string")
        }
        return try decoder.decode(T.self, from: data)
    }

    /// Extracts the "id" field from a Codable item by encoding to JSON dictionary.
    private func extractID(from item: some Encodable) throws -> String {
        let data = try encoder.encode(item)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = dict["id"] else {
            throw StorageError.insertFailed("Item must have an 'id' field")
        }
        return "\(id)"
    }
}
