#!/usr/bin/env bash
# Validate the source catalog, download every model URL, fill SHA-256/size,
# and optionally sign the result.
#
# Usage:
#   ./tools/publish_static_assets.sh           # hash + sign (requires STATIC_ASSETS_PRIVATE_KEY JSON)
#   SIGN=0 ./tools/publish_static_assets.sh    # hash only (PRs / local check)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/static-assets.manifest.json"
OUT="$ROOT/.well-known/static-assets.json"
SIGN="${SIGN:-1}"
FILLED="$(mktemp)"
cleanup() { rm -f "$FILLED"; }
trap cleanup EXIT

if [[ ! -f "$SRC" ]]; then
  echo "Missing source manifest: $SRC" >&2
  exit 1
fi

python3 "$ROOT/tools/validate_static_assets_manifest.py" "$SRC"
python3 "$ROOT/tools/fill_static_assets_hashes.py" "$SRC" "$FILLED" "$OUT"

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
"$ROOT/tools/sign_static_assets.sh" "$FILLED" "$OUT"
echo "Published signed catalog to $OUT"
