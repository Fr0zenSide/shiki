# Feature: shikki ship --testflight
> Created: 2026-03-26 | Status: Phase 4 — Test Plan | Owner: @Daimyo
> Agents: @Sensei (architecture), @Kenshi (release engineering), @Katana (security), @Hanami (UX)

## Phase 1 — Inspiration

### Problem

GitHub Actions CI/CD for iOS costs real money (paid macOS minutes). The user has an M2 Max 64GB that can archive, sign, and upload faster than any CI runner. Two apps need TestFlight: WabiSabi (OBYW.one, Team `L8NRHDDSWG`) and Maya (FJ Studio, Team `UVC4JM6XD4`). Today, getting a build to TestFlight is a manual 7-step slog: clean, test, archive, export, upload, distribute, notify. This should be one command.

### Brainstorm

#### @Sensei — Architecture

| # | Idea | Verdict |
|---|------|---------|
| S1 | **TestFlightGate as ShipGate extension** — new gates (ArchiveGate, ExportGate, UploadGate, DistributeGate) plug into the existing pipeline-of-gates. Same ShipContext, same event bus, same dry-run. Zero new orchestration code. | BUILD |
| S2 | **AppConfig registry** — `~/.config/shikki/apps.toml` maps app slugs to scheme, team ID, bundle ID, export options path, TestFlight group. `--app wabisabi` resolves to a typed `AppConfig` struct. | BUILD |
| S3 | **asc CLI wrapper** — thin `ASCClient` struct that shells out to `asc` binary. No Go FFI, no reimplementation. External tool philosophy: use now, replace if limited. | BUILD |
| S4 | **ExportOptions.plist generation** — template per method (app-store, ad-hoc, development). Shikki generates from AppConfig at archive time. No manual plist maintenance. | BUILD |
| S5 | **Scheme auto-detection** — parse `.xcodeproj/xcshareddata/xcschemes/` or `xcodebuild -list` to find the app scheme. Fallback: require in apps.toml. | v1.1 |

#### @Kenshi — Release Engineering

| # | Idea | Verdict |
|---|------|---------|
| K1 | **Build number auto-increment** — read current from `agvtool`, bump +1, write back. Tag `vX.Y.Z+build` after successful upload. Never collide with App Store Connect. | BUILD |
| K2 | **Archive → Export → Upload → Distribute as atomic pipeline** — if any step fails, the .xcarchive and .ipa are preserved in `~/.shikki/archives/` for manual retry. Never lose a successful build. | BUILD |
| K3 | **Rollback = no rollback** — TestFlight is append-only. If a build is bad, ship a new one. The "rollback" is just `shikki ship --testflight` again with the fix. Simple. | BUILD |
| K4 | **Release notes from changelog** — ChangelogGate already generates grouped entries. Pipe the markdown into TestFlight "What to Test" field via `asc testflight`. | BUILD |
| K5 | **Nightly scheduled builds** — cron trigger via ShikkiKernel (launchd plist). Picks up whatever is on develop, ships to TestFlight with auto-generated notes. | v2 |

#### @Katana — Security

| # | Idea | Verdict |
|---|------|---------|
| A1 | **API key in macOS Keychain** — `security add-generic-password` stores .p8 content. `shikki doctor` validates it exists. Never on disk in plaintext, never in git. | BUILD |
| A2 | **Fallback: ~/.config/shikki/keys/** — for headless/CI use, .p8 files in a chmod 600 directory. `.gitignore`'d globally. Keychain preferred, file fallback explicit opt-in. | BUILD |
| A3 | **Certificate validation** — before archive, check signing identity exists in Keychain (`security find-identity -v -p codesigning`). Fail early with doctor hint, not cryptic xcodebuild error. | BUILD |
| A4 | **Team ID isolation** — Maya and WabiSabi use different Apple Developer accounts. AppConfig stores team ID per app. Never cross-contaminate signing. | BUILD |
| A5 | **Audit log** — every upload event logged to ShikkiDB with: app, version, build, team ID, timestamp, who triggered it. Tamper-evident release trail. | BUILD |

#### @Hanami — UX

| # | Idea | Verdict |
|---|------|---------|
| H1 | **Extended preflight** — before archive, show: app name, scheme, team, bundle ID, version, build number, signing identity, TestFlight group, estimated archive time. One Enter to launch. | BUILD |
| H2 | **Progress phases** — archive is slow (~2-5 min). Show phase name + elapsed time, not a wall of xcodebuild output. Capture full log to `~/.shikki/logs/` for debugging. | BUILD |
| H3 | **ntfy with install link** — when TestFlight build is ready, push ntfy with `itms-beta://` deep link. Tap notification on iPhone = open TestFlight and install. | BUILD |
| H4 | **Two-stage notification** — first ntfy: "Build uploading..." (after export), second ntfy: "Build 42 ready on TestFlight" (after distribute). User knows progress without watching terminal. | BUILD |
| H5 | **Failure diagnosis** — on archive failure, parse xcodebuild log for common errors (signing, provisioning, Swift compilation) and show a one-line diagnosis + `shikki doctor --signing` hint. | BUILD |

### Selected for v1

All ideas marked BUILD above. 15 ideas, 0 deferred to v1.1+ (scheme auto-detect is nice-to-have, nightly builds are v2).

---

## Phase 2 — Synthesis

### Goal

`shikki ship --testflight` = one command from clean code to TestFlight install on your phone. Run the existing ShipGate quality pipeline, then archive, export, upload, distribute, and notify. Both WabiSabi and Maya ship from the same CLI.

### Scope v1 (this spec)

- `--testflight` flag on existing `shikki ship` command
- 4 new gates: ArchiveGate, ExportGate, UploadGate, DistributeGate
- Multi-app config in `~/.config/shikki/apps.toml`
- ExportOptions.plist generation from config
- Build number auto-increment via `agvtool`
- API key storage in Keychain (file fallback)
- Signing identity pre-check
- ntfy notifications (uploading + ready)
- Archive/IPA preservation on failure
- Release notes from ChangelogGate output
- Full xcodebuild log capture

### Scope v1.1

- Scheme auto-detection from Xcode project
- `shikki ship --testflight --ad-hoc` for device-direct installs
- Build history browser (`shikki ship --testflight --history`)

### Scope v2

- VPS Mac mini build farm (remote `xcodebuild` via SSH)
- Nightly scheduled builds via ShikkiKernel (launchd)
- Parallel builds (WabiSabi + Maya simultaneously)

### Out of scope

- App Store submission (manual gate — human decision)
- Android builds
- Fastlane (we are replacing it, not wrapping it)
- GitHub Actions integration (the whole point is to NOT use it)

### Success criteria

1. WabiSabi on TestFlight via `shikki ship --testflight --app wabisabi --why "first local build"`
2. Maya on TestFlight via `shikki ship --testflight --app maya --why "first local build"`
3. ntfy notification arrives on iPhone with install link
4. Total time from command to TestFlight processing < 10 minutes (M2 Max)
5. `--dry-run` shows full plan including archive/export/upload steps without executing
6. API key never appears in logs, git, or event payloads

### Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| `asc` CLI | Install needed | `brew install cidverse/tap/asc` — Go binary, MIT |
| Apple Developer account (OBYW.one) | Enrollment in progress | Required for WabiSabi signing |
| .p8 API key (OBYW.one) | Need to generate | App Store Connect > Keys |
| .p8 API key (FJ Studio/Maya) | Need from Faustin | Maya uses his account |
| Signing certificate | In Keychain | Distribution cert per team |
| Provisioning profiles | Download needed | Per bundle ID |
| Existing ShipGate pipeline | DONE | 8 gates working |
| ntfy | DONE | PR #1, running |

---

## Phase 3 — Business Rules

### App Configuration

**BR-01**: App configuration MUST be stored in `~/.config/shikki/apps.toml`. Each app is a TOML table with required fields: `slug`, `scheme`, `team_id`, `bundle_id`, `project_path` (absolute path to .xcodeproj or .xcworkspace). Optional fields: `testflight_group` (default: "External Testers"), `export_method` (default: "app-store").

```toml
[wabisabi]
scheme = "WabiSabi"
team_id = "L8NRHDDSWG"
bundle_id = "one.obyw.wabisabi"
project_path = "/Users/jeoffrey/Documents/Workspaces/shiki/projects/wabisabi/WabiSabi.xcodeproj"
testflight_group = "Beta Testers"
export_method = "app-store"

[maya]
scheme = "Maya"
team_id = "UVC4JM6XD4"
bundle_id = "fit.maya.app"
project_path = "/Users/jeoffrey/Documents/Workspaces/Maya/MayaFit.xcodeproj"
testflight_group = "Beta Testers"
export_method = "app-store"
```

**BR-02**: `--app <slug>` selects the app configuration. If omitted AND only one app is configured, use that app. If omitted with multiple apps, fail with: "Multiple apps configured. Use --app wabisabi or --app maya."

**BR-03**: `shikki ship --testflight` with an unknown `--app` slug MUST fail with a list of configured apps.

### Pre-flight Checks

**BR-04**: Before entering the gate pipeline, `--testflight` mode MUST verify:
1. `xcodebuild` is installed and accessible (`xcrun --find xcodebuild`)
2. `asc` CLI is installed (`which asc`)
3. Signing identity exists for the app's team ID (`security find-identity -v -p codesigning | grep <team_id>`)
4. API key is accessible (Keychain first, then file fallback)
5. apps.toml exists and the selected app has all required fields
6. The project file at `project_path` exists

If ANY check fails, abort with a specific diagnostic message and `shikki doctor --signing` hint. Do NOT proceed to the gate pipeline.

**BR-05**: Pre-flight check results MUST be displayed as part of the extended preflight manifest (before Enter to proceed):
```
  App:        WabiSabi
  Scheme:     WabiSabi
  Team:       L8NRHDDSWG (OBYW.one)
  Bundle:     one.obyw.wabisabi
  Version:    1.2.0 (build 42 -> 43)
  Signing:    Apple Distribution: Jeoffrey (L8NRHDDSWG)
  Group:      Beta Testers
  API Key:    AuthKey_XXXX (Keychain)
  Dest:       TestFlight
```

### Build Pipeline (Gates 9-12)

**BR-06**: When `--testflight` is passed, 4 additional gates append to the existing 8-gate pipeline:
- Gate 9: ArchiveGate
- Gate 10: ExportGate
- Gate 11: UploadGate
- Gate 12: DistributeGate

The existing gates (1-8: CleanBranch, Test, Coverage, Risk, Changelog, VersionBump, Commit, PR) run first. If any existing gate fails, the TestFlight gates never execute. The PR gate (Gate 8) runs BEFORE archive — the PR is the quality checkpoint; TestFlight is the delivery.

**BR-07**: **ArchiveGate** (Gate 9) MUST:
1. Auto-increment the build number via `agvtool next-version -all`
2. Run `xcodebuild archive` with: `-scheme`, `-project` (or `-workspace`), `-archivePath`, `-destination 'generic/platform=iOS'`, `DEVELOPMENT_TEAM=<team_id>`
3. Archive path: `~/.shikki/archives/<slug>/<version>+<build>/<slug>.xcarchive`
4. Capture full xcodebuild output to `~/.shikki/logs/<slug>-archive-<timestamp>.log`
5. On failure: parse log for common errors (signing, provisioning, compilation), return `.fail` with one-line diagnosis
6. On success: return `.pass` with archive path and size

**BR-08**: **ExportGate** (Gate 10) MUST:
1. Generate `ExportOptions.plist` from AppConfig (method, team ID, bundle ID, provisioning profile name)
2. Run `xcodebuild -exportArchive` with: `-archivePath`, `-exportPath`, `-exportOptionsPlist`
3. Export path: `~/.shikki/archives/<slug>/<version>+<build>/`
4. Verify the .ipa file exists after export
5. Send first ntfy notification: "WabiSabi 1.2.0 (43) archived — uploading to App Store Connect..."
6. On failure: preserve the .xcarchive for manual retry

**BR-09**: **UploadGate** (Gate 11) MUST:
1. Resolve the API key: try Keychain first (`security find-generic-password -s shikki-asc-<team_id> -w`), fall back to `~/.config/shikki/keys/AuthKey_<key_id>.p8`
2. Upload the .ipa via `asc upload --file <ipa_path> --key-id <key_id> --issuer-id <issuer_id> --key <key_path>`
3. On failure: retry up to 2 times with 10-second delay between attempts (network transient errors)
4. After 3 failures: preserve the .ipa and return `.fail` with: "Upload failed after 3 attempts. IPA preserved at: <path>. Retry manually with: asc upload --file <path>"
5. On success: return `.pass` with the build processing URL

**BR-10**: **DistributeGate** (Gate 12) MUST:
1. Add the build to the TestFlight group via `asc testflight add-build-to-group --group "<group_name>" --app-id <app_id> --build-number <build>`
2. Set release notes from ChangelogGate output (the "What to Test" field)
3. Send second ntfy notification: "WabiSabi 1.2.0 (43) on TestFlight — install now" with `itms-beta://` link as click action
4. On failure: the build is already uploaded — notify user that manual group assignment is needed via App Store Connect

### Version & Build Management

**BR-11**: Build number auto-increment MUST use `agvtool next-version -all` which increments the `CURRENT_PROJECT_VERSION` in ALL targets. The build number is an integer, always incrementing. The marketing version (`MARKETING_VERSION`) comes from VersionBumpGate (Gate 6).

**BR-12**: After successful upload, create a git tag: `v<version>+<build>` (e.g., `v1.2.0+43`). If `--dry-run`, skip tagging. The tag is lightweight (not annotated) to avoid GPG signing requirements.

**BR-13**: The build number increment and git tag MUST be committed as a single commit: `chore(release): bump build to <build> [skip ci]`. This commit happens after ArchiveGate succeeds, before ExportGate. If the pipeline fails after this point, the commit remains (the build number was consumed).

### API Key Security

**BR-14**: API key storage priority:
1. **macOS Keychain** (preferred): stored via `security add-generic-password -s shikki-asc-<team_id> -a <key_id> -w <base64_p8_content> -U`. Retrieved via `security find-generic-password -s shikki-asc-<team_id> -w`. The `-U` flag updates if exists.
2. **File fallback**: `~/.config/shikki/keys/AuthKey_<key_id>.p8` with `chmod 600`. Only used if Keychain lookup fails.
3. **Environment variable fallback**: `SHIKKI_ASC_KEY_<TEAM_ID>` containing base64-encoded .p8. For CI/headless only.

**BR-15**: `shikki doctor --signing` MUST check and report:
1. Keychain has signing identity for each configured team ID
2. Keychain has ASC API key for each configured team ID (or file fallback exists)
3. Provisioning profiles are installed (`~/Library/MobileDevice/Provisioning Profiles/`)
4. `asc` CLI is installed and version is >= 0.5.0
5. `xcodebuild` is accessible and Xcode version is >= 16.0
6. Each app's project file exists at the configured path

**BR-16**: API key content MUST NEVER appear in:
- ShipEvent payloads (log key_id only, never key content)
- xcodebuild logs saved to `~/.shikki/logs/`
- ntfy notifications
- Ship log entries
- Terminal output (show `AuthKey_XXXX...` truncated)

### API Key Setup

**BR-17**: `shikki ship --testflight --setup` provides an interactive setup flow:
1. Ask for app slug (or create new entry in apps.toml)
2. Ask for .p8 file path — reads it, stores in Keychain, deletes the file
3. Ask for Key ID and Issuer ID — stores in apps.toml under `[<slug>.asc]`
4. Validates by calling `asc apps list` with the credentials
5. Confirms with: "API key stored in Keychain. .p8 file deleted. You're ready to ship."

```toml
[wabisabi.asc]
key_id = "XXXXXXXXXX"
issuer_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

### Notification

**BR-18**: ntfy notifications use the existing shikki ntfy infrastructure. Two notifications per TestFlight pipeline:
1. **After ExportGate passes**: title: "Building", body: `<app> <version> (<build>) — uploading to App Store Connect`, priority: 3 (default)
2. **After DistributeGate passes**: title: "TestFlight Ready", body: `<app> <version> (<build>) — install now`, priority: 5 (urgent), click action: `itms-beta://beta.apple.com/v1/app/<app_store_id>`, tags: `rocket`
3. **On any gate failure**: title: "Build Failed", body: `<app> failed at <gate>: <reason>`, priority: 4 (high), tags: `x`

**BR-19**: ntfy notifications MUST use the Process-based approach (not curl -sf) to avoid error blindness. Use the same pattern as existing ShipCommand ntfy integration.

### Error Handling & Recovery

**BR-20**: If ArchiveGate fails:
- Parse xcodebuild log for: `error:` lines, `Code Sign error`, `No provisioning profile`, `module .* not found`
- Show the top 3 error lines + hint: "Full log: ~/.shikki/logs/<slug>-archive-<timestamp>.log"
- Suggest: `shikki doctor --signing` if signing-related

**BR-21**: If ExportGate fails:
- Preserve .xcarchive at its archive path
- Show: "Archive preserved at: <path>. Fix the issue and retry with: xcodebuild -exportArchive ..."

**BR-22**: If UploadGate fails after retries:
- Preserve .ipa at its export path
- Show: "IPA preserved at: <path>. Retry manually with: asc upload --file <path> ..."

**BR-23**: `~/.shikki/archives/` MUST be pruned: keep only the last 5 archives per app. Prune happens at the START of ArchiveGate (before creating a new archive). Pruning deletes oldest .xcarchive and .ipa files.

### Dry Run

**BR-24**: `--dry-run --testflight` MUST show the full 12-gate pipeline plan without executing any builds, uploads, or distributions. Archive/export/upload/distribute gates return `.pass` with `[dry-run]` prefix in detail. The extended preflight manifest (BR-05) is shown in dry-run mode.

### Event Bus Integration

**BR-25**: TestFlight gates emit `ShikkiEvent` with type `.testflightArchive`, `.testflightExport`, `.testflightUpload`, `.testflightDistribute`. Payload includes: app slug, version, build number, duration. Upload event includes App Store Connect build URL. Distribute event includes TestFlight group name.

**BR-26**: All TestFlight events are persisted to ShikkiDB if available (same graceful degradation as existing ship events). Audit trail: who shipped what, when, to which group.

### Multi-App Isolation

**BR-27**: Maya and WabiSabi MUST be completely isolated:
- Separate team IDs (UVC4JM6XD4 vs L8NRHDDSWG)
- Separate API keys (different Apple Developer accounts)
- Separate signing identities
- Separate provisioning profiles
- Separate archive directories (`~/.shikki/archives/maya/` vs `~/.shikki/archives/wabisabi/`)
- Separate log files

**BR-28**: The `--app` flag MUST be validated against apps.toml before ANY pipeline execution. Cross-team contamination (e.g., signing Maya with WabiSabi's cert) is a hard error caught in pre-flight (BR-04).

---

## Phase 4 — Test Plan

### Pre-flight & Configuration Tests

```
BR-01 -> test_appConfig_parsesValidToml()
BR-01 -> test_appConfig_missingRequiredField_fails()
BR-01 -> test_appConfig_multipleApps_parsesAll()
BR-02 -> test_appSelector_singleApp_autoSelects()
BR-02 -> test_appSelector_multipleApps_noFlag_failsWithList()
BR-02 -> test_appSelector_multipleApps_withFlag_selects()
BR-03 -> test_appSelector_unknownSlug_failsWithConfiguredList()
BR-04 -> test_preflight_xcodebuildMissing_failsWithHint()
BR-04 -> test_preflight_ascMissing_failsWithHint()
BR-04 -> test_preflight_signingIdentityMissing_failsWithHint()
BR-04 -> test_preflight_apiKeyMissing_failsWithHint()
BR-04 -> test_preflight_projectPathMissing_failsWithHint()
BR-04 -> test_preflight_allChecksPass_proceeds()
BR-05 -> test_preflightManifest_displaysAppConfig()
BR-05 -> test_preflightManifest_showsBuildNumberIncrement()
```

### Archive Gate Tests

```
BR-07 -> test_archiveGate_incrementsBuildNumber()
BR-07 -> test_archiveGate_buildsXcarchive()
BR-07 -> test_archiveGate_capturesLogToFile()
BR-07 -> test_archiveGate_signingError_failsWithDiagnosis()
BR-07 -> test_archiveGate_compilationError_failsWithDiagnosis()
BR-07 -> test_archiveGate_archiveSavedToCorrectPath()
BR-07 -> test_archiveGate_dryRun_noSideEffects()
```

### Export Gate Tests

```
BR-08 -> test_exportGate_generatesExportOptionsPlist()
BR-08 -> test_exportGate_exportOptionsHasCorrectTeamAndMethod()
BR-08 -> test_exportGate_producesIpa()
BR-08 -> test_exportGate_sendsUploadingNotification()
BR-08 -> test_exportGate_failure_preservesXcarchive()
BR-08 -> test_exportGate_dryRun_noSideEffects()
```

### Upload Gate Tests

```
BR-09 -> test_uploadGate_resolvesKeyFromKeychain()
BR-09 -> test_uploadGate_fallsBackToFileKey()
BR-09 -> test_uploadGate_fallsBackToEnvKey()
BR-09 -> test_uploadGate_successOnFirstAttempt()
BR-09 -> test_uploadGate_retriesOnTransientFailure()
BR-09 -> test_uploadGate_failsAfter3Attempts_preservesIpa()
BR-09 -> test_uploadGate_dryRun_noSideEffects()
```

### Distribute Gate Tests

```
BR-10 -> test_distributeGate_addsBuildToGroup()
BR-10 -> test_distributeGate_setsReleaseNotes()
BR-10 -> test_distributeGate_sendsReadyNotification()
BR-10 -> test_distributeGate_notificationHasInstallLink()
BR-10 -> test_distributeGate_failure_advisesManualGroupAssignment()
BR-10 -> test_distributeGate_dryRun_noSideEffects()
```

### Version & Build Tests

```
BR-11 -> test_buildNumberIncrement_usesAgvtool()
BR-11 -> test_buildNumberIncrement_incrementsAllTargets()
BR-12 -> test_gitTag_createdAfterUpload()
BR-12 -> test_gitTag_format_versionPlusBuild()
BR-12 -> test_gitTag_dryRun_skipped()
BR-13 -> test_buildBumpCommit_hasSkipCiMessage()
BR-13 -> test_buildBumpCommit_survivesGateFailure()
```

### Security Tests

```
BR-14 -> test_apiKeyStorage_keychainPreferred()
BR-14 -> test_apiKeyStorage_fileFallback()
BR-14 -> test_apiKeyStorage_envFallback()
BR-15 -> test_doctor_signingIdentityCheck()
BR-15 -> test_doctor_apiKeyCheck()
BR-15 -> test_doctor_provisioningProfileCheck()
BR-15 -> test_doctor_ascCliCheck()
BR-16 -> test_apiKeyNeverInEventPayload()
BR-16 -> test_apiKeyNeverInLogFile()
BR-16 -> test_apiKeyNeverInNtfyBody()
BR-16 -> test_apiKeyTruncatedInTerminal()
```

### Setup Flow Tests

```
BR-17 -> test_setup_createsAppsToml()
BR-17 -> test_setup_storesKeyInKeychain()
BR-17 -> test_setup_deletesP8File()
BR-17 -> test_setup_validatesCredentials()
BR-17 -> test_setup_existingConfig_updatesEntry()
```

### Notification Tests

```
BR-18 -> test_ntfy_exportGate_sendsUploadingNotification()
BR-18 -> test_ntfy_distributeGate_sendsReadyNotification()
BR-18 -> test_ntfy_distributeGate_hasInstallLink()
BR-18 -> test_ntfy_gateFailure_sendsFailureNotification()
BR-19 -> test_ntfy_usesProcessNotCurl()
```

### Error Handling & Recovery Tests

```
BR-20 -> test_archiveFailure_parsesSigningError()
BR-20 -> test_archiveFailure_parsesCompilationError()
BR-20 -> test_archiveFailure_parsesProvisioningError()
BR-20 -> test_archiveFailure_showsLogPath()
BR-21 -> test_exportFailure_preservesXcarchive()
BR-22 -> test_uploadFailure_preservesIpa()
BR-22 -> test_uploadFailure_showsManualRetryCommand()
BR-23 -> test_archivePruning_keepsLast5()
BR-23 -> test_archivePruning_deletesOldest()
BR-23 -> test_archivePruning_emptyDir_noop()
```

### Pipeline Integration Tests

```
BR-06 -> test_testflightPipeline_has12Gates()
BR-06 -> test_testflightPipeline_existingGatesRunFirst()
BR-06 -> test_testflightPipeline_existingGateFailure_skipsTestflightGates()
BR-24 -> test_dryRun_testflight_shows12GatePlan()
BR-24 -> test_dryRun_testflight_noBuildNoUpload()
BR-25 -> test_testflightEvents_emittedPerGate()
BR-25 -> test_testflightEvents_payloadHasAppAndVersion()
BR-26 -> test_testflightEvents_persistedToDb()
BR-26 -> test_testflightEvents_dbUnavailable_continues()
```

### Multi-App Isolation Tests

```
BR-27 -> test_maya_usesOwnTeamId()
BR-27 -> test_maya_usesOwnApiKey()
BR-27 -> test_maya_usesOwnArchiveDir()
BR-27 -> test_wabisabi_usesOwnTeamId()
BR-27 -> test_wabisabi_usesOwnApiKey()
BR-28 -> test_crossTeamSigning_failsInPreflight()
BR-28 -> test_invalidAppSlug_failsBeforePipeline()
```

### Test Totals

| Category | Count |
|----------|-------|
| Configuration | 15 |
| ArchiveGate | 7 |
| ExportGate | 6 |
| UploadGate | 7 |
| DistributeGate | 6 |
| Version & Build | 7 |
| Security | 12 |
| Setup | 5 |
| Notification | 5 |
| Error & Recovery | 9 |
| Pipeline Integration | 8 |
| Multi-App Isolation | 7 |
| **Total** | **94** |

---

## Architecture

### Files to Create/Modify

| Path | Purpose | Status |
|------|---------|--------|
| `Sources/ShikkiKit/Services/TestFlightGates.swift` | ArchiveGate, ExportGate, UploadGate, DistributeGate | New |
| `Sources/ShikkiKit/Services/AppConfig.swift` | AppConfig struct + TOML parser for apps.toml | New |
| `Sources/ShikkiKit/Services/ASCClient.swift` | Thin wrapper around `asc` CLI binary | New |
| `Sources/ShikkiKit/Services/SigningValidator.swift` | Pre-flight signing checks (Keychain, identity, provisioning) | New |
| `Sources/ShikkiKit/Services/ExportOptionsGenerator.swift` | Generate ExportOptions.plist from AppConfig | New |
| `Sources/ShikkiKit/Services/ArchiveManager.swift` | Archive path management, pruning, log capture | New |
| `Sources/shikki/Commands/ShipCommand.swift` | Modify: add --testflight, --app, --group, --setup flags | Modify |
| `Tests/ShikkiKitTests/TestFlightGateTests.swift` | All gate tests | New |
| `Tests/ShikkiKitTests/AppConfigTests.swift` | Config parsing tests | New |
| `Tests/ShikkiKitTests/SigningValidatorTests.swift` | Security tests | New |
| `Tests/ShikkiKitTests/ArchiveManagerTests.swift` | Archive management tests | New |

### Data Flow

```
shikki ship --testflight --app wabisabi --why "v1.2.0 beta"
    |
    +-- Parse apps.toml -> AppConfig
    +-- Pre-flight checks (BR-04)
    +-- Extended preflight manifest (BR-05)
    +-- [Enter]
    |
    +-- Gate 1-8: Existing ShipGate pipeline
    |   (CleanBranch -> Test -> Coverage -> Risk -> Changelog -> VersionBump -> Commit -> PR)
    |
    +-- Gate 9: ArchiveGate
    |   agvtool next-version -> xcodebuild archive -> save .xcarchive
    |
    +-- Gate 10: ExportGate
    |   generate ExportOptions.plist -> xcodebuild -exportArchive -> .ipa
    |   ntfy: "uploading..."
    |
    +-- Gate 11: UploadGate
    |   resolve API key -> asc upload (retry 2x) -> App Store Connect processing
    |
    +-- Gate 12: DistributeGate
    |   asc testflight add-build-to-group -> set release notes
    |   ntfy: "install now" + itms-beta:// link
    |
    +-- git tag v1.2.0+43
    +-- Ship log entry
    +-- ShikkiDB event persistence
```

### Key Structs

```swift
/// App configuration from ~/.config/shikki/apps.toml
public struct AppConfig: Sendable, Codable {
    public let slug: String
    public let scheme: String
    public let teamID: String
    public let bundleID: String
    public let projectPath: String
    public let testflightGroup: String      // default: "External Testers"
    public let exportMethod: String          // default: "app-store"
    public let asc: ASCKeyConfig?
}

public struct ASCKeyConfig: Sendable, Codable {
    public let keyID: String
    public let issuerID: String
}
```

## Review History

| Date | Phase | Reviewer | Decision | Notes |
|------|-------|----------|----------|-------|
| 2026-03-26 | Phase 1-4 | @Sensei, @Kenshi, @Katana, @Hanami | Full spec | 28 BRs, 94 tests, practical for this-week delivery |
