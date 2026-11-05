# KOReader emulator runtime image.
#
# Contents of the published (final) image: Ubuntu 24.04, the apt toolchain,
# and /opt/koreader-cache/stable/runtime built from public upstream KOReader
# sources. Nothing else: no task files, no tests, no solutions, no Zen UI
# references. See README.md for provenance and the upgrade procedure.
#
# Only the final stage ("runtime") is published. The builder stage (zen-os
# checkout, KOReader source, vendored seeds) is discarded and never pushed.
# The final stage contains no COPY from the build context at all.

ARG UBUNTU_DIGEST=sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852
ARG ZEN_OS_COMMIT=a2c4524cd6c38bb4b2113dffb9a6a4f40145c9d9

FROM docker.io/library/ubuntu:24.04@${UBUNTU_DIGEST} AS builder
ARG ZEN_OS_COMMIT
ENV DEBIAN_FRONTEND=noninteractive \
    ZEN_UI_KOREADER_CACHE=/opt/koreader-cache \
    KOREADER_DIR=/opt/koreader-cache/stable/runtime
RUN set -eux \
    && apt-get update \
    && apt-get install --no-install-recommends -y build-essential ca-certificates cmake gettext git lua5.1 luarocks meson nasm ninja-build pkg-config procps python3 xvfb libsdl2-dev libfreetype6-dev libfontconfig1-dev libharfbuzz-dev libxtst-dev libfribidi-dev libpng-dev libjpeg-dev libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git init /build/zen-os \
    && git -C /build/zen-os remote add origin https://github.com/xZenLabs/zen-os.git \
    && git -C /build/zen-os fetch --depth 1 origin "$ZEN_OS_COMMIT" \
    && git -C /build/zen-os checkout "$ZEN_OS_COMMIT" \
    && git -C /build/zen-os log --oneline | wc -l

WORKDIR /build/zen-os

# Redirect the provisioner's djvulibre prefetch at a local file:// mirror,
# exactly as the task Dockerfiles do (gitlab.com egress is blocked on some
# builders). Provenance: koreader-base 6232b26 thirdparty/djvulibre,
# DOWNLOAD GIT release.3.5.30.1-2-g69e23da; md5 f23318d5138b2dac1b9bfe31b303e9fe.
COPY seeds/djvulibre-release.3.5.30.1-2-g69e23da.tar.gz /opt/koreader-vendor/djvulibre/release.3.5.30.1-2-g69e23da/djvulibre-release.3.5.30.1-2-g69e23da.tar.gz
RUN sed -i 's|https://gitlab.com/koreader/djvulibre/-/archive/|file:///opt/koreader-vendor/djvulibre/|' /build/zen-os/spec/provision-koreader.sh \
    && grep -c 'file:///opt/koreader-vendor/djvulibre/' /build/zen-os/spec/provision-koreader.sh

# Pre-seed the second djvulibre fetch, as the task Dockerfiles do: the
# provisioner clones KOReader before downloading anything, then skips its
# own clone when $SOURCE/.git exists. The seed lives in the source tree,
# which cmake never wipes, so download_archive's md5 check hits.
RUN REF="$(python3 -c 'import json; lock = json.load(open("/build/zen-os/spec/koreader-lock.json")); print(lock["stable"].get("tag") or lock["stable"]["commit"])')" \
    && mkdir -p /opt/koreader-cache/stable \
    && git clone --recurse-submodules --depth=1 --branch "$REF" https://github.com/koreader/koreader.git /opt/koreader-cache/stable/source \
    && git -C /opt/koreader-cache/stable/source log -1 --format='%H %d'
COPY seeds/djvulibre-release.3.5.30.1-2-g69e23da.tar.gz /opt/koreader-cache/stable/source/base/thirdparty/djvulibre/build/downloads/djvulibre-release.3.5.30.1-2-g69e23da.tar.gz

# Pre-seed every other non-GitHub fetch in the Linux emulator build, as the
# task Dockerfiles do. Each DOWNLOAD_DIR is md5-validated at build time.
COPY seeds/dep-seeds/ /opt/koreader-vendor/dep-seeds/
RUN cd /opt/koreader-vendor/dep-seeds && md5sum -c CHECKSUMS.md5 \
    && TP=/opt/koreader-cache/stable/source/base/thirdparty \
    && seed() { mkdir -p "$TP/$1/build/downloads" && cp "/opt/koreader-vendor/dep-seeds/$2" "$TP/$1/build/downloads/$2"; } \
    && seed certifi certifi-2026.6.17-py3-none-any.whl \
    && seed dkjson dkjson-2.10.tar.gz \
    && seed giflib giflib-6.1.3.tar.gz \
    && seed glib glib-2.82.1.tar.xz \
    && seed libwebp libwebp-1.6.0.tar.gz \
    && seed sqlite sqlite-amalgamation-3530300.zip \
    && seed spec/busted busted-2.3.0-1.src.rock \
    && seed spec/cluacov cluacov-0.1.4-1.src.rock \
    && seed spec/luacov luacov-0.15.0-1.src.rock \
    && seed spec/luafilesystem luafilesystem-1.9.0-1.src.rock \
    && seed spec/luassert luassert-1.9.0-1.src.rock \
    && seed spec/luasystem luasystem-0.7.1-1.src.rock \
    && seed spec/penlight penlight-1.15.0-1.src.rock \
    && seed spec/say say-1.4.1-3.src.rock \
    && mkdir -p "$TP/lua-Spore/build/downloads/source" \
    && tar -xzf /opt/koreader-vendor/dep-seeds/lua-spore-0.4.2-source.tar.gz -C "$TP/lua-Spore/build/downloads/source" \
    && chown -R root:root "$TP/lua-Spore/build/downloads/source" \
    && git -C "$TP/lua-Spore/build/downloads/source" rev-parse 0.4.2^{commit} \
    && find "$TP" -path '*build/downloads*' \( -type f -name '*.tar.*' -o -name '*.zip' -o -name '*.rock' -o -name '*.whl' \) | sort

# Bake the KOReader emulator runtime (test time is offline).
RUN ./spec/provision-koreader.sh stable \
    && rm -rf /opt/koreader-cache/stable/source /opt/koreader-cache/stable/downloads \
    && test -x "$KOREADER_DIR/luajit" \
    && test -d "$KOREADER_DIR/frontend" \
    && test -d "$KOREADER_DIR/spec/rocks" \
    && test -d "$KOREADER_DIR/plugins/coverbrowser.koplugin"

# Scrub the one Zen UI trace the provisioner leaves in the runtime: its
# cache marker file. The marker is only read by the provisioner itself,
# which never runs from this image. Fail the build if any other Zen UI
# reference (filename or file text) appears in the runtime.
RUN rm -f "$KOREADER_DIR/.zen-ui-cache-ref" \
    && test -z "$(find "$KOREADER_DIR" \( -iname '*zen-ui*' -o -iname '*zen_os*' \) -print -quit)" \
    && ! grep -rI -e 'ZEN_UI' -e 'zen-ui' -e 'Zen UI' "$KOREADER_DIR"

FROM docker.io/library/ubuntu:24.04@${UBUNTU_DIGEST} AS runtime
ENV DEBIAN_FRONTEND=noninteractive \
    KOREADER_DIR=/opt/koreader-cache/stable/runtime
RUN set -eux \
    && apt-get update \
    && apt-get install --no-install-recommends -y build-essential ca-certificates cmake gettext git lua5.1 luarocks meson nasm ninja-build pkg-config procps python3 xvfb libsdl2-dev libfreetype6-dev libfontconfig1-dev libharfbuzz-dev libxtst-dev libfribidi-dev libpng-dev libjpeg-dev libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /opt/koreader-cache/stable/runtime /opt/koreader-cache/stable/runtime
RUN test -x "$KOREADER_DIR/luajit" \
    && test -d "$KOREADER_DIR/frontend" \
    && test -d "$KOREADER_DIR/spec/rocks" \
    && test -d "$KOREADER_DIR/plugins/coverbrowser.koplugin" \
    && mkdir -p /logs/verifier /logs/agent
LABEL org.opencontainers.image.title="KOReader emulator runtime" \
      org.opencontainers.image.description="Ubuntu 24.04 with a prebuilt KOReader emulator runtime and its toolchain. Contains no task files, tests, or solutions." \
      org.opencontainers.image.source="https://github.com/srlsoc/koreader-emulator-runtime" \
      org.opencontainers.image.version="v2026.07-v1"
