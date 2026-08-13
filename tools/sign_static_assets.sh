#!/usr/bin/env bash
# Sign a hashed static-assets manifest with Ed25519 (OpenSSL 3.x).
#
# STATIC_ASSETS_PRIVATE_KEY must be JSON:
#   {"keyId":"models-k1","privateKey":"-----BEGIN PRIVATE KEY-----\\n...\\n-----END PRIVATE KEY-----\\n"}
#
# Usage:
#   export STATIC_ASSETS_PRIVATE_KEY='{"keyId":"models-k1","privateKey":"..."}'
#   ./tools/sign_static_assets.sh \
#     /tmp/static-assets.filled.json \
#     .well-known/static-assets.json
#
# Signed payload (UTF-8 bytes, no trailing newline):
#   scomm-static-assets-v1\0<signatureKeyId>\0<manifestSha256>
#
# manifestSha256 is lowercase hex SHA-256 of the canonical unsigned manifest JSON
# (sorted keys, models sorted by id, signature fields removed).
set -euo pipefail

MANIFEST_IN="${1:?source manifest path}"
MANIFEST_OUT="${2:?signed manifest output path}"

if [[ -z "${STATIC_ASSETS_PRIVATE_KEY:-}" ]]; then
  echo "Missing STATIC_ASSETS_PRIVATE_KEY env var" >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "OpenSSL 3.x is required" >&2
  exit 1
fi

KEY_FILE="$(mktemp)"
SIGN_INPUT="$(mktemp)"
cleanup() { rm -f "$KEY_FILE" "$SIGN_INPUT"; }
trap cleanup EXIT

KEY_ID="$(
  python3 - "$KEY_FILE" <<'PY'
import json
import os
import sys
from pathlib import Path

raw = os.environ.get("STATIC_ASSETS_PRIVATE_KEY", "").strip()
try:
    data = json.loads(raw)
except json.JSONDecodeError as exc:
    raise SystemExit(
        "STATIC_ASSETS_PRIVATE_KEY must be JSON with keyId and privateKey: "
        f"{exc}"
    ) from exc

if not isinstance(data, dict):
    raise SystemExit("STATIC_ASSETS_PRIVATE_KEY JSON must be an object")

key_id = data.get("keyId")
pem = data.get("privateKey")
if not isinstance(key_id, str) or not key_id.strip():
    raise SystemExit("STATIC_ASSETS_PRIVATE_KEY.keyId must be a non-empty string")
if not isinstance(pem, str) or "BEGIN" not in pem:
    raise SystemExit("STATIC_ASSETS_PRIVATE_KEY.privateKey must be a PEM string")

pem = pem.replace("\\n", "\n").strip() + "\n"
Path(sys.argv[1]).write_text(pem, encoding="utf-8")
print(key_id.strip())
PY
)"

manifest_sha="$(python3 - "$MANIFEST_IN" "$SIGN_INPUT" "$KEY_ID" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
sign_input_path = Path(sys.argv[2])
key_id = sys.argv[3]

data = json.loads(manifest_path.read_text(encoding="utf-8"))
for field in ("signatureKeyId", "signatureAlgorithm", "signature"):
    data.pop(field, None)

models = data.get("models")
if not isinstance(models, list):
    raise SystemExit("models must be an array")
data["models"] = sorted(models, key=lambda item: item["id"])

canonical = json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
manifest_sha = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
payload = f"scomm-static-assets-v1\x00{key_id}\x00{manifest_sha}".encode("utf-8")
sign_input_path.write_bytes(payload)
print(manifest_sha)
PY
)"

signature_b64="$(
  openssl pkeyutl -sign -inkey "$KEY_FILE" -rawin -in "$SIGN_INPUT" | openssl base64 -A
)"

python3 - "$MANIFEST_IN" "$MANIFEST_OUT" "$KEY_ID" "$signature_b64" <<'PY'
import json
import sys
from pathlib import Path

manifest_in = Path(sys.argv[1])
manifest_out = Path(sys.argv[2])
key_id = sys.argv[3]
signature_b64 = sys.argv[4]

data = json.loads(manifest_in.read_text(encoding="utf-8"))
for field in ("signatureKeyId", "signatureAlgorithm", "signature"):
    data.pop(field, None)

data["signatureKeyId"] = key_id
data["signatureAlgorithm"] = "Ed25519"
data["signature"] = signature_b64

manifest_out.parent.mkdir(parents=True, exist_ok=True)
manifest_out.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

echo "Signed $MANIFEST_OUT with key $KEY_ID (manifestSha256=$manifest_sha)"
