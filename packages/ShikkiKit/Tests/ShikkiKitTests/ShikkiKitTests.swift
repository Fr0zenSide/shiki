import Testing
@testable import ShikkiKit

@Suite("ShikkiKit Module")
struct ShikkiKitModuleTests {
    @Test("ShikkiKit imports and version is accessible")
    func test_shikiKitImports() {
        #expect(ShikkiKit.version == "4.0.0")
    }
}
