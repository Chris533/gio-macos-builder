# Self-contained macOS Universal Binary (arm64 + amd64) cross-builder for Go / Gio / CGO apps.
# Usage (from any Go/Gio project root):
#   docker run --rm -v "${PWD}:/workspace" -v gio-macos-cache:/cache ghcr.io/chris533/gio-macos-builder:15.5
FROM crazymax/osxcross:15.5-ubuntu AS osxcross
FROM golang:1.26-bookworm AS golang

FROM ubuntu:24.04
LABEL org.opencontainers.image.source="https://github.com/Chris533/gio-macos-builder"
LABEL org.opencontainers.image.description="Zero-config macOS Universal Binary (.app/.zip/.dmg) cross-builder for Go/Gio/CGO apps (osxcross MacOSX15.5.sdk + Clang 18 + Go 1.26)"
LABEL org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    clang-18 \
    file \
    genisoimage \
    git \
    icnsutils \
    python3 \
    python3-pil \
    && rm -rf /var/lib/apt/lists/*

# 1. Go 1.26 toolchain
COPY --from=golang /usr/local/go /usr/local/go

# 2. osxcross cctools (ld/lipo) + MacOSX15.5.sdk + SDK modulemap deduplication fix
COPY --from=osxcross /osxcross /osxcross
RUN ln -sfn /usr/lib/llvm-18/lib/clang /usr/include/clang \
    && rm -rf /osxcross/SDK/MacOSX15.5.sdk/usr/include/libxml \
    && ln -sfn libxml2/libxml /osxcross/SDK/MacOSX15.5.sdk/usr/include/libxml

# 3. Clang 18 cross-compile wrappers (prioritize Clang builtin stddef/stdint headers via -I
#    before MacOSX15.5.sdk/usr/include, and append -fno-modules after "$@" to override -fmodules)
RUN cat <<'EOF' > /usr/local/bin/oa64-cc
#!/usr/bin/env bash
exec /usr/lib/llvm-18/bin/clang \
  -target arm64-apple-darwin24.5 \
  -mlinker-version=711 \
  -B/osxcross/bin \
  -isysroot /osxcross/SDK/MacOSX15.5.sdk \
  -I/usr/lib/llvm-18/lib/clang/18/include \
  -mmacosx-version-min="${MACOSX_DEPLOYMENT_TARGET:-11.0}" \
  -arch arm64 \
  "$@" \
  -fno-modules \
  -Wno-nullability-completeness \
  -Wno-deprecated-declarations \
  -Wno-elaborated-enum-base
EOF

RUN cat <<'EOF' > /usr/local/bin/o64-cc
#!/usr/bin/env bash
exec /usr/lib/llvm-18/bin/clang \
  -target x86_64-apple-darwin24.5 \
  -mlinker-version=711 \
  -B/osxcross/bin \
  -isysroot /osxcross/SDK/MacOSX15.5.sdk \
  -I/usr/lib/llvm-18/lib/clang/18/include \
  -mmacosx-version-min="${MACOSX_DEPLOYMENT_TARGET:-11.0}" \
  -arch x86_64 \
  "$@" \
  -fno-modules \
  -Wno-nullability-completeness \
  -Wno-deprecated-declarations \
  -Wno-elaborated-enum-base
EOF

RUN chmod +x /usr/local/bin/oa64-cc /usr/local/bin/o64-cc \
    && git config --system --add safe.directory '*'

ENV PATH="/usr/local/go/bin:/osxcross/bin:${PATH}" \
    LD_LIBRARY_PATH="/osxcross/lib" \
    GOCACHE="/cache/gocache" \
    GOMODCACHE="/cache/gomodcache" \
    MACOSX_DEPLOYMENT_TARGET="11.0"

COPY entrypoint.sh /usr/local/bin/build-macos
RUN chmod +x /usr/local/bin/build-macos

VOLUME ["/cache"]
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/build-macos"]
