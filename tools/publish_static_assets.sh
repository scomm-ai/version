#!/usr/bin/env bash
# Validate the source catalog, assemble docs/, and optionally download,
# hash, and sign the model catalog.
#
# Source (repo root): index.json, CNAME, static-assets.manifest.json
# Output (docs/):     GitHub Pages tree (/docs)
#
# Usage:
#   ASSEMBLE=1 SIGN=1 ./tools/publish_static_assets.sh
#   SIGN=0 ./tools/publish_static_assets.sh              # PR check: hash only
#   ASSEMBLE=1 HASH=0 SIGN=0 ./tools/publish_static_assets.sh  # copy index.json only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/static-assets.manifest.json"
OUT="$ROOT/docs"
SIGNED="$OUT/.well-known/static-assets.json"
SIGN="${SIGN:-1}"
ASSEMBLE="${ASSEMBLE:-0}"
if [[ "$SIGN" == "1" ]]; then
  HASH="${HASH:-1}"
  ASSEMBLE=1
else
  HASH="${HASH:-1}"
fi

FILLED="$(mktemp)"
cleanup() { rm -f "$FILLED"; }
trap cleanup EXIT

if [[ ! -f "$SRC" ]]; then
  echo "Missing source manifest: $SRC" >&2
  exit 1
fi
if [[ ! -f "$ROOT/index.json" ]]; then
  echo "Missing source versions file: $ROOT/index.json" >&2
  exit 1
fi
if [[ ! -f "$ROOT/CNAME" ]]; then
  echo "Missing source CNAME: $ROOT/CNAME" >&2
  exit 1
fi

python3 "$ROOT/tools/validate_static_assets_manifest.py" "$SRC"
python3 -m json.tool "$ROOT/index.json" >/dev/null

if [[ "$ASSEMBLE" == "1" ]]; then
  mkdir -p "$OUT/.well-known"
  cp "$ROOT/index.json" "$OUT/index.json"
  cp "$ROOT/CNAME" "$OUT/CNAME"
  : > "$OUT/.nojekyll"
  echo "Assembled Pages tree at $OUT"
fi

if [[ "$HASH" == "1" ]]; then
  python3 "$ROOT/tools/fill_static_assets_hashes.py" "$SRC" "$FILLED" "$SIGNED"

  if [[ "$SIGN" == "0" ]]; then
    echo "Skipping signing (SIGN=0). Computed catalog:"
    python3 - "$FILLED" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(f"updated_at={data.get('updated_at')}")
for model in data.get("models", []):
    print(f"{model['id']}: sha256={model['sha256']} bytes={model['bytes']}")
PY
    exit 0
  fi

  chmod +x "$ROOT/tools/sign_static_assets.sh"
  "$ROOT/tools/sign_static_assets.sh" "$FILLED" "$SIGNED"
  echo "Published signed catalog to $SIGNED"
  exit 0
fi

echo "Skipping download/hash (HASH=0)"
