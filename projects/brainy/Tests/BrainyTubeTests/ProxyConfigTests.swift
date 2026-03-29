import BrainyCore
@testable import BrainyTubeKit
import Testing

@Suite("ProxyConfig")
struct ProxyConfigTests {

    @Test("SOCKS5 proxy builds correct yt-dlp argument")
    func socks5ProxyBuildsCorrectArgument() {
        let config = ProxyConfig(
            type: .socks5,
            host: "10.64.0.1",
            port: 1080
        )

        #expect(config.ytdlpArgument == "socks5://10.64.0.1:1080")
    }

    @Test("No proxy returns nil argument")
    func noProxyReturnsNil() {
        let config = ProxyConfig(type: .none)
        #expect(config.ytdlpArgument == nil)
    }

    @Test("HTTP proxy with credentials includes auth")
    func httpProxyWithCredentialsIncludesAuth() {
        let config = ProxyConfig(
            type: .http,
            host: "proxy.example.com",
            port: 8080,
            username: "user",
            password: "pass"
        )

        #expect(config.ytdlpArgument == "http://user:pass@proxy.example.com:8080")
    }

    @Test("HTTPS proxy with username only omits password")
    func httpsProxyUsernameOnly() {
        let config = ProxyConfig(
            type: .https,
            host: "secure.proxy.io",
            port: 443,
            username: "admin"
        )

        #expect(config.ytdlpArgument == "https://admin@secure.proxy.io:443")
    }

    @Test("Proxy with empty host returns nil")
    func proxyWithEmptyHostReturnsNil() {
        let config = ProxyConfig(type: .socks5, host: "", port: 1080)
        #expect(config.ytdlpArgument == nil)
    }

    @Test("Geo-bypass appends country flag")
    func geoBypassAppendsCountryFlag() {
        let config = ProxyConfig(type: .none)
        let args = config.ytdlpArguments(geoBypass: .jp)

        #expect(args.contains("--geo-bypass-country"))
        #expect(args.contains("JP"))
    }

    @Test("No geo-bypass produces no country arguments")
    func noGeoBypassNoCountryArguments() {
        let config = ProxyConfig(type: .none)
        let args = config.ytdlpArguments(geoBypass: .none)

        #expect(args.isEmpty)
    }

    @Test("Combined proxy and geo-bypass produces both arguments")
    func combinedProxyAndGeoBypass() {
        let config = ProxyConfig(
            type: .socks5,
            host: "10.64.0.1",
            port: 1080
        )
        let args = config.ytdlpArguments(geoBypass: .us)

        #expect(args.contains("--proxy"))
        #expect(args.contains("socks5://10.64.0.1:1080"))
        #expect(args.contains("--geo-bypass-country"))
        #expect(args.contains("US"))
    }

    @Test("Mullvad preset has correct values")
    func mullvadPresetHasCorrectValues() {
        let config = ProxyConfig.mullvad

        #expect(config.type == .socks5)
        #expect(config.host == "10.64.0.1")
        #expect(config.port == 1080)
        #expect(config.username.isEmpty)
        #expect(config.password.isEmpty)
    }
}
