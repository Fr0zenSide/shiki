import ArgumentParser
import Foundation
import ShikkiKit

struct TemplatesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "templates",
        abstract: "Browse, install, and manage project templates",
        subcommands: [
            ListSubcommand.self,
            SearchSubcommand.self,
            InfoSubcommand.self,
            InstallSubcommand.self,
            ApplySubcommand.self,
            UninstallSubcommand.self,
        ],
        defaultSubcommand: ListSubcommand.self
    )
}

// MARK: - List

extension TemplatesCommand {
    struct ListSubcommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all available templates"
        )

        @Option(name: .long, help: "Filter by language")
        var language: String?

        func run() throws {
            let registry = TemplateRegistry()

            do {
                var templates = try registry.listInstalled()

                if let language {
                    templates = templates.filter {
                        $0.template.language.lowercased() == language.lowercased()
                    }
                }

                if templates.isEmpty {
                    print(styled("No templates found.", .dim))
                    return
                }

                print(styled("Available Templates", .bold, .cyan))
                print(String(repeating: "\u{2500}", count: 60))
                print()

                for item in templates {
                    let tmpl = item.template
                    let sourceTag: String
                    switch item.source {
                    case .builtin: sourceTag = styled("[built-in]", .dim)
                    case .local: sourceTag = styled("[local]", .yellow)
                    case .github: sourceTag = styled("[github]", .cyan)
                    }

                    print("  \(styled(tmpl.name, .bold))  \(sourceTag)")
                    print("  \(styled(tmpl.id, .dim))  v\(tmpl.version)  \(tmpl.language)")
                    print("  \(tmpl.description)")
                    if !tmpl.tags.isEmpty {
                        let tagLine = tmpl.tags.map { styled("#\($0)", .dim) }.joined(separator: " ")
                        print("  \(tagLine)")
                    }
                    print()
                }

                print(styled("Use `shikki templates info <id>` for details.", .dim))
                print(styled("Use `shikki templates apply <id>` to apply a template.", .dim))
            } catch RegistryError.registryCorrupted {
                print(styled("Error:", .red, .bold) + " Template registry is corrupted.")
                print(styled("  Delete ~/.config/shikki/templates/index.json and try again.", .dim))
                throw ExitCode(1)
            }
        }
    }
}

// MARK: - Search

extension TemplatesCommand {
    struct SearchSubcommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "search",
            abstract: "Search templates by keyword"
        )

        @Argument(help: "Search query")
        var query: String

        func run() throws {
            let registry = TemplateRegistry()
            let results = try registry.search(query: query)

            if results.isEmpty {
                print(styled("No templates matching '\(query)'.", .dim))
                return
            }

            print(styled("Search results for '\(query)'", .bold, .cyan))
            print()

            for item in results {
                let tmpl = item.template
                print("  \(styled(tmpl.id, .bold))  \(tmpl.name)  v\(tmpl.version)")
                print("  \(styled(tmpl.description, .dim))")
                print()
            }
        }
    }
}

// MARK: - Info

extension TemplatesCommand {
    struct InfoSubcommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "info",
            abstract: "Show detailed information about a template"
        )

        @Argument(help: "Template ID")
        var id: String

        func run() throws {
            let registry = TemplateRegistry()

            do {
                let item = try registry.get(id: id)
                let tmpl = item.template

                print(styled(tmpl.name, .bold, .cyan))
                print(String(repeating: "\u{2500}", count: 40))
                print()
                print("  ID:          \(tmpl.id)")
                print("  Version:     \(tmpl.version)")
                print("  Author:      \(tmpl.author)")
                print("  Language:    \(tmpl.language)")
                print("  Description: \(tmpl.description)")

                if !tmpl.tags.isEmpty {
                    print("  Tags:        \(tmpl.tags.joined(separator: ", "))")
                }

                print("  Source:      \(item.source.rawValue)")
                if let url = item.sourceURL {
                    print("  URL:         \(url)")
                }
                print("  Installed:   \(item.installedAt.shortDisplay)")

                if !tmpl.files.isEmpty {
                    print()
                    print(styled("  Files:", .bold))
                    for file in tmpl.files {
                        let execTag = file.executable ? styled(" [exec]", .yellow) : ""
                        print("    \(styled(file.relativePath, .dim))\(execTag)")
                    }
                }

                if let moto = tmpl.motoOverrides {
                    print()
                    print(styled("  .moto overrides:", .bold))
                    if let buildSystem = moto.buildSystem {
                        print("    Build System: \(buildSystem)")
                    }
                    if let framework = moto.framework {
                        print("    Framework:    \(framework)")
                    }
                    if let arch = moto.architecture?.pattern {
                        print("    Architecture: \(arch)")
                    }
                }

                print()
                print(styled("Apply with: shikki templates apply \(id)", .dim))

            } catch RegistryError.templateNotFound {
                print(styled("Error:", .red, .bold) + " Template '\(id)' not found.")
                print(styled("  Use `shikki templates list` to see available templates.", .dim))
                throw ExitCode(1)
            }
        }
    }
}

// MARK: - Install

extension TemplatesCommand {
    struct InstallSubcommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "install",
            abstract: "Install a template from a local JSON file or GitHub"
        )

        @Argument(help: "Path to template JSON file, or GitHub repo (owner/repo)")
        var source: String

        func run() throws {
            let registry = TemplateRegistry()

            // Check if it's a local file
            if FileManager.default.fileExists(atPath: source) {
                try installFromFile(registry: registry)
            } else if source.contains("/") && !source.contains(" ") {
                // Looks like a GitHub repo
                installFromGitHub(registry: registry)
            } else {
                print(styled("Error:", .red, .bold) + " Unknown source: \(source)")
                print(styled("  Provide a path to a .json file or a GitHub repo (owner/repo).", .dim))
                throw ExitCode(1)
            }
        }

        private func installFromFile(registry: TemplateRegistry) throws {
            guard let data = FileManager.default.contents(atPath: source) else {
                print(styled("Error:", .red, .bold) + " Could not read file: \(source)")
                throw ExitCode(1)
            }

            guard let template = try? JSONDecoder().decode(ProjectTemplate.self, from: data) else {
                print(styled("Error:", .red, .bold) + " Invalid template JSON.")
                throw ExitCode(1)
            }

            do {
                try registry.install(template: template, source: .local, sourceURL: source)
                print(styled("Installed!", .bold, .green) + " \(template.name) v\(template.version)")
            } catch RegistryError.templateAlreadyInstalled(let id) {
                print(styled("Already installed:", .yellow) + " \(id)")
                throw ExitCode(1)
            }
        }

        private func installFromGitHub(registry: TemplateRegistry) {
            // GitHub install requires network -- placeholder for v1
            print(styled("GitHub install coming soon.", .yellow))
            print(styled("  For now, download the template JSON and use:", .dim))
            print(styled("  shikki templates install ./path/to/template.json", .dim))
        }
    }
}

// MARK: - Apply

extension TemplatesCommand {
    struct ApplySubcommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "apply",
            abstract: "Apply a template to the current project"
        )

        @Argument(help: "Template ID to apply")
        var id: String

        @Option(name: .long, help: "Target directory (defaults to current)")
        var path: String?

        @Flag(name: .long, help: "Overwrite existing files")
        var force: Bool = false

        @Flag(name: .long, help: "Allow creating executable files from templates")
        var allowExec: Bool = false

        func run() throws {
            let registry = TemplateRegistry()
            let targetPath = path ?? FileManager.default.currentDirectoryPath

            do {
                let created = try registry.apply(
                    templateId: id,
                    to: targetPath,
                    force: force,
                    allowExecutables: allowExec
                )

                if created.isEmpty {
                    print(styled("Template applied.", .green) + " No new files created (all exist already).")
                    print(styled("  Use --force to overwrite.", .dim))
                } else {
                    print(styled("Template applied!", .bold, .green))
                    print()
                    for file in created {
                        print("  \(styled("+", .green)) \(file)")
                    }
                    print()
                }
            } catch RegistryError.templateNotFound {
                print(styled("Error:", .red, .bold) + " Template '\(id)' not found.")
                throw ExitCode(1)
            } catch RegistryError.pathTraversal(let path) {
                print(styled("Error:", .red, .bold) + " Path traversal detected: \(path)")
                print(styled("  Template contains a file path that escapes the target directory.", .dim))
                throw ExitCode(1)
            } catch RegistryError.executableNotAllowed(let path) {
                print(styled("Error:", .red, .bold) + " Executable file not allowed: \(path)")
                print(styled("  Use --allow-exec to permit executable files.", .dim))
                throw ExitCode(1)
            }
        }
    }
}

// MARK: - Uninstall

extension TemplatesCommand {
    struct UninstallSubcommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "uninstall",
            abstract: "Remove an installed template"
        )

        @Argument(help: "Template ID to uninstall")
        var id: String

        func run() throws {
            let registry = TemplateRegistry()

            do {
                try registry.uninstall(id: id)
                print(styled("Uninstalled:", .green) + " \(id)")
            } catch RegistryError.templateNotFound {
                print(styled("Error:", .red, .bold) + " Template '\(id)' not found.")
                throw ExitCode(1)
            } catch RegistryError.invalidTemplate(let msg) {
                print(styled("Error:", .red, .bold) + " \(msg)")
                throw ExitCode(1)
            }
        }
    }
}
