import BrainyCore
import Foundation

// MARK: - Proxy Type

public enum ProxyType: String, Codable, CaseIterable, Sendable {
    case none
    case socks5
    case http
    case https
}

// MARK: - Proxy Config

/// Configuration for yt-dlp proxy and geo-bypass arguments.
///
/// Proxy credentials (username/password) are stored in Keychain via `Security.framework`,
/// not in UserDefaults. Only the host, port, and type are persisted in plain storage.
public struct ProxyConfig: Codable, Equatable, Sendable {
    public var type: ProxyType
    public var host: String
    public var port: Int
    public var username: String
    public var password: String

    public init(
        type: ProxyType = .none,
        host: String = "",
        port: Int = 1080,
        username: String = "",
        password: String = ""
    ) {
        self.type = type
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }

    /// Builds the `--proxy` argument for yt-dlp.
    /// Returns `nil` when proxy is `.none` or host is empty.
    public var ytdlpArgument: String? {
        guard type != .none, !host.isEmpty else { return nil }

        let scheme = type.rawValue
        let auth: String
        if !username.isEmpty {
            if !password.isEmpty {
                auth = "\(username):\(password)@"
            } else {
                auth = "\(username)@"
            }
        } else {
            auth = ""
        }

        return "\(scheme)://\(auth)\(host):\(port)"
    }

    /// Builds the full set of yt-dlp proxy + geo-bypass arguments.
    public func ytdlpArguments(geoBypass: GeoBypassCountry = .none) -> [String] {
        var args: [String] = []

        if let proxy = ytdlpArgument {
            args.append(contentsOf: ["--proxy", proxy])
        }

        if geoBypass != .none {
            args.append(contentsOf: ["--geo-bypass-country", geoBypass.rawValue])
        }

        return args
    }

    /// Preset configuration for Mullvad VPN SOCKS5.
    public static let mullvad = ProxyConfig(
        type: .socks5,
        host: "10.64.0.1",
        port: 1080
    )
}
