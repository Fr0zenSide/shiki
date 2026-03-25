public enum StorageFilter: Sendable, Equatable {
    case equals(column: String, value: String)
    case like(column: String, pattern: String)
    case isNull(column: String)
    case and([StorageFilter])
    case or([StorageFilter])

    /// Generates a SQL WHERE clause and associated parameter values.
    /// - Parameter paramOffset: Starting index offset for parameter placeholders.
    /// - Returns: A tuple of the SQL clause string and an array of parameter values.
    public func toSQL(paramOffset: Int = 0) -> (clause: String, params: [String]) {
        switch self {
        case .equals(let column, let value):
            return ("\(column) = ?", [value])

        case .like(let column, let pattern):
            return ("\(column) LIKE ?", [pattern])

        case .isNull(let column):
            return ("\(column) IS NULL", [])

        case .and(let filters):
            var clauses: [String] = []
            var allParams: [String] = []
            var offset = paramOffset
            for filter in filters {
                let result = filter.toSQL(paramOffset: offset)
                clauses.append(result.clause)
                allParams.append(contentsOf: result.params)
                offset += result.params.count
            }
            let combined = clauses.map { "(\($0))" }.joined(separator: " AND ")
            return (combined, allParams)

        case .or(let filters):
            var clauses: [String] = []
            var allParams: [String] = []
            var offset = paramOffset
            for filter in filters {
                let result = filter.toSQL(paramOffset: offset)
                clauses.append(result.clause)
                allParams.append(contentsOf: result.params)
                offset += result.params.count
            }
            let combined = clauses.map { "(\($0))" }.joined(separator: " OR ")
            return (combined, allParams)
        }
    }
}
