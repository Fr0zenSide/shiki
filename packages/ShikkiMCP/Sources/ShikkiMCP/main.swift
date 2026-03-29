import Foundation
import Logging

LoggingSystem.bootstrap { label in
    var handler = StreamLogHandler.standardError(label: label)
    handler.logLevel = .info
    return handler
}

let dbURL = ProcessInfo.processInfo.environment["SHIKI_DB_URL"] ?? "http://localhost:3900"
let dbClient = ShikkiDBClient(baseURL: dbURL)
let server = MCPServer(dbClient: dbClient)
await server.run()
