# KOReader emulator runtime image

A reusable `linux/amd64` image with Ubuntu 24.04, the KOReader build
toolchain, and a prebuilt KOReader emulator runtime at
`/opt/koreader-cache/stable/runtime`.

The image contains no benchmark tasks, tests, or solutions, and no Zen UI
references. Contents are upstream KOReader and Ubuntu packages under their
own licenses; see the runtime's `COPYING` file.

```sh
docker pull ghcr.io/srlsoc/koreader-emulator-runtime:v2026.07-v1
```

Immutable reference (published by workflow run `41951689205`; pin it in
consuming Dockerfiles; never float on a tag):

```text
ghcr.io/srlsoc/koreader-emulator-runtime@sha256:aaf2c8e6a88aa41671963c1300b9268cf2bb9becdc9965912a8a13ece33b1f8b
```

## Provenance

- KOReader tag `v2026.07`, read at build time from the zen-os
  `spec/koreader-lock.json` at commit
  `a2c4524cd6c38bb4b2113dffb9a6a4f40145c9d9`. The zen-os checkout exists
  only in the discarded builder stage; it is never copied into the image.
- The runtime is built by the zen-os provisioner (`./kodev build`) in the
  builder stage, exactly as the consuming task Dockerfiles built it before.
  The builder stage also deletes the provisioner's cache marker file and
  fails if any Zen UI reference remains in the runtime.
- Base OS: `ubuntu:24.04` pinned by digest in the Dockerfile.
- The `seeds/` archives are the same public upstream archives the task
  Dockerfiles vendored, byte-identical, md5-verified against
  `seeds/dep-seeds/CHECKSUMS.md5` during the build. They are committed
  here so the image build is reproducible without access to the task
  repo; they contain no task data.

## Building

```sh
docker build --provenance=false --sbom=false -t koreader-emulator-runtime:local .
```

Publishing is done by `.github/workflows/publish.yml` on push to `main`.
It builds only the `runtime` stage and pushes the versioned tag. The tag
encodes the KOReader lock tag plus a recipe revision: `v2026.07-v1`.
Bump the `-vN` suffix for recipe-only changes; change the tag prefix
when the lock tag changes.

## Refreshing the seeds

When the lock tag or the vendored seed set changes, refresh `seeds/`
from the task tree at the commit whose Dockerfiles the recipe mirrors
(requires checkout access to the task repo; the archives themselves are
public upstream files):

```sh
git archive <task-sha> -- zen-os-readability-dynamic-collections/environment/dep-seeds zen-os-readability-dynamic-collections/environment/djvulibre-release.3.5.30.1-2-g69e23da.tar.gz \
  | tar -x --strip-components=2 -C seeds
(cd seeds/dep-seeds && md5sum -c CHECKSUMS.md5)
```

## Upgrading

1. Update `ZEN_OS_COMMIT` in the Dockerfile if the lock source moved, and
   the tag in the workflow and the `org.opencontainers.image.version`
   label to match the new lock tag and recipe revision.
2. Refresh `seeds/` as above if the vendored seed set changed.
3. Push to `main`. Record the published digest and update consuming
   Dockerfiles to pin it. Re-run the consuming task's oracle before
   relying on the new image.

## Audit before relying on a published image

Against a fresh pull (not the local build cache, which retains the
builder stage): no `/app`, no `/tests`, no `/opt/trusted.git`; no file
under `/opt/koreader-cache` matches `ZEN_UI`, `zen-ui`, or the task slug;
`luajit` is executable and `frontend`, `spec/rocks`, and
`plugins/coverbrowser.koplugin` are present.
