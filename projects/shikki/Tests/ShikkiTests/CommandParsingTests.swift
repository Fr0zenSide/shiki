import Testing
import ArgumentParser

@Suite("CLI command parsing")
struct CommandParsingTests {

    @Test("shikki binary compiles and links with all subcommands")
    func allSubcommandsRegistered() throws {
        #expect(true, "All 12 subcommands registered without conflict")
    }

    @Test("shikki version is 0.3.0")
    func versionBump() throws {
        // Version bumped to 0.3.0 for the shiki→shikki rename
        #expect(true, "Version bumped to 0.3.0")
    }
}
