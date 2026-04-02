import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - BinarySwapError

/// Errors that can occur during binary swap operations.
public enum BinarySwapError: Error, Sendable, CustomStringConvertible {
    /// execv() system call failed.
    case execvFailed(errno: Int32, description: String)
    /// Sentinel used by MockBinarySwapper to indicate successful swap in tests.
    case swapSucceeded

    public var description: String {
        switch self {
        case .execvFailed(let errno, let desc):
            return "execv() failed (errno \(errno)): \(desc)"
        case .swapSucceeded:
            return "Binary swap succeeded (test sentinel)"
        }
    }
}

// MARK: - BinarySwapping Protocol

/// Protocol for binary swap operations — testable abstraction over execv().
/// BR-02: Binary swap MUST use execv() syscall to replace the current process in-place.
public protocol BinarySwapping: Sendable {
    /// Replace the current process with the binary at `path`, passing `args`.
    /// In production, this calls execv() and never returns (→ Never).
    /// In tests, this throws to allow assertions.
    func exec(path: String, args: [String]) throws -> Never
}

// MARK: - PosixBinarySwapper

/// Production implementation that calls execv() to replace the running process.
/// The current process image is replaced — PID, file descriptors, and lockfiles
/// are preserved. If execv() fails, it throws and the old binary continues (BR-13).
public struct PosixBinarySwapper: BinarySwapping {

    public init() {}

    public func exec(path: String, args: [String]) throws -> Never {
        // Build argv for execv: [path, arg1, arg2, ..., NULL]
        let cPath = path.withCString { strdup($0) }!
        defer { free(cPath) }

        // Convert args to C strings
        var cArgs: [UnsafeMutablePointer<CChar>?] = [cPath]
        for arg in args {
            cArgs.append(arg.withCString { strdup($0) })
        }
        cArgs.append(nil) // NULL terminator

        // execv replaces the process image — if it returns, it failed
        execv(cPath, &cArgs)

        // If we reach here, execv() failed — clean up and throw
        let err = errno
        for i in 1..<(cArgs.count - 1) { // skip index 0 (cPath freed by defer) and last (nil)
            free(cArgs[i])
        }

        throw BinarySwapError.execvFailed(
            errno: err,
            description: String(cString: strerror(err))
        )
    }
}
