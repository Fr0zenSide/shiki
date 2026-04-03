import CommonCrypto
import Foundation

/// Scans memory directory, computes content hashes, and provides file metadata.
/// Used by both verification (Phase 3) and cleanup (Phase 4).
public struct MemoryFileScanner: Sendable {

    public let memoryDirectory: String

    public init(memoryDirectory: String) {
        self.memoryDirectory = memoryDirectory
    }

    /// Default memory directory for the Shiki workspace.
    public static let defaultMemoryDirectory: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cwd = FileManager.default.currentDirectoryPath
        let projectSlug = cwd.replacingOccurrences(of: "/", with: "-")
        return "\(home)/.claude/projects/\(projectSlug)/memory"
    }()

    /// List all .md files in the memory directory (sorted, excludes MEMORY.md).
    public func listFiles() throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: memoryDirectory) else {
            throw MemoryFileScannerError.directoryNotFound(memoryDirectory)
        }

        let contents = try fm.contentsOfDirectory(atPath: memoryDirectory)
        return contents
            .filter { $0.hasSuffix(".md") && $0 != "MEMORY.md" }
            .sorted()
    }

    /// Read file content at the given filename within the memory directory.
    public func readFile(_ filename: String) throws -> String {
        let path = (memoryDirectory as NSString).appendingPathComponent(filename)
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            throw MemoryFileScannerError.fileNotFound(filename)
        }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    /// Compute SHA-256 hash of a file's content.
    public func contentHash(of filename: String) throws -> String {
        let content = try readFile(filename)
        return Self.sha256(content)
    }

    /// Compute SHA-256 hash of a string.
    public static func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Full path for a given filename.
    public func fullPath(for filename: String) -> String {
        (memoryDirectory as NSString).appendingPathComponent(filename)
    }

    /// Check if MEMORY.md exists in the directory.
    public func hasMemoryIndex() -> Bool {
        let path = (memoryDirectory as NSString).appendingPathComponent("MEMORY.md")
        return FileManager.default.fileExists(atPath: path)
    }

    /// Read MEMORY.md content.
    public func readMemoryIndex() throws -> String {
        let path = (memoryDirectory as NSString).appendingPathComponent("MEMORY.md")
        guard FileManager.default.fileExists(atPath: path) else {
            throw MemoryFileScannerError.fileNotFound("MEMORY.md")
        }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    /// Count total .md files including MEMORY.md.
    public func totalFileCount() throws -> Int {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(atPath: memoryDirectory)
        return contents.filter { $0.hasSuffix(".md") }.count
    }
}

public enum MemoryFileScannerError: Error, CustomStringConvertible, Equatable {
    case directoryNotFound(String)
    case fileNotFound(String)

    public var description: String {
        switch self {
        case .directoryNotFound(let path):
            "Memory directory not found: \(path)"
        case .fileNotFound(let name):
            "File not found: \(name)"
        }
    }
}
