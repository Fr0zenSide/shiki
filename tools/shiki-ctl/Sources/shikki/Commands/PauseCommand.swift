import ArgumentParser
import ShikiCtlKit

struct PauseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pause",
        abstract: "Pause a company"
    )

    @Argument(help: "Company slug (e.g. wabisabi, maya)")
    var slug: String

    @Option(name: .long, help: "Backend URL")
    var url: String = "http://localhost:3900"

    func run() async throws {
        let client = BackendClient(baseURL: url)

        do {
            let companies = try await client.getCompanies()

            guard let company = companies.first(where: { $0.slug == slug }) else {
                try await client.shutdown()
                print("\u{1B}[31mError:\u{1B}[0m Company '\(slug)' not found")
                throw ExitCode.failure
            }

            if company.status == .paused {
                try await client.shutdown()
                print("Company '\(slug)' is already paused")
                return
            }

            _ = try await client.patchCompany(id: company.id, updates: ["status": "paused"])
            try await client.shutdown()
            print("\u{1B}[33mPaused\u{1B}[0m company '\(slug)'")
        } catch {
            try? await client.shutdown()
            throw error
        }
    }
}
