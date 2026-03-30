import Foundation

// MARK: - Protocol

/// Abstraction for environment checks, enabling test doubles.
public protocol EnvironmentChecking: Sendable {
    func isDockerRunning() async -> Bool
    func isColimaRunning() async -> Bool
    func isBackendHealthy(url: String) async -> Bool
    func isLMStudioRunning(url: String) async -> Bool
    func isTmuxSessionRunning(name: String) async -> Bool
    func binaryExists(at path: String) -> Bool
    func companyCount(backendURL: String) async -> Int
}

// MARK: - Concrete Implementation

/// Detects the local environment for the Shiki orchestrator system.
/// Uses `Process` to shell out for each check — lightweight, no heavy dependencies.
public struct EnvironmentDetector: EnvironmentChecking, Sendable {

    public init() {}

    public func isDockerRunning() async -> Bool {
        exitCodeIsZero("docker", arguments: ["info"])
    }

    public func isColimaRunning() async -> Bool {
        exitCodeIsZero("colima", arguments: ["status"])
    }

    public func isBackendHealthy(url: String) async -> Bool {
        exitCodeIsZero("curl", arguments: ["-sf", "\(url)/health"])
    }

    public func isLMStudioRunning(url: String) async -> Bool {
        exitCodeIsZero("curl", arguments: ["-sf", "\(url)/v1/models"])
    }

    public func isTmuxSessionRunning(name: String) async -> Bool {
        exitCodeIsZero("tmux", arguments: ["has-session", "-t", name])
    }

    public func binaryExists(at path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    public func companyCount(backendURL: String) async -> Int {
        guard let output = try? runProcessCapture(
            "curl", arguments: ["-sf", "\(backendURL)/api/companies"]
        ) else { return 0 }

        // Parse the JSON array and count elements.
        guard let data = output.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return 0 }

        return array.count
    }

    // MARK: - Private Helpers

    private func exitCodeIsZero(_ executable: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func runProcessCapture(
        _ executable: String, arguments: [String]
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Read pipe BEFORE waitUntilExit to prevent pipe buffer deadlock (~64KB)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw EnvironmentDetectorError.processExitedWithCode(process.terminationStatus)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum EnvironmentDetectorError: Error {
    case processExitedWithCode(Int32)
}

// MARK: - Mock for Tests

/// Test double that returns pre-configured values for each environment check.
public final class MockEnvironmentChecker: EnvironmentChecking, @unchecked Sendable {
    public var dockerRunning = false
    public var colimaRunning = false
    public var backendHealthy = false
    public var lmStudioRunning = false
    public var tmuxSessionRunning = false
    public var binaryExistsResult = false
    public var companyCountResult = 0

    public init() {}

    public func isDockerRunning() async -> Bool { dockerRunning }
    public func isColimaRunning() async -> Bool { colimaRunning }
    public func isBackendHealthy(url: String) async -> Bool { backendHealthy }
    public func isLMStudioRunning(url: String) async -> Bool { lmStudioRunning }
    public func isTmuxSessionRunning(name: String) async -> Bool { tmuxSessionRunning }
    public func binaryExists(at path: String) -> Bool { binaryExistsResult }
    public func companyCount(backendURL: String) async -> Int { companyCountResult }
}
