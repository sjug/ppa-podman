#!/bin/bash
set -euo pipefail

# Download and prepare upstream source tarballs for PPA packaging
# Each tarball is placed in its package directory as <pkg>_<ver>.orig.tar.gz

BASEDIR="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---------- conmon 2.2.1 ----------
pkg_conmon() {
    info "Downloading conmon 2.2.1..."
    cd "$TMPDIR"
    curl -sSL -o conmon-2.2.1.tar.gz \
        "https://github.com/containers/conmon/archive/refs/tags/v2.2.1.tar.gz"
    cp conmon-2.2.1.tar.gz "$BASEDIR/conmon/conmon_2.2.1.orig.tar.gz"
    info "conmon done."
}

# ---------- crun 1.26 ----------
pkg_crun() {
    info "Downloading crun 1.26..."
    cd "$TMPDIR"
    # Use the release tarball which includes generated configure script
    curl -sSL -o crun-1.26.tar.gz \
        "https://github.com/containers/crun/releases/download/1.26/crun-1.26.tar.gz"
    cp crun-1.26.tar.gz "$BASEDIR/crun/crun_1.26.orig.tar.gz"
    info "crun done."
}

# ---------- passt ----------
pkg_passt() {
    info "Downloading passt 2026_01_20.386b5f5..."
    cd "$TMPDIR"
    git clone --depth 1 --branch 2026_01_20.386b5f5 \
        https://passt.top/passt passt-0.0~git20260120.386b5f5
    # Remove .git to reduce tarball size
    rm -rf passt-0.0~git20260120.386b5f5/.git
    tar czf passt_0.0~git20260120.386b5f5.orig.tar.gz passt-0.0~git20260120.386b5f5/
    cp passt_0.0~git20260120.386b5f5.orig.tar.gz "$BASEDIR/passt/"
    info "passt done."
}

# ---------- netavark 1.13.1 (with vendored Rust deps) ----------
pkg_netavark() {
    info "Downloading netavark 1.13.1 and vendoring Rust deps..."
    cd "$TMPDIR"
    git clone --depth 1 --branch v1.13.1 \
        https://github.com/containers/netavark.git netavark-1.13.1
    cd netavark-1.13.1
    cargo vendor
    # Create .cargo/config.toml for offline builds
    mkdir -p .cargo
    cat > .cargo/config.toml <<'TOML'
[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "vendor"
TOML
    rm -rf .git
    cd "$TMPDIR"
    tar czf netavark_1.13.1.orig.tar.gz netavark-1.13.1/
    cp netavark_1.13.1.orig.tar.gz "$BASEDIR/netavark/"
    info "netavark done."
}

# ---------- aardvark-dns 1.13.1 (with vendored Rust deps) ----------
pkg_aardvark() {
    info "Downloading aardvark-dns 1.13.1 and vendoring Rust deps..."
    cd "$TMPDIR"
    git clone --depth 1 --branch v1.13.1 \
        https://github.com/containers/aardvark-dns.git aardvark-dns-1.13.1
    cd aardvark-dns-1.13.1
    cargo vendor
    mkdir -p .cargo
    cat > .cargo/config.toml <<'TOML'
[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "vendor"
TOML
    rm -rf .git
    cd "$TMPDIR"
    tar czf aardvark-dns_1.13.1.orig.tar.gz aardvark-dns-1.13.1/
    cp aardvark-dns_1.13.1.orig.tar.gz "$BASEDIR/aardvark-dns/"
    info "aardvark-dns done."
}

# ---------- podman 5.8.1 (with vendored Go deps) ----------
pkg_podman() {
    info "Downloading podman 5.8.1 and vendoring Go deps..."
    cd "$TMPDIR"
    git clone --depth 1 --branch v5.8.1 \
        https://github.com/containers/podman.git podman-5.8.1
    cd podman-5.8.1
    go mod vendor
    rm -rf .git
    cd "$TMPDIR"
    tar czf podman_5.8.1.orig.tar.gz podman-5.8.1/
    cp podman_5.8.1.orig.tar.gz "$BASEDIR/podman/"
    info "podman done."
}

# ---------- containers-common (no download needed) ----------
pkg_containers_common() {
    info "containers-common is a native package, no upstream tarball needed."
}

# Run all in sequence (parallel would fight over network/disk)
info "=== Downloading all upstream sources ==="
info "Working in: $TMPDIR"
echo

pkg_conmon
pkg_crun
pkg_passt
pkg_netavark
pkg_aardvark
pkg_podman
pkg_containers_common

echo
info "=== All source tarballs ready ==="
ls -lh "$BASEDIR"/*//*.orig.tar.gz 2>/dev/null || true
