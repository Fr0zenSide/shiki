import ArgumentParser
import Foundation
import ShikkiKit

/// `shikki ask "how does X work?"` -- natural language Q&A over the codebase.
///
/// Single-shot retrieval: query -> BM25 + ArchitectureCache -> cited answer.
/// Fits in one terminal screen. No chat history, no streaming.
struct AskCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ask",
        abstract: "Ask a question about the codebase (Answer Engine)",
        discussion: "Natural language Q&A over source code, specs, and architecture cache."
    )

    @Argument(help: "The question to ask (e.g. \"how does the event bus work?\")")
    var question: String

    @Option(name: .long, help: "Project path (defaults to current directory)")
    var project: String?

    @Flag(name: .long, help: "Output plain text without ANSI styling")
    var plain: Bool = false

    @Option(name: .long, help: "Maximum number of results to consider")
    var maxResults: Int = 10

    func run() async throws {
        let projectPath = project ?? findProjectRoot() ?? FileManager.default.currentDirectoryPath

        // Build engine
        let engine = LocalAnswerEngine()

        // Build context
        let analyzer = ProjectAnalyzer()
        let cache = try? await analyzer.analyze(projectPath: projectPath)

        let context = AnswerContext(
            projectPath: projectPath,
            architectureCache: cache,
            maxResults: maxResults
        )

        // Ask
        do {
            let result = try await engine.ask(question, context: context)
            let output = AnswerRenderer.render(result: result, query: question, plain: plain)
            fputs(output, stdout)
        } catch let error as AnswerEngineError {
            fputs("\(ANSI.red)Error: \(error.localizedDescription)\(ANSI.reset)\n", stderr)
            throw ExitCode(1)
        }
    }

    // MARK: - Helpers

    private func findProjectRoot() -> String? {
        var dir = FileManager.default.currentDirectoryPath
        while dir != "/" {
            // Look for Package.swift (SPM project)
            if FileManager.default.fileExists(atPath: "\(dir)/Package.swift") {
                return dir
            }
            // Look for .git root
            if FileManager.default.fileExists(atPath: "\(dir)/.git") {
                return dir
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }
}
