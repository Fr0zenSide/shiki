import Foundation
import Testing
@testable import ShikkiKit

@Suite("NATSConfig — Configuration model")
struct NATSConfigTests {

    @Test("Default config has correct host and port")
    func defaultHostAndPort() {
        let config = NATSConfig.default
        #expect(config.host == "127.0.0.1")
        #expect(config.port == 4222)
    }

    @Test("Default max payload is 1MB")
    func defaultMaxPayload() {
        let config = NATSConfig.default
        #expect(config.maxPayload == 1_048_576)
    }

    @Test("Auto-generates auth token when empty")
    func autoGeneratesToken() {
        let config = NATSConfig(authToken: "")
        #expect(!config.authToken.isEmpty)
        #expect(config.authToken.count == 32) // 16 bytes = 32 hex chars
    }

    @Test("Preserves explicit auth token")
    func preservesExplicitToken() {
        let config = NATSConfig(authToken: "my-secret-token")
        #expect(config.authToken == "my-secret-token")
    }

    @Test("Custom port is respected")
    func customPort() {
        let config = NATSConfig(port: 5222)
        #expect(config.port == 5222)
    }

    @Test("Config file path resolves under ~/.config/shiki/")
    func configFilePath() {
        let path = NATSConfig.configFilePath
        #expect(path.contains(".config/shiki/nats-server.conf"))
    }

    @Test("Binary path resolves under ~/.config/shiki/bin/")
    func binaryPath() {
        let path = NATSConfig.binaryPath
        #expect(path.contains(".config/shiki/bin/nats-server"))
    }

    @Test("PID file path resolves under ~/.config/shiki/")
    func pidFilePath() {
        let path = NATSConfig.defaultPidFile
        #expect(path.contains(".config/shiki/nats-server.pid"))
    }

    @Test("NKey file path resolves under ~/.config/shiki/")
    func nkeyFilePath() {
        let path = NATSConfig.nkeyFilePath
        #expect(path.contains(".config/shiki/nats-key.nk"))
    }

    @Test("Log file path resolves under ~/.shiki/logs/")
    func logFilePath() {
        let path = NATSConfig.defaultLogFile
        #expect(path.contains(".shiki/logs/nats-server.log"))
    }

    @Test("Config content contains listen directive")
    func configContentListen() {
        let config = NATSConfig(host: "127.0.0.1", port: 4222)
        let content = config.toConfigFileContent()
        #expect(content.contains("listen: 127.0.0.1:4222"))
    }

    @Test("Config content contains max_payload")
    func configContentMaxPayload() {
        let config = NATSConfig(maxPayload: 2_097_152)
        let content = config.toConfigFileContent()
        #expect(content.contains("max_payload: 2097152"))
    }

    @Test("Config content contains authorization block")
    func configContentAuth() {
        let config = NATSConfig(authToken: "test-token-abc")
        let content = config.toConfigFileContent()
        #expect(content.contains("authorization {"))
        #expect(content.contains("token: \"test-token-abc\""))
    }

    @Test("Config content contains log_file")
    func configContentLogFile() {
        let config = NATSConfig.default
        let content = config.toConfigFileContent()
        #expect(content.contains("log_file:"))
        #expect(content.contains("nats-server.log"))
    }

    @Test("Config content contains pid_file")
    func configContentPidFile() {
        let config = NATSConfig.default
        let content = config.toConfigFileContent()
        #expect(content.contains("pid_file:"))
        #expect(content.contains("nats-server.pid"))
    }

    @Test("Token generation produces unique values")
    func tokenUniqueness() {
        let token1 = NATSConfig.generateToken()
        let token2 = NATSConfig.generateToken()
        #expect(token1 != token2)
        #expect(token1.count == 32)
        #expect(token2.count == 32)
    }

    @Test("Config writes to temp file")
    func writeToFile() throws {
        let tmpDir = NSTemporaryDirectory()
        let tmpPath = "\(tmpDir)nats-test-\(UUID().uuidString).conf"
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        let config = NATSConfig(authToken: "write-test-token")
        try config.writeToFile(at: tmpPath)

        let content = try String(contentsOfFile: tmpPath, encoding: .utf8)
        #expect(content.contains("listen: 127.0.0.1:4222"))
        #expect(content.contains("write-test-token"))
    }

    @Test("Config creates parent directories when writing")
    func writeCreatesDirectories() throws {
        let tmpDir = NSTemporaryDirectory()
        let nested = "\(tmpDir)nats-nested-\(UUID().uuidString)/sub/dir/nats.conf"
        defer {
            let base = "\(tmpDir)nats-nested-\(nested.components(separatedBy: "nats-nested-").last?.components(separatedBy: "/").first ?? "")"
            try? FileManager.default.removeItem(atPath: base)
        }

        let config = NATSConfig.default
        try config.writeToFile(at: nested)

        #expect(FileManager.default.fileExists(atPath: nested))
    }

    @Test("Equatable conformance works")
    func equatable() {
        let config1 = NATSConfig(host: "127.0.0.1", port: 4222, authToken: "same")
        let config2 = NATSConfig(host: "127.0.0.1", port: 4222, authToken: "same")
        #expect(config1 == config2)

        let config3 = NATSConfig(host: "127.0.0.1", port: 5222, authToken: "same")
        #expect(config1 != config3)
    }
}
