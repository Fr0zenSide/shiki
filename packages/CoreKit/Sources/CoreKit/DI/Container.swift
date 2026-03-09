//
//  Container.swift
//  CoreKit
//
//  Extracted from WabiSabi — Created by Jeoffrey Thirot on 20/02/2026.
//  Dependency Injection Container with Swinject-style API
//  Features: Circular dependency detection, Memory leak prevention, Resolver protocol
//

import Foundation
import os

// MARK: - Container Error

public enum ContainerError: Error, LocalizedError, CustomStringConvertible {
    case notRegistered(String)
    case circularDependency(String)
    case resolutionFailed(String, underlying: Error)
    case invalidRegistration(String)

    public var description: String {
        switch self {
        case .notRegistered(let type):
            return "ContainerError: '\(type)' is not registered in the container"
        case .circularDependency(let path):
            return "ContainerError: Circular dependency detected: \(path)"
        case .resolutionFailed(let type, let underlying):
            return "ContainerError: Failed to resolve '\(type)': \(underlying.localizedDescription)"
        case .invalidRegistration(let message):
            return "ContainerError: Invalid registration: \(message)"
        }
    }

    public var errorDescription: String? { description }
}

// MARK: - Registration Scope

public enum RegistrationScope: Sendable {
    /// New instance created every time (no caching)
    case transient
    /// Single instance per container (singleton pattern)
    case cached
    /// Weak reference - instance can be deallocated, recreated on next resolve
    case weak
}

// MARK: - Resolver Protocol (Swinject-style)

/// Protocol for resolving dependencies (passed to factory closures)
public protocol Resolver {
    /// Resolve a dependency by type
    func resolve<T>(_ type: T.Type) throws -> T

    /// Resolve a dependency by type with name (for multiple registrations)
    func resolve<T>(_ type: T.Type, name: String) throws -> T

    /// Resolve optional dependency (returns nil if not registered)
    func resolveOptional<T>(_ type: T.Type) -> T?
}

// MARK: - Registration Protocol

protocol RegistrationProtocol {
    var scope: RegistrationScope { get }
    func resolve(using resolver: Resolver) throws -> Any
    func resetInstance()
}

// MARK: - Registration

class Registration<T>: RegistrationProtocol {
    let scope: RegistrationScope
    let factory: (Resolver) throws -> T

    private var instance: T?
    private weak var weakInstance: AnyObject?
    private let lock = NSLock()

    init(scope: RegistrationScope, factory: @escaping (Resolver) throws -> T) {
        self.scope = scope
        self.factory = factory
    }

    func resolve(using resolver: Resolver) throws -> Any {
        lock.lock()
        defer { lock.unlock() }

        switch scope {
        case .transient:
            return try factory(resolver)

        case .cached:
            if let existing = instance {
                return existing
            }
            let newInstance = try factory(resolver)
            instance = newInstance
            return newInstance

        case .weak:
            if let weakRef = weakInstance, let existing = weakRef as? T {
                return existing
            }
            let newInstance = try factory(resolver)
            weakInstance = newInstance as AnyObject
            return newInstance
        }
    }

    func resetInstance() {
        lock.lock()
        defer { lock.unlock() }
        instance = nil
        weakInstance = nil
    }
}

// MARK: - Resolution Context (Thread Safety + Circular Detection)

/// Thread-safe context for tracking resolution state
final class ResolutionContext {
    private var stack: [String] = []
    private let lock = NSLock()

    /// Push type onto stack, returns error string if circular dependency detected
    func push(_ type: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        if stack.contains(type) {
            let path = stack.joined(separator: " → ") + " → " + type
            return path
        }
        stack.append(type)
        return nil
    }

    /// Pop type from stack
    func pop(_ type: String) {
        lock.lock()
        defer { lock.unlock() }

        if let index = stack.lastIndex(of: type) {
            stack.remove(at: index)
        }
    }

    /// Clear entire stack
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        stack.removeAll()
    }
}

// MARK: - Container

/// Dependency Injection Container with Swinject-style API
open class Container: Resolver, @unchecked Sendable {

    // MARK: - Static Properties

    private static let defaultLock = NSLock()
    nonisolated(unsafe) private static var _default: Container = Container()

    /// Default shared container instance (thread-safe)
    public static var `default`: Container {
        get {
            defaultLock.lock()
            defer { defaultLock.unlock() }
            return _default
        }
        set {
            defaultLock.lock()
            defer { defaultLock.unlock() }
            _default = newValue
        }
    }

    // MARK: - Properties

    private var registrations: [String: any RegistrationProtocol] = [:]
    private let lock = NSLock()
    private let context = ResolutionContext()
    private weak var parent: Container?

    /// Container name for debugging
    public let name: String

    // MARK: - Initialization

    public init(name: String = "Container", parent: Container? = nil) {
        self.name = name
        self.parent = parent
    }

    deinit {
        cleanup()
    }

    // MARK: - Registration

    /// Register a factory for a type with default scope (.cached)
    @discardableResult
    public func register<T>(
        _ type: T.Type = T.self,
        name: String? = nil,
        factory: @escaping (Resolver) throws -> T
    ) -> Container {
        try! register(type, name: name, scope: .cached, factory: factory)
        return self
    }

    /// Register a factory for a type with specific scope
    @discardableResult
    public func register<T>(
        _ type: T.Type = T.self,
        name: String? = nil,
        scope: RegistrationScope,
        factory: @escaping (Resolver) throws -> T
    ) throws -> Container {
        let key = registrationKey(for: type, name: name)

        lock.lock()
        defer { lock.unlock() }

        registrations[key] = Registration(scope: scope) { resolver in
            try factory(resolver)
        }

        return self
    }

    // MARK: - Resolver Protocol

    public func resolve<T>(_ type: T.Type = T.self) throws -> T {
        try resolve(type, name: nil)
    }

    public func resolve<T>(_ type: T.Type = T.self, name: String? = nil) throws -> T {
        let key = registrationKey(for: type, name: name)
        let typeName = String(describing: type) + (name.map { "(\($0))" } ?? "")

        // Circular dependency detection
        if let cyclePath = context.push(typeName) {
            throw ContainerError.circularDependency(cyclePath)
        }

        defer { context.pop(typeName) }

        // Look up registration
        lock.lock()
        let registration = registrations[key]
        lock.unlock()

        guard let reg = registration else {
            // Try parent container
            if let parent = parent {
                return try parent.resolve(type, name: name)
            }
            throw ContainerError.notRegistered(typeName)
        }

        // Resolve instance
        do {
            let resolved = try reg.resolve(using: self)
            guard let typed = resolved as? T else {
                    throw ContainerError.resolutionFailed(
                    typeName,
                    underlying: NSError(
                        domain: "Container",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Type mismatch: expected \(T.self), got \(Swift.type(of: resolved))"]
                    )
                )
            }
            return typed
        } catch let error as ContainerError {
            throw error
        } catch {
            throw ContainerError.resolutionFailed(typeName, underlying: error)
        }
    }

    /// Resolve with non-optional name (for Resolver protocol conformance)
    public func resolve<T>(_ type: T.Type, name: String) throws -> T {
        try resolve(type, name: Optional(name))
    }

    public func resolveOptional<T>(_ type: T.Type = T.self) -> T? {
        try? resolve(type)
    }

    // MARK: - Instance Management

    /// Register an existing instance (singleton, always cached)
    public func registerInstance<T>(_ instance: T, for type: T.Type = T.self, name: String? = nil) {
        let key = registrationKey(for: type, name: name)

        lock.lock()
        defer { lock.unlock() }

        registrations[key] = Registration(scope: .cached) { _ in instance }
    }

    // MARK: - Cleanup (Memory Leak Prevention)

    /// Clear all cached instances (keeps registrations)
    public func resetCache() {
        lock.lock()
        defer { lock.unlock() }

        for (_, registration) in registrations {
            registration.resetInstance()
        }
    }

    /// Clear all registrations and instances
    public func cleanup() {
        lock.lock()
        defer { lock.unlock() }

        for (_, registration) in registrations {
            registration.resetInstance()
        }
        registrations.removeAll()
        context.clear()
    }

    /// Remove specific registration
    public func remove<T>(_ type: T.Type = T.self, name: String? = nil) {
        let key = registrationKey(for: type, name: name)

        lock.lock()
        defer { lock.unlock() }

        if let registration = registrations.removeValue(forKey: key) {
            registration.resetInstance()
        }
    }

    /// Check if a type is registered
    public func isRegistered<T>(_ type: T.Type = T.self, name: String? = nil) -> Bool {
        let key = registrationKey(for: type, name: name)

        lock.lock()
        defer { lock.unlock() }

        return registrations[key] != nil || parent?.isRegistered(type, name: name) == true
    }

    // MARK: - Debug Helpers

    /// Print all registered types (for debugging)
    public func printRegistrations() {
        lock.lock()
        defer { lock.unlock() }

        AppLog.di.debug("Container '\(self.name)' registrations:")
        for (key, _) in registrations {
            AppLog.di.debug("  - \(key)")
        }
        if let parent = parent {
            AppLog.di.debug("Parent container '\(parent.name)':")
            parent.printRegistrations()
        }
    }

    // MARK: - Private Helpers

    private func registrationKey<T>(for type: T.Type, name: String?) -> String {
        let baseKey = String(describing: type)
        return name.map { "\(baseKey):\($0)" } ?? baseKey
    }
}

// MARK: - Global Convenience Functions

/// Resolve a dependency from the default container
public func resolve<T>(_ type: T.Type = T.self) throws -> T {
    try Container.default.resolve(type)
}

/// Resolve an optional dependency from the default container
public func resolveOptional<T>(_ type: T.Type = T.self) -> T? {
    Container.default.resolveOptional(type)
}
