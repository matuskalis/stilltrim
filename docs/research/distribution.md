# Getting the app onto iPhones from a public GitHub repo

Research by an Opus subagent, 29 Sep 2026. Facts dated where they can change. Nothing here was verified on a device except the local unsigned build.

## Two findings in the project itself

- The version number is ignored. XcodeGen writes `CFBundleShortVersionString` 1.0 and `CFBundleVersion` 1 into the generated `App/Info.plist`, so `MARKETING_VERSION: "0.1.0"` in `project.yml` never reaches the app. Confirmed with PlistBuddy on the built `.app`.
- There is no app icon. The build has no asset catalog.

## 1. Installation paths

### (a) Build it yourself in Xcode with a free Apple ID
- Needs a Mac, Xcode, XcodeGen, and a USB or paired iPhone.
- Free "Personal Team" limits: 3 devices, 3 apps per device, 10 App IDs, each expiring after 7 days. Provisioning profiles expire 7 days after issue, then the app stops launching until rebuilt. (developer.apple.com/support/compare-memberships, read 29 Sep 2026)
- The phone needs Developer Mode on. The switch only appears in Settings after the phone has been paired with a Mac. (developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- The repo already supports this path through `Config/Local.xcconfig.example`.

### (b) TestFlight (paid account)
- Up to 100 internal testers and 10,000 external testers. A public link needs no email addresses and no UDIDs, capped anywhere from 1 to 10,000 people.
- Before external testers or a public link, the first build must pass Beta App Review. Later builds of the same version usually skip a full review.
- A build expires 90 days after upload. Testers use the TestFlight app and need no Developer Mode.
- Since 28 Apr 2026 every upload must be built with Xcode 26 or later and the iOS 26 SDK. Local Xcode 26.1.1 qualifies.
- The first TestFlight upload creates the App Store Connect record, and that locks the bundle id to the uploading team.
- Sources: developer.apple.com/testflight, developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers, developer.apple.com/news/upcoming-requirements.

### (c) Ad hoc (paid account)
- Each device UDID must be registered: 100 iPhones per membership year, resets only at renewal.
- Over-the-air install works with an `itms-services://?action=download-manifest&url=https://…/manifest.plist` link over HTTPS. Apple lists MIME types `application/octet-stream` for `.ipa` and `application/x-plist` for `.plist`.
- GitHub Pages serves `.plist` as `application/octet-stream`, not `application/x-plist` (checked with curl 29 Sep 2026). Public repos use this setup, but an install from Pages was not seen on a device.
- For a handful of friends it gives nothing TestFlight does not, and adds UDID collection and a re-sign per device.

### (d) Unsigned IPA on GitHub Releases, installed with the user's own Apple ID
Same limits as (a): 3 apps, 7 days, Developer Mode.
- AltStore Classic 2.3 (14 Sep 2026) adds "Remote AltServer" so installs and refreshes work without a computer. Minimum iOS raised to 17.4, so iOS 17.0 to 17.3 is not covered.
- SideStore refreshes on the device over a local VPN; first install through iloader (v2.3.4, 23 Sep 2026). On 9 Sep 2026 release 0.6.4 was marked "DO NOT USE" after an Apple server-side change; fix in 0.7.0-alpha on 15 Sep 2026. This path can break without warning.
- Sideloadly claims iOS 27 support on X. Its own claim only.
- Fine for technical visitors. Least reliable path.

### (e) EU Web Distribution and alternative marketplaces
Apple announced on 18 Aug 2026 that new terms take effect 1 Oct 2026:
- The per-install Core Technology Fee becomes a 5% Core Technology Commission, charged only on digital sales. A free app pays nothing.
- The "EU legal entity" requirement is dropped.
- Web Distribution requires one of seven criteria: a Dun & Bradstreet "Low Risk" or "Below Average Risk" score; publicly traded; venture funding from a listed investor; an audit with an unqualified opinion; nonprofit, school or government; a USD 1M stand-by letter of credit; or 1 million first annual installs worldwide plus 2 or more years of membership.
- Other conditions: iOS 17.5 or later, EU users only, installs only from a domain registered in App Store Connect, notarization required.
- A solo portfolio app meets none of these. A paid account alone is not enough.
- Sources: apple.com/newsroom/2026/08/apple-announces-changes-for-apps-in-the-european-union, developer.apple.com/support/apps-in-the-eu, developer.apple.com/support/web-distribution-eu.

### (f) Other
- Listing in an EU marketplace such as AltStore PAL (EU, Japan, Brazil): paid account, the EU terms, Apple notarization, then host the Alternative Distribution Package plus a JSON source. EU users only, extra work for a v1.
- No new Apple sideloading or notarization path outside the EU was found.

## 2. GitHub Actions

- `macos-26` (arm64) generally available since 26 Feb 2026. Image 20260907 carries Xcode 26.0.1, 26.1.1, 26.2, 26.3, 26.4.1, 26.5 and 26.6 (default). `xcode-27` is in public preview on macOS 27.
- Standard GitHub-hosted runners, including `macos-26`, are free and unlimited on public repositories. The repo is private today, so macOS minutes bill at $0.062 per minute until it goes public.
- XcodeGen is not on the images. Download the pinned release zip (2.46.0, 16 Jul 2026); it contains `xcodegen/bin/xcodegen`.
- Unsigned IPA verified locally on a fresh clone with no `Local.xcconfig` (17 s, `** BUILD SUCCEEDED **`): `xcodebuild … -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build`. `codesign` reports "not signed at all", binary arm64, `Payload/` zipped to a 344 KB IPA. `scripts/check-no-network.sh` passes on it. `Local.xcconfig` does not block CI because `#include?` is optional.

Minimal workflow, not yet run on a hosted runner:

```yaml
name: Release
on:
  push:
    tags: ['v*']
permissions:
  contents: write
jobs:
  ipa:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v5
      - run: sudo xcode-select -s /Applications/Xcode_26.6.app
      - name: Install XcodeGen
        run: |
          curl -sSL -o xg.zip https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip
          unzip -q xg.zip -d "$RUNNER_TEMP"
          echo "$RUNNER_TEMP/xcodegen/bin" >> "$GITHUB_PATH"
      - name: Build unsigned IPA
        run: |
          VERSION="${GITHUB_REF_NAME#v}"
          xcodegen generate
          xcodebuild -project PhotoCleanup.xcodeproj -scheme PhotoCleanup -configuration Release \
            -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build \
            MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$GITHUB_RUN_NUMBER" \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
          scripts/check-no-network.sh
          mkdir Payload && cp -R build/Build/Products/Release-iphoneos/PhotoCleanup.app Payload/
          zip -qry "PhotoCleanup-$VERSION-unsigned.ipa" Payload
      - name: Publish release
        env: { GH_TOKEN: "${{ github.token }}" }
        run: gh release create "$GITHUB_REF_NAME" PhotoCleanup-*-unsigned.ipa --generate-notes
```

Changes the project needs:
- In `project.yml` under `info.properties`, add `CFBundleShortVersionString: $(MARKETING_VERSION)` and `CFBundleVersion: $(CURRENT_PROJECT_VERSION)`. TestFlight needs a build number that rises with every upload.
- Add an AppIcon asset catalog. Upload validation requires one.
- Replace the placeholder `APP_BUNDLE_ID` in `Shared.xcconfig` with the real id before the first upload.

## 3. Apple Developer Program (29 Sep 2026)

- Price: 99 USD a year, in local currency (99 € in the EU per a secondary source). Same for individuals and organisations.
- Individual: legal name shown as seller. Apple Account with two-factor. Confirmation within about 24 to 48 hours.
- Organisation: legal entity shown as seller. Needs a D-U-N-S number (up to 5 business days from D&B, then up to 2 business days at Apple), a work email on the company domain, a public website, and Apple's manual check.
- Moving later: converting an individual account to an organisation is "contact us". App transfer to another account needs at least one version released on the App Store; the bundle id moves with the app. An app that has only been on TestFlight cannot be moved. Pick the seller before the first TestFlight upload.

## 4. Recommendation

Primary: TestFlight public link. The 99 € account is needed for the App Store anyway. Covers the owner's iPhone and friends' phones with no computer, no Developer Mode, no UDIDs, no 7-day expiry, only a 90-day re-upload.

Fallback: build from source with the current `Local.xcconfig` flow (works for a stranger's clone with a free Apple ID; CI works with no `Local.xcconfig`). Also attach an unsigned IPA to each GitHub Release for AltStore, SideStore or Sideloadly users, with their limits stated. Skip ad hoc and EU Web Distribution for v1.

Repo needs: a README "Install" section (TestFlight link, build from source, unsigned IPA); `.github/workflows/release.yml`; signing as now (`Shared.xcconfig` holds the real bundle id and an empty team, `Local.xcconfig` overrides both; strangers use their own bundle id because a free team cannot register an id someone else owns); the version keys and the icon.

Account: paid, individual, unless a company must ever be the seller, in which case enrol the company with a D-U-N-S number before the first TestFlight upload.

Bundle id: decide before the first upload. Reverse-DNS on a domain the owner controls, based on the final product name. The prefix does not have to match the seller and survives a transfer.

## Could not verify

- An `itms-services` install from GitHub Pages or Release assets on a device.
- Whether ad hoc installs need Developer Mode (blogs only).
- The workflow on a hosted runner; whether macOS minutes count against a private repo's included minutes.
- Exact euro price for the owner's country and individual enrolment time.
- Whether individual accounts may list in AltStore PAL; EU terms for a free app after 1 Oct 2026.
- Sideloadly's iOS 27 claim; SideStore 0.7.0-alpha stability.
- Beta App Review turnaround in 2026.
