#!/bin/bash
set -euo pipefail

# Build Debian source packages (.dsc + .changes) for all components.
# Usage: ./build-source-packages.sh [--sign KEYID] [--only pkg1 pkg2 ...]

BASEDIR="$(cd "$(dirname "$0")/.." && pwd)"
SIGN_KEY=""
ONLY_PKGS=()
ONLY_FLAG=0

KNOWN_PKGS=(conmon crun passt netavark aardvark-dns podman podman-docker containers-common)

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
        --only)
            ONLY_FLAG=1
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
                ONLY_PKGS+=("$1")
                shift
            done
            ;;
        *) echo "Usage: $0 [--sign GPGKEYID] [--only pkg1 pkg2 ...]"; exit 1 ;;
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

if [[ ${#ONLY_PKGS[@]} -gt 0 ]]; then
    info "Selective build: only building: ${ONLY_PKGS[*]}"
fi

# Helper: should we build this package?
should_build() {
    local name="$1"
    if [[ ${#ONLY_PKGS[@]} -eq 0 ]]; then
        return 0  # build all
    fi
    for pkg in "${ONLY_PKGS[@]}"; do
        if [[ "$pkg" == "$name" ]]; then
            return 0
        fi
    done
    return 1  # skip
}

build_quilt_package() {
    local name="$1"
    local version="$2"
    local orig_tarball="$3"

    should_build "$name" || { info "Skipping: ${name}"; return 0; }

    local src_dir="${name}-${version}"

    info "Building source package: ${name} ${version}"
    cd "$BASEDIR/$name"

    # Clean previous builds
    rm -rf "$src_dir"

    # Extract orig tarball
    tar xzf "$orig_tarball"

    # Rename extracted dir if needed (some tarballs use different naming)
    local extracted
    extracted=$(set +o pipefail; tar tzf "$orig_tarball" | head -1 | cut -d/ -f1)
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

    should_build "$name" || { info "Skipping: ${name}"; return 0; }

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
build_quilt_package "conmon"       "2.2.1"                          "conmon_2.2.1.orig.tar.gz"
build_quilt_package "crun"         "1.27"                           "crun_1.27.orig.tar.gz"
build_quilt_package "passt"        "0.0~git20260120.386b5f5"        "passt_0.0~git20260120.386b5f5.orig.tar.gz"
build_quilt_package "netavark"     "1.17.2+ds"                      "netavark_1.17.2+ds.orig.tar.gz"
build_quilt_package "aardvark-dns" "1.17.1+ds"                      "aardvark-dns_1.17.1+ds.orig.tar.gz"
build_quilt_package "podman"       "5.8.2"                          "podman_5.8.2.orig.tar.gz"
build_quilt_package "podman-docker" "5.8.2"                         "podman-docker_5.8.2.orig.tar.gz"

# Native package (no orig tarball)
build_native_package "containers-common"

echo
info "=== All source packages built ==="
echo
info "Source packages (.changes files):"
find "$BASEDIR" -name '*.changes' -type f | sort
