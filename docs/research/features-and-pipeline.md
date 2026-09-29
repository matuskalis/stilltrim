# Evidence for decisions 13 to 19

Read-only codebase assessment by an Opus subagent, 29 Sep 2026. Paths relative to the repo root. Line numbers as of commit c62a5b0.

## Most urgent: never run Test on the phone

The scheme's test action runs the UI tests (project.yml:58-60). On a physical iPhone, `UITests/CleanupFlow.swift:19-27` taps "Select all" on Screenshots and confirms iOS's delete dialog. That would move real screenshots to Recently Deleted. `ScanControl` also erases app data. Never run Test (⌘U) with the phone as the destination.

## A. Decision 13, next features

Cold scan today, `App/Scan/ScanPipeline.swift`: list the library (`loadAssets`, PhotoLibraryService.swift:50-83); sizes for every uncached item (`addSizes`, :90-112); sort into groups (:48-62, screenshots and recordings go straight to the result and are never fingerprinted); analyse photos (:116-179); group similar shots (:181-204); build Blurry and dark (:77-80). The only write to the library today is `deleteAssets` (PhotoLibraryService.swift:151-161).

| # | Feature | Where it plugs in | Effort | Risk | iOS | Portfolio value |
|---|---|---|---|---|---|---|
| 1 | Exact duplicates anywhere | New pure function in `Grouping.swift`, called from `ScanPipeline.makeGroups` before the 10-minute grouping; members removed from that grouping's input. Reuses `SimilarGroup`, so removal, promotion and ReviewState rules apply for free. A group kind flag changes the header in `ReviewView.swift:58`. | 6-10 h with tests | Low | 17 | High. Algorithmic, testable on the Mac. |
| 2 | Live Photo to still | Detect with `mediaSubtypes.contains(.photoLive)`. Record paired-video bytes by resource type in `details()` (PhotoLibraryService.swift:96-102). New write path: `PHAssetResourceManager.writeData` to a temp file, `PHAssetCreationRequest`, delete the original. New `CleanupCategory` case, `ScanModels`, `ReviewView`, `AppModel`, cache version bump. | 14-20 h | High. New asset loses album membership, edits, captions, people tags, gets a new id. Breaks "the app only deletes". | 17 | Medium |
| 3 | Smarter screenshots (OCR) | Analysis step for screenshots only (they skip analysis today, ScanPipeline.swift:55-56). `VNRecognizeTextRequest` plus a barcode request on a larger thumbnail; store only a label enum in the cache, never the text. Badge or sort order in the Screenshots review. Keyword rules in CleanupCore, testable on the Mac. | 10-16 h | Low for deletion (no pre-selection). Keep text out of the cache. | 17 | High. On-device ML beyond feature prints. |
| 4 | Web and chat images by file name | `PHAssetResource.originalFilename` is already in hand in `details()` (PhotoLibraryService.swift:96). Only holds while sizes are looked up for every item, so conflicts with the size-lookup optimisation. | 4-8 h plus research | Medium: false positives. Unknown whether iOS keeps WhatsApp or Messenger names. | 17 | Low to medium |
| 5 | Compress big videos | `PHImageManager.requestExportSession` (network off), temp file, `PHAssetCreationRequest`, delete original. Long-running progress, cancellation, temp disk space. | 20-30 h | High: quality loss, metadata loss, disk, battery. | 17 | Medium |
| 6 | Widget or background scanning | Widget needs a new target; `check-no-network.sh:25` rejects any `path:` other than App, UITests or Packages/*, so the guard fails as written. Needs an App Group because the cache lives in Application Support (AppStorage.swift:7). Background needs `BGProcessingTask`, Info.plist keys, resumable phases. | widget 8-12 h, background 12-20 h | Medium. Hard to test. Free Apple ID and App Groups unverified. | 17 (Apple's newer continued-processing API needs 26) | Medium |
| 7 | Aesthetics score | One more request in `analyzeOne` (:169-179), cached (version bump). Would change `ranked()` (Grouping.swift:78-84), the rule the 16/16 file-size result calibrated, so needs recalibration. Its `isUtility` flag could feed feature 3. | 6-10 h | Low to medium | Behind `if #available(iOS 18, *)`, floor stays 17. Package tests need a macOS 15 gate (Package.swift:6 says macOS 14). | High |

Notes on feature 1: bucket by pixel dimensions plus identical fingerprint bytes (O(N), no new PhotoKit work), then look up sizes only for buckets with two or more photos. Do not key on byte size alone (`byteSize` includes the edited render and the Live Photo video). Near-exact copies need a new, tighter threshold; 0.45 is far too loose and nothing tight has been measured. Duplicate screenshots are missed because screenshots are never fingerprinted.

Ranking: 1, 3, 7, 2, 4, 6, 5. Proposed v1.1: exact duplicates; smarter screenshots (label only, nothing pre-selected); aesthetics score behind `#available`, as a tie-break until calibrated. Live Photo to still drops out because it is the first feature that writes to the library.

## B. Decision 14, pre-selection

`QualityThresholds.issue` returns the first matching rule (ImageMetrics.swift:41-43): black frame = "Very dark" (99th percentile below 0.12); white frame = "Overexposed" (1st percentile above 0.92); "Blank" (standard deviation below 0.02) only for flat mid-tones. So "blank, black and white" is three labels.

Evidence is synthetic only: `ImageMetricsTests.swift:31-44` tests pure black, pure white, mid-grey with 0.004 noise; :46-49 checks a night scene with lights is not flagged; seeded frames (scripts/SeedMedia.swift:139-140) are synthetic. The only real-photo check (`CalibrationTests.swift:90-106`) is that the 16 sharp daylight originals get no label. No night, snow, sky, whiteboard or document photo was measured. A sparse page of text can read "Overexposed"; a candle-lit shot "Very dark".

Pre-selecting is not safe yet: favourites and edited photos can land in Blurry and dark (`ScanPipeline.swift:77-79` does not exclude them, `CleanupItem` carries no favourite or edited flag); and `ScanResult.suggestedSelection` (:130) only covers similar groups, so a suggestion set that `removing` maintains plus a "Select suggested" branch in `ReviewView.swift:84-96` are needed.

Safer rule when it comes: gate on cached numbers, not the label (low standard deviation and either darkness or brightness), exclude favourites and edited. Side effect: a burst of black frames will probably group as similar shots, so one black frame is Best and unselected.

Screenshots: never analysed, sorted newest first (:82), nothing pre-selected. Age-based pre-selection is 2-3 h: `creationDate` is on `CleanupItem`, `isFavorite` and `isEdited` are known in the pipeline, pass `now` in for tests, same suggestion plumbing, marked-up screenshots count as edited and must be excluded.

## C. Decision 15, similarity strictness

`SimilarityRules.maxDistance = 0.45` (Grouping.swift:29), used via the default `rules: .init()` (:49) and `ScanPipeline.makeGroups` (:194). Comment on :28 says 0.74 while CalibrationTests.swift:11 and PROJECT.md say 0.72.

A Strict / Normal / Loose control touches: a stored setting, a `rules` property on `ScanPipeline`, a control in `SettingsView`. Store it in a small file like `KeepList` (UserDefaults would need a required-reason entry in PrivacyInfo.xcprivacy; the app's own `enum AppStorage` clashes with SwiftUI's `@AppStorage`). No cache invalidation: fingerprints do not depend on the threshold, a warm rescan regroups in under a second. Changing the setting wipes the user's choices, since regrouping goes through `finishScan`, which replaces the selection (ReviewState.swift:36), and photos move between Similar and Blurry and dark. Loose ceiling about 0.52 (CalibrationTests.swift:50). Consider no pre-selection in Loose. The simulator `TinyImageFingerprinter` shares 0.45 on a different scale (FingerprintTests.swift:79-80); threshold should be per fingerprinter.

Timing: after device numbers. Calibration used synthetic variants, not real bursts, and fed Vision 256 px images (CalibrationTests.swift:44) while the app feeds 512 px thumbnails (ScanPipeline.swift:11).

## D. Decision 16, extra protection

Once per scan: `PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular)`, then `PHAsset.fetchAssets(in:)` per album, collect ids into one set. Alternative: `fetchAssetCollectionsContaining(asset, with: .album)` per group member only; per-call cost unmeasured.

Changes: a new function on `PhotoLibraryService` returning protected ids; an `isInUserAlbum` flag on `GroupingItem`; keeper rank (Grouping.swift:79-81); suggestion filter (Grouping.swift:97-99). The rule belongs in grouping, not ReviewState. Add a test that `suggestedSelection` never contains a protected id.

Gap: `LibraryChangeObserver.swift:31` watches only the asset fetch, so a photo added to an album during review probably stays pre-selected. Do not cache membership. Shared Albums hold separate copies, so a library photo is probably not a member; needs a device check.

## E. Decision 18, speed

Cold scan today: `loadAssets`; cache load; `addSizes` for every uncached item in batches of 500, serially on the actor (8.8 s of 18.6 s at 4.3 ms per item); sort; analyse 4 at a time; save, group, Blurry and dark. UI sees only progress until the end (AppModel.swift:107-115); HomeView.swift:15 shows groups only in `.finished`.

Quick scan first:
- Phase 1 (seconds): list library; sizes for videos (50 MB test), screenshots and recordings; publish a partial result with Screenshots and Big videos.
- Phase 2: analyse photos; group and build Blurry and dark; sizes only for group members and flagged photos; rank Best, build suggestions; finish.

Required changes:
- Skipping sizes silently drops analysis: cache entries are created only in `addSizes` (ScanPipeline.swift:102-107), `analyze` stores results only `if var entry = entries[id]` (:139), `Entry.byteSize` is non-optional with 0 for unknown. Make size and edited flag optional, bump cache version (AppStorage.swift:31).
- Split clustering from ranking in Grouping; ranking uses `byteSize` and `isEdited` (Grouping.swift:80, 98). Re-running `groups()` on a subset changes the 30-neighbour windows.
- `isEdited` is safety-critical and must exist for every group member before suggestions. `PHAsset.hasAdjustments` in `loadAssets` could decouple it from size lookups; equivalence needs checking.
- UI: group rows while scanning; "Checking photo X of Y" for Similar and Blurry; Screenshots and Big videos openable during phase 2.
- Cancel sets `.idle` (AppModel.swift:117-119) and hides the partial result; needs a partial state with Resume. Analysis survives cancel via `saveEvery` and the save in `run`'s catch (:32-37).
- Partial-result callback needs the `generation == scanGeneration` check (:110); the progress hop (:108) only checks `isScanning`.
- ReviewState: `finishScan` must merge suggestions into phase-2 picks (:36); `remove(ids:)` during a scan must record ids in `changedDuringScan`; `libraryChangedEverywhere` during a scan must clear the partial result (:54-58).
- Actor contention: a 500-item `details()` batch holds the actor about 2 s; use smaller batches if phases overlap.

Size lookups only for candidates. Needed: all videos; screenshots and recordings; group members; flagged photos. Not needed: ordinary photos neither grouped nor flagged, iCloud-only photos. Estimated saving 50-75% of the sizing stage, roughly 45-65 s of about 86 s at 20,000 items; real share = candidates ÷ total on the first device scan. Conflicts with file-name detection (A4) and a byte-size duplicate key.

## F. Decision 19, undocumented keys

Read at PhotoLibraryService.swift:89-102. `locallyAvailable`: `responds(to:)` guard, resource skipped only when exactly `false`. `fileSize`: `responds(to:)`, then `as? NSNumber ?? 0`. No KVC crash possible. The edited flag uses public resource types (:97).

If `fileSize` disappears, everything reads 0 silently: Big videos empty (ScanPipeline.swift:53); totals "Zero KB" and "Nothing to clean up" (HomeView.swift:86); Best falls to the earliest among equal resolutions (Grouping.swift:79-81), losing the 16/16 rule; zeros are cached while `modificationDate` is unchanged (AppStorage.swift:48-56) and survive a later fix until Erase or a cache version bump. If `locallyAvailable` disappears: iCloud-only resources are counted, space overstated, iCloud-only videos listed under Big videos.

Acceptable for display, not for ranking. Hardening, about 2 h: record once per scan whether the keys exist, show "sizes unavailable" instead of 0, do not cache sizes when a key is missing, put key status in the cache header. The official `PHAssetResourceManager.requestData` reads whole files; only tolerable for a handful of candidates.

## G. Decision 17, device run readiness

To fill in: copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`, set `DEVELOPMENT_TEAM` and a unique `APP_BUNDLE_ID` (`com.example.photocleanup` will not register), `xcodegen generate`. `CODE_SIGN_STYLE = Automatic` is set (Shared.xcconfig:5). UI test target signs as `$(APP_BUNDLE_ID).uitests`.

Differs on a device:
- `-tinyFingerprints` is honoured in any Debug build (AppModel.swift:60-63). If still set in the scheme, the device measures the stand-in, not Vision, and nothing in the UI shows which is active. Remove it before the device run.
- Vision runs on a device for the first time; 20 failures produce "This device could not analyse the photos" (AppModel.swift:121-124).
- Run uses Debug (project.yml:57), about 6 times slower in analysis. For timing switch to Release, which also ignores debug launch arguments (AppModel.swift:67-69).
- UI tests delete real photos (see top).

Surprises: Developer Mode is missing from PROJECT.md steps (Settings, Privacy & Security, Developer Mode, restart). App Privacy Report must be on before the scan. Settings shows version 1.0 (App/Info.plist:20), not 0.1.0. The privacy guard's binary check only looks under `build/` (check-no-network.sh:87); Xcode device builds land in DerivedData. iCloud Optimize Storage: iCloud-only originals count as 0 bytes, Best then favours whichever copy is local; PhotoKit may serve 512 px thumbnails from local copies with network off, so fewer photos may be skipped than expected; with iCloud Photos a deletion removes the photo from every device. A large delete may clear the results (PROJECT.md:231). Thumbnail cache allows 600 images of 400 px, up to about 380 MB (AppModel.swift:20), evicted only under memory pressure.

## Not settled by code alone

Shared Album and iCloud Shared Library linkage; real night, snow, whiteboard, document photos against the thresholds; real Vision distances for bursts and the 256 vs 512 px difference; whether text recognition and the aesthetics request run in the iOS 26.1 Simulator; album lookup cost; real candidate share for size lookups; WhatsApp and Messenger file names; App Groups on a free Apple ID; `PHAsset.hasAdjustments` vs the resource-type check; local thumbnails for Optimize Storage photos with network off.
