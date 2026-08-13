# scomm.ai version catalog

Public JSON endpoints for **scomm.ai** product versions and the signed on-device model catalog.

GitHub Pages serves **`docs/`** from `main` at [https://version.scomm.ai](https://version.scomm.ai).

PRs edit source files at the repo root. After merge to `main`, CI downloads each model URL, fills SHA-256, signs the catalog, and publishes the tree under `docs/`.

## Live endpoints

| Resource | URL |
| --- | --- |
| Latest app versions | https://version.scomm.ai/index.json |
| Signed static-assets catalog | https://version.scomm.ai/.well-known/static-assets.json |

Clients should fetch the **signed** catalog, not the source manifest.

## Files

| Path | Role |
| --- | --- |
| `index.json` | Source: latest version numbers per product and platform |
| `CNAME` | Source: custom domain `version.scomm.ai` |
| `static-assets.manifest.json` | Source catalog: model id, kind, filename, and download URL. Do not put SHA-256 or sizes here. |
| `docs/` | Published site. Do not edit by hand; CI overwrites it. |
| `docs/index.json` | Published versions file |
| `docs/.well-known/static-assets.json` | Published catalog with CI-computed `sha256` / `bytes` and Ed25519 signature |

## Updating the model catalog

1. Edit `static-assets.manifest.json` (add/change `id`, `kind`, `filename`, `url`).
2. Leave `sha256`, `bytes`, and `signature` to CI.
3. Open a pull request. CI downloads every URL and checks that hashing succeeds.
4. After merge to `main`, CI hashes again, signs, copies `index.json` / `CNAME`, and commits `docs/`.

Version-only changes: edit `index.json` in a PR. Merge to `main` and CI copies it into `docs/`.

## Signing secret

The `STATIC_ASSETS_PRIVATE_KEY` Actions secret is a single JSON object:

```json
{
  "keyId": "models-k1",
  "privateKey": "-----BEGIN PRIVATE KEY-----\\n...\\n-----END PRIVATE KEY-----\\n"
}
```

The signed payload is:

```text
scomm-static-assets-v1\0<signatureKeyId>\0<manifestSha256>
```

`manifestSha256` is the SHA-256 of the canonical unsigned JSON (sorted keys, models sorted by `id`, signature fields removed).
