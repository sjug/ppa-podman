#!/bin/bash
set -euo pipefail

# Download and prepare upstream source tarballs for PPA packaging
# Each tarball is placed in its package directory as <pkg>_<ver>.orig.tar.gz
#
# IMPORTANT: Rust packages (netavark, aardvark-dns) must be vendored with
# Rust 1.86, not the system Rust. Ensure /usr/local/bin/cargo is 1.86 before
# running this script. See CLAUDE.md for setup instructions.

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

# Verify Rust version for vendoring
CARGO_VER=$(cargo --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "none")
if [[ "$CARGO_VER" != 1.86.* ]]; then
    warn "cargo version is $CARGO_VER, expected 1.86.x"
    warn "Rust packages may fail to build if vendored with wrong version"
    warn "See CLAUDE.md for Rust 1.86 setup instructions"
fi

# ---------- conmon 2.2.1 ----------
pkg_conmon() {
    info "Downloading conmon 2.2.1..."
    cd "$TMPDIR"
    curl -sSL -o conmon-2.2.1.tar.gz \
        "https://github.com/containers/conmon/archive/refs/tags/v2.2.1.tar.gz"
    cp conmon-2.2.1.tar.gz "$BASEDIR/conmon/conmon_2.2.1.orig.tar.gz"
    info "conmon done."
}

# ---------- crun 1.27 ----------
pkg_crun() {
    info "Downloading crun 1.27..."
    cd "$TMPDIR"
    curl -sSL -o crun-1.27.tar.gz \
        "https://github.com/containers/crun/releases/download/1.27/crun-1.27.tar.gz"
    cp crun-1.27.tar.gz "$BASEDIR/crun/crun_1.27.orig.tar.gz"
    info "crun done."
}

# ---------- passt ----------
pkg_passt() {
    info "Downloading passt 2026_01_20.386b5f5..."
    cd "$TMPDIR"
    git clone --depth 1 --branch 2026_01_20.386b5f5 \
        https://passt.top/passt passt-0.0~git20260120.386b5f5
    rm -rf passt-0.0~git20260120.386b5f5/.git
    tar czf passt_0.0~git20260120.386b5f5.orig.tar.gz passt-0.0~git20260120.386b5f5/
    cp passt_0.0~git20260120.386b5f5.orig.tar.gz "$BASEDIR/passt/"
    info "passt done."
}

# ---------- netavark 1.17.2 (with vendored Rust deps) ----------
pkg_netavark() {
    local ver="1.17.2"
    local dsver="${ver}+ds"
    info "Downloading netavark ${ver} and vendoring Rust deps..."
    cd "$TMPDIR"
    git clone --depth 1 --branch "v${ver}" \
        https://github.com/containers/netavark.git "netavark-${dsver}"
    cd "netavark-${dsver}"
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
    tar czf "netavark_${dsver}.orig.tar.gz" "netavark-${dsver}/"
    cp "netavark_${dsver}.orig.tar.gz" "$BASEDIR/netavark/"
    info "netavark done."
}

# ---------- aardvark-dns 1.17.1 (with vendored Rust deps) ----------
pkg_aardvark() {
    local ver="1.17.1"
    local dsver="${ver}+ds"
    info "Downloading aardvark-dns ${ver} and vendoring Rust deps..."
    cd "$TMPDIR"
    git clone --depth 1 --branch "v${ver}" \
        https://github.com/containers/aardvark-dns.git "aardvark-dns-${dsver}"
    cd "aardvark-dns-${dsver}"
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
    tar czf "aardvark-dns_${dsver}.orig.tar.gz" "aardvark-dns-${dsver}/"
    cp "aardvark-dns_${dsver}.orig.tar.gz" "$BASEDIR/aardvark-dns/"
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

# ---------- rust-toolchain 1.86.0 (aarch64 standalone binary) ----------
pkg_rust_toolchain() {
    info "Downloading Rust 1.86.0 standalone for aarch64..."
    cd "$TMPDIR"
    curl -sSL -o rust-1.86.0-aarch64.tar.xz \
        "https://static.rust-lang.org/dist/rust-1.86.0-aarch64-unknown-linux-gnu.tar.xz"
    cp rust-1.86.0-aarch64.tar.xz "$BASEDIR/rust-toolchain/"
    info "rust-toolchain done."
}

# ---------- containers-common (no download needed) ----------
pkg_containers_common() {
    info "containers-common is a native package, no upstream tarball needed."
}

# Run all in sequence
info "=== Downloading all upstream sources ==="
info "Working in: $TMPDIR"
echo

pkg_conmon
pkg_crun
pkg_passt
pkg_netavark
pkg_aardvark
pkg_podman
pkg_rust_toolchain
pkg_containers_common

echo
info "=== All source tarballs ready ==="
ls -lh "$BASEDIR"/*/*.orig.tar.gz "$BASEDIR"/rust-toolchain/*.tar.xz 2>/dev/null || true
