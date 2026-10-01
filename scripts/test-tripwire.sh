#!/bin/bash
# Self-test for scripts/check-no-network.sh. Copies the repo to a temp folder (nothing is planted in the
# working tree), plants one violation per case and checks the verdict: the clean copy must pass and every
# planted case must fail. A "known gap" is a violation the tripwire does not see yet: it must still pass,
# so that closing one is noticed and moves to the closed cases on purpose.
# Prints one PASS or FAIL line per case and exits non-zero on any surprise.
set -uo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home"

cases=0
surprises=0

fresh_copy() {
  rm -rf "$TMP/t"
  mkdir -p "$TMP/t"
  (cd "$SRC" && tar cf - scripts App project.yml Config Packages/*/Package.swift Packages/*/Sources) | (cd "$TMP/t" && tar xf -)
}

# Plants in a fresh copy, runs the tripwire there, prints PASS (exit 0) or FAIL (non-zero).
verdict() {
  fresh_copy
  (cd "$TMP/t" && eval "$1" && HOME="$TMP/home" ./scripts/check-no-network.sh >/dev/null 2>&1) && echo PASS || echo FAIL
}

add_project_line() { LINE="$1" AFTER="$2" perl -pi -e '$_ .= "$ENV{LINE}\n" if $_ eq "$ENV{AFTER}\n"' project.yml; }

# expect <name> <PASS|FAIL> <plant command> [known-gap]
expect() {
  local name="$1" expected="$2" plant="$3" gap="${4:-}" actual
  cases=$((cases + 1))
  actual=$(verdict "$plant")
  if [ "$actual" = "$expected" ]; then
    echo "PASS  ${gap:+known gap: }$name (tripwire $actual, expected $expected)"
  else
    echo "FAIL  ${gap:+known gap: }$name (tripwire $actual, expected $expected)${gap:+, the gap closed: move it to the closed cases}"
    surprises=$((surprises + 1))
  fi
}

DEPENDENCY_ANCHOR='      - package: CleanupCore'
PACKAGES_ANCHOR='packages:'

expect clean_copy                 PASS 'true'
expect c1_URLSession              FAIL 'printf "import Foundation\nlet s = URLSession.shared\n" > App/Evil.swift'
expect c2_requestAssets           FAIL 'printf "import Foundation\nfunc f(r: AnyObject) { r.requestAssets() }\n" > App/Evil.swift'
expect c3_import_struct           FAIL 'printf "import struct Network.NWEndpoint\nlet e = NWEndpoint.self\n" > App/Evil.swift'
expect c4_import_two_spaces       FAIL 'printf "import  Network\n" > App/Evil.swift'
expect c5_AsyncImage              FAIL 'printf "import SwiftUI\nstruct V: View { let u: URL; var body: some View { AsyncImage(url: u) } }\n" > App/Evil.swift'
expect c7_objc_file               FAIL 'printf "#import <Foundation/Foundation.h>\nvoid f(void){ [NSURLSession sharedSession]; }\n" > App/Bridge.m'
expect c8_import_MapKit           FAIL 'printf "import MapKit\n" > App/Evil.swift'
expect c8_import_LinkPresentation FAIL 'printf "import LinkPresentation\n" > App/Evil.swift'
expect c8_import_Multipeer        FAIL 'printf "import MultipeerConnectivity\n" > App/Evil.swift'
expect c9_bsd_socket              FAIL 'printf "import Foundation\nlet fd = socket(AF_INET, SOCK_STREAM, 0)\n" > App/Evil.swift'
expect c10_github_package         FAIL 'add_project_line "  Foo:" "$PACKAGES_ANCHOR"; add_project_line "    github: someone/somepkg" "  Foo:"; add_project_line "      - package: Foo" "$DEPENDENCY_ANCHOR"'
expect c11_url_package            FAIL 'add_project_line "  Foo:" "$PACKAGES_ANCHOR"; add_project_line "    url: https://example.com/foo.git" "  Foo:"'
expect c13_UIPasteboard           FAIL 'printf "import UIKit\nlet p = UIPasteboard.general\n" > App/Evil.swift'
expect c15_kvc_network            FAIL 'printf "import Photos\nfunc f(o: PHImageRequestOptions) { o.setValue(true, forKey: \"networkAccessAllowed\") }\n" > App/Evil.swift'
expect c18_widget_target          FAIL 'perl -0pi -e "s/\nschemes:/\n  Widget:\n    type: app-extension\n    sources:\n      - path: Widget\nschemes:/" project.yml'
expect c19_sdk_dependency         FAIL 'add_project_line "      - sdk: Network.framework" "$DEPENDENCY_ANCHOR"'
expect c20_framework_dependency   FAIL 'add_project_line "      - framework: Vendor.xcframework" "$DEPENDENCY_ANCHOR"'
expect c21_model_file             FAIL 'mkdir -p App/Models && printf x > App/Models/Clf.mlmodelc'
expect c29_import_AVKit_allowed   PASS 'printf "import AVKit\nimport AVFoundation\n" > App/Playback.swift'
expect c30_AVURLAsset            FAIL 'printf "import AVFoundation\nlet a = AVURLAsset(url: u)\n" > App/Evil.swift'
expect c32_AVAsset_url           FAIL 'printf "import AVFoundation\nlet a = AVAsset(url: u)\n" > App/Evil.swift'
expect c33_AVPlayerItem_asset    FAIL 'printf "import AVFoundation\nlet i = AVPlayerItem( asset: a)\n" > App/Evil.swift'
expect c31_AVPlayer_url          FAIL 'printf "import AVKit\nlet p = AVPlayer(url: u)\n" > App/Evil.swift'
expect c6_URL_init_split_literal  PASS 'printf "import Foundation\nlet u = URL.init(string: \"ht\" + \"tps://example.com\")\n" > App/Evil.swift' known-gap
expect c22_second_import_after_semicolon FAIL 'printf "import Foundation; import MapKit\n" > App/Evil.swift'
expect c23_import_after_comment   FAIL 'printf "/* x */ import MapKit\n" > App/Evil.swift'
expect c24_dlsym                  FAIL 'printf "import Foundation\nlet p = dlsym(nil, \"connect\")\n" > App/Evil.swift'
expect c25_getStreamsToHost       FAIL 'printf "import Foundation\nfunc f() { Stream.getStreamsToHost(withName: \"h\", port: 1, inputStream: nil, outputStream: nil) }\n" > App/Evil.swift'
expect c26_flow_style_url_package FAIL 'add_project_line "  Foo: {url: \"https://example.com/foo.git\", from: 1.0.0}" "$PACKAGES_ANCHOR"'
expect c27_quoted_key             FAIL 'add_project_line "      - \"github\": someone/somepkg" "$DEPENDENCY_ANCHOR"'
expect c28_flow_sources_path      FAIL 'add_project_line "    sources: [{path: ../evil}]" "    platform: iOS"'

# Built-app check: fixture bundles with a binary built by swiftc, asserted by exit code.
FIXTURES="$TMP/fixtures"
mkdir -p "$FIXTURES"

build_fixture() {
  local name="$1" source="$2"
  mkdir -p "$FIXTURES/$name.app"
  printf '%s\n' "$source" > "$FIXTURES/$name.swift"
  if ! swiftc -O -parse-as-library -emit-library "$FIXTURES/$name.swift" -o "$FIXTURES/$name.app/Stilltrim" >/dev/null 2>&1; then
    echo "FAIL  could not build fixture $name with swiftc"
    surprises=$((surprises + 1))
  fi
}

# expect_app <name> <expected exit code> <app folder>
expect_app() {
  local name="$1" expected="$2" app="$3" actual
  cases=$((cases + 1))
  "$SRC/scripts/check-built-app.sh" "$app" >/dev/null 2>&1
  actual=$?
  if [ "$actual" = "$expected" ]; then
    echo "PASS  $name (check-built-app exit $actual, expected $expected)"
  else
    echo "FAIL  $name (check-built-app exit $actual, expected $expected)"
    surprises=$((surprises + 1))
  fi
}

build_fixture clean 'import Foundation
public func f() -> Int { "a".count }'
build_fixture socket 'import Foundation
public func f() -> Int32 { socket(AF_INET, SOCK_STREAM, 0) }'
build_fixture cfnetwork 'import Foundation
public func f() -> AnyObject { URLSession.shared }'
build_fixture avkit 'import AVKit
public func f() -> AnyObject { AVPlayerView() }'
build_fixture avurl 'import AVFoundation
public func f() -> AnyObject { AVURLAsset(url: URL(fileURLWithPath: "/x")) }'
build_fixture avasset 'import AVFoundation
public func f() -> AnyObject { AVAsset(url: URL(fileURLWithPath: "/x")) }'
build_fixture outside 'import MapKit
public func f() -> AnyObject { MKMapView() }'

cp -R "$FIXTURES/clean.app" "$FIXTURES/unreadable.app"
printf 'not a binary' > "$FIXTURES/unreadable.app/Stilltrim"
cp -R "$FIXTURES/clean.app" "$FIXTURES/embedded.app"
mkdir -p "$FIXTURES/embedded.app/Frameworks/Vendor.framework"

expect_app b1_clean_app_passes          0 "$FIXTURES/clean.app"
expect_app b2_socket_symbol             1 "$FIXTURES/socket.app"
expect_app b3_links_CFNetwork           1 "$FIXTURES/cfnetwork.app"
expect_app b8_links_AVKit_passes        0 "$FIXTURES/avkit.app"
expect_app b9_AVURLAsset_symbol       1 "$FIXTURES/avurl.app"
expect_app b10_AVAsset_symbol         1 "$FIXTURES/avasset.app"
expect_app b4_library_outside_allowlist 1 "$FIXTURES/outside.app"
expect_app b5_unreadable_binary         1 "$FIXTURES/unreadable.app"
expect_app b6_embedded_frameworks       1 "$FIXTURES/embedded.app"
expect_app b7_missing_app               1 "$FIXTURES/nothing.app"

echo
if [ "$surprises" -eq 0 ]; then
  echo "tripwire self-test: $cases cases, all as expected"
else
  echo "tripwire self-test: $surprises of $cases cases surprised"
fi
[ "$surprises" -eq 0 ]
