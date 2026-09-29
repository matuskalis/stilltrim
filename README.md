# Photo Cleanup

iPhone app that finds junk in your photo library and deletes what you pick: screenshots and screen recordings, similar shots, blurry and dark frames, big videos. Working title.

Your photos never leave the phone. There is no server, account, analytics or third-party code. `scripts/check-no-network.sh` is a tripwire that fails the build when networking code, a web view, a tracking setting or a non-local dependency appears.

## Run it

Needs Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```
xcodegen generate
open PhotoCleanup.xcodeproj
```

Pick a simulator and run. `scripts/seed-simulator.sh <simulator UDID>` fills its library with test media. Similarity uses Apple's Vision feature prints, which do not run correctly in the simulator. There, add the launch argument `-tinyFingerprints` (Edit Scheme, Run, Arguments) to use a simple stand-in.

### On your own iPhone

1. Xcode, Settings, Accounts: add your Apple ID.
2. `cp Config/Local.xcconfig.example Config/Local.xcconfig` and fill in your team ID and a bundle id of your own.
3. `xcodegen generate`, open the project, choose your iPhone, run. Trust the developer under Settings, General, VPN & Device Management. A build signed with a free Apple ID expires after seven days.

Check the promise yourself: turn on airplane mode and scan, or open Settings, Privacy & Security, App Privacy Report after a scan and look for this app under network activity.

## Checks

```
scripts/verify.sh          # package tests, simulator build, privacy guard
scripts/verify.sh --ui     # plus UI tests (they delete seeded simulator photos)
```

`SPEC.md` has the design and every measured threshold. `CLAUDE.md` has the rules and the simulator traps.
