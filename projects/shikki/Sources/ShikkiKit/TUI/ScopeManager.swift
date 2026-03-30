import Foundation

// MARK: - Scope

/// A resolved scope that filters palette/chat/editor context.
public struct Scope: Sendable, Equatable {
    public let tag: String
    public let kind: ScopeKind

    public init(tag: String, kind: ScopeKind) {
        self.tag = tag
        self.kind = kind
    }
}

/// The kind of scope — determines how filtering is applied.
public enum ScopeKind: Sendable, Equatable {
    case project(String)
    case pr(Int)
    case branch(String)
    case today
    case wave(Int)
    case session(String)
    case custom(String)
}

// MARK: - ScopeManager

/// Manages the sticky scope stack (# notation from the spec).
/// Multiple scopes stack: `#maya #wave1` = maya project, wave 1 only.
/// `#` with no argument clears all scopes.
public struct ScopeManager: Sendable {
    private var stack: [Scope]
    private var userDefinedScopes: [String: [Scope]]

    public init(
        stack: [Scope] = [],
        userDefinedScopes: [String: [Scope]] = [:]
    ) {
        self.stack = stack
        self.userDefinedScopes = userDefinedScopes
    }

    /// Active scopes (ordered, most recent last).
    public var activeScopes: [Scope] { stack }

    /// Whether any scope is active.
    public var hasScope: Bool { !stack.isEmpty }

    /// Human-readable label of active scopes.
    public var label: String {
        if stack.isEmpty { return "all" }
        return stack.map { "#\($0.tag)" }.joined(separator: " ")
    }

    /// Push a scope from raw `#tag` input. Returns the resolved scope.
    /// Returns nil if the tag is empty (clear command).
    public mutating func push(rawTag: String) -> Scope? {
        let tag = rawTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else {
            clearAll()
            return nil
        }

        // Check user-defined first
        if let defined = userDefinedScopes[tag] {
            for scope in defined {
                stack.append(scope)
            }
            return defined.last
        }

        let scope = resolve(tag: tag)
        stack.append(scope)
        return scope
    }

    /// Remove the most recent scope.
    @discardableResult
    public mutating func pop() -> Scope? {
        stack.popLast()
    }

    /// Clear all active scopes.
    public mutating func clearAll() {
        stack.removeAll()
    }

    /// Define a user scope alias.
    /// `#define auth = #maya #wave1 f:auth`
    public mutating func define(name: String, scopes: [Scope]) {
        userDefinedScopes[name] = scopes
    }

    /// All user-defined scope names.
    public var definedScopeNames: [String] {
        Array(userDefinedScopes.keys.sorted())
    }

    /// Check if a PaletteResult matches the current scope stack.
    public func matches(result: PaletteResult) -> Bool {
        guard hasScope else { return true }
        for scope in stack {
            if !matchesSingle(result: result, scope: scope) {
                return false
            }
        }
        return true
    }

    // MARK: - Private

    private func resolve(tag: String) -> Scope {
        // PR pattern: PR-<number>
        if tag.uppercased().hasPrefix("PR-"),
           let num = Int(tag.dropFirst(3)) {
            return Scope(tag: tag, kind: .pr(num))
        }
        // Wave pattern: wave<number>
        if tag.lowercased().hasPrefix("wave"),
           let num = Int(tag.dropFirst(4)) {
            return Scope(tag: tag, kind: .wave(num))
        }
        // Session pattern: session-<id>
        if tag.lowercased().hasPrefix("session-") {
            return Scope(tag: tag, kind: .session(String(tag.dropFirst(8))))
        }
        // Time scopes
        if tag.lowercased() == "today" {
            return Scope(tag: tag, kind: .today)
        }
        // Default: treat as project slug
        return Scope(tag: tag, kind: .project(tag))
    }

    private func matchesSingle(result: PaletteResult, scope: Scope) -> Bool {
        switch scope.kind {
        case .project(let slug):
            return result.title.localizedCaseInsensitiveContains(slug)
                || result.id.localizedCaseInsensitiveContains(slug)

        case .pr(let number):
            return result.id.contains("pr:\(number)")
                || result.title.contains("PR-\(number)")
                || result.title.contains("#\(number)")

        case .branch(let name):
            return result.category == "branch"
                && result.title.localizedCaseInsensitiveContains(name)

        case .today:
            // Time-based filtering requires metadata; pass-through for now
            return true

        case .wave(let number):
            return result.title.localizedCaseInsensitiveContains("wave\(number)")
                || result.title.localizedCaseInsensitiveContains("wave-\(number)")

        case .session(let id):
            return result.category == "session"
                && result.id.localizedCaseInsensitiveContains(id)

        case .custom:
            return true
        }
    }
}

// MARK: - Persistence

extension ScopeManager {
    /// Load user-defined scopes from a JSON file.
    public static func loadUserScopes(from path: String) -> [String: [Scope]] {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [[String: String]]] else {
            return [:]
        }
        var result: [String: [Scope]] = [:]
        for (name, scopeDefs) in json {
            result[name] = scopeDefs.compactMap { def in
                guard let tag = def["tag"], let kindStr = def["kind"] else { return nil }
                let kind: ScopeKind
                switch kindStr {
                case "project": kind = .project(tag)
                case "today": kind = .today
                default: kind = .custom(tag)
                }
                return Scope(tag: tag, kind: kind)
            }
        }
        return result
    }
}
