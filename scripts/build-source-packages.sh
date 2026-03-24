#!/bin/bash
set -euo pipefail

# Build Debian source packages (.dsc + .changes) for all components.
# Usage: ./build-source-packages.sh [--sign KEYID]

BASEDIR="$(cd "$(dirname "$0")/.." && pwd)"
SIGN_KEY=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign) SIGN_KEY="$2"; shift 2 ;;
        *) echo "Usage: $0 [--sign GPGKEYID]"; exit 1 ;;
    esac
done

# Load maintainer identity from .env
if [[ -f "$BASEDIR/.env" ]]; then
    source "$BASEDIR/.env"
fi

if [[ -z "${PPA_MAINTAINER:-}" ]]; then
    error "PPA_MAINTAINER not set. Create .env with: PPA_MAINTAINER=\"Name <email>\""
    exit 1
fi

# Substitute placeholder in all packaging files
info "Setting maintainer to: $PPA_MAINTAINER"
find "$BASEDIR" -path '*/debian/changelog' -o -path '*/debian/control' | while read -r f; do
    sed -i "s|Podman PPA Maintainer <maintainer@ppa>|${PPA_MAINTAINER}|g" "$f"
done

if [[ -n "$SIGN_KEY" ]]; then
    SIGN_ARGS="-k${SIGN_KEY}"
    info "Will sign packages with key: $SIGN_KEY"
else
    SIGN_ARGS="-us -uc"
    warn "Building UNSIGNED source packages (use --sign KEYID for PPA upload)"
fi

build_quilt_package() {
    local name="$1"
    local version="$2"
    local orig_tarball="$3"
    local src_dir="${name}-${version}"

    info "Building source package: ${name} ${version}"
    cd "$BASEDIR/$name"

    # Clean previous builds
    rm -rf "$src_dir"

    # Extract orig tarball
    tar xzf "$orig_tarball"

    # Rename extracted dir if needed (some tarballs use different naming)
    local extracted
    extracted=$(tar tzf "$orig_tarball" | head -1 | cut -d/ -f1)
    if [[ "$extracted" != "$src_dir" ]]; then
        mv "$extracted" "$src_dir"
    fi

    # Copy debian/ directory into source
    cp -a debian/ "$src_dir/debian/"

    # For Rust packages: ensure .cargo/config.toml is in place
    if [[ -f "debian/cargo-vendor-config" ]] && [[ -d "$src_dir/vendor" ]]; then
        mkdir -p "$src_dir/.cargo"
        cp debian/cargo-vendor-config "$src_dir/.cargo/config.toml"
    fi

    # Build source package
    cd "$src_dir"
    dpkg-buildpackage -S -d $SIGN_ARGS

    info "${name} source package built."
    cd "$BASEDIR/$name"
    ls -la *.dsc *.changes 2>/dev/null || true
    echo
}

build_native_package() {
    local name="$1"

    info "Building native source package: ${name}"
    cd "$BASEDIR/$name"

    dpkg-buildpackage -S -d $SIGN_ARGS

    info "${name} source package built."
    cd "$BASEDIR"
    ls -la "$name"/../*.dsc "$name"/../*.changes 2>/dev/null || \
    ls -la "$name"/*.dsc "$name"/*.changes 2>/dev/null || true
    echo
}

info "=== Building source packages ==="
echo

# Quilt (upstream tarball) packages
build_quilt_package "conmon"      "2.2.1"                          "conmon_2.2.1.orig.tar.gz"
build_quilt_package "crun"        "1.26"                           "crun_1.26.orig.tar.gz"
build_quilt_package "passt"       "0.0~git20260120.386b5f5"        "passt_0.0~git20260120.386b5f5.orig.tar.gz"
build_quilt_package "netavark"    "1.13.1"                         "netavark_1.13.1.orig.tar.gz"
build_quilt_package "aardvark-dns" "1.13.1"                        "aardvark-dns_1.13.1.orig.tar.gz"
build_quilt_package "podman"      "5.8.1"                          "podman_5.8.1.orig.tar.gz"

# Native package (no orig tarball)
cd "$BASEDIR/containers-common"
dpkg-buildpackage -S -d $SIGN_ARGS
info "containers-common source package built."

echo
info "=== All source packages built ==="
echo
info "Source packages (.changes files):"
find "$BASEDIR" -name '*.changes' -type f | sort
