import Foundation

// MARK: - Node Type

/// Every queryable entity in Shiki.
public enum NodeType: String, Codable, Sendable, CaseIterable {
    case session
    case task
    case feature
    case decision
    case agent
    case file
    case pr
    case memory
    case plan
    case concern
    case command
    case branch
}

// MARK: - ShikiNode

/// Unified node protocol for the command palette and search system.
/// Sessions, tasks, features, decisions, agents, files — all queryable the same way.
public protocol ShikiNode: Identifiable, Sendable {
    var id: String { get }
    var nodeType: NodeType { get }
    var title: String { get }
    var subtitle: String? { get }
    var icon: String? { get }
    var parentId: String? { get }
    var relations: [String: String] { get }
    var createdAt: Date { get }
}

// MARK: - GenericNode

/// Concrete node implementation for ad-hoc results.
public struct GenericNode: ShikiNode, Equatable {
    public let id: String
    public let nodeType: NodeType
    public let title: String
    public let subtitle: String?
    public let icon: String?
    public let parentId: String?
    public let relations: [String: String]
    public let createdAt: Date

    public init(
        id: String,
        nodeType: NodeType,
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        parentId: String? = nil,
        relations: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.nodeType = nodeType
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.parentId = parentId
        self.relations = relations
        self.createdAt = createdAt
    }
}

// MARK: - PaletteResult <-> ShikiNode Bridge

extension PaletteResult {
    /// Create a PaletteResult from any ShikiNode.
    public init(node: any ShikiNode, score: Int) {
        self.init(
            id: node.id,
            title: node.title,
            subtitle: node.subtitle,
            category: node.nodeType.rawValue,
            icon: node.icon,
            score: score
        )
    }
}
