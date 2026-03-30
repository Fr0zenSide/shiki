import Foundation

// MARK: - PaletteResult

public struct PaletteResult: Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let category: String
    public let icon: String?
    public let score: Int

    public init(
        id: String, title: String, subtitle: String?,
        category: String, icon: String?, score: Int
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.icon = icon
        self.score = score
    }
}

// MARK: - PaletteSource Protocol

public protocol PaletteSource: Sendable {
    var category: String { get }
    var prefix: String? { get }
    func search(query: String) async -> [PaletteResult]
}
