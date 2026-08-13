#!/usr/bin/env python3
"""Validate the source static-assets / models manifest (pre-hash, pre-sign).

SHA-256 and byte sizes are computed by CI after downloading each URL, so they
are optional in the source file.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SUPPORTED_FORMAT_VERSION = 1
PLACEHOLDER_SIGNATURES = {
    "",
    "REPLACE_BY_CI_AFTER_SIGNING",
    "PLACEHOLDER_SIGNED_BY_CI",
}


def _fail(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)
    raise SystemExit(1)


def validate_manifest(path: Path) -> None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        _fail(f"Invalid JSON in {path}: {exc}")

    if not isinstance(data, dict):
        _fail("Manifest root must be a JSON object")

    format_version = data.get("formatVersion")
    if format_version != SUPPORTED_FORMAT_VERSION:
        _fail(f"Unsupported formatVersion: {format_version!r}")

    manifest_version = data.get("manifestVersion")
    if not isinstance(manifest_version, str) or not manifest_version.strip():
        _fail("manifestVersion must be a non-empty string")

    updated_at = data.get("updated_at")
    if updated_at is not None and (
        not isinstance(updated_at, str) or not updated_at.strip()
    ):
        _fail("updated_at must be a non-empty string when present")

    key_id = data.get("signatureKeyId")
    if key_id is not None and (not isinstance(key_id, str) or not key_id.strip()):
        _fail("signatureKeyId must be a non-empty string when present")

    algorithm = data.get("signatureAlgorithm")
    if algorithm is not None and algorithm != "Ed25519":
        _fail(f"Unsupported signatureAlgorithm: {algorithm!r}")

    signature = data.get("signature")
    if signature is not None:
        if not isinstance(signature, str):
            _fail("signature must be a string when present")
        if signature not in PLACEHOLDER_SIGNATURES and len(signature) < 64:
            _fail(
                "signature in source must be a CI placeholder "
                f"(got {signature!r})"
            )

    models = data.get("models")
    if not isinstance(models, list) or not models:
        _fail("models must be a non-empty array")

    seen_ids: set[str] = set()
    for index, model in enumerate(models):
        if not isinstance(model, dict):
            _fail(f"models[{index}] must be an object")

        model_id = model.get("id")
        if not isinstance(model_id, str) or not model_id.strip():
            _fail(f"models[{index}].id must be a non-empty string")
        if model_id in seen_ids:
            _fail(f"Duplicate model id: {model_id}")
        seen_ids.add(model_id)

        kind = model.get("kind")
        if not isinstance(kind, str) or not kind.strip():
            _fail(f"models[{index}].kind must be a non-empty string")

        filename = model.get("filename")
        if not isinstance(filename, str) or not filename.strip():
            _fail(f"models[{index}].filename must be a non-empty string")

        url = model.get("url")
        if not isinstance(url, str) or not url.startswith(("http://", "https://")):
            _fail(f"models[{index}].url must be an absolute http(s) URL")

        sha256 = model.get("sha256")
        if sha256 is not None and (
            not isinstance(sha256, str) or not SHA256_RE.fullmatch(sha256.lower())
        ):
            _fail(
                f"models[{index}].sha256 must be omitted or a 64-char lowercase hex string"
            )

        bytes_value = model.get("bytes")
        if bytes_value is not None and (
            not isinstance(bytes_value, int)
            or isinstance(bytes_value, bool)
            or bytes_value < 1
        ):
            _fail(f"models[{index}].bytes must be omitted or a positive integer")

    print(f"[OK] Valid static-assets manifest: {path}")


def main() -> None:
    if len(sys.argv) != 2:
        _fail(f"Usage: {Path(sys.argv[0]).name} <manifest.json>")
    validate_manifest(Path(sys.argv[1]))


if __name__ == "__main__":
    main()
