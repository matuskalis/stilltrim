# Photo Cleanup

iPhone app that finds junk in the photo library (screenshots, similar shots, blurry and dark frames, big videos) and deletes what the user picks. All analysis runs on the device. `SPEC.md` holds the design and the measurements behind every number.

## Rules that must hold

- Nothing leaves the phone. No networking code, no third-party code, no analytics. `scripts/check-no-network.sh` is a tripwire for it (not a proof) and runs inside `scripts/verify.sh`. The real check is a device in airplane mode plus the iOS App Privacy Report. When StoreKit joins for a paywall, allow it in that script on purpose and nowhere else.
- `isNetworkAccessAllowed` is always false. The app never downloads from iCloud.
- Deleting goes only through `PHAssetChangeRequest.deleteAssets`, so iOS shows its own confirmation. Nothing is pre-selected except the non-best photos of a similar group, never favourites or edited photos.
- Result and selection change only through `ReviewState` (CleanupCore), so the selection never holds an id that is not shown and a freshly promoted best photo starts unselected. Rules about removing, promoting and suggesting live in `ScanResult.swift` and `ReviewState.swift`, with tests.
- Every threshold comes from a measurement. Change one together with `CalibrationTests`: `scripts/fetch-fixtures.sh`, then `CLEANUP_FIXTURES=$PWD/.fixtures swift test` inside `Packages/CleanupCore`.
- No em dashes in in-app copy.

## Commands

- `xcodegen generate` builds the Xcode project from `project.yml`. The `.xcodeproj` is not committed.
- `scripts/verify.sh` runs package tests, the simulator build and the privacy guard, then prints READY or NOT-READY. `--ui` adds the UI tests.
- `cd Packages/CleanupCore && swift test` is the fastest loop for the pure logic.
- `scripts/seed-simulator.sh <UDID>` fills a simulator library with near-duplicates, blurry and blank frames, screenshots and a 78 MB video. `scripts/seed-bulk.sh <UDID> 2000` adds a scale set.
- Debug launch arguments: `-autoScan`, `-tinyFingerprints`, `-openCategory similar|screenshots|lowQuality|bigVideos`.

## Simulator traps (iOS 26.1)

- `simctl privacy grant photos` is ignored (it writes auth_version 1, PhotoKit wants 2). Run `UITests/GrantPhotosAccess` once per simulator.
- Vision feature prints in the simulator are near-identical for different photos. Use `-tinyFingerprints` there. Check real similarity on the Mac (`swift test`) and on a device.
- Debug builds run the pixel loops about 6 times slower than optimized ones. Time scans with `SWIFT_OPTIMIZATION_LEVEL=-O`.
- Seeded screenshots carry EXIF UserComment "Screenshot" so Photos flags them. Screen recordings cannot be seeded.
- `UITests/CleanupFlow` deletes the seeded screenshots. Reseed before running it again.
- `UITests/ScanControl` (cancel, erase mid-scan) needs `scripts/seed-bulk.sh <UDID> 2000` and skips itself on a small library.

## Placeholders

App name, bundle id `com.example.photocleanup`, accent colour and app icon. Replace before release.
