@testable import CoreKit
import XCTest

final class ContainerTests: XCTestCase {

    var container: Container!

    override func setUp() {
        super.setUp()
        container = Container(name: "Test")
    }

    override func tearDown() {
        container.cleanup()
        container = nil
        super.tearDown()
    }

    // MARK: - Registration & Resolution

    func testRegisterAndResolve() throws {
        container.register(String.self) { _ in "Hello" }

        let result: String = try container.resolve()
        XCTAssertEqual(result, "Hello")
    }

    func testResolveUnregisteredTypeThrows() {
        XCTAssertThrowsError(try container.resolve(Int.self)) { error in
            guard case ContainerError.notRegistered = error else {
                XCTFail("Expected notRegistered error, got \(error)")
                return
            }
        }
    }

    func testResolveOptionalReturnsNilWhenNotRegistered() {
        let result: Int? = container.resolveOptional(Int.self)
        XCTAssertNil(result)
    }

    func testResolveOptionalReturnsValueWhenRegistered() {
        container.register(Int.self) { _ in 42 }
        let result: Int? = container.resolveOptional(Int.self)
        XCTAssertEqual(result, 42)
    }

    // MARK: - Named Registrations

    func testNamedRegistrations() throws {
        container.register(String.self, name: "greeting") { _ in "Hello" }
        container.register(String.self, name: "farewell") { _ in "Goodbye" }

        let greeting: String = try container.resolve(String.self, name: "greeting")
        let farewell: String = try container.resolve(String.self, name: "farewell")

        XCTAssertEqual(greeting, "Hello")
        XCTAssertEqual(farewell, "Goodbye")
    }

    // MARK: - Scopes

    func testCachedScopeReturnsSameInstance() throws {
        var count = 0
        try container.register(Int.self, scope: .cached) { _ in
            count += 1
            return count
        }

        let a: Int = try container.resolve()
        let b: Int = try container.resolve()
        XCTAssertEqual(a, b)
        XCTAssertEqual(count, 1)
    }

    func testTransientScopeReturnsDifferentInstances() throws {
        var count = 0
        try container.register(Int.self, scope: .transient) { _ in
            count += 1
            return count
        }

        let a: Int = try container.resolve()
        let b: Int = try container.resolve()
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Circular Dependency Detection

    func testCircularDependencyDetection() {
        container.register(String.self) { resolver in
            let _: Int = try resolver.resolve(Int.self)
            return "unreachable"
        }
        container.register(Int.self) { resolver in
            let _: String = try resolver.resolve(String.self)
            return 0
        }

        XCTAssertThrowsError(try container.resolve(String.self)) { error in
            guard case ContainerError.circularDependency = error else {
                XCTFail("Expected circularDependency error, got \(error)")
                return
            }
        }
    }

    // MARK: - Parent Container

    func testParentContainerFallback() throws {
        let parent = Container(name: "Parent")
        parent.register(String.self) { _ in "FromParent" }

        let child = Container(name: "Child", parent: parent)

        let result: String = try child.resolve()
        XCTAssertEqual(result, "FromParent")
    }

    // MARK: - Instance Registration

    func testRegisterInstance() throws {
        container.registerInstance(99, for: Int.self)
        let result: Int = try container.resolve()
        XCTAssertEqual(result, 99)
    }

    // MARK: - isRegistered

    func testIsRegistered() {
        XCTAssertFalse(container.isRegistered(String.self))
        container.register(String.self) { _ in "test" }
        XCTAssertTrue(container.isRegistered(String.self))
    }

    // MARK: - Cleanup

    func testCleanupRemovesAllRegistrations() {
        container.register(String.self) { _ in "test" }
        XCTAssertTrue(container.isRegistered(String.self))

        container.cleanup()
        XCTAssertFalse(container.isRegistered(String.self))
    }

    func testRemoveSpecificRegistration() throws {
        container.register(String.self) { _ in "test" }
        container.register(Int.self) { _ in 42 }

        container.remove(String.self)

        XCTAssertFalse(container.isRegistered(String.self))
        XCTAssertTrue(container.isRegistered(Int.self))
    }

    // MARK: - Reset Cache

    func testResetCacheRecreateCachedInstances() throws {
        var count = 0
        container.register(Int.self) { _ in
            count += 1
            return count
        }

        let first: Int = try container.resolve()
        XCTAssertEqual(first, 1)

        container.resetCache()

        let second: Int = try container.resolve()
        XCTAssertEqual(second, 2)
    }
}
