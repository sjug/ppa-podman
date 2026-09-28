#!/bin/bash
set -euo pipefail

# Download and prepare upstream source tarballs for PPA packaging.
# Each upstream tarball is placed in its package directory as <pkg>_<ver>.orig.tar.gz.
#
# IMPORTANT for Podman 6.1.2:
# - Podman requires Go 1.26.0+ to vendor/build. This PPA pins the latest
#   Go 1.26.x patch release (currently 1.26.8), so install that x86_64
#   official toolchain in the build VM before running this script.
# - Rust packages (netavark, aardvark-dns) require Rust 1.88 to vendor/build.
#   Install the x86_64 official Rust 1.88 toolchain in the build VM before
#   running this script. The PPA packages the arm64 toolchains for Launchpad.

BASEDIR="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

ONLY_PKGS=()
ONLY_FLAG=0

KNOWN_PKGS=(go-toolchain rust-toolchain conmon crun passt netavark aardvark-dns podman podman-docker containers-common)
GO_TOOLCHAIN_SHA256="211ffced9dcb9633a55eac6364816ec0ddd951389a740e88fa8b3337971bdda0"
RUST_TOOLCHAIN_SHA256="d5decc46123eb888f809f2ee3b118d13586a37ffad38afaefe56aa7139481d34"
CONTAINER_COMMON_VERSION="0.69.2"
CONTAINER_STORAGE_VERSION="1.64.1"
CONTAINER_IMAGE_VERSION="5.41.2"
CONTAINER_SHORTNAMES_VERSION="2025.03.19"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --only)
            ONLY_FLAG=1
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
                ONLY_PKGS+=("$1")
                shift
            done
            ;;
        *) echo "Usage: $0 [--only pkg1 pkg2 ...]"; exit 1 ;;
    esac
done

if [[ $ONLY_FLAG -eq 1 && ${#ONLY_PKGS[@]} -eq 0 ]]; then
    error "--only requires at least one package name"
    error "Known packages: ${KNOWN_PKGS[*]}"
    exit 1
fi

for pkg in "${ONLY_PKGS[@]}"; do
    found=0
    for known in "${KNOWN_PKGS[@]}"; do
        [[ "$pkg" == "$known" ]] && { found=1; break; }
    done
    if [[ $found -eq 0 ]]; then
        error "Unknown package: $pkg"
        error "Known packages: ${KNOWN_PKGS[*]}"
        exit 1
    fi
done

should_download() {
    local name="$1"
    if [[ ${#ONLY_PKGS[@]} -eq 0 ]]; then
        return 0
    fi
    for pkg in "${ONLY_PKGS[@]}"; do
        [[ "$pkg" == "$name" ]] && return 0
    done
    return 1
}

version_ge() {
    dpkg --compare-versions "$1" ge "$2"
}

download_checked() {
    local url="$1"
    local dest="$2"
    local sha256="$3"
    curl -fsSL -o "$dest" "$url"
    printf '%s  %s\n' "$sha256" "$dest" | sha256sum -c - >/dev/null
}

# Ensure the latest Go 1.26.x is in PATH when Podman vendoring is requested.
if should_download "podman" || should_download "podman-docker"; then
    if [[ -d /usr/local/go/bin ]]; then
        export PATH="/usr/local/go/bin:$PATH"
        info "Added /usr/local/go/bin to PATH"
    elif [[ -d /usr/lib/go-1.26/bin ]]; then
        export PATH="/usr/lib/go-1.26/bin:$PATH"
        info "Added /usr/lib/go-1.26/bin to PATH"
    fi
    if ! command -v go >/dev/null 2>&1; then
        error "Go not found. Install Go 1.26.8 in the build VM."
        exit 1
    fi
    GO_VER=$(go version 2>/dev/null | grep -oP 'go\K\d+\.\d+\.\d+' || echo "none")
    if [[ "$GO_VER" == "none" ]] || [[ "$GO_VER" != 1.26.* ]] || ! version_ge "$GO_VER" "1.26.8"; then
        error "go version is $GO_VER, expected latest Go 1.26.x (currently 1.26.8) for Podman 6.1.2"
        error "Install the x86_64 official Go 1.26.8 toolchain in the build VM."
        exit 1
    fi
fi

# Verify Rust version when Rust vendoring is requested.
if should_download "netavark" || should_download "aardvark-dns"; then
    CARGO_VER=$(cargo --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "none")
    if [[ "$CARGO_VER" == "none" ]] || ! version_ge "$CARGO_VER" "1.88.0"; then
        warn "cargo version is $CARGO_VER, expected 1.88.x or newer"
        warn "Rust packages may fail to build if vendored with the wrong version"
        warn "See CLAUDE.md for Rust setup instructions"
    fi
fi

# ---------- go-toolchain 1.26.8 (aarch64 standalone binary) ----------
pkg_go_toolchain() {
    info "Downloading Go 1.26.8 standalone for arm64..."
    cd "$TMPDIR"
    curl -sSL -o go1.26.8.linux-arm64.tar.gz \
        "https://go.dev/dl/go1.26.8.linux-arm64.tar.gz"
    printf '%s  %s\n' \
        "$GO_TOOLCHAIN_SHA256" \
        "go1.26.8.linux-arm64.tar.gz" | sha256sum -c -
    rm -f "$BASEDIR/go-toolchain"/go1.*.linux-arm64.tar.gz
    cp go1.26.8.linux-arm64.tar.gz "$BASEDIR/go-toolchain/"
    info "go-toolchain done."
}

# ---------- conmon 2.2.1 ----------
pkg_conmon() {
    info "Downloading conmon 2.2.1..."
    cd "$TMPDIR"
    curl -sSL -o conmon-2.2.1.tar.gz \
        "https://github.com/containers/conmon/archive/refs/tags/v2.2.1.tar.gz"
    cp conmon-2.2.1.tar.gz "$BASEDIR/conmon/conmon_2.2.1.orig.tar.gz"
    info "conmon done."
}

# ---------- crun 1.30.1 ----------
pkg_crun() {
    info "Downloading crun 1.30.1..."
    cd "$TMPDIR"
    curl -sSL -o crun-1.30.1.tar.gz \
        "https://github.com/containers/crun/releases/download/1.30.1/crun-1.30.1.tar.gz"
    cp crun-1.30.1.tar.gz "$BASEDIR/crun/crun_1.30.1.orig.tar.gz"
    info "crun done."
}

# ---------- passt ----------
pkg_passt() {
    info "Downloading passt 2026_09_25.df90211..."
    cd "$TMPDIR"
    git clone --depth 1 --branch 2026_09_25.df90211 \
        https://passt.top/passt passt-0.0~git20260925.df90211
    rm -rf passt-0.0~git20260925.df90211/.git
    tar czf passt_0.0~git20260925.df90211.orig.tar.gz passt-0.0~git20260925.df90211/
    cp passt_0.0~git20260925.df90211.orig.tar.gz "$BASEDIR/passt/"
    info "passt done."
}

# ---------- netavark 2.1.0 (with vendored Rust deps) ----------
pkg_netavark() {
    local ver="2.1.0"
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

# ---------- aardvark-dns 2.1.0 (with vendored Rust deps) ----------
pkg_aardvark() {
    local ver="2.1.0"
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

# ---------- podman 6.1.2 (with vendored Go deps) ----------
pkg_podman() {
    info "Downloading podman 6.1.2 and vendoring Go deps..."
    cd "$TMPDIR"
    git clone --depth 1 --branch v6.1.2 \
        https://github.com/podman-container-tools/podman.git podman-6.1.2
    cd podman-6.1.2
    go mod vendor
    rm -rf .git
    cd "$TMPDIR"
    tar czf podman_6.1.2.orig.tar.gz podman-6.1.2/
    cp podman_6.1.2.orig.tar.gz "$BASEDIR/podman/"
    cp podman_6.1.2.orig.tar.gz "$BASEDIR/podman-docker/podman-docker_6.1.2.orig.tar.gz"
    info "podman done."
}

# ---------- rust-toolchain 1.88.0 (aarch64 standalone binary) ----------
pkg_rust_toolchain() {
    info "Downloading Rust 1.88.0 standalone for aarch64..."
    cd "$TMPDIR"
    curl -sSL -o rust-1.88.0-aarch64-unknown-linux-gnu.tar.xz \
        "https://static.rust-lang.org/dist/rust-1.88.0-aarch64-unknown-linux-gnu.tar.xz"
    printf '%s  %s\n' \
        "$RUST_TOOLCHAIN_SHA256" \
        "rust-1.88.0-aarch64-unknown-linux-gnu.tar.xz" | sha256sum -c -
    cp rust-1.88.0-aarch64-unknown-linux-gnu.tar.xz "$BASEDIR/rust-toolchain/rust-1.88.0-aarch64.tar.xz"
    info "rust-toolchain done."
}

# ---------- containers-common configuration from upstream component tags ----------
pkg_containers_common() {
    info "Downloading containers-common config files from upstream tags..."
    cd "$TMPDIR"

    local base="https://raw.githubusercontent.com/podman-container-tools/container-libs"
    download_checked \
        "$base/common/v${CONTAINER_COMMON_VERSION}/common/pkg/config/containers.conf" \
        containers.conf \
        "0dc1c6cc0c41d1cb1ac63154c328cbcbe6ff4666f21f4795d7d12c506db41650"
    download_checked \
        "$base/common/v${CONTAINER_COMMON_VERSION}/common/pkg/seccomp/seccomp.json" \
        seccomp.json \
        "9b755202516aee4b45d9d411ab800c20fe4f7af97166a93b7f07d5b16c1a4ecd"
    download_checked \
        "$base/storage/v${CONTAINER_STORAGE_VERSION}/storage/storage.conf" \
        storage.conf \
        "322dffd5a543bb9e1ca9c67cc56999c62b746118674d004180fe60dddfc21979"
    download_checked \
        "$base/image/v${CONTAINER_IMAGE_VERSION}/image/registries.conf" \
        registries.conf \
        "517b917ff7ad391d20ca3850ca80f3da5be102bbb3267cc3c9875909178bd6de"
    download_checked \
        "$base/image/v${CONTAINER_IMAGE_VERSION}/image/default-policy.json" \
        policy.json \
        "cddfaa8e6a7e5497b67cc0dd8e8517058d0c97de91bf46fff867528415f2d946"
    download_checked \
        "$base/image/v${CONTAINER_IMAGE_VERSION}/image/default.yaml" \
        default.yaml \
        "370f4cd92207c958346363b35df4f81bf5a84e4ef5b3f97a7990595ac0e04297"
    download_checked \
        "https://raw.githubusercontent.com/containers/shortnames/v${CONTAINER_SHORTNAMES_VERSION}/shortnames.conf" \
        shortnames.conf \
        "14a40c93c2d7cea9c0b28c69b0ba01ef1d232add9be9803691280d2f9dc018d3"

    cp containers.conf seccomp.json storage.conf registries.conf policy.json default.yaml shortnames.conf \
        "$BASEDIR/containers-common/"
    printf '%s\n' "$CONTAINER_COMMON_VERSION" > "$BASEDIR/containers-common/container-libs.version"
    info "containers-common config files synced from container-libs common v${CONTAINER_COMMON_VERSION}, storage v${CONTAINER_STORAGE_VERSION}, image v${CONTAINER_IMAGE_VERSION}, shortnames v${CONTAINER_SHORTNAMES_VERSION}."
}

if [[ ${#ONLY_PKGS[@]} -gt 0 ]]; then
    info "=== Downloading sources: ${ONLY_PKGS[*]} ==="
else
    info "=== Downloading all upstream sources ==="
fi
info "Working in: $TMPDIR"
echo

should_download "go-toolchain"       && pkg_go_toolchain
should_download "conmon"             && pkg_conmon
should_download "crun"               && pkg_crun
should_download "passt"              && pkg_passt
should_download "netavark"           && pkg_netavark
should_download "aardvark-dns"       && pkg_aardvark
# pkg_podman produces the tarball used by both podman and podman-docker.
if should_download "podman" || should_download "podman-docker"; then
    pkg_podman
fi
should_download "rust-toolchain"     && pkg_rust_toolchain
should_download "containers-common"  && pkg_containers_common

echo
info "=== All source tarballs ready ==="
ls -lh "$BASEDIR"/*/*.orig.tar.gz \
       "$BASEDIR"/go-toolchain/*.tar.gz \
       "$BASEDIR"/rust-toolchain/*.tar.xz 2>/dev/null || true
