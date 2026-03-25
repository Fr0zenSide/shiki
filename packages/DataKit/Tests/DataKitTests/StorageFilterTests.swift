import Testing
@testable import DataKit

@Suite("StorageFilter SQL generation")
struct StorageFilterTests {

    @Test("equals generates column = ? with param")
    func equalsFilter() {
        let filter = StorageFilter.equals(column: "name", value: "Alice")
        let (clause, params) = filter.toSQL()

        #expect(clause == "name = ?")
        #expect(params == ["Alice"])
    }

    @Test("like generates column LIKE ? with param")
    func likeFilter() {
        let filter = StorageFilter.like(column: "title", pattern: "%swift%")
        let (clause, params) = filter.toSQL()

        #expect(clause == "title LIKE ?")
        #expect(params == ["%swift%"])
    }

    @Test("isNull generates column IS NULL with no params")
    func isNullFilter() {
        let filter = StorageFilter.isNull(column: "deleted_at")
        let (clause, params) = filter.toSQL()

        #expect(clause == "deleted_at IS NULL")
        #expect(params.isEmpty)
    }

    @Test("and composes filters with AND")
    func andFilter() {
        let filter = StorageFilter.and([
            .equals(column: "status", value: "active"),
            .like(column: "name", pattern: "%test%"),
        ])
        let (clause, params) = filter.toSQL()

        #expect(clause == "(status = ?) AND (name LIKE ?)")
        #expect(params == ["active", "%test%"])
    }

    @Test("or composes filters with OR")
    func orFilter() {
        let filter = StorageFilter.or([
            .equals(column: "role", value: "admin"),
            .equals(column: "role", value: "owner"),
        ])
        let (clause, params) = filter.toSQL()

        #expect(clause == "(role = ?) OR (role = ?)")
        #expect(params == ["admin", "owner"])
    }

    @Test("paramOffset shifts initial offset for nested filters")
    func paramOffset() {
        let filter = StorageFilter.and([
            .equals(column: "a", value: "1"),
            .equals(column: "b", value: "2"),
        ])
        let (clause, params) = filter.toSQL(paramOffset: 3)

        #expect(clause == "(a = ?) AND (b = ?)")
        #expect(params == ["1", "2"])
    }

    @Test("nested and/or compose correctly")
    func nestedComposition() {
        let filter = StorageFilter.and([
            .equals(column: "active", value: "1"),
            .or([
                .like(column: "name", pattern: "%foo%"),
                .isNull(column: "deleted_at"),
            ]),
        ])
        let (clause, params) = filter.toSQL()

        #expect(clause == "(active = ?) AND ((name LIKE ?) OR (deleted_at IS NULL))")
        #expect(params == ["1", "%foo%"])
    }

    @Test("Equatable conformance")
    func equatable() {
        let a = StorageFilter.equals(column: "x", value: "1")
        let b = StorageFilter.equals(column: "x", value: "1")
        let c = StorageFilter.equals(column: "x", value: "2")

        #expect(a == b)
        #expect(a != c)
    }
}
