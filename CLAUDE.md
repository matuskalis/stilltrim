# Stilltrim

iPhone app that finds junk in the photo library (screenshots, similar shots, blurry and dark frames, big videos) and deletes what the user picks. All analysis runs on the device. `SPEC.md` holds the design and the measurements behind every number.

## Rules that must hold

- Nothing leaves the phone. No networking code, no third-party code, no analytics. `scripts/check-no-network.sh` is a tripwire for it (not a proof) and runs inside `scripts/verify.sh`. The real check is a device in airplane mode plus the iOS App Privacy Report. When StoreKit joins for a paywall, allow it in that script on purpose and nowhere else.
- `isNetworkAccessAllowed` is always false. The app never downloads from iCloud.
- Deleting goes only through `PHAssetChangeRequest.deleteAssets`, so iOS shows its own confirmation. Nothing is pre-selected except the non-best photos of a similar group, never favourites or edited photos. Bulk selection ("Select all", a section Select) also skips favourites and edited photos outside similar groups; the user can still tick one by hand.
- Result and selection change only through `ReviewState` (CleanupCore), so the selection never holds an id that is not shown and a freshly promoted best photo starts unselected. Rules about removing, promoting and suggesting live in `ScanResult.swift` and `ReviewState.swift`, with tests.
- Every threshold comes from a measurement. Change one together with `CalibrationTests`: `scripts/fetch-fixtures.sh`, then `CLEANUP_FIXTURES=$PWD/.fixtures swift test` inside `Packages/CleanupCore`.
- Never press Test with a phone as the destination. The `Stilltrim` scheme has no tests; the UI tests are in `Stilltrim-UITests`, delete seeded photos, and skip themselves outside a simulator.
- A post-build step (`scripts/check-built-app.sh`) fails any Xcode build whose app links a networking or web framework or embeds a framework. Keep it in `project.yml`.
- No em dashes in in-app copy.

## Commands

- `xcodegen generate` builds the Xcode project from `project.yml`. The `.xcodeproj` is not committed.
- `scripts/verify.sh` runs package tests, the simulator build and the privacy guard, then prints READY or NOT-READY. `--ui` adds the UI tests (scheme `Stilltrim-UITests`).
- `scripts/render-icon.sh` renders `Design/AppIcon.svg` into the asset catalog. Releases: push a tag `v0.1.0` and `.github/workflows/release.yml` builds the unsigned IPA.
- `cd Packages/CleanupCore && swift test` is the fastest loop for the pure logic.
- `scripts/classify-folder.sh <folder> [--dump]` classifies every image in a folder with the app's Vision classifier on the Mac (AirDrop real screenshots to try it); `--dump` also prints the recognised text.
- `scripts/seed-simulator.sh <UDID>` fills a simulator library with near-duplicates, blurry and blank frames, screenshots and a 78 MB video. `scripts/seed-bulk.sh <UDID> 2000` adds a scale set.
- Debug launch arguments: `-autoScan`, `-tinyFingerprints`, `-openCategory similar|screenshots|lowQuality|bigVideos`.

## Simulator traps (iOS 26.1)

- After an Xcode update every developer tool (`git` included, it is Xcode's shim) stops until the licence is accepted (`sudo xcodebuild -license accept`), and `xcodebuild` and `simctl` then fail to load a plug-in until `sudo xcodebuild -runFirstLaunch` has run. Both need the owner's password, so ask, do not work around them. `xcodebuild -checkFirstLaunchStatus` exits 0 once done.

- `simctl privacy grant photos` is ignored (it writes auth_version 1, PhotoKit wants 2). Run `UITests/GrantPhotosAccess` once per simulator.
- Vision feature prints in the simulator are near-identical for different photos. Use `-tinyFingerprints` there; it only works in simulator builds, and Settings, About shows the active check. Check real similarity on the Mac (`swift test`) and on a device.
- Debug builds run the pixel loops about 6 times slower than optimized ones. Time scans with `SWIFT_OPTIMIZATION_LEVEL=-O`.
- Seeded screenshots carry EXIF UserComment "Screenshot" so Photos flags them. Screen recordings cannot be seeded.
- The first UI test run right after `simctl erase` failed once in four (the photo permission ended up denied and the scan never started). Reset it with `xcrun simctl privacy <udid> reset photos com.matuskalis.stilltrim` and rerun. The helper says so when it sees the denied state.
- `UITests/CleanupFlow` deletes the seeded screenshots. Reseed before running it again.
- Vision fails in the simulator for text, scene labels and barcodes too ("Failed to create espresso context"), so every seeded screenshot is read as Mix there. Kinds are checked by the classifier tests, the Mac-only `ScreenshotAnalyzerTests`, and on a phone.
- Never put `scrollPosition(id:)` or `scrollTargetLayout()` on the review grid. On the seeded similar list (about 35 groups) the main thread sat at 100% in `LazySubviewPlacements` and the app froze (measured 30 Sep 2026; the old layout, and the same grid without scroll tracking, were fine). `ReviewView` tracks scrolled-past cells with `onGeometryChange` instead.
- `UITests/DeleteAbove` needs a long similar list: `scripts/seed-bulk.sh <UDID> 800 pairs` (the plain bulk set forms only about 35 groups with the stand-in fingerprint). It deletes photos: add more pairs before running it again, and it skips itself when the list is short.
- `UITests/ScanControl` (cancel, erase mid-scan) needs `scripts/seed-bulk.sh <UDID> 2000` and skips itself on a small library.

## Repositories

`origin` is the public repo matuskalis/stilltrim (MIT). `archive` is a read-only remote for the private repo matuskalis/stilltrim-archive, which keeps the history from before the public release: never push to it. A local, untracked overview memo may sit in the folder (listed in `.git/info/exclude`): never add it to git. Commits in this repo use the GitHub no-reply address. Pushing workflow files needs the `workflow` scope on the `gh` token, and the repo-local credential helper is set to use only `gh` (the macOS keychain helper holds an older token).

## CI

`ci.yml` and `release.yml` run on `macos-26` with Xcode 26.6, the image's default. Xcode 26.1.1 is on that image without an iOS simulator runtime, so it cannot build for a simulator there. Run the release workflow by hand with `publish` off for a dry run that only keeps the IPA as an artifact.

## Placeholders

Applied 29 Sep 2026: name Stilltrim, bundle id `com.matuskalis.stilltrim`, red accent, contact-sheet icon. The accent hex values (#D12E1F light, #FF5B47 dark) stay placeholders until judged on a device. Research behind every decision: `docs/research/`.
