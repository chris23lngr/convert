#!/bin/bash
# Conversion smoke test: generates small sample files and converts each one to
# every output format the app offers for it, using the app's --cli mode.
#
#   scripts/smoke-test.sh [--strict] [--out DIR] [--keep] [BINARY]
#
#   BINARY    the Convert executable (default: build/Convert.app/Contents/MacOS/Convert;
#             run ./build.sh first, or use `scripts/check.sh smoke`, which builds for you)
#   --strict  missing ffmpeg/ffprobe/cwebp is a failure (CI uses this). Without it,
#             formats that need a missing tool are reported as SKIP.
#   --out DIR keep samples, outputs and per-conversion logs in DIR (default: a temp folder,
#             deleted afterwards unless something failed or --keep is given)
#
# A conversion passes when the app exits 0, prints no FAIL line, and writes at least one
# non-empty file. Each conversion gets $SMOKE_TIMEOUT seconds (default 120).
#
# Formats with a hardware encoder (H.264, HEVC, ProRes, MKV) also run with hardware
# encoding off. The hardware runs are skipped when this machine has no such encoder
# (e.g. GitHub's macOS VMs); the software runs must always pass.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

STRICT=0 KEEP=0 OUT="" BIN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) STRICT=1 ;;
    --keep) KEEP=1 ;;
    --out) OUT="${2:?--out needs a directory}"; shift ;;
    -h|--help) sed -n '2,/^set /p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) BIN="$1" ;;
  esac
  shift
done
BIN="${BIN:-build/Convert.app/Contents/MacOS/Convert}"
TIMEOUT="${SMOKE_TIMEOUT:-120}"
HW_TARGETS=" mp4-h264 mkv mp4-hevc mov-prores "

if [[ ! -x "$BIN" ]]; then
  echo "No Convert binary at $BIN. Run ./build.sh first (or scripts/check.sh smoke)." >&2
  exit 2
fi
BIN="$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")"

if [[ -z "$OUT" ]]; then
  OUT="$(mktemp -d "${TMPDIR:-/tmp}/convert-smoke.XXXXXX")"
else
  rm -rf "$OUT" && mkdir -p "$OUT"
fi
OUT="$(cd "$OUT" && pwd)"
SAMPLES="$OUT/samples" RUNS="$OUT/runs"
mkdir -p "$SAMPLES" "$RUNS"

PASSED=0 SKIPPED=0 FAILURES="" COVERED=" "

# The app looks for its tools in these folders (see Tools in Process.swift), not on $PATH.
tool() {
  local d
  for d in /opt/homebrew/bin /usr/local/bin /usr/bin; do
    [[ -x "$d/$1" ]] && { echo "$d/$1"; return 0; }
  done
  return 1
}
FFMPEG="$(tool ffmpeg || true)"
FFPROBE="$(tool ffprobe || true)"
CWEBP="$(tool cwebp || true)"

pass() { PASSED=$((PASSED + 1)); printf 'PASS  %-14s %-11s %s\n' "$1" "$2" "$3"; }
skip() { SKIPPED=$((SKIPPED + 1)); printf 'SKIP  %-14s %-11s %s\n' "$1" "$2" "$3"; }
fail() {
  FAILURES="$FAILURES$(printf '%-14s %-11s %s' "$1" "$2" "$3")"$'\n'
  printf 'FAIL  %-14s %-11s %s\n' "$1" "$2" "$3"
}

# run_conversion <label> <target> <sample file> [settings JSON]
run_conversion() {
  local label="$1" target="$2" sample="$3" settings="${4:-}"
  local base dir input log status
  base="$(basename "$sample")"
  dir="$RUNS/$base-$label"
  mkdir -p "$dir" && cp "$sample" "$dir/"
  input="$dir/$base" log="$dir/output.log"
  # macOS has no `timeout`; perl's alarm kills the app if a conversion hangs.
  if [[ -n "$settings" ]]; then
    CONVERT_SETTINGS="$settings" perl -e 'alarm shift; exec @ARGV' "$TIMEOUT" "$BIN" --cli "$target" "$input" >"$log" 2>&1
  else
    perl -e 'alarm shift; exec @ARGV' "$TIMEOUT" "$BIN" --cli "$target" "$input" >"$log" 2>&1
  fi
  status=$?
  local outputs
  outputs="$(find "$dir" -type f -size +0 ! -name output.log ! -path "$input" | wc -l | tr -d ' ')"
  if [[ $status -eq 142 ]]; then
    fail "$label" "$(basename "$sample")" "timed out after ${TIMEOUT}s"
  elif grep -q '^FAIL' "$log" || [[ $status -ne 0 ]]; then
    fail "$label" "$(basename "$sample")" "$(grep -m1 '^FAIL' "$log" || tail -n1 "$log") (exit $status)"
  elif [[ "$outputs" -eq 0 ]]; then
    fail "$label" "$(basename "$sample")" "no output file written"
  else
    pass "$label" "$(basename "$sample")" "$(sed -n 's/^OK *//p' "$log" | head -n1)"
  fi
}

# Whether ffmpeg can use this encoder here (hardware encoders are missing on most VMs).
encoder_works() {
  "$FFMPEG" -v error -f lavfi -i testsrc2=size=320x240:rate=30:duration=0.5 -c:v "$1" -f null - >/dev/null 2>&1
}

hw_encoder_for() {
  case "$1" in
    mp4-h264|mkv) echo h264_videotoolbox ;;
    mp4-hevc) echo hevc_videotoolbox ;;
    mov-prores) echo prores_videotoolbox ;;
  esac
}

echo "Convert smoke test"
echo "  app:     $BIN"
echo "  ffmpeg:  ${FFMPEG:-not installed}"
echo "  cwebp:   ${CWEBP:-not installed}"
echo "  output:  $OUT"
echo

# --- Tools ---------------------------------------------------------------------------

ALL_TARGETS="$("$BIN" --cli 2>&1 | sed -n 's/^targets: //p')"
if [[ -z "$ALL_TARGETS" ]]; then
  echo "Couldn't read the target list from '$BIN --cli'." >&2
  exit 1
fi

if [[ -z "$FFMPEG" || -z "$FFPROBE" ]]; then
  if [[ $STRICT -eq 1 ]]; then
    fail "ffmpeg" "-" "ffmpeg/ffprobe not installed (brew install ffmpeg)"
  else
    echo "Note: ffmpeg isn't installed, so audio and video formats are skipped (brew install ffmpeg)."
  fi
fi
if [[ " $ALL_TARGETS " != *" webp "* ]]; then
  # The app only offers WebP when cwebp is installed.
  if [[ $STRICT -eq 1 ]]; then
    fail "webp" "-" "WebP isn't offered: cwebp not installed (brew install webp)"
  else
    skip "webp" "-" "cwebp not installed (brew install webp)"
  fi
  COVERED="$COVERED webp "
fi

# --- Samples (generated, nothing committed) -------------------------------------------

cat >"$SAMPLES/sample.md" <<'EOF'
# Smoke test

Some **bold**, *italic* and `code`, plus a [link](https://example.com).

1. First
2. Second
   - nested item

- [x] done
- [ ] open

| Format | Engine |
|--------|--------|
| PDF    | AppKit |

> A quote.

```swift
print("hello")
```
EOF

cat >"$SAMPLES/sample.txt" <<'EOF'
Smoke test

Plain text with some accents: café, naïve, Zürich.
A second paragraph.
EOF

# The PDF comes from the app itself (Markdown → PDF), so it has real, extractable text.
# If that fails, every PDF format is reported as failed below.
mkdir -p "$OUT/pdf-sample"
cp "$SAMPLES/sample.md" "$OUT/pdf-sample/"
if perl -e 'alarm shift; exec @ARGV' "$TIMEOUT" "$BIN" --cli pdf-doc "$OUT/pdf-sample/sample.md" >"$OUT/pdf-sample/output.log" 2>&1 \
  && [[ -s "$OUT/pdf-sample/sample.pdf" ]]; then
  cp "$OUT/pdf-sample/sample.pdf" "$SAMPLES/sample.pdf"
fi

if [[ -n "$FFMPEG" ]]; then
  ff() { "$FFMPEG" -v error -y "$@"; }
  # Hi-res stereo WAV: 24-bit, 96 kHz.
  ff -f lavfi -i "sine=frequency=440:sample_rate=96000:duration=2" -ac 2 -c:a pcm_s24le "$SAMPLES/sample.wav"
  # Short video with a soundtrack.
  ff -f lavfi -i "testsrc2=size=320x240:rate=30:duration=2" -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=2" \
    -c:v mpeg4 -q:v 5 -pix_fmt yuv420p -c:a aac -shortest "$SAMPLES/sample.mp4"
  ff -f lavfi -i "testsrc2=size=320x240" -frames:v 1 "$SAMPLES/sample.png"
elif [[ -f "$SAMPLES/sample.pdf" ]]; then
  sips -s format png "$SAMPLES/sample.pdf" --out "$SAMPLES/sample.png" >/dev/null
fi

# --- Hardware encoders ----------------------------------------------------------------

HW_OK=" "
if [[ -n "$FFMPEG" ]]; then
  for enc in h264_videotoolbox hevc_videotoolbox prores_videotoolbox; do
    if encoder_works "$enc"; then HW_OK="$HW_OK$enc "; fi
  done
  echo "Hardware encoders available:${HW_OK% }"
  echo
fi

# --- Conversions ----------------------------------------------------------------------

for name in sample.mp4 sample.wav sample.png sample.md sample.txt sample.pdf; do
  sample="$SAMPLES/$name"
  # Ask the app which formats it offers for this kind of file (same logic as the window).
  probe="$OUT/probe/$name"
  mkdir -p "$OUT/probe" && : >"$probe"
  targets="$("$BIN" --cli --targets "$probe")" || {
    fail "-" "$name" "app doesn't recognise this file type: $targets"
    continue
  }

  for target in $targets; do
    COVERED="$COVERED$target "
    if [[ ! -f "$sample" ]]; then
      if [[ -z "$FFMPEG" && $name != sample.md && $name != sample.txt && $name != sample.pdf && $STRICT -eq 0 ]]; then
        skip "$target" "$name" "ffmpeg not installed"
      else
        fail "$target" "$name" "sample couldn't be created (see $OUT/pdf-sample/output.log)"
      fi
      continue
    fi

    if [[ "$HW_TARGETS" == *" $target "* ]]; then
      if [[ "$HW_OK" == *" $(hw_encoder_for "$target") "* ]]; then
        run_conversion "$target" "$target" "$sample"
      else
        skip "$target" "$name" "no $(hw_encoder_for "$target") on this machine; software run below"
      fi
      run_conversion "$target+sw" "$target" "$sample" '{"hardware": false}'
    else
      run_conversion "$target" "$target" "$sample"
    fi
  done
done

# Every format the app lists must have been tried by at least one sample.
for target in $ALL_TARGETS; do
  if [[ "$COVERED" != *" $target "* ]]; then
    fail "$target" "-" "no sample covers this format; add one to scripts/smoke-test.sh"
  fi
done

# --- Summary --------------------------------------------------------------------------

FAILED=$(printf '%s' "$FAILURES" | grep -c . || true)
echo
echo "$PASSED passed, $FAILED failed, $SKIPPED skipped"
if [[ $FAILED -gt 0 ]]; then
  echo
  echo "Failed formats:"
  printf '%s' "$FAILURES" | sed 's/^/  /'
  echo
  echo "Samples, outputs and logs: $OUT"
  exit 1
fi
if [[ $KEEP -eq 0 ]]; then rm -rf "$OUT"; fi
exit 0
