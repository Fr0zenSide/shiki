import BrainyCore
import Foundation

/// Manages app-level settings: proxy, codec preference, geo-bypass, and quality defaults.
///
/// Proxy credentials are stored in Keychain via `Security.framework`.
/// Other settings use `UserDefaults`.
@Observable
@MainActor
public final class SettingsViewModel {

    // MARK: - State

    public var proxyConfig: ProxyConfig
    public var geoBypass: GeoBypassCountry
    public var codecPreference: VideoCodecPreference
    public var defaultQuality: VideoQuality

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let proxyType = "brainytube.proxy.type"
        static let proxyHost = "brainytube.proxy.host"
        static let proxyPort = "brainytube.proxy.port"
        static let geoBypass = "brainytube.geoBypass"
        static let codecPreference = "brainytube.codecPreference"
        static let defaultQuality = "brainytube.defaultQuality"
    }

    private static let keychainService = "com.brainy.proxy"

    // MARK: - Init

    public init() {
        let defaults = UserDefaults.standard

        let proxyType = ProxyType(rawValue: defaults.string(forKey: Keys.proxyType) ?? "") ?? .none
        let proxyHost = defaults.string(forKey: Keys.proxyHost) ?? ""
        let proxyPort = defaults.integer(forKey: Keys.proxyPort)
        let credentials = Self.loadCredentials()

        self.proxyConfig = ProxyConfig(
            type: proxyType,
            host: proxyHost,
            port: proxyPort > 0 ? proxyPort : 1080,
            username: credentials.username,
            password: credentials.password
        )

        self.geoBypass = GeoBypassCountry(
            rawValue: defaults.string(forKey: Keys.geoBypass) ?? ""
        ) ?? .none

        self.codecPreference = VideoCodecPreference(
            rawValue: defaults.string(forKey: Keys.codecPreference) ?? ""
        ) ?? .native

        self.defaultQuality = VideoQuality(
            rawValue: defaults.string(forKey: Keys.defaultQuality) ?? ""
        ) ?? .best
    }

    // MARK: - Save

    public func save() {
        let defaults = UserDefaults.standard
        defaults.set(proxyConfig.type.rawValue, forKey: Keys.proxyType)
        defaults.set(proxyConfig.host, forKey: Keys.proxyHost)
        defaults.set(proxyConfig.port, forKey: Keys.proxyPort)
        defaults.set(geoBypass.rawValue, forKey: Keys.geoBypass)
        defaults.set(codecPreference.rawValue, forKey: Keys.codecPreference)
        defaults.set(defaultQuality.rawValue, forKey: Keys.defaultQuality)

        Self.saveCredentials(username: proxyConfig.username, password: proxyConfig.password)
    }

    // MARK: - Mullvad Detection

    /// Auto-fill proxy config for Mullvad VPN SOCKS5.
    public func detectMullvad() {
        proxyConfig = .mullvad
    }

    // MARK: - Keychain

    private static func loadCredentials() -> (username: String, password: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let item = result as? [String: Any],
              let data = item[kSecValueData as String] as? Data,
              let password = String(data: data, encoding: .utf8),
              let account = item[kSecAttrAccount as String] as? String
        else {
            return ("", "")
        }

        return (account, password)
    }

    private static func saveCredentials(username: String, password: String) {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard !username.isEmpty || !password.isEmpty else { return }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: username,
            kSecValueData as String: password.data(using: .utf8) ?? Data(),
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}
