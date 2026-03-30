import Foundation

/// MCP tool definitions for the Moto DNS protocol.
///
/// All Moto tools use the `moto_` prefix per the namespace rule in the spec.
/// These are stubs that define the tool interface — actual MCP transport
/// (JSON-RPC over stdio/SSE) will be implemented when ShikkiMCP integrates.
///
/// Tools:
/// - `moto_get_context` — full project context from manifest
/// - `moto_get_type` — single type descriptor by name
/// - `moto_get_protocol` — single protocol descriptor by name
/// - `moto_get_pattern` — code pattern by name
/// - `moto_get_dependency_graph` — module dependency graph
/// - `moto_get_api_surface` — public API surface
/// - `moto_validate_cache` — check cache integrity
public struct MotoMCPInterface: Sendable {

    private let cacheReader: MotoCacheReader

    /// Create an MCP interface backed by a local cache directory.
    ///
    /// - Parameter cachePath: Absolute path to the `.moto-cache/` directory.
    public init(cachePath: String) {
        self.cacheReader = MotoCacheReader(cachePath: cachePath)
    }

    /// Create an MCP interface from an existing reader.
    public init(reader: MotoCacheReader) {
        self.cacheReader = reader
    }

    // MARK: - MCP Tool Handlers

    /// `moto_get_context` — Returns the full project manifest with stats.
    ///
    /// MCP parameters:
    /// - `project`: project identifier (optional, defaults to manifest project)
    /// - `scope`: which section to return ("manifest", "protocols", "types", "all")
    public func getContext(scope: ContextScope = .manifest) throws -> MotoContextResponse {
        let manifest = try cacheReader.loadManifest()

        switch scope {
        case .manifest:
            return MotoContextResponse(
                manifest: manifest,
                protocols: nil,
                types: nil,
                dependencies: nil,
                patterns: nil,
                tests: nil,
                apiSurface: nil
            )
        case .protocols:
            let protocols = try cacheReader.loadProtocols()
            return MotoContextResponse(
                manifest: manifest,
                protocols: protocols,
                types: nil,
                dependencies: nil,
                patterns: nil,
                tests: nil,
                apiSurface: nil
            )
        case .types:
            let types = try cacheReader.loadTypes()
            return MotoContextResponse(
                manifest: manifest,
                protocols: nil,
                types: types,
                dependencies: nil,
                patterns: nil,
                tests: nil,
                apiSurface: nil
            )
        case .all:
            let protocols = try cacheReader.loadProtocols()
            let types = try cacheReader.loadTypes()
            let deps = try cacheReader.loadDependencies()
            let patterns = try cacheReader.loadPatterns()
            let tests = try cacheReader.loadTestInfo()
            let api = try cacheReader.loadAPISurface()
            return MotoContextResponse(
                manifest: manifest,
                protocols: protocols,
                types: types,
                dependencies: deps,
                patterns: patterns,
                tests: tests,
                apiSurface: api
            )
        }
    }

    /// `moto_get_type` — Look up a single type by name.
    ///
    /// MCP parameters:
    /// - `project`: project identifier
    /// - `name`: type name to find
    public func getType(name: String) throws -> TypeDescriptor? {
        try cacheReader.findType(named: name)
    }

    /// `moto_get_protocol` — Look up a single protocol by name.
    ///
    /// MCP parameters:
    /// - `project`: project identifier
    /// - `name`: protocol name to find
    public func getProtocol(name: String) throws -> ProtocolDescriptor? {
        try cacheReader.findProtocol(named: name)
    }

    /// `moto_get_pattern` — Look up a code pattern by name.
    ///
    /// MCP parameters:
    /// - `project`: project identifier
    /// - `name`: pattern name (e.g. "error_pattern", "mock_pattern")
    public func getPattern(name: String) throws -> CodePattern? {
        let patterns = try cacheReader.loadPatterns()
        return patterns.first { $0.name == name }
    }

    /// `moto_get_dependency_graph` — Full module dependency graph.
    ///
    /// MCP parameters:
    /// - `project`: project identifier
    /// - `module`: optional — filter to a single module's dependencies
    public func getDependencyGraph(module: String? = nil) throws -> [String: [String]] {
        let graph = try cacheReader.loadDependencies()
        if let module {
            return graph.filter { $0.key == module }
        }
        return graph
    }

    /// `moto_get_api_surface` — Public API surface.
    ///
    /// MCP parameters:
    /// - `project`: project identifier
    /// - `module`: optional — filter to a single module
    public func getAPISurface(module: String? = nil) throws -> APISurface {
        let surface = try cacheReader.loadAPISurface()
        if let module {
            let filtered = surface.modules.filter { $0.name == module }
            return APISurface(modules: filtered)
        }
        return surface
    }

    /// `moto_validate_cache` — Check cache integrity.
    ///
    /// MCP parameters:
    /// - `project`: project identifier
    public func validateCache() throws -> MotoValidationResponse {
        let failures = try cacheReader.validate()
        return MotoValidationResponse(
            valid: failures.isEmpty,
            failedFiles: failures
        )
    }

    // MARK: - MCP Tool Descriptors

    /// Returns MCP tool definitions for registration with an MCP server.
    ///
    /// Each tool follows the MCP Tool schema:
    /// ```json
    /// { "name": "moto_get_context", "description": "...", "inputSchema": {...} }
    /// ```
    public static var toolDescriptors: [MotoToolDescriptor] {
        [
            MotoToolDescriptor(
                name: "moto_get_context",
                description: "Get project architecture context from Moto cache. Returns manifest, protocols, types, dependencies, patterns, tests, and API surface.",
                parameters: [
                    .init(name: "project", type: "string", description: "Project identifier", required: false),
                    .init(name: "scope", type: "string", description: "Which section: manifest, protocols, types, all", required: false),
                ]
            ),
            MotoToolDescriptor(
                name: "moto_get_type",
                description: "Look up a single type by name from the Moto cache.",
                parameters: [
                    .init(name: "project", type: "string", description: "Project identifier", required: false),
                    .init(name: "name", type: "string", description: "Type name to find", required: true),
                ]
            ),
            MotoToolDescriptor(
                name: "moto_get_protocol",
                description: "Look up a single protocol by name from the Moto cache.",
                parameters: [
                    .init(name: "project", type: "string", description: "Project identifier", required: false),
                    .init(name: "name", type: "string", description: "Protocol name to find", required: true),
                ]
            ),
            MotoToolDescriptor(
                name: "moto_get_pattern",
                description: "Look up a code pattern by name (e.g. error_pattern, mock_pattern).",
                parameters: [
                    .init(name: "project", type: "string", description: "Project identifier", required: false),
                    .init(name: "name", type: "string", description: "Pattern name to find", required: true),
                ]
            ),
            MotoToolDescriptor(
                name: "moto_get_dependency_graph",
                description: "Get the module dependency graph from the Moto cache.",
                parameters: [
                    .init(name: "project", type: "string", description: "Project identifier", required: false),
                    .init(name: "module", type: "string", description: "Filter to a single module", required: false),
                ]
            ),
            MotoToolDescriptor(
                name: "moto_get_api_surface",
                description: "Get the public API surface from the Moto cache.",
                parameters: [
                    .init(name: "project", type: "string", description: "Project identifier", required: false),
                    .init(name: "module", type: "string", description: "Filter to a single module", required: false),
                ]
            ),
            MotoToolDescriptor(
                name: "moto_validate_cache",
                description: "Validate cache integrity by checking checksums against the manifest.",
                parameters: [
                    .init(name: "project", type: "string", description: "Project identifier", required: false),
                ]
            ),
        ]
    }
}

// MARK: - Context Scope

extension MotoMCPInterface {
    /// Scope of context to return from `moto_get_context`.
    public enum ContextScope: String, Sendable, Codable {
        case manifest
        case protocols
        case types
        case all
    }
}

// MARK: - Response Types

/// Response from `moto_get_context`.
public struct MotoContextResponse: Sendable, Codable {
    public let manifest: MotoCacheManifest
    public let protocols: [ProtocolDescriptor]?
    public let types: [TypeDescriptor]?
    public let dependencies: [String: [String]]?
    public let patterns: [CodePattern]?
    public let tests: TestInfo?
    public let apiSurface: APISurface?

    enum CodingKeys: String, CodingKey {
        case manifest
        case protocols
        case types
        case dependencies
        case patterns
        case tests
        case apiSurface = "api_surface"
    }
}

/// Response from `moto_validate_cache`.
public struct MotoValidationResponse: Sendable, Codable, Equatable {
    public let valid: Bool
    public let failedFiles: [String]

    enum CodingKeys: String, CodingKey {
        case valid
        case failedFiles = "failed_files"
    }
}

// MARK: - Tool Descriptor

/// MCP tool descriptor for registration.
public struct MotoToolDescriptor: Sendable, Codable, Equatable {
    public var name: String
    public var description: String
    public var parameters: [ParameterDescriptor]

    public init(name: String, description: String, parameters: [ParameterDescriptor]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    public struct ParameterDescriptor: Sendable, Codable, Equatable {
        public var name: String
        public var type: String
        public var description: String
        public var required: Bool

        public init(name: String, type: String, description: String, required: Bool) {
            self.name = name
            self.type = type
            self.description = description
            self.required = required
        }
    }
}
