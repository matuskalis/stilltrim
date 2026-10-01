#!/bin/bash
# Tripwire for the privacy promise: the app has no networking code, no third-party code and no tracking.
# It catches accidents and lazy additions. It is not a proof against code written to evade it, so the
# final check stays on a device: airplane mode, and iOS Settings > Privacy & Security > App Privacy Report.
# Exits non-zero when any rule breaks and prints every offending line.
# When StoreKit joins for a paywall, allow it here on purpose and nowhere else.
set -uo pipefail
cd "$(dirname "$0")/.."

failed=0
fail() { echo "FAIL  $1"; failed=1; }
pass() { echo "PASS  $1"; }

SOURCES="App Packages/*/Sources"

# Matching lines of Swift, Objective-C and C-family code, comments excluded.
code_matching() {
  grep -rnE --include='*.swift' --include='*.m' --include='*.mm' --include='*.c' --include='*.cc' --include='*.cpp' --include='*.h' "$1" $SOURCES | grep -vE ':[0-9]+:[[:space:]]*//' || true
}

# 1. No third-party dependencies: only local path packages, no binaries, no linked frameworks.
deps=$(grep -nE "(^|[[:space:]{,])[\"']?(url|github|framework|sdk|xcframework|carthage)[\"']?[[:space:]]*:" project.yml || true)
deps+=$(grep -rnE '\.package\(url:|\.binaryTarget|\.xcframework' Packages/*/Package.swift 2>/dev/null || true)
deps+=$(ls Podfile Cartfile 2>/dev/null || true)
outside=$(grep -nE "(^|[[:space:]{,])[\"']?path[\"']?[[:space:]]*:[[:space:]]" project.yml | grep -vE 'path:\s+(App|App/Info\.plist|UITests|Packages/[A-Za-z0-9]+)\s*$' || true)
if [ -n "$deps$outside" ]; then
  fail "third-party dependency, binary or linked framework declared:"; echo "$deps$outside"
else
  pass "no third-party dependencies"
fi

# 2. No networking, web, ads, tracking or analytics APIs in the source. The last five are OS calls that make
# the system fetch data for the app (embedding assets, a cloud language model, resource upload, downloadable
# Vision assets), which no networking symbol would show.
DENY='requestAssets|PrivateCloudComputeLanguageModel|PHAssetResourceUploadJob|downloadAssets|DownloadableAssetsRequest|NSURLSession|URLComponents|NSURLComponents|NSURL\b|dataRepresentation|resolvingBookmarkData|dlopen|dlsym|getStreamsToHost|NSClassFromString|URLSession|URLRequest|URLConnection|NWConnection|NWPathMonitor|NWListener|CFNetwork|CFSocket|CFStream|import Network|import WebKit|WKWebView|SFSafariViewController|import SafariServices|ASWebAuthenticationSession|import AdSupport|ASIdentifierManager|AppTrackingTransparency|ATTrackingManager|import StoreKit|import CloudKit|import MessageUI|import Firebase|import Sentry|import Crashlytics|import Amplitude|import Mixpanel|import Segment|AsyncImage|NSUbiquitousKeyValueStore|NSBundleResourceRequest|AVAsset|AVURLAsset|AVAggregateAssetDownloadTask|AVContentKeySession|AVQueuePlayer|AVPlayerLooper|AVPlayer\([[:space:]]*url|AVPlayerItem\([[:space:]]*(url|asset)|UIPasteboard|ShareLink|UIActivityViewController|\bgetaddrinfo\b|\bgethostbyname\b|\bsocket\(|https?://'
hits=$(code_matching "$DENY")
if [ -n "$hits" ]; then
  fail "network, web, ad or analytics API in source:"; echo "$hits"
else
  pass "no network, web, ad or analytics APIs in source"
fi

# 2a. Import allow-list: a new framework is a deliberate edit of this list.
# Keep in step with ALLOW_LIBS in scripts/check-built-app.sh (the libraries the built binary may bind).
# AVKit and AVFoundation are allowed on purpose, for local video preview only: playback goes through
# PHImageManager player items with isNetworkAccessAllowed = false, and the code never builds a URL and
# never opens a stream (AVAsset and its subclasses, AVQueuePlayer, AVPlayer(url:) and AVPlayerItem(asset:) stay denied below)
# (rules 2 and 3 reject URL(string:), NSURL and https literals).
ALLOWED_IMPORTS='Foundation|SwiftUI|UIKit|Photos|PhotosUI|Vision|AVKit|AVFoundation|CoreGraphics|Accelerate|Observation|os|CleanupCore|QuartzCore|ImageIO|CoreImage|CoreText|UniformTypeIdentifiers'
# An import at the start of a line, or after a ";" or a "*/" on the same line.
hits=$(grep -rnE --include='*.swift' '(^|;|\*/)[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+' $SOURCES | perl -ne 'my ($where, $code) = /^([^:]+:\d+):(.*)$/s or next; while ($code =~ /(?:^|;|\*\/)\s*(?:@\w+\s+)*import\s+(?:(?:struct|class|enum|protocol|func|var|let|typealias)\s+)?(\w+)/g) { print "$1 $where\n" }' | awk -v allow="^($ALLOWED_IMPORTS)$" '$1 !~ allow' || true)
if [ -n "$hits" ]; then
  fail "import of a framework that is not on the allow-list:"; echo "$hits"
else
  pass "every import is on the allow-list"
fi

# 2a2. No C-family source, model or binary resource in the shipped folders.
hits=$(find $SOURCES \( -name '*.m' -o -name '*.mm' -o -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.h' -o -name '*.mlmodel*' -o -name '*.dylib' -o -name '*.a' -o -name '*.framework' -o -name '*.xcframework' -o -name '*.bundle' \) 2>/dev/null || true)
if [ -n "$hits" ]; then
  fail "C-family source, model or binary resource in a shipped folder:"; echo "$hits"
else
  pass "no C-family source, model or binary resource"
fi

# 2b. Reading file contents is fine for local files only. The single place that does it is AppStorage.
hits=$(code_matching '(Data|String|NSData|NSString)\(contentsOf' | grep -v '^App/Storage/AppStorage.swift' || true)
if [ -n "$hits" ]; then
  fail "contentsOf outside App/Storage/AppStorage.swift (could read a remote URL):"; echo "$hits"
else
  pass "contentsOf only in AppStorage, on local files"
fi

# 3. URLs may only open the iOS Settings page.
hits=$(code_matching 'UIApplication\.shared\.open|URL\(string:' | grep -v 'openSettingsURLString' || true)
if [ -n "$hits" ]; then
  fail "URL opened or built outside the Settings page:"; echo "$hits"
else
  pass "URLs only open iOS Settings"
fi

# 4. Photos are never downloaded from iCloud: every isNetworkAccessAllowed must be false.
hits=$(code_matching '[Nn]etworkAccessAllowed' | grep -vE 'isNetworkAccessAllowed = false' || true)
if [ -n "$hits" ]; then
  fail "isNetworkAccessAllowed is not always false:"; echo "$hits"
else
  pass "isNetworkAccessAllowed is only ever false"
fi

# 5. No transport-security exceptions, tracking prompt, push or associated domains.
hits=$(grep -nE 'NSAppTransportSecurity|NSAllowsArbitraryLoads|NSUserTrackingUsageDescription|remote-notification|aps-environment|associated-domains|com\.apple\.developer\.icloud' project.yml || true)
if [ -n "$hits" ]; then
  fail "transport, tracking, push or iCloud setting in project.yml:"; echo "$hits"
else
  pass "no ATS exceptions, tracking prompt, push or iCloud entitlement"
fi

# 6. The privacy manifest declares no tracking and no collected data.
manifest=App/PrivacyInfo.xcprivacy
tracking=$(plutil -extract NSPrivacyTracking raw "$manifest" 2>/dev/null || echo missing)
domains=$(plutil -extract NSPrivacyTrackingDomains json -o - "$manifest" 2>/dev/null || echo missing)
collected=$(plutil -extract NSPrivacyCollectedDataTypes json -o - "$manifest" 2>/dev/null || echo missing)
if [ "$tracking" = "false" ] && [ "$domains" = "[]" ] && [ "$collected" = "[]" ]; then
  pass "privacy manifest: no tracking, no collected data"
else
  fail "privacy manifest declares tracking or collected data (tracking=$tracking domains=$domains collected=$collected)"
fi

# 7. Built apps found on disk (this repo's build folder and Xcode's DerivedData, so device builds count).
checked=0
for app in build/Build/Products/*/Stilltrim.app "$HOME"/Library/Developer/Xcode/DerivedData/Stilltrim-*/Build/Products/*/Stilltrim.app; do
  [ -d "$app" ] || continue
  checked=$((checked + 1))
  ./scripts/check-built-app.sh "$app" || failed=1
done
if [ "$checked" -eq 0 ]; then
  echo "SKIP  no built app found to inspect"
elif [ "$failed" = 0 ]; then
  pass "$checked built app(s) link no networking or web framework and embed none"
else
  fail "a built app breaks the rules above"
fi

exit $failed
