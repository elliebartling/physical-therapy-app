#!/bin/sh
# Regenerates catalog.json from the upstream workout-guide manifest.
# Run by hand when upstream changes; the output is committed.
# Usage: ./generate-catalog.sh   (from any directory)
set -eu

URL="https://cdn.jsdelivr.net/npm/@bryllim/workout-guide@1.0.0/manifest.json"
OUT="$(cd "$(dirname "$0")" && pwd)/catalog.json"

curl -fsSL "$URL" | python3 -I -c '
import json, sys

KEEP = {
    "Bodyweight", "Resistance Band", "Wall", "Towel",
    "Doorway", "Chair", "Box", "Stability Ball",
}
FIELDS = ("slug", "name", "equipment", "primaryMuscle", "secondaryMuscles", "isStretch")

manifest = json.load(sys.stdin)
entries = [{k: e[k] for k in FIELDS} for e in manifest if e["equipment"] in KEEP]
json.dump(entries, sys.stdout, indent=2, ensure_ascii=False)
sys.stdout.write("\n")
' > "$OUT.tmp"

mv "$OUT.tmp" "$OUT"
echo "Wrote $OUT"
