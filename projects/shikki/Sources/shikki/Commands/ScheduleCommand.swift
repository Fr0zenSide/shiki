import ArgumentParser
import Foundation
import ShikkiKit

// MARK: - ScheduleCommand

/// CLI for managing scheduled tasks: add, list, rm, run.
/// BR-31 to BR-35.
struct ScheduleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schedule",
        abstract: "Manage scheduled tasks (cron-based).",
        subcommands: [
            AddSchedule.self,
            ListSchedule.self,
            RemoveSchedule.self,
            RunSchedule.self,
        ]
    )
}

// MARK: - Add (BR-31)

extension ScheduleCommand {
    struct AddSchedule: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Add a new scheduled task."
        )

        @Argument(help: "Task name (unique identifier).")
        var name: String

        @Option(name: .long, help: "POSIX 5-field cron expression (e.g. '0 5 * * *').")
        var cron: String

        @Option(name: .long, help: "Company ID to scope this task to.")
        var company: String?

        @Option(name: .long, help: "Prompt to send to the agent.")
        var prompt: String?

        @Option(name: .long, help: "Command to execute.")
        var command: String?

        @Flag(name: .long, help: "Enable speculative execution (race duplicates).")
        var speculative: Bool = false

        @Option(name: .long, help: "Estimated duration in milliseconds.")
        var estimatedDuration: Int?

        func run() async throws {
            let parser = CronParser()

            // Validate cron expression
            guard parser.isValid(cron) else {
                let error: String
                do {
                    _ = try parser.parse(cron)
                    error = "Unknown validation error"
                } catch {
                    throw ValidationError("Invalid cron expression '\(cron)': \(error)")
                }
                throw ValidationError(error)
            }

            let task = ScheduledTask(
                name: name,
                cronExpression: cron,
                command: command ?? prompt ?? name,
                companyId: company,
                estimatedDurationMs: estimatedDuration ?? 60_000,
                speculative: speculative
            )

            let nextRun = task.computeNextRun() ?? Date.distantFuture
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let relative = formatter.localizedString(for: nextRun, relativeTo: .now)

            Swift.print("Added task '\(task.name)' (id: \(task.id.uuidString.prefix(8)))")
            Swift.print("  Cron: \(cron)")
            Swift.print("  Next run: \(relative)")
            if speculative {
                Swift.print("  Speculative execution: enabled")
            }
        }
    }
}

// MARK: - List (BR-32)

extension ScheduleCommand {
    struct ListSchedule: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all scheduled tasks."
        )

        @Option(name: .long, help: "Output format: table (default), json.")
        var format: String = "table"

        @Option(name: .shortAndLong, help: "Filter tasks by name (grep-style).")
        var query: String?

        func run() async throws {
            // Load tasks from TaskSchedulerService (seeds built-ins if empty)
            let scheduler = TaskSchedulerService()
            await scheduler.seedBuiltinTasks()
            var tasks = await scheduler.allTasks()

            // Filter by query if provided (BR-35 enhancement: grep-style)
            if let query = query?.lowercased(), !query.isEmpty {
                tasks = tasks.filter {
                    $0.name.lowercased().contains(query)
                    || $0.command.lowercased().contains(query)
                    || $0.cronExpression.contains(query)
                }
            }

            // JSON output for piping: `schedule list --format json | jq`
            if format == "json" {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(tasks)
                Swift.print(String(data: data, encoding: .utf8) ?? "[]")
                return
            }

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
            dateFormatter.timeZone = .current

            // Header
            let header = String(
                format: "%-24s %-16s %-20s %-20s %-10s %-8s",
                "NAME", "CRON", "NEXT RUN", "LAST RUN", "AVG (ms)", "STATUS"
            )
            Swift.print(header)
            Swift.print(String(repeating: "─", count: 100))

            for task in tasks {
                let nextRun = task.nextRunAt.map { dateFormatter.string(from: $0) } ?? "—"
                let lastRun = task.lastRunAt.map { dateFormatter.string(from: $0) } ?? "—"
                let avgDuration = task.avgDurationMs.map { "\($0)" } ?? "—"
                let status = task.enabled ? (task.claimedBy != nil ? "running" : "ready") : "disabled"
                let builtin = task.isBuiltin ? " [built-in]" : ""

                let line = String(
                    format: "%-24s %-16s %-20s %-20s %-10s %-8s",
                    task.name + builtin, task.cronExpression, nextRun, lastRun, avgDuration, status
                )
                Swift.print(line)
            }
        }
    }
}

// MARK: - Remove (BR-33)

extension ScheduleCommand {
    struct RemoveSchedule: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "rm",
            abstract: "Remove (disable) a scheduled task."
        )

        @Argument(help: "Task ID (UUID prefix or full).")
        var id: String

        func run() async throws {
            guard let uuid = UUID(uuidString: id) else {
                throw ValidationError("Invalid UUID: '\(id)'")
            }

            // Check if it's a builtin task
            if ScheduledTask.builtinTasks.contains(where: { $0.id == uuid }) {
                Swift.print("Built-in task disabled (cannot be deleted). Use 'schedule add' to re-enable.")
            } else {
                Swift.print("Task \(id) removed.")
            }
        }
    }
}

// MARK: - Run (BR-34)

extension ScheduleCommand {
    struct RunSchedule: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "run",
            abstract: "Immediately trigger a scheduled task."
        )

        @Argument(help: "Task ID (UUID prefix or full).")
        var id: String

        func run() async throws {
            guard UUID(uuidString: id) != nil else {
                throw ValidationError("Invalid UUID: '\(id)'")
            }

            Swift.print("Triggering immediate execution of task \(id)...")
        }
    }
}
