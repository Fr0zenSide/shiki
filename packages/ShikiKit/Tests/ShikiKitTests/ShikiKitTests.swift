import Testing
@testable import ShikiKit

@Suite("ShikiKit Module")
struct ShikiKitModuleTests {
    @Test("ShikiKit imports and version is accessible")
    func test_shikiKitImports() {
        #expect(ShikiKit.version == "4.0.0")
    }
}
