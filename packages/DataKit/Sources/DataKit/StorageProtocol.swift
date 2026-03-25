public protocol StorageProtocol: Sendable {
    func get<T: Codable & Sendable>(id: String, from table: String) async throws -> T
    func getAll<T: Codable & Sendable>(from table: String, filter: StorageFilter?) async throws -> [T]
    func insert<T: Codable & Sendable>(_ item: T, into table: String) async throws
    func update<T: Codable & Sendable>(id: String, _ item: T, in table: String) async throws
    func delete(id: String, from table: String) async throws
    func count(in table: String, filter: StorageFilter?) async throws -> Int
    func execute(sql: String, params: [String]) async throws
    func query<T: Codable & Sendable>(sql: String, params: [String]) async throws -> [T]
}
