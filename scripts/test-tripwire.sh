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
expect c6_URL_init_split_literal  PASS 'printf "import Foundation\nlet u = URL.init(string: \"ht\" + \"tps://example.com\")\n" > App/Evil.swift' known-gap

echo
if [ "$surprises" -eq 0 ]; then
  echo "tripwire self-test: $cases cases, all as expected"
else
  echo "tripwire self-test: $surprises of $cases cases surprised"
fi
[ "$surprises" -eq 0 ]
