//
//  Resolve.swift
//  CoreKit
//
//  Extracted from WabiSabi — Created by Jeoffrey Thirot on 20/02/2026.
//

import Foundation

// MARK: - Resolve Property Wrapper

/// Property wrapper that automatically resolves dependencies from the current container.
///
/// Usage:
/// ```swift
/// @Resolve var networkService: NetworkProtocol
/// @Resolve var authManager: AuthPersistenceManagerProtocol
/// ```
@propertyWrapper
public struct Resolve<Service> {
    private var cachedService: Service?
    private let serviceType: Service.Type

    public init() {
        self.serviceType = Service.self
    }

    public init(_ serviceType: Service.Type) {
        self.serviceType = serviceType
    }

    public var wrappedValue: Service {
        mutating get {
            if let cached = cachedService {
                return cached
            }
            guard let service = try? Container.default.resolve(Service.self) else {
                fatalError("DI: Failed to resolve \(Service.self). Ensure it is registered in the container.")
            }
            cachedService = service
            return service
        }
        mutating set {
            cachedService = newValue
        }
    }

    /// Reset the cached value to force re-resolution on next access
    public mutating func reset() {
        cachedService = nil
    }
}

// MARK: - Resolve Optional Property Wrapper

/// Property wrapper that resolves optional dependencies (returns nil if not registered).
///
/// Usage:
/// ```swift
/// @ResolveOptional var cacheProvider: CacheProvider?
/// ```
@propertyWrapper
public struct ResolveOptional<Service> {
    private var cachedService: Service?
    private let serviceType: Service.Type

    public init() {
        self.serviceType = Service.self
    }

    public var wrappedValue: Service? {
        mutating get {
            if let cached = cachedService {
                return cached
            }
            let service = Container.default.resolveOptional(Service.self)
            cachedService = service
            return service
        }
        mutating set {
            cachedService = newValue
        }
    }
}

// MARK: - Resolve Weak Property Wrapper

/// Property wrapper that resolves weak dependencies for avoiding retain cycles.
///
/// Usage:
/// ```swift
/// @ResolveWeak var delegate: MyDelegate?
/// ```
@propertyWrapper
public struct ResolveWeak<Service: AnyObject> {
    private weak var _wrappedValue: Service?
    private let serviceType: Service.Type

    public init() {
        self.serviceType = Service.self
    }

    public var wrappedValue: Service? {
        mutating get {
            if let value = _wrappedValue {
                return value
            }
            let service = Container.default.resolveOptional(Service.self)
            _wrappedValue = service
            return service
        }
        mutating set {
            _wrappedValue = newValue
        }
    }
}
