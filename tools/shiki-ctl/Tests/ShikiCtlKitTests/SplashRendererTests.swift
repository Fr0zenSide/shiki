import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("SplashRenderer")
struct SplashRendererTests {

    @Test("Splash renders version string")
    func splashRendersVersion() {
        let output = SplashRenderer.renderToString(version: "1.0.0")
        let stripped = TerminalSnapshot.stripANSI(output)
        #expect(stripped.contains("v1.0.0"))
        #expect(stripped.contains("███████"))
    }

    @Test("Splash includes resume context when provided")
    func splashIncludesResumeContext() {
        let output = SplashRenderer.renderToString(
            version: "1.0.0",
            resumeContext: "Resuming: feature/splash — added ASCII art"
        )
        let stripped = TerminalSnapshot.stripANSI(output)
        #expect(stripped.contains("Resuming: feature/splash"))
    }
}
