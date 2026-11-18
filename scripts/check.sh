#!/bin/bash
# Runs the same checks as CI (.github/workflows/ci.yml).
#
#   scripts/check.sh                 everything: format, build, smoke, site
#   scripts/check.sh format [--fix]  swift-format lint (--fix reformats in place)
#   scripts/check.sh build           debug build + tests (warnings are errors), then the release app
#   scripts/check.sh smoke [--no-build] [smoke-test.sh options…]
#                                    rebuild the release app, then run scripts/smoke-test.sh
#   scripts/check.sh site            syntax-check the website's server functions
#
# With only the Command Line Tools installed (no Xcode), the universal app can't be built
# (that needs Xcode's build system), so build/smoke use a native release build instead.
# CI always builds and tests the universal app.
set -euo pipefail
cd "$(dirname "$0")/.."

SWIFT_FORMAT_VERSION="6.3"   # the one in Xcode 26.6, which CI uses
STEP="${1:-all}"
[[ $# -gt 0 ]] && shift

say() { printf '\n==> %s\n' "$*"; }

developer_dir() { echo "${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"; }
command_line_tools_only() { [[ "$(developer_dir)" == *CommandLineTools* ]]; }

# SwiftPM doesn't find Swift Testing inside the Command Line Tools on its own.
swift_test_flags() {
  local clt
  clt="$(developer_dir)/Library/Developer"
  if command_line_tools_only && [[ -d "$clt/Frameworks/Testing.framework" ]]; then
    echo "-Xswiftc -F -Xswiftc $clt/Frameworks -Xlinker -F -Xlinker $clt/Frameworks" \
      "-Xlinker -rpath -Xlinker $clt/Frameworks -Xlinker -rpath -Xlinker $clt/usr/lib"
  fi
}

check_format() {
  local fix=0
  [[ "${1:-}" == "--fix" ]] && fix=1
  local version
  version="$(xcrun swift-format --version)"
  if [[ "$version" != "$SWIFT_FORMAT_VERSION".* ]]; then
    echo "warning: swift-format $version here, CI uses $SWIFT_FORMAT_VERSION.x; results may differ." >&2
  fi
  if [[ $fix -eq 1 ]]; then
    say "swift-format format (in place)"
    git ls-files -z '*.swift' | xargs -0 xcrun swift-format format --configuration .swift-format --in-place
  else
    say "swift-format lint --strict"
    git ls-files -z '*.swift' | xargs -0 xcrun swift-format lint --configuration .swift-format --strict \
      || { echo "Formatting is off. Fix it with: scripts/check.sh format --fix" >&2; return 1; }
  fi
}

# The binary the smoke test runs.
release_binary() {
  if command_line_tools_only; then echo ".build/release/Convert"; else echo "build/Convert.app/Contents/MacOS/Convert"; fi
}

build_release_app() {
  if command_line_tools_only; then
    say "release build (native only: the universal app needs Xcode; CI builds it)"
    swift build -c release
  else
    say "./build.sh (universal release app)"
    ./build.sh
    local archs
    archs="$(lipo -archs build/Convert.app/Contents/MacOS/Convert)"
    if [[ " $archs " != *" arm64 "* || " $archs " != *" x86_64 "* ]]; then
      echo "Expected a universal binary (arm64 and x86_64), got: $archs" >&2
      return 1
    fi
  fi
  say "$(release_binary) --cli lists the formats"
  local list
  list="$("$(release_binary)" --cli || true)"
  echo "$list"
  [[ "$list" == *"targets: "*mp3* ]] || { echo "The app didn't list its formats." >&2; return 1; }
}

check_build() {
  say "swift build (warnings are errors)"
  swift build -Xswiftc -warnings-as-errors
  say "swift test (warnings are errors)"
  # shellcheck disable=SC2046 # the flags are meant to split into words
  swift test -Xswiftc -warnings-as-errors $(swift_test_flags)
  build_release_app
}

check_smoke() {
  local build=1 args=()
  for a in "$@"; do
    if [[ "$a" == "--no-build" ]]; then build=0; else args+=("$a"); fi
  done
  if [[ $build -eq 1 ]]; then build_release_app; fi
  say "smoke test"
  scripts/smoke-test.sh ${args[@]+"${args[@]}"} "$(release_binary)"
}

check_site() {
  say "node --check site/api/*.mjs"
  if ! command -v node >/dev/null; then
    echo "SKIP: node isn't installed (CI checks this)."
    return 0
  fi
  local f
  for f in site/api/*.mjs; do
    node --check "$f"
    echo "ok   $f"
  done
}

case "$STEP" in
  format) check_format "$@" ;;
  build) check_build ;;
  smoke) check_smoke "$@" ;;
  site) check_site ;;
  all)
    check_format
    check_build
    check_smoke --no-build
    check_site
    say "All checks passed"
    ;;
  -h|--help) sed -n '2,/^set /p' "$0" | sed '$d; s/^# \{0,1\}//' ;;
  *) echo "unknown step: $STEP (format, build, smoke, site, or nothing for all)" >&2; exit 2 ;;
esac
