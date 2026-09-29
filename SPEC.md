# Photo Cleanup (working title)

iPhone app that finds junk in the photo library (screenshots, duplicates, bad shots, big videos) and lets the user delete it in a few taps. All analysis runs on the device.

## Promise

Your photos never leave this phone. No server, no account, no analytics, no crash reporter, no third-party SDK, no network code.

The app keeps a small cache on the device so rescans are fast. An "Erase app data" button wipes it, and the cache is excluded from device backups. The in-app wording says "never leaves this phone", not "nothing is stored", because the cache exists.

`scripts/check-no-network.sh` guards the promise. It is a tripwire against accidents and lazy additions, not a proof against code written to evade it. It fails on network APIs, web views, third-party or binary dependencies, embedded frameworks, `contentsOf` outside the storage file, an `isNetworkAccessAllowed` that is not `false`, URLs opened outside the Settings page, ATS exceptions, tracking or push settings, a privacy manifest that declares tracking or collected data, and built binaries that link networking or web frameworks. It runs inside `scripts/verify.sh` and was checked against planted violations. The final check happens on a device: airplane mode, and the iOS App Privacy Report.

## Decisions (29 Sep 2026)

- Native: Swift 6, SwiftUI, PhotoKit, Vision. Cross-platform layers would need native modules for both frameworks.
- iOS 17.0 minimum, iPhone only.
- Business model undecided. No paywall in v1. When StoreKit arrives, the network check gets one explicit allowance for it.
- Categories in v1: screenshots and screen recordings, similar shots, blurry/dark/accidental shots, big videos.
- Placeholders: app name "Photo Cleanup", bundle id `com.example.photocleanup`, accent colour, app icon. Replace before signing for release.

## How it works

### Access

Read/write library access, because deleting needs it. Limited access works: the scan covers the selected photos and Settings offers the system picker to change the selection.

### Scan

One pass over `PHAsset.fetchAssets`, sorted by creation date. Each asset lands in at most one category, in this priority: screenshots and recordings, similar shots, low quality, big videos. The reclaimable total counts each asset once.

Analysis reads 512 px thumbnails from `PHImageManager` (`.highQualityFormat`, `.exact`, network access off). An asset with no local thumbnail is skipped and counted as "in iCloud, not scanned". The app never asks PhotoKit to download anything.

At most 4 analyses run at once. The screen stays awake during a scan. Progress is shown and the scan can be cancelled. If the first 20 analyses all fail, the scan stops with an error instead of producing garbage.

### Categories

Screenshots and recordings: `mediaSubtypes` contains `.photoScreenshot` or `.videoScreenRecording`. Nothing pre-selected, "Select all" available.

Similar shots: a Vision feature print per photo (revision 2 pinned, 768 values), compared with the next photos in creation order (at most 30, within 10 minutes). Leader clustering: a photo joins the earliest group whose first photo it is within 0.45 of, so a slow drift across a burst cannot merge the two ends. The keeper of a group is chosen by favourite, then edited, then resolution, then file size, then the earliest photo. Every other photo is pre-selected, except favourites and edited photos.

Why file size and not sharpness: on 16 photographs against recompressed, cropped, downsized and blurred copies of the same photo, file size picked the original 16 times of 16. Laplacian sharpness picked it once, because JPEG blocking adds edges.

Low quality: measured on a 512 px grayscale copy. One issue per photo, most telling first: too dark (99th percentile luminance below 0.12), overexposed (1st percentile above 0.92), blank (luminance standard deviation below 0.02), blurry (detail at full size divided by detail at half size below 0.21, or Laplacian variance below 0.0003). Nothing pre-selected.

Big videos: videos of at least 50 MB, largest first, with size and duration. Nothing pre-selected.

Every threshold comes from a measured fixture set. `CalibrationTests` records the numbers and re-checks them on real photographs.

### Safety

Deletion goes through `PHAssetChangeRequest.deleteAssets`. iOS shows its own confirmation and the items sit in Recently Deleted for 30 days. The done screen reports what was really deleted (photos already gone from the library are not counted), says space returns only after Recently Deleted is emptied, and lists the steps.

"Keep" on an item adds it to an on-device keep list and it never shows again. The best photo of a group is kept anyway, so it has no "Keep" action.

Results follow the library. A `PHPhotoLibraryChangeObserver` drops every scanned asset that was removed or changed since the scan (a favourite added in the Photos app, an edit, a deletion), so a stale suggestion cannot be acted on. When PhotoKit cannot describe a change, the results are cleared and a rescan is needed. The selection can only hold ids that are shown: every change to the results goes through one function that prunes it.

When the best photo of a group is deleted, the best of the rest takes its place and is no longer suggested for removal, so a group never ends up with every copy suggested. A group with fewer than two photos left disappears.

### Cache

One binary plist in Application Support, keyed by `localIdentifier`, valid while `modificationDate` is unchanged. It holds the half-precision feature print, quality metrics, byte size and an edited flag. The header names the fingerprinter, so a different fingerprinter or file version drops the cache. Excluded from backup. "Erase app data" deletes it together with the keep list.

Measured: 1.7 KB per photo (3.5 MB for 2,031 photos), so about 34 MB at 20,000 photos.

File size comes from `PHAssetResource` through the key-value keys `fileSize` and `locallyAvailable`. They are not public API, widely used, and each key is checked with `responds(to:)` before use. Only resources on this phone count towards reclaimable space.

## Screens

1. Welcome: the promise in three lines, one button to grant access.
2. Home: total reclaimable space, four category rows with count and size, scan progress.
3. Review: thumbnail grid, tap to select, tap-hold for preview and "Keep". Similar shots show as groups with a "Best" mark. Bottom bar: "Delete N · X MB".
4. Done: space freed once Recently Deleted is emptied, with steps.
5. Settings: privacy in plain words and how to verify it (airplane mode, iOS App Privacy Report), manage limited access, erase app data.

Look: native iOS, SF, system materials, one accent colour. No emoji markers, no accent-bar cards.

## Structure

- `Packages/CleanupCore`: image quality metrics, feature print distance, grouping, keeper choice, and the result model (`ScanResult`, with removal, promotion and selection rules). Takes `CGImage` and plain values, no PhotoKit, so `swift test` runs on the Mac.
- `App`: PhotoKit behind one actor (`PhotoLibraryService`), scan pipeline, cache, SwiftUI screens.
- `project.yml` for XcodeGen. The generated `.xcodeproj` is not committed.
- `scripts`: `verify.sh`, `check-no-network.sh`, `fetch-fixtures.sh`, `seed-simulator.sh`, `seed-bulk.sh`.

## Findings

- The iOS 26.1 simulator cannot run Vision feature prints: the default path throws "Failed to create espresso context", and forcing the CPU returns near-identical vectors for different photos. The simulator uses `TinyImageFingerprinter` (16x16 thumbnail) through `-tinyFingerprints`. Vision is verified on the Mac and needs a device pass.
- Vision revision 2 distances on 16 photographs: different scenes start at 0.72, same-scene variants (recompressed, cropped, exposure shifted) stay at or below 0.44. The 0.45 threshold sits in that gap.
- `simctl privacy grant photos` does not work on this simulator, the UI test accepts the prompt instead.
- Scale, 2,031 photos in the simulator with an optimized build: cold scan 18.6 s, warm rescan 0.44 s. A Debug build is about 6 times slower in the analysis stage.
- Sizing (`PHAssetResource` lookups) costs about 4.3 ms per asset and is now the largest cold-scan stage (8.8 s of 18.6 s). At 20,000 assets that is about 90 s.

## Review

An independent Opus review of the first version found 8 issues, all fixed with tests where the logic is pure: a single broken photo made every rescan fail, results went stale when the library changed, "Deselect all" left hand-picked photos selected, the privacy guard could be sidestepped in three ways, the cache was rewritten after every non-analysed photo, erasing data did not wait for a running scan, keeping or deleting the best photo dropped its whole group, and the result rules had no tests.

## Next

1. Look up sizes only for candidates (screenshots, videos, group members, flagged photos), not for every asset.
2. Exact duplicates anywhere in the library (same pixel size and byte size, confirmed by feature print). Needs sizes for all photos, so it waits for step 1.
3. Real-device pass on a large library: speed, iCloud behaviour, Vision similarity quality. Needs an Apple ID signed in to Xcode.
4. Business model, name, icon, accent colour.

## Out of scope for v1

Paywall, sync, widgets, Slovak strings, OCR-based smart suggestions, aesthetics scoring (needs iOS 18), Live Photo to still conversion, background scanning.
