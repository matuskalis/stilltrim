# Stilltrim

An iPhone app that finds junk in your photo library and deletes what you pick: screenshots and screen recordings, similar shots, blurry and dark frames, big videos.

Everything is checked on the phone. Nothing is uploaded. There is no account, no analytics, no ads and no networking code.

Status: version 0.1, a portfolio project. It is not on the App Store. You build it yourself or install a release file.

## What it does

- **Screenshots.** Whatever iOS flagged as a screenshot or screen recording.
- **Similar shots.** Photos taken minutes apart that look alike. One is marked Best, the rest are pre-selected. Favourites, edited photos and the Best one are never pre-selected.
- **Blurry and dark.** Very dark, overexposed, blank or blurry photos. Listed for review, never pre-selected.
- **Big videos.** Videos of 50 MB or more, largest first.

You tick what goes and tap Delete. iOS asks you to confirm, and the photos move to Recently Deleted. The space comes back when you empty it.

## The promise, and how to check it

Your photos never leave the phone. A small cache of numbers per photo (no pictures) stays on the phone, out of backups, and Settings, Erase app data wipes it.

- The code has no networking. `scripts/check-no-network.sh` fails on networking, web views, third-party code and tracking settings, and a build step checks the finished app for linked networking frameworks after every build. It is a tripwire, not a proof.
- Check it yourself on the phone: Settings, Privacy & Security, App Privacy Report, turn it on, run a scan, then open the report and look for Stilltrim under network activity. Or run a whole scan in airplane mode.

## Install

### Build it yourself (most reliable)

You need a Mac with Xcode 26 or 27 (built and tested with 26.1.1, 26.6 and 27.0), [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), and an iPhone on iOS 17 or later. A free Apple ID is enough.

1. In Xcode, Settings, Accounts: add your Apple ID. That creates your personal team.
2. Connect the iPhone with a cable and trust the Mac. Turn on Developer Mode on the phone (Settings, Privacy & Security, Developer Mode, then restart). The switch only appears after the phone has been connected to Xcode once.
3. Clone this repo, then `cp Config/Local.xcconfig.example Config/Local.xcconfig` and fill in your team ID and a bundle id of your own. A free team cannot use `com.matuskalis.stilltrim`, so pick something like `com.yourname.stilltrim`. If you cannot find your team ID, open the project once, choose your team under the target's Signing tab, and read it with `grep -m1 DEVELOPMENT_TEAM Stilltrim.xcodeproj/project.pbxproj`.
4. `xcodegen generate`, open `Stilltrim.xcodeproj`, choose your iPhone and press Run.
5. The first launch stops with an untrusted developer message. Trust yourself under Settings, General, VPN & Device Management, then press Run again.

With a free Apple ID the app stops launching after 7 days (build again), and one phone holds 3 such apps.

Do not press Test with your phone selected. The `Stilltrim` scheme has no tests for that reason. The UI tests are in the `Stilltrim-UITests` scheme, they delete photos, and they skip themselves anywhere but a simulator.

### Unsigned IPA from Releases

Each release has `Stilltrim-<version>-unsigned.ipa` and `SHA256SUMS`. The file is not signed, so install it with a tool that signs it with your own Apple ID (AltStore, SideStore or Sideloadly). The same 7 day and 3 app limits apply. Those tools change often. If one breaks, build it yourself.

### TestFlight and the App Store

Not available. Both need a paid Apple Developer account.

## Simulator

`xcodegen generate`, open the project and run on an iPhone 17 simulator. Vision does not work in the simulator, so add the launch argument `-tinyFingerprints` (Edit Scheme, Run, Arguments). It swaps in a simple stand-in and only takes effect in simulator builds, and Settings, About shows which similarity check is active. `scripts/seed-simulator.sh <UDID>` fills a simulator with test photos.

## Checks

```
scripts/verify.sh          # package tests, simulator build, privacy guard
scripts/verify.sh --ui     # plus the UI tests (simulator only, they delete seeded photos)
```

Continuous integration runs on GitHub once the repository is public: unit tests without the Vision ones, a simulator build and the privacy guard.

## Support

Open an issue: https://github.com/matuskalis/stilltrim/issues

`SPEC.md` has the design and every measured threshold. `CLAUDE.md` has the rules for coding sessions. `docs/research/` has the research behind the name, the icon and how to distribute the app.

## Licence

MIT, see `LICENSE`. The code is free to use, change and share, including commercially, as long as the copyright notice stays with it. The name Stilltrim and the icon are not part of that grant: a fork needs its own name and icon.
