import Foundation
import Testing
@testable import ShikkiKit

@Suite("PluginManifest — Codable, validation, version comparison")
struct PluginManifestTests {

    // MARK: - Test Fixtures

    private static func makeManifest(
        id: PluginID = "shikki/creative-studio",
        displayName: String = "Creative Studio",
        version: SemanticVersion = SemanticVersion(major: 0, minor: 1, patch: 0),
        source: PluginSource = .builtin,
        commands: [PluginCommand] = [PluginCommand(name: "creative", description: "Generate images")],
        capabilities: [String] = ["t2i", "t2v"],
        dependencies: PluginDependencies = PluginDependencies(
            systemTools: ["python3"],
            pythonPackages: ["diffusers"],
            minimumDiskGB: 15.0,
            minimumRAMGB: 16.0,
            venvPath: "~/.venvs/shikki-creative"
        ),
        minimumShikkiVersion: SemanticVersion = SemanticVersion(major: 0, minor: 3, patch: 0),
        entryPoint: String = "CreativeStudioPlugin",
        author: String = "shikki",
        license: String = "AGPL-3.0",
        description: String = "Local AI image generation",
        checksum: String = "abc123def456",
        certification: PluginCertification? = nil
    ) -> PluginManifest {
        PluginManifest(
            id: id,
            displayName: displayName,
            version: version,
            source: source,
            commands: commands,
            capabilities: capabilities,
            dependencies: dependencies,
            minimumShikkiVersion: minimumShikkiVersion,
            entryPoint: entryPoint,
            author: author,
            license: license,
            description: description,
            checksum: checksum,
            certification: certification
        )
    }

    // MARK: - Codable Round-Trip

    @Test("PluginManifest encodes and decodes with builtin source")
    func codableRoundTrip_builtin() throws {
        let manifest = Self.makeManifest()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(manifest)
        let decoded = try decoder.decode(PluginManifest.self, from: data)

        #expect(decoded.id == manifest.id)
        #expect(decoded.displayName == manifest.displayName)
        #expect(decoded.version == manifest.version)
        #expect(decoded.source == manifest.source)
        #expect(decoded.commands.count == manifest.commands.count)
        #expect(decoded.commands.first?.name == "creative")
        #expect(decoded.capabilities == manifest.capabilities)
        #expect(decoded.entryPoint == manifest.entryPoint)
        #expect(decoded.author == manifest.author)
        #expect(decoded.license == manifest.license)
        #expect(decoded.checksum == manifest.checksum)
    }

    @Test("PluginManifest encodes and decodes with local source")
    func codableRoundTrip_localSource() throws {
        let manifest = Self.makeManifest(source: .local(path: "/opt/plugins/creative"))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(manifest)
        let decoded = try decoder.decode(PluginManifest.self, from: data)

        #expect(decoded.source == .local(path: "/opt/plugins/creative"))
    }

    @Test("PluginManifest encodes and decodes with marketplace source")
    func codableRoundTrip_marketplaceSource() throws {
        let url = URL(string: "https://plugins.shikki.dev/creative-studio")!
        let manifest = Self.makeManifest(source: .marketplace(url: url, verified: true))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(manifest)
        let decoded = try decoder.decode(PluginManifest.self, from: data)

        #expect(decoded.source == .marketplace(url: url, verified: true))
    }

    @Test("PluginManifest decodes from JSON string matching spec format")
    func decodeFromSpecJSON() throws {
        let json = """
        {
            "id": "shikki/creative-studio",
            "displayName": "Creative Studio",
            "version": "0.1.0",
            "source": { "type": "builtin" },
            "commands": [{ "name": "creative", "description": "Generate images" }],
            "capabilities": ["t2i", "t2v", "compositing", "comfyui"],
            "dependencies": {
                "systemTools": ["python3", "pip3"],
                "pythonPackages": ["diffusers", "transformers"],
                "minimumDiskGB": 15.0,
                "minimumRAMGB": 16.0,
                "venvPath": "~/.venvs/shikki-creative"
            },
            "minimumShikkiVersion": "0.3.0",
            "entryPoint": "CreativeStudioPlugin",
            "author": "shikki",
            "license": "AGPL-3.0",
            "description": "Local AI image and video generation.",
            "checksum": "sha256-abc123",
            "updatedAt": "2026-03-27T14:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = json.data(using: .utf8)!
        let manifest = try decoder.decode(PluginManifest.self, from: data)

        #expect(manifest.id == PluginID("shikki/creative-studio"))
        #expect(manifest.displayName == "Creative Studio")
        #expect(manifest.version == SemanticVersion(major: 0, minor: 1, patch: 0))
        #expect(manifest.capabilities.count == 4)
        #expect(manifest.dependencies.systemTools == ["python3", "pip3"])
        #expect(manifest.dependencies.minimumDiskGB == 15.0)
        #expect(manifest.certification == nil)
    }

    @Test("PluginManifest round-trips with certification data")
    func codableRoundTrip_withCertification() throws {
        let cert = PluginCertification(
            level: .shikkiCertified,
            certifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
            certifiedBy: "shikki-bot",
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            signature: "GPG-SIG-ABC123"
        )
        let manifest = Self.makeManifest(certification: cert)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(manifest)
        let decoded = try decoder.decode(PluginManifest.self, from: data)

        #expect(decoded.certification?.level == .shikkiCertified)
        #expect(decoded.certification?.certifiedBy == "shikki-bot")
        #expect(decoded.certification?.signature == "GPG-SIG-ABC123")
    }

    // MARK: - Validation

    @Test("Valid manifest passes validation")
    func validate_validManifest_succeeds() throws {
        let manifest = Self.makeManifest()
        try manifest.validate()
    }

    @Test("Empty ID fails validation")
    func validate_emptyID_throws() {
        let manifest = Self.makeManifest(id: PluginID(""))
        #expect(throws: PluginManifest.ValidationError.self) {
            try manifest.validate()
        }
    }

    @Test("Empty display name fails validation")
    func validate_emptyDisplayName_throws() {
        let manifest = Self.makeManifest(displayName: "")
        #expect(throws: PluginManifest.ValidationError.self) {
            try manifest.validate()
        }
    }

    @Test("Empty author fails validation")
    func validate_emptyAuthor_throws() {
        let manifest = Self.makeManifest(author: "")
        #expect(throws: PluginManifest.ValidationError.self) {
            try manifest.validate()
        }
    }

    @Test("Empty entry point fails validation")
    func validate_emptyEntryPoint_throws() {
        let manifest = Self.makeManifest(entryPoint: "")
        #expect(throws: PluginManifest.ValidationError.self) {
            try manifest.validate()
        }
    }

    @Test("Empty checksum fails validation")
    func validate_emptyChecksum_throws() {
        let manifest = Self.makeManifest(checksum: "")
        #expect(throws: PluginManifest.ValidationError.self) {
            try manifest.validate()
        }
    }

    @Test("No commands fails validation")
    func validate_noCommands_throws() {
        let manifest = Self.makeManifest(commands: [])
        #expect(throws: PluginManifest.ValidationError.self) {
            try manifest.validate()
        }
    }

    // MARK: - Version Compatibility

    @Test("Plugin is compatible when current version meets minimum")
    func isCompatible_whenVersionMeets_returnsTrue() {
        let manifest = Self.makeManifest(
            minimumShikkiVersion: SemanticVersion(major: 0, minor: 3, patch: 0)
        )
        let current = SemanticVersion(major: 0, minor: 3, patch: 0)
        #expect(manifest.isCompatible(with: current) == true)
    }

    @Test("Plugin is compatible when current version exceeds minimum")
    func isCompatible_whenVersionExceeds_returnsTrue() {
        let manifest = Self.makeManifest(
            minimumShikkiVersion: SemanticVersion(major: 0, minor: 2, patch: 0)
        )
        let current = SemanticVersion(major: 1, minor: 0, patch: 0)
        #expect(manifest.isCompatible(with: current) == true)
    }

    @Test("Plugin is incompatible when current version is below minimum")
    func isCompatible_whenVersionBelow_returnsFalse() {
        let manifest = Self.makeManifest(
            minimumShikkiVersion: SemanticVersion(major: 1, minor: 0, patch: 0)
        )
        let current = SemanticVersion(major: 0, minor: 3, patch: 0)
        #expect(manifest.isCompatible(with: current) == false)
    }

    // MARK: - Checksum Verification

    @Test("Checksum verification passes with matching checksum")
    func verifyChecksum_matching_returnsTrue() {
        let manifest = Self.makeManifest(checksum: "sha256-abc123")
        #expect(manifest.verifyChecksum("sha256-abc123") == true)
    }

    @Test("Checksum verification fails with mismatched checksum")
    func verifyChecksum_mismatched_returnsFalse() {
        let manifest = Self.makeManifest(checksum: "sha256-abc123")
        #expect(manifest.verifyChecksum("sha256-different") == false)
    }
}

// MARK: - SemanticVersion Tests

@Suite("SemanticVersion — parsing, comparison, encoding")
struct SemanticVersionTests {

    @Test("Parse valid version string")
    func parseValid() {
        let version = SemanticVersion(string: "1.2.3")
        #expect(version != nil)
        #expect(version?.major == 1)
        #expect(version?.minor == 2)
        #expect(version?.patch == 3)
    }

    @Test("Parse zero version")
    func parseZero() {
        let version = SemanticVersion(string: "0.0.0")
        #expect(version != nil)
        #expect(version?.major == 0)
    }

    @Test("Reject invalid version string")
    func parseInvalid() {
        #expect(SemanticVersion(string: "1.2") == nil)
        #expect(SemanticVersion(string: "abc") == nil)
        #expect(SemanticVersion(string: "1.2.3.4") == nil)
        #expect(SemanticVersion(string: "") == nil)
    }

    @Test("Version comparison: major takes precedence")
    func compare_majorPrecedence() {
        let v1 = SemanticVersion(major: 1, minor: 9, patch: 9)
        let v2 = SemanticVersion(major: 2, minor: 0, patch: 0)
        #expect(v1 < v2)
    }

    @Test("Version comparison: minor takes precedence over patch")
    func compare_minorPrecedence() {
        let v1 = SemanticVersion(major: 1, minor: 0, patch: 9)
        let v2 = SemanticVersion(major: 1, minor: 1, patch: 0)
        #expect(v1 < v2)
    }

    @Test("Version comparison: patch ordering")
    func compare_patchOrdering() {
        let v1 = SemanticVersion(major: 1, minor: 0, patch: 0)
        let v2 = SemanticVersion(major: 1, minor: 0, patch: 1)
        #expect(v1 < v2)
    }

    @Test("Version equality")
    func compare_equality() {
        let v1 = SemanticVersion(major: 1, minor: 2, patch: 3)
        let v2 = SemanticVersion(major: 1, minor: 2, patch: 3)
        #expect(v1 == v2)
        #expect(!(v1 < v2))
        #expect(!(v2 < v1))
    }

    @Test("Version description format")
    func descriptionFormat() {
        let version = SemanticVersion(major: 0, minor: 3, patch: 0)
        #expect(version.description == "0.3.0")
    }

    @Test("Version Codable round-trip encodes as string")
    func codableRoundTrip() throws {
        let version = SemanticVersion(major: 1, minor: 2, patch: 3)
        let data = try JSONEncoder().encode(version)
        let jsonString = String(data: data, encoding: .utf8)!
        #expect(jsonString == "\"1.2.3\"")

        let decoded = try JSONDecoder().decode(SemanticVersion.self, from: data)
        #expect(decoded == version)
    }
}

// MARK: - CertificationLevel Tests

@Suite("CertificationLevel — ordering and trust hierarchy")
struct CertificationLevelTests {

    @Test("Certification levels are ordered by trust")
    func trustOrdering() {
        #expect(CertificationLevel.uncertified < .communityReviewed)
        #expect(CertificationLevel.communityReviewed < .shikkiCertified)
        #expect(CertificationLevel.shikkiCertified < .enterpriseSafe)
    }

    @Test("Uncertified is lowest trust")
    func uncertifiedIsLowest() {
        let sorted = CertificationLevel.allCases.sorted()
        #expect(sorted.first == .uncertified)
        #expect(sorted.last == .enterpriseSafe)
    }

    @Test("Same certification level is equal, not less than")
    func sameLevelEquality() {
        #expect(!(CertificationLevel.shikkiCertified < .shikkiCertified))
    }

    @Test("Certification expiration detects expired cert")
    func certification_isExpired() {
        let expired = PluginCertification(
            level: .shikkiCertified,
            expiresAt: Date(timeIntervalSinceNow: -86400)  // yesterday
        )
        #expect(expired.isExpired == true)
    }

    @Test("Certification expiration detects valid cert")
    func certification_isNotExpired() {
        let valid = PluginCertification(
            level: .shikkiCertified,
            expiresAt: Date(timeIntervalSinceNow: 86400)  // tomorrow
        )
        #expect(valid.isExpired == false)
    }

    @Test("Certification without expiry is never expired")
    func certification_noExpiry_isNotExpired() {
        let noExpiry = PluginCertification(level: .communityReviewed)
        #expect(noExpiry.isExpired == false)
    }
}

// MARK: - PluginSource Tests

@Suite("PluginSource — Codable encoding variants")
struct PluginSourceTests {

    @Test("Builtin source round-trips through JSON")
    func builtin_codableRoundTrip() throws {
        let source = PluginSource.builtin
        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(PluginSource.self, from: data)
        #expect(decoded == source)
    }

    @Test("Local source round-trips through JSON")
    func local_codableRoundTrip() throws {
        let source = PluginSource.local(path: "/opt/plugins/test")
        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(PluginSource.self, from: data)
        #expect(decoded == source)
    }

    @Test("Marketplace source round-trips through JSON")
    func marketplace_codableRoundTrip() throws {
        let url = URL(string: "https://plugins.shikki.dev/test")!
        let source = PluginSource.marketplace(url: url, verified: true)
        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(PluginSource.self, from: data)
        #expect(decoded == source)
    }
}

// MARK: - PluginID Tests

@Suite("PluginID — identity and equality")
struct PluginIDTests {

    @Test("PluginID initializes from string literal")
    func stringLiteral() {
        let id: PluginID = "shikki/test"
        #expect(id.rawValue == "shikki/test")
        #expect(id.description == "shikki/test")
    }

    @Test("PluginID equality works")
    func equality() {
        let a = PluginID("shikki/test")
        let b: PluginID = "shikki/test"
        #expect(a == b)
    }

    @Test("PluginID Codable round-trip")
    func codableRoundTrip() throws {
        let id = PluginID("shikki/creative-studio")
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(PluginID.self, from: data)
        #expect(decoded == id)
    }
}
