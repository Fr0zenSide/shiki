import BrainyCore
import SwiftUI

/// App settings view for proxy, codec, geo-bypass, and quality configuration.
struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        TabView {
            playbackTab
                .tabItem { Label("Playback", systemImage: "play.circle") }

            networkTab
                .tabItem { Label("Network", systemImage: "network") }
        }
        .frame(width: 500, height: 400)
        .onChange(of: viewModel.proxyConfig) { _, _ in viewModel.save() }
        .onChange(of: viewModel.geoBypass) { _, _ in viewModel.save() }
        .onChange(of: viewModel.codecPreference) { _, _ in viewModel.save() }
        .onChange(of: viewModel.defaultQuality) { _, _ in viewModel.save() }
    }

    // MARK: - Playback Tab

    private var playbackTab: some View {
        Form {
            Section("Codec Preference") {
                Picker("Video Codec", selection: $viewModel.codecPreference) {
                    Text("Native (AV1 + H.264 — hardware decode)")
                        .tag(VideoCodecPreference.native)
                    Text("Universal (adds VP9 — software decode)")
                        .tag(VideoCodecPreference.universal)
                }
                .pickerStyle(.radioGroup)

                Text("Native mode uses hardware acceleration for smooth playback. Universal adds VP9 support but uses more CPU.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Default Quality") {
                Picker("Quality", selection: $viewModel.defaultQuality) {
                    ForEach(VideoQuality.allCases, id: \.self) { quality in
                        Text(quality.rawValue).tag(quality)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding()
    }

    // MARK: - Network Tab

    private var networkTab: some View {
        Form {
            Section("Proxy") {
                Picker("Type", selection: $viewModel.proxyConfig.type) {
                    ForEach(ProxyType.allCases, id: \.self) { type in
                        Text(type.rawValue.uppercased()).tag(type)
                    }
                }

                if viewModel.proxyConfig.type != .none {
                    TextField("Host", text: $viewModel.proxyConfig.host)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Text("Port")
                        TextField(
                            "Port",
                            value: $viewModel.proxyConfig.port,
                            format: .number
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    }

                    TextField("Username", text: $viewModel.proxyConfig.username)
                        .textFieldStyle(.roundedBorder)

                    SecureField("Password", text: $viewModel.proxyConfig.password)
                        .textFieldStyle(.roundedBorder)

                    Button("Detect Mullvad VPN") {
                        viewModel.detectMullvad()
                    }
                    .help("Auto-fill with Mullvad SOCKS5 settings (10.64.0.1:1080)")
                }
            }

            Section("Geo-bypass") {
                Picker("Country", selection: $viewModel.geoBypass) {
                    ForEach(GeoBypassCountry.allCases, id: \.self) { country in
                        Text(country.label).tag(country)
                    }
                }

                if viewModel.geoBypass != .none {
                    Text("Tells yt-dlp to bypass geographic restrictions by pretending to be in \(viewModel.geoBypass.label).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Region-Locked Content") {
                Text("When a video fails due to region restrictions, BrainyTube will show an actionable error with a direct link to these settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
