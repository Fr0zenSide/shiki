import ArgumentParser
import Foundation
import ShikiCtlKit

struct WakeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wake",
        abstract: "Force-launch a company session"
    )

    @Argument(help: "Company slug (e.g. wabisabi, maya)")
    var slug: String

    @Option(name: .long, help: "Backend URL")
    var url: String = "http://localhost:3900"

    @Option(name: .long, help: "Workspace root path")
    var workspace: String = "."

    func run() async throws {
        let client = BackendClient(baseURL: url)
        let companies: [Company]
        do {
            companies = try await client.getCompanies()
            try await client.shutdown()
        } catch {
            try? await client.shutdown()
            throw error
        }

        guard let company = companies.first(where: { $0.slug == slug }) else {
            print("\u{1B}[31mError:\u{1B}[0m Company '\(slug)' not found")
            let slugs = companies.map(\.slug).joined(separator: ", ")
            print("Available: \(slugs)")
            throw ExitCode.failure
        }

        let workspacePath = workspace == "." ? FileManager.default.currentDirectoryPath : workspace
        let launcher = TmuxProcessLauncher(workspacePath: workspacePath)

        if await launcher.isSessionRunning(slug: slug) {
            print("Session already running for '\(slug)'")
            return
        }

        let projectPath = (company.config["project_path"]?.value as? String) ?? slug
        try await launcher.launchCompanySession(
            companyId: company.id,
            slug: slug,
            projectPath: projectPath
        )

        print("\u{1B}[32mLaunched\u{1B}[0m session for '\(slug)'")
    }
}
