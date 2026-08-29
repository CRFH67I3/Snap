#!/bin/zsh
# Verifies the stitching engine against synthetic screenshots with known scroll
# offsets. Runs on the Mac — no device or simulator needed — because the engine
# depends only on CoreGraphics and Foundation.
#
#   ./Tools/StitchTest/run.sh
#
# Exits non-zero if any check fails.

set -e
cd "$(dirname "$0")"

SRC="../../Snap/Stitching"
OUT="$(mktemp -d)"

swiftc -O -o "$OUT/stitchtest" \
  main.swift \
  "$SRC/FrameBitmap.swift" \
  "$SRC/StickyRegionDetector.swift" \
  "$SRC/OverlapMatcher.swift" \
  "$SRC/StitchPlan.swift" \
  "$SRC/StitchRenderer.swift"

"$OUT/stitchtest"
