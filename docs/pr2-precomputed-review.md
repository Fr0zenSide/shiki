# PR #2 Review Summary — Media Strategy

**Title:** story: Media Strategy -- MediaKit SPM + Garage S3 infra
**Branch:** `story/media-strategy` -> `develop`
**State:** OPEN
**Size:** +2,022 / -0 across 48 files (32 commits)
**Author:** Jeoffrey Thirot
**Date:** 2026-03-12

---

## 1. PR Overview

Cross-app media infrastructure for Maya and WabiSabi. Two major deliverables:

1. **MediaKit SPM package** (26 source files, 13 test files, 39 tests) -- GPS-authenticated activity photo pipeline with models, protocols, services, and DI assembly.
2. **Garage S3 v2.2.0 infrastructure** -- Docker Compose service, production deploy script, Caddy route (`s3.obyw.one`), PocketBase migrations (`activity_photos` collection), and local bootstrap script.

Key capabilities: photo metadata extraction (EXIF/GPS), GPS corridor matching (Haversine formula), image compression pipeline (HEIC passthrough, JPEG/PNG recompression), actor-based retry queue with exponential backoff, and protocol-driven photo import with `PhotoLibraryProvider` abstraction.

---

## 2. Risk Assessment Per File

### HIGH Risk

| File | Reason |
|------|--------|
| `deploy/garage.toml` | Hardcoded `rpc_secret` and `admin_token` in config committed to repo. Production config (`garage-prod.toml`) mentioned in PR body but not in diff -- unclear if secrets are separated. |
| `scripts/setup-garage-local.sh` | Appears twice in the diff (commits 11 and 12 are identical -- duplicate commit). Uses `grep -Eo` for macOS compat but the layout version parsing chain is fragile. |
| `Services/BackgroundRetryQueue.swift` | Actor processes items sequentially with `Task.sleep` inside the loop. Items that exhaust retries are silently dropped with no callback, logging, or persistence. The `!succeeded && retryCount < maxRetries` condition on line ~58 is always false after the while loop (dead code path). |
| `Services/MediaUploader.swift` | Stub-only implementation. No real S3/PocketBase upload path exists yet. The `@unchecked Sendable` on `StubMediaUploader` masks a mutable `shouldFail` property. |

### MEDIUM Risk

| File | Reason |
|------|--------|
| `Services/DefaultPhotoImportService.swift` | Sequential photo processing (no concurrency for large batches). Builds new `PhotoMetadata` structs to patch in `creationDate` -- could lose future fields if `PhotoMetadata` grows. |
| `Services/CompressionPipeline.swift` | Uses `NSMutableData` (reference type) inside a `Sendable` struct. Safe in practice (local scope), but relies on implementation detail. HEIC passthrough skips size validation. |
| `Services/MetadataExtractor.swift` | Extracts EXIF via `CGImageSourceCopyPropertiesAtIndex`. No error handling if `ImageIO` returns partial metadata. Relies on `kCGImagePropertyGPSLatitude` key presence. |
| `DI/MediaKitAssembly.swift` | Registers `StubMediaUploader` as default -- easy to ship to production accidentally. `BackgroundRetryQueue` registered as singleton but depends on the uploader instance at registration time. |
| `docker-compose.yml` | Garage memory limit 256M may be tight for concurrent uploads with large HEIC files. |
| `Models/CorridorConfig.swift` | Uses `[(latitude: Double, longitude: Double)]` tuple array -- not `Codable`, not `Hashable`, prevents serialization. |

### LOW Risk

| File | Reason |
|------|--------|
| `Package.swift` | Clean structure. Depends on `CoreKit`, `NetworkKit` (for NetKit), `SecurityKit`. iOS 17+ / macOS 14+. |
| `Models/MIMEType.swift` | Simple 3-case enum. Covers HEIC/JPEG/PNG. |
| `Models/MediaBucket.swift` | Two buckets: `maya-photos`, `wabisabi-photos`. |
| `Models/UploadProgress.swift` | Clean value type with fraction calculation. Guards against divide-by-zero. |
| `Models/UploadResult.swift` | Clean value type. |
| `Models/PhotoMetadata.swift` | All-optional fields, `Codable` + `Sendable`. |
| `Models/MediaValidationError.swift` | Clear error cases. |
| `Models/MediaError.swift` | Comprehensive error enum with `localizedDescription`. |
| `Models/PhotoPinAnnotation.swift` | MapKit annotation model. |
| `Protocols/MediaUploadable.swift` | Clean protocol. |
| `Protocols/GPSCorridorMatcher.swift` | Clean 3-method protocol. |
| `Protocols/PhotoImportService.swift` | Single-method async protocol. |
| `Protocols/PhotoLibraryProvider.swift` | Good abstraction over `PHPhotoLibrary`. |
| `Services/PhotoValidator.swift` | Simple size + format check. |
| `Services/HaversineCalculator.swift` | Standard Haversine formula. Correct implementation. |
| `Services/DefaultGPSCorridorMatcher.swift` | Linear search over route coordinates. Fine for typical route sizes. |
| `Services/CameraCaptureService.swift` | Protocol + stub. |
| `Services/PhotoDeletionService.swift` | Protocol + stub. |
| `Services/FailedUploadManager.swift` | UserDefaults-based persistence for failed upload keys. |
| `Examples/ActivityPhotoIntegration.swift` | All commented-out example code. No runtime impact. |
| `.gitignore` | Minor addition. |
| `deploy/example.env` | Template with placeholder values. |
| All test files | Well-structured, good mock usage. |
| `projects/obyw-one` (submodule) | Submodule pointer updates (4 commits). |

---

## 3. Key Concerns (Top 5)

### C1: Hardcoded secrets in `deploy/garage.toml`

The `rpc_secret` and `admin_token` values are committed in plaintext. Even for local dev, this sets a bad precedent. The `deploy/example.env` exists but `garage.toml` inlines the secrets rather than referencing environment variables. Production config (`garage-prod.toml`) is mentioned but absent from the diff.

**Recommendation:** Move secrets to `.env` / environment variables. Add `garage.toml` to `.gitignore` and ship only `garage.toml.example`.

### C2: Stub-only upload path ships as default

`MediaKitAssembly` registers `StubMediaUploader` when no uploader is provided. `BackgroundRetryQueue` and the entire upload pipeline terminate at a stub that generates fake S3 keys. No compile-time or runtime guard prevents this from reaching production.

**Recommendation:** Make `uploader` a required parameter (no default) or add a `#if DEBUG` guard around the stub registration.

### C3: BackgroundRetryQueue silently drops failed uploads

After exhausting `maxRetries`, items vanish with no callback, no logging, no persistence. The `FailedUploadManager` exists (UserDefaults-based) but is not wired into the retry queue. These are two independent systems that should be connected.

**Recommendation:** Wire `FailedUploadManager` as the exhaustion handler for `BackgroundRetryQueue`. Add an `onExhausted` callback or delegate.

### C4: Duplicate commit (setup-garage-local.sh appears twice)

Commits 11 and 12 have identical content (same file, same diff). This is a rebase artifact that adds noise to the history.

**Recommendation:** Interactive rebase to squash the duplicate before merge.

### C5: CorridorConfig is not Codable

`CorridorConfig.routeCoordinates` uses a tuple array `[(latitude: Double, longitude: Double)]` which prevents the struct from conforming to `Codable`. This blocks serialization for caching, API transport, or persistence.

**Recommendation:** Replace tuples with a `Coordinate` struct conforming to `Codable, Sendable, Hashable`.

---

## 4. Test Coverage Status

| Test Suite | Tests | Status |
|------------|-------|--------|
| PhotoValidatorTests | 5 | PASS |
| MetadataExtractorTests | 6 | PASS (real HEIC fixtures) |
| GPSCorridorMatcherTests | 5 | PASS |
| HaversineCalculatorTests | 2 | PASS |
| CompressionPipelineTests | 3 | PASS |
| MediaUploaderTests | 3 | PASS |
| BackgroundRetryQueueTests | 2 | PASS |
| DefaultPhotoImportServiceTests | 7 | PASS |
| MediaKitAssemblyTests | 1 | PASS |
| CameraCaptureServiceTests | 2 | PASS |
| PhotoPinAnnotationTests | 2 | PASS |
| FailedUploadManagerTests | 2 (est.) | PASS |
| PhotoDeletionServiceTests | 1 | PASS |
| MediaErrorTests | 2 (est.) | PASS |
| **Total** | **~39** | **All passing** |

### Coverage Gaps

- **No integration test** for the full import-validate-compress-upload pipeline end-to-end.
- **BackgroundRetryQueue** has only 2 tests; no test for partial failure (first attempt fails, retry succeeds).
- **CompressionPipeline** tests rely on CGImage creation in test context -- may behave differently on CI without GPU.
- **FailedUploadManager** uses `UserDefaults.standard` directly -- not isolated in tests (shared state risk).
- **DefaultPhotoImportService** tests acknowledge they cannot inject real GPS metadata through `MetadataExtractor` from raw bytes, so all GPS-filtering paths return empty results.
- Infra scripts (`setup-garage-local.sh`, `deploy.sh`) have no automated tests.

---

## 5. Verdict

**Overall: MEDIUM risk, approve with conditions.**

The MediaKit architecture is solid: clean protocol boundaries, proper `Sendable` conformance, DI integration via CoreKit, and 39 tests covering core logic. The GPS corridor matching and Haversine implementation are correct. The Garage S3 infrastructure is well-structured for local dev.

**Merge blockers:**
1. Remove hardcoded secrets from `deploy/garage.toml` (C1)
2. Squash duplicate commit (C4)

**Post-merge follow-ups:**
- Wire `FailedUploadManager` into `BackgroundRetryQueue` (C3)
- Replace `StubMediaUploader` default with required parameter (C2)
- Replace tuple array in `CorridorConfig` with `Codable` struct (C5)
- Add partial-retry success test for `BackgroundRetryQueue`

---

*Generated: 2026-03-17 by shiki-ctl precompute-review*
