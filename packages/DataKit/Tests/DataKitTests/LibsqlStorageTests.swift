import Foundation
import Testing
@testable import DataKit

// Test model
struct Item: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let score: Int
}

@Suite("LibsqlStorage integration tests")
struct LibsqlStorageTests {

    private func makeStorage() async throws -> LibsqlStorage {
        let storage = try LibsqlStorage(path: ":memory:")
        // Create a test table with id + data columns (the convention LibsqlStorage uses)
        try await storage.execute(
            sql: "CREATE TABLE items (id TEXT PRIMARY KEY, data TEXT NOT NULL)",
            params: []
        )
        return storage
    }

    // MARK: - CRUD Cycle

    @Test("insert and get round-trip")
    func insertAndGet() async throws {
        let storage = try await makeStorage()
        let item = Item(id: "1", name: "Test", score: 42)

        try await storage.insert(item, into: "items")
        let fetched: Item = try await storage.get(id: "1", from: "items")

        #expect(fetched == item)
    }

    @Test("get throws notFound for missing item")
    func getNotFound() async throws {
        let storage = try await makeStorage()

        await #expect(throws: StorageError.self) {
            let _: Item = try await storage.get(id: "missing", from: "items")
        }
    }

    @Test("update modifies existing item")
    func updateItem() async throws {
        let storage = try await makeStorage()
        let original = Item(id: "1", name: "Original", score: 10)
        try await storage.insert(original, into: "items")

        let updated = Item(id: "1", name: "Updated", score: 99)
        try await storage.update(id: "1", updated, in: "items")

        let fetched: Item = try await storage.get(id: "1", from: "items")
        #expect(fetched.name == "Updated")
        #expect(fetched.score == 99)
    }

    @Test("delete removes item")
    func deleteItem() async throws {
        let storage = try await makeStorage()
        let item = Item(id: "1", name: "ToDelete", score: 0)
        try await storage.insert(item, into: "items")

        try await storage.delete(id: "1", from: "items")

        await #expect(throws: StorageError.self) {
            let _: Item = try await storage.get(id: "1", from: "items")
        }
    }

    // MARK: - getAll

    @Test("getAll returns all items")
    func getAllItems() async throws {
        let storage = try await makeStorage()
        try await storage.insert(Item(id: "1", name: "A", score: 1), into: "items")
        try await storage.insert(Item(id: "2", name: "B", score: 2), into: "items")

        let all: [Item] = try await storage.getAll(from: "items", filter: nil)
        #expect(all.count == 2)
    }

    @Test("getAll with equals filter")
    func getAllWithFilter() async throws {
        let storage = try await makeStorage()
        // For filtering on columns, we need a table with actual columns
        try await storage.execute(
            sql: "CREATE TABLE tagged (id TEXT PRIMARY KEY, data TEXT NOT NULL, status TEXT NOT NULL)",
            params: []
        )
        // Insert via raw execute to control the status column
        let encoder = JSONEncoder()
        let item1 = Item(id: "1", name: "Active", score: 10)
        let item2 = Item(id: "2", name: "Inactive", score: 20)
        let json1 = String(data: try encoder.encode(item1), encoding: .utf8)!
        let json2 = String(data: try encoder.encode(item2), encoding: .utf8)!

        try await storage.execute(
            sql: "INSERT INTO tagged (id, data, status) VALUES (?, ?, ?)",
            params: ["1", json1, "active"]
        )
        try await storage.execute(
            sql: "INSERT INTO tagged (id, data, status) VALUES (?, ?, ?)",
            params: ["2", json2, "inactive"]
        )

        let active: [Item] = try await storage.getAll(
            from: "tagged",
            filter: .equals(column: "status", value: "active")
        )
        #expect(active.count == 1)
        #expect(active[0].name == "Active")
    }

    // MARK: - Count

    @Test("count returns correct number")
    func countItems() async throws {
        let storage = try await makeStorage()
        try await storage.insert(Item(id: "1", name: "A", score: 1), into: "items")
        try await storage.insert(Item(id: "2", name: "B", score: 2), into: "items")
        try await storage.insert(Item(id: "3", name: "C", score: 3), into: "items")

        let total = try await storage.count(in: "items", filter: nil)
        #expect(total == 3)
    }

    @Test("count with filter")
    func countWithFilter() async throws {
        let storage = try await makeStorage()
        try await storage.execute(
            sql: "CREATE TABLE scored (id TEXT PRIMARY KEY, data TEXT NOT NULL, level TEXT NOT NULL)",
            params: []
        )

        let encoder = JSONEncoder()
        for i in 1...5 {
            let item = Item(id: "\(i)", name: "Item\(i)", score: i)
            let json = String(data: try encoder.encode(item), encoding: .utf8)!
            try await storage.execute(
                sql: "INSERT INTO scored (id, data, level) VALUES (?, ?, ?)",
                params: ["\(i)", json, i > 3 ? "high" : "low"]
            )
        }

        let highCount = try await storage.count(
            in: "scored",
            filter: .equals(column: "level", value: "high")
        )
        #expect(highCount == 2)
    }

    // MARK: - Custom Query / Execute

    @Test("execute runs raw SQL")
    func executeRawSQL() async throws {
        let storage = try await makeStorage()

        try await storage.execute(
            sql: "CREATE TABLE custom (key TEXT PRIMARY KEY, value TEXT)",
            params: []
        )
        try await storage.execute(
            sql: "INSERT INTO custom (key, value) VALUES (?, ?)",
            params: ["greeting", "hello"]
        )

        // Verify via query
        let count = try await storage.count(in: "custom", filter: nil)
        #expect(count == 1)
    }

    @Test("query returns decoded results")
    func queryCustomSQL() async throws {
        let storage = try await makeStorage()
        try await storage.insert(Item(id: "1", name: "Found", score: 100), into: "items")

        let results: [Item] = try await storage.query(
            sql: "SELECT data FROM items WHERE id = ?",
            params: ["1"]
        )
        #expect(results.count == 1)
        #expect(results[0].name == "Found")
    }

    // MARK: - Full CRUD cycle

    @Test("full CRUD cycle: insert, get, update, get, delete, verify gone")
    func fullCRUDCycle() async throws {
        let storage = try await makeStorage()

        // Create
        let item = Item(id: "cycle-1", name: "Created", score: 1)
        try await storage.insert(item, into: "items")

        // Read
        let read: Item = try await storage.get(id: "cycle-1", from: "items")
        #expect(read == item)

        // Update
        let modified = Item(id: "cycle-1", name: "Modified", score: 999)
        try await storage.update(id: "cycle-1", modified, in: "items")
        let afterUpdate: Item = try await storage.get(id: "cycle-1", from: "items")
        #expect(afterUpdate == modified)

        // Delete
        try await storage.delete(id: "cycle-1", from: "items")

        // Verify gone
        await #expect(throws: StorageError.self) {
            let _: Item = try await storage.get(id: "cycle-1", from: "items")
        }
    }
}
