# Stilltrim

Portfolio project. iPhone app that finds junk in the photo library (screenshots, similar shots, blurry photos, big videos) and lets the user delete it. All analysis runs on the device.

## Promise

Stilltrim sends nothing off this phone. No server, no account, no analytics, no crash reporter, no third-party SDK, no network code.

The app keeps a small cache on the device so rescans are fast. An "Erase app data" button wipes it, and the cache is excluded from device backups. The in-app wording says "sends nothing off this phone", not "nothing is stored", because the cache exists.

`scripts/check-no-network.sh` guards the promise. It is a tripwire against accidents and lazy additions, not a proof against code written to evade it. It searches the Swift, Objective-C and C-family source for a list of names: networking, web, advertising, tracking and analytics APIs, BSD sockets, `AsyncImage`, OS calls that make the system fetch data for the app (asset requests, the cloud language model, resource upload jobs, downloadable Vision assets), and the pasteboard and share surfaces. It fails on any Swift import of a framework that is not on its allow-list, so a new framework is a deliberate edit of that list (an import is recognised at the start of a line or after a `;` or a `*/` on the same line; an import written any other way is not seen). It fails on third-party, package, SDK or framework dependencies and on target paths outside the allow-listed ones in `project.yml` (the keys `url`, `github`, `framework`, `sdk`, `xcframework`, `carthage` and `path` are found in block style and in flow style, bare or quoted; a key built any other way, or set in another file, is not seen), on C-family source, model or binary files in the shipped folders, on `contentsOf` outside the storage file, on any `NetworkAccessAllowed` that is not `isNetworkAccessAllowed = false`, on URLs opened or built with `URL(string:)` outside the Settings page, on ATS exceptions, tracking, push or iCloud settings in `project.yml`, and on a privacy manifest that declares tracking or collected data. It does not see a URL built another way (`URL.init(string:)` with a split literal passes), a network call written with a name that is not on its lists, a setting outside `project.yml` (an `.xcconfig` link flag, a hand-edited `Info.plist`), or what the operating system does for the app. It runs inside `scripts/verify.sh`, and `scripts/test-tripwire.sh` checks it against planted violations in a temporary copy. A post-build step in the Xcode project (`scripts/check-built-app.sh`) checks the finished app after every build, device builds included. It fails the build when a binary links a networking or web framework, binds symbols from a library that is not on its allow-list (local Apple frameworks only, for example Photos, PhotosUI, Vision and Core Graphics; libraries are named in the script), or references a listed networking symbol, and when the app embeds a framework. The final check happens on a device: airplane mode, and the iOS App Privacy Report.

## Decisions (29 Sep 2026)

- Native: Swift 6, SwiftUI, PhotoKit, Vision. Cross-platform layers would need native modules for both frameworks.
- iOS 17.0 minimum, iPhone only.
- Free, no paywall. If StoreKit ever arrives, the network check gets one explicit allowance for it.
- It is a portfolio piece, not on the App Store for now. People install it by building it or from an unsigned IPA on GitHub Releases (`docs/research/distribution.md`).
- Categories in v1: screenshots and screen recordings, similar shots, blurry/dark/accidental shots, big videos.
- Name Stilltrim, bundle id `com.matuskalis.stilltrim` (a free Apple ID cannot use it, so a clone sets its own in `Config/Local.xcconfig`).
- Accent red, light #D12E1F and dark #FF5B47. The hex values are still placeholders until judged on a device. Icon: a contact sheet, a 3 by 3 grid of grey frames with one circled in red (`Design/AppIcon.svg`, rendered by `scripts/render-icon.sh`). Research: `docs/research/identity.md`.

## How it works

### Access

Read/write library access, because deleting needs it. Limited access works: the scan covers the selected photos and Settings offers the system picker to change the selection.

### Scan

One pass over `PHAsset.fetchAssets`, sorted by creation date. Each asset lands in at most one category, in this priority: screenshots and recordings, similar shots, low quality, big videos. The reclaimable total counts each asset once.

Analysis reads 512 px thumbnails from `PHImageManager` (`.highQualityFormat`, `.exact`, network access off). An asset with no local thumbnail is skipped and counted as "in iCloud, not scanned". The app never asks PhotoKit to download anything.

At most 4 analyses run at once. The screen stays awake during a scan. Progress is shown and the scan can be cancelled. If the first 20 analyses all fail, the scan stops with an error instead of producing garbage.

### Categories

Screenshots and recordings: `mediaSubtypes` contains `.photoScreenshot` or `.videoScreenRecording`. Nothing pre-selected, "Select all" available.

Each screenshot is filed under one kind: chats, receipts and tickets, codes and barcodes, verification codes, maps, web pages, social posts, documents, pictures, or Mix when nothing fits. Recordings are a kind of their own. The review shows the biggest kind first and Mix last, each under a heading with its own Select button. `ScreenshotClassifier` in CleanupCore decides, from rules and without Vision, so `swift test` covers it. `ScreenshotAnalyzer` feeds it from a 1,536 px copy of the screenshot: Vision text recognition at the fast level (the accurate level needed 63 s to prepare its model the first time), with the request revisions pinned (text 3, classification 2, barcodes 4) so an OS update cannot change what a cached kind meant, barcode detection and Vision's scene labels, all on the phone. Each kind earns a score from a few signals: clock times with bubbles on both sides for chats (bubbles on one row with a line on the other side are table cells, not chat, and a clock time still counts when the fast reader writes it as "12'.41"), money words next to an amount on the same row for receipts (also Czech, German, Hungarian and Polish words, and an amount without its euro sign) and booking words for tickets, a barcode for codes, a short message with one number and a code word for verification codes (a PIN, a password, a Wi-Fi, recovery or pickup code stays a plain code, because it stays valid), a map label or two map words, plus distances, for maps, a domain line centred at the top or in Safari's bottom bar, with cookie words, for web pages, handles and like counts for social posts, a dense page of long lines for documents, a strong scene label with almost no text for pictures. The status bar and home indicator strips are ignored, and words are matched without accents, so a Slovak receipt works. Below a score of 0.5 the answer is Mix. The classifier is at version 2, so screenshots cached by version 1 are read again once. A wrong guess only files a screenshot under another heading, nothing is selected by kind. A screenshot Vision cannot read this time is shown under Mix and read again on the next scan.

Similar shots: a Vision feature print per photo (revision 2 pinned, 768 values), compared with the next photos in creation order (at most 30, within 10 minutes). Leader clustering: a photo joins the earliest group whose first photo it is within 0.45 of, so a slow drift across a burst cannot merge the two ends. The keeper of a group is chosen by favourite, then edited, then resolution, then two votes, then the earliest photo. The votes are the bytes of the still alone (a Live Photo's video and a RAW alternate do not count), which needs a gap of 5 percent, and sharpness (the cached fine-to-coarse detail ratio), which needs a gap of 10 percent. A vote abstains inside its gap (margins measured on adjacent video frames and two framings of one photo). Votes that agree make a clear win. Split votes keep the size winner, and no vote at all keeps the larger still by exact bytes; both are marked a close call. In a clear group every other photo is pre-selected, except favourites and edited photos. In a close call nothing is pre-selected, and the user can still tick by hand. Each group header carries one plain line with the reason ("Best: larger file, more detail (+35%).") or "Close call. These look equally good. One is marked Best." Without still bytes or sharpness the order is the old one, exact file size, which picked the original 16 times of 16 on blurred, recompressed, cropped and downsized copies.

Why file size and not sharpness: on 16 photographs against recompressed, cropped, downsized and blurred copies of the same photo, file size picked the original 16 times of 16. Laplacian sharpness picked it once, because JPEG blocking adds edges.

Low quality: measured on a 512 px grayscale copy. One issue per photo, most telling first: too dark (99th percentile luminance below 0.12), overexposed (1st percentile above 0.92), blank (luminance standard deviation below 0.02), blurry (detail at full size divided by detail at half size below 0.21, or Laplacian variance below 0.0003). Nothing pre-selected.

Big videos: videos of at least 50 MB, largest first, with size and duration. Nothing pre-selected.

Every threshold comes from a measured fixture set. `CalibrationTests` records the numbers and re-checks them on real photographs.

### Safety

Deletion goes through `PHAssetChangeRequest.deleteAssets`. iOS shows its own confirmation and the items sit in Recently Deleted for 30 days. The done screen reports what was really deleted (photos already gone from the library are not counted), says space returns only after Recently Deleted is emptied, and lists the steps.

"Keep" on an item adds it to an on-device keep list and it never shows again. The best photo of a group is kept anyway, so it has no "Keep" action.

A bulk action ("Select all", a screenshot section's "Select") never selects a favourite or an edited photo. They carry a small heart or pencil mark, a line above the grid says how many were left out, and the user can still tick one by hand.

Results follow the library. A `PHPhotoLibraryChangeObserver` drops every scanned asset that was removed or changed since the scan (a favourite added in the Photos app, an edit, a deletion), so a stale suggestion cannot be acted on. Changes that arrive while a scan runs are held back and applied when it finishes, so a photo favourited mid-scan is not pre-selected. When PhotoKit cannot describe a change, the results are cleared and a rescan is needed (mid-scan, the finished scan is discarded).

The observer is not the only guard: it lags, and delivery while the app is suspended is unverified. So `delete` re-reads each photo's modification date and favourite flag right before calling PhotoKit (`DeletionGate` in CleanupCore). A photo that differs from the scan, or that the scan recorded no date for, is kept, leaves the results and is reported on the done screen ("2 photos changed after the scan and were kept."). Photos already gone are skipped as before. `hasAdjustments` is not compared, because the app derives its edited flag differently.

`ReviewState` in CleanupCore owns the result and the selection, so the two cannot drift apart: the selection only holds ids that are shown, and a photo that just became the best of its group starts unselected (a deletion elsewhere in the group promotes it). Picking a best photo by hand stays possible. A group with fewer than two photos left disappears. When the best photo of a group is deleted, the best of the rest takes its place and is no longer suggested for removal, so a group never ends up with every copy suggested.

A thumbnail request ends when the scan is cancelled or after 30 seconds, and a degraded preview of an iCloud photo counts as "not on this phone", so a scan can always be stopped and erasing app data cannot hang.

Delete above: a long list is worked through in batches. `ReviewState.selectedIDs(in:above:)` returns the selected ids that come before the photo at the top of the screen, in the order `ScanResult.items(in:)` gives, which is the order on screen. When that photo is not in the result (it was just deleted) nothing is above it, so a stale position can never widen what gets deleted. iOS still asks for its own confirmation each time.

### Cache

One binary plist in Application Support, keyed by `localIdentifier`, valid while `modificationDate` is unchanged. It holds the half-precision feature print, quality metrics, byte size, the bytes of the still and an edited flag, and for a screenshot its kind together with the classifier version that chose it (a new version reads screenshots again and leaves the fingerprints alone). The header names the fingerprinter, so a different fingerprinter or file version drops the cache. The bytes of the still are optional: an entry stored without them is sized again once on the next scan and keeps its fingerprint. Excluded from backup. "Erase app data" deletes it together with the keep list.

Measured: 1.7 KB per photo (3.5 MB for 2,031 photos), so about 34 MB at 20,000 photos.

File size comes from `PHAssetResource` through the key-value keys `fileSize` and `locallyAvailable`. They are not public API, widely used, and each key is checked with `responds(to:)` before use. Only resources on this phone count towards reclaimable space.

## Screens

1. Welcome: the promise in three lines, one button to grant access.
2. Home: total reclaimable space, four category rows with count and size, scan progress.
3. Review: thumbnail grid, tap to select, tap-hold for preview and "Keep". Similar shots show as groups with a "Best" mark. Screenshots sit under a heading per kind with a Select button. Bottom bar: "Delete N · X MB", and "Delete N above" once some ticked photos have been scrolled past. The selection mark is a 22 pt disc with a white ring, a dark scrim inside and a dark keyline outside, so it keeps 3:1 against any photo (`Contrast` tests in CleanupCore); selected adds the accent fill and a check and shrinks the photo to 90 percent, so the states differ in shape, not only colour. Haptics come from `sensoryFeedback` on the Review screen, driven by event counters: a light tick for one photo, a firmer impact for Select all or a section Select, a success when a delete completes.
4. Done: space freed once Recently Deleted is emptied, with steps.
5. Settings: privacy in plain words and how to verify it (airplane mode, iOS App Privacy Report), manage limited access, erase app data.

Look: native iOS, SF, system materials, one accent colour (red). The selection mark and the Delete button share it: red means "this goes". No emoji markers, no accent-bar cards.

## Structure

- `Packages/CleanupCore`: image quality metrics, feature print distance, grouping, keeper choice, and the result model (`ScanResult`, with removal, promotion and selection rules). Takes `CGImage` and plain values, no PhotoKit, so `swift test` runs on the Mac.
- `App`: PhotoKit behind one actor (`PhotoLibraryService`), scan pipeline, cache, SwiftUI screens.
- `project.yml` for XcodeGen. The generated `.xcodeproj` is not committed. The `Stilltrim` scheme has no tests, so pressing Test with a phone selected cannot delete its photos. The UI tests live in `Stilltrim-UITests` and skip themselves anywhere but a simulator.
- `Design`: the icon source. `Config`: bundle id and team, `Local.xcconfig` overrides and is not committed.
- `scripts`: `verify.sh`, `check-no-network.sh`, `check-built-app.sh`, `fetch-fixtures.sh`, `seed-simulator.sh`, `seed-bulk.sh`, `render-icon.sh`.
- `.github/workflows`: `release.yml` builds an unsigned IPA on a version tag; `ci.yml` runs the checks and stays idle while the repository is private (macOS minutes cost money then).

## Findings

- The iOS 26.1 simulator cannot run Vision feature prints: the default path throws "Failed to create espresso context", and forcing the CPU returns near-identical vectors for different photos. The simulator uses `TinyImageFingerprinter` (16x16 thumbnail) through `-tinyFingerprints`. Vision is verified on the Mac and needs a device pass.
- Text recognition, scene labels and barcode detection fail the same way in the simulator, so every screenshot lands in Mix there. The rules are covered by `ScreenshotClassifierTests`, Vision on drawn screens by `ScreenshotAnalyzerTests` (Mac only), and real screenshots need a device pass.
- Vision revision 2 distances on 16 photographs: different scenes start at 0.72, same-scene variants (recompressed, cropped, exposure shifted) stay at or below 0.44. The 0.45 threshold sits in that gap.
- `simctl privacy grant photos` does not work on this simulator, the UI test accepts the prompt instead.
- A delete of 349 photos in one batch on the simulator left the rest of the review list in place, so the library change observer did not clear it (30 Sep 2026). Whether a phone behaves the same is still to check.
- Scale, 2,031 photos in the simulator with an optimized build: cold scan 18.6 s, warm rescan 0.44 s. A Debug build is about 6 times slower in the analysis stage.
- Sizing (`PHAssetResource` lookups) costs about 4.3 ms per asset and is now the largest cold-scan stage (8.8 s of 18.6 s). At 20,000 assets that is about 90 s.

## Review

Two independent Opus reviews. The first found 8 issues: a single broken photo made every rescan fail, results went stale when the library changed, "Deselect all" left hand-picked photos selected, the privacy guard could be sidestepped in three ways, the cache was rewritten after every non-analysed photo, erasing data did not wait for a running scan, keeping or deleting the best photo dropped its whole group, and the result rules had no tests.

The second checked those fixes and found 3 more: a photo promoted to best after a deletion stayed selected (one tap on Delete could remove a whole burst), library changes during a scan were lost, and a thumbnail request could not be cancelled or time out. All fixed. The first is covered by `ReviewStateTests`, the other two by `ScanControl` UI tests on a 2,000 photo library (cancel, and erase in the middle of a scan).

## Next

1. Look up sizes only for candidates (screenshots, videos, group members, flagged photos), not for every asset.
2. Exact duplicates anywhere in the library (same pixel size and byte size, confirmed by feature print). Needs sizes for all photos, so it waits for step 1.
3. Real-device pass on a large library. First run done on 30 Sep 2026: installed on a physical iPhone (iPhone 15, iOS 27.0, where the `fileSize` key still works) with `scripts/install-on-iphone.sh`, scanned, and the owner reports it works well. Still to record: scan time and library size, false alarms in Blurry and dark, whether the Best picks are right, iCloud Optimize Storage behaviour, and whether the app's own large batch delete reaches the change observer as a non-incremental change (that would clear the results after a successful delete, which is safe but should not happen). Settings, About shows which similarity check is active.
4. Later, decided but not built: exact duplicates anywhere, aesthetics score as a tie-break behind `#available(iOS 18)`, user-album protection, a strictness control, quick scan first. Ranking and effort: `docs/research/features-and-pipeline.md`.

## Out of scope for v1

Paywall, sync, widgets, Slovak strings, suggestions chosen by what a screenshot says (kinds only sort them), aesthetics scoring (needs iOS 18), Live Photo to still conversion, background scanning.
