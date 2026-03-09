@testable import CoreKit
import XCTest

struct TestModel: Codable, Equatable, Sendable {
    let id: Int
    let name: String
}

final class CacheRepositoryTests: XCTestCase {

    var cache: CacheRepository<TestModel>!
    let testId = "test-item-\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        cache = CacheRepository<TestModel>("CacheRepoTests", invalidateTime: .inTime(ttl: 3600))
    }

    override func tearDown() {
        // Clean up any cached files
        try? cache.delete(testId)
        cache = nil
        super.tearDown()
    }

    // MARK: - Save & Get

    func testSaveAndGet() throws {
        let model = TestModel(id: 1, name: "Test")

        try cache.save(testId, data: model)
        XCTAssertTrue(cache.exists(testId))

        let retrieved: TestModel = try cache.get(testId)
        XCTAssertEqual(retrieved, model)
    }

    // MARK: - Exists

    func testExistsReturnsFalseWhenNotCached() {
        XCTAssertFalse(cache.exists("nonexistent-\(UUID().uuidString)"))
    }

    func testExistsReturnsTrueWhenCached() throws {
        let model = TestModel(id: 2, name: "Exists Test")
        try cache.save(testId, data: model)
        XCTAssertTrue(cache.exists(testId))
    }

    // MARK: - Delete

    func testDelete() throws {
        let model = TestModel(id: 3, name: "Delete Test")
        try cache.save(testId, data: model)
        XCTAssertTrue(cache.exists(testId))

        try cache.delete(testId)
        XCTAssertFalse(cache.exists(testId))
    }

    func testDeleteNonexistentThrows() {
        XCTAssertThrowsError(try cache.delete("nonexistent-\(UUID().uuidString)")) { error in
            guard let cacheError = error as? CacheRepositoryError else {
                XCTFail("Expected CacheRepositoryError, got \(error)")
                return
            }
            XCTAssertEqual(String(describing: cacheError), String(describing: CacheRepositoryError.notFound))
        }
    }

    // MARK: - Get Non-existent

    func testGetNonexistentThrows() {
        XCTAssertThrowsError(try cache.get("nonexistent-\(UUID().uuidString)")) { error in
            guard let cacheError = error as? CacheRepositoryError else {
                XCTFail("Expected CacheRepositoryError, got \(error)")
                return
            }
            XCTAssertEqual(String(describing: cacheError), String(describing: CacheRepositoryError.notFound))
        }
    }

    // MARK: - TTL Expiry

    func testExpiredCacheIsInvalidated() throws {
        // Create a cache with 0 TTL (immediately expired)
        let expiredCache = CacheRepository<TestModel>("CacheRepoExpiredTests", invalidateTime: .inTime(ttl: 0))
        let expiredId = "expired-\(UUID().uuidString)"
        let model = TestModel(id: 4, name: "Expired")

        try expiredCache.save(expiredId, data: model)
        XCTAssertTrue(expiredCache.exists(expiredId))

        // Should throw because cache is expired (and hasNetwork defaults to true in sync version)
        XCTAssertThrowsError(try expiredCache.get(expiredId))
    }

    // MARK: - Never Invalidate

    func testNeverInvalidateAlwaysReturns() throws {
        let neverCache = CacheRepository<TestModel>("CacheRepoNeverTests", invalidateTime: .never)
        let neverId = "never-\(UUID().uuidString)"
        let model = TestModel(id: 5, name: "Never Expire")

        try neverCache.save(neverId, data: model)
        let retrieved: TestModel = try neverCache.get(neverId)
        XCTAssertEqual(retrieved, model)

        // Cleanup
        try? neverCache.delete(neverId)
    }
}
