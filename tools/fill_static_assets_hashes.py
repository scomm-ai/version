#!/usr/bin/env python3
"""Download each model URL, compute SHA-256 and size, write a filled manifest.

Source hashes/sizes are ignored. CI is the source of truth so humans cannot
accidentally publish a mismatched digest.
"""

from __future__ import annotations

import json
import hashlib
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

USER_AGENT = "scomm-ai-version-ci/1.0"
CHUNK_SIZE = 1024 * 1024
PROGRESS_EVERY_BYTES = 16 * 1024 * 1024
RETRIES = 3
TIMEOUT_SECONDS = 120


def _fail(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)
    raise SystemExit(1)


def _download_sha256(url: str) -> tuple[str, int]:
    last_error: Exception | None = None
    for attempt in range(1, RETRIES + 1):
        try:
            request = urllib.request.Request(
                url,
                headers={"User-Agent": USER_AGENT, "Accept": "*/*"},
            )
            digest = hashlib.sha256()
            size = 0
            last_progress = 0
            with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
                content_type = (response.headers.get("Content-Type") or "").lower()
                if "text/html" in content_type:
                    raise RuntimeError(
                        f"unexpected HTML response from {url} ({content_type})"
                    )
                while True:
                    chunk = response.read(CHUNK_SIZE)
                    if not chunk:
                        break
                    digest.update(chunk)
                    size += len(chunk)
                    if size - last_progress >= PROGRESS_EVERY_BYTES:
                        print(f"  ... {size / (1024 * 1024):.1f} MiB", flush=True)
                        last_progress = size
            if size < 1:
                raise RuntimeError(f"downloaded 0 bytes from {url}")
            return digest.hexdigest(), size
        except (urllib.error.URLError, TimeoutError, RuntimeError, OSError) as exc:
            last_error = exc
            print(
                f"  download attempt {attempt}/{RETRIES} failed: {exc}",
                file=sys.stderr,
                flush=True,
            )
            if attempt < RETRIES:
                time.sleep(2 ** attempt)
    _fail(f"Failed to download {url}: {last_error}")


def _previous_digests(previous_path: Path | None) -> tuple[dict[str, tuple[str, int]], str | None]:
    if previous_path is None or not previous_path.is_file():
        return {}, None
    try:
        previous = json.loads(previous_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}, None
    models = previous.get("models")
    if not isinstance(models, list):
        return {}, None
    digests: dict[str, tuple[str, int]] = {}
    for model in models:
        if not isinstance(model, dict):
            continue
        model_id = model.get("id")
        sha256 = model.get("sha256")
        size = model.get("bytes")
        if isinstance(model_id, str) and isinstance(sha256, str) and isinstance(size, int):
            digests[model_id] = (sha256, size)
    updated_at = previous.get("updated_at")
    if not isinstance(updated_at, str) or not updated_at.strip():
        updated_at = None
    return digests, updated_at


def fill_manifest(
    source_path: Path, output_path: Path, previous_path: Path | None = None
) -> None:
    try:
        data = json.loads(source_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        _fail(f"Invalid JSON in {source_path}: {exc}")

    models = data.get("models")
    if not isinstance(models, list) or not models:
        _fail("models must be a non-empty array")

    previous_digests, previous_updated_at = _previous_digests(previous_path)

    print(f"Hashing {len(models)} asset(s) from {source_path}")
    for index, model in enumerate(models):
        if not isinstance(model, dict):
            _fail(f"models[{index}] must be an object")
        model_id = model.get("id", f"index-{index}")
        url = model.get("url")
        if not isinstance(url, str):
            _fail(f"models[{index}].url must be a string")
        print(f"[{index + 1}/{len(models)}] {model_id}")
        print(f"  GET {url}", flush=True)
        sha256, size = _download_sha256(url)
        model["sha256"] = sha256
        model["bytes"] = size
        print(f"  sha256={sha256}")
        print(f"  bytes={size}", flush=True)

    current_digests = {
        model["id"]: (model["sha256"], model["bytes"]) for model in models
    }
    if previous_digests == current_digests and previous_updated_at:
        data["updated_at"] = previous_updated_at
        print("Asset digests unchanged; keeping previous updated_at")
    else:
        data["updated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"[OK] Wrote hashed manifest: {output_path}")


def main() -> None:
    if len(sys.argv) not in (3, 4):
        _fail(
            f"Usage: {Path(sys.argv[0]).name} "
            "<source-manifest.json> <output.json> [previous-signed.json]"
        )
    previous = Path(sys.argv[3]) if len(sys.argv) == 4 else None
    fill_manifest(Path(sys.argv[1]), Path(sys.argv[2]), previous)


if __name__ == "__main__":
    main()
