# KubeClaw Image

This image extends the upstream OpenClaw image and bakes in KubeClaw-specific runtime tooling.

- Image name: `ghcr.io/imerica/kubeclaw`
- Build workflow: `.github/workflows/build-kubeclaw-image.yaml`
- Dockerfile: `images/kubeclaw/Dockerfile`
- Package manifest: `images/kubeclaw/packages.json`

## Package Manifest

All package declarations live in `images/kubeclaw/packages.json`:

- `linuxPackages`: OS packages installed in the final image (`apk` or `apt` depending on base image)
- `goPackages`: `go install` package specs installed into `/opt/kubeclaw/bin`
- `npmGlobalPackages`: npm packages installed into `/opt/kubeclaw/npm-global` with binaries linked into `/opt/kubeclaw/bin`
- `skillsSh`: verified script downloads executed during build (`url` + required `sha256`)
- `cli`: curated binary installers (`gh`, `jira`, `linear`, `asana`, `trello`)
- `qmd`: QMD package source + required npm integrity hash baked into `/opt/kubeclaw/qmd-bin`

Example:

```json
{
  "linuxPackages": ["git", "ripgrep"],
  "goPackages": ["github.com/fullstorydev/grpcurl/cmd/grpcurl@latest"],
  "npmGlobalPackages": ["@openapitools/openapi-generator-cli@2.15.3"],
  "skillsSh": [
    {
      "url": "https://example.skills.sh/install.sh",
      "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    }
  ]
}
```

## Runtime Bootstrap

`images/kubeclaw/scripts/bootstrap.sh` runs before the OpenClaw Gateway process and:

- applies `config.desired` using `merge` or `overwrite` mode
- syncs baked skillstacks from `/opt/kubeclaw/skillstacks` into `/home/node/.openclaw/skills` (and prunes stale managed stack skills)
- generates and merges `skills.*` config so OpenClaw knows what to load
