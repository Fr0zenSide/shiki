import Foundation

// MARK: - Duration convenience

extension Duration {
    /// Total duration expressed as seconds (with sub-second precision).
    ///
    /// Consolidates the repeated `Double(seconds) + Double(attoseconds) / 1e18`
    /// pattern into a single computed property.
    public var totalSeconds: Double {
        let (seconds, attoseconds) = self.components
        return Double(seconds) + Double(attoseconds) / 1_000_000_000_000_000_000
    }
}
