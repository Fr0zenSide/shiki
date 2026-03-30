import Foundation
import Logging

/// Protocol for checkpoint DB synchronization.
/// All methods are soft-fail: never throw, return false/nil on error.
public protocol DBSyncing: Sendable {
    func uploadCheckpoint(_ cp: Checkpoint) async -> Bool
    func downloadCheckpoint(hostname: String) async -> Checkpoint?
}

/// Soft-fail checkpoint sync to ShikiDB.
/// BR-25: Upload: local first (hard error), then DB (soft warning).
/// BR-26: Download: local first, fallback DB by hostname.
/// BR-51: DB unavailable → returns false/nil, logs warning.
/// Uses curl subprocess (same pattern as BackendClient) with 3s timeout.
public struct DBSyncClient: DBSyncing, Sendable {
    private let baseURL: String
    public let timeoutSeconds: Int
    private let logger = Logger(label: "shikki.db-sync")

    public init(baseURL: String = "http://localhost:3900", timeoutSeconds: Int = 3) {
        self.baseURL = baseURL
        self.timeoutSeconds = timeoutSeconds
    }

    /// Upload checkpoint to DB. Returns true on success, false on failure (soft-fail).
    public func uploadCheckpoint(_ cp: Checkpoint) async -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cp)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "curl", "-sf",
                "--max-time", "\(timeoutSeconds)",
                "-X", "POST",
                "-H", "Content-Type: application/json",
                "-d", "@-",
                "\(baseURL)/api/checkpoints",
            ]
            let stdin = Pipe()
            process.standardInput = stdin
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            try process.run()
            stdin.fileHandleForWriting.write(data)
            try stdin.fileHandleForWriting.close()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                return true
            } else {
                logger.warning("DB upload failed: exit code \(process.terminationStatus)")
                return false
            }
        } catch {
            logger.warning("DB upload error: \(error)")
            return false
        }
    }

    /// Download checkpoint from DB by hostname. Returns nil on failure (soft-fail).
    public func downloadCheckpoint(hostname: String) async -> Checkpoint? {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "curl", "-sf",
                "--max-time", "\(timeoutSeconds)",
                "\(baseURL)/api/checkpoints?hostname=\(hostname)",
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0, !data.isEmpty else {
                return nil
            }

            return try JSONDecoder.shikkiDecoder.decode(Checkpoint.self, from: data)
        } catch {
            logger.warning("DB download error: \(error)")
            return nil
        }
    }
}
