#!/bin/bash
set -euo pipefail

# Check and install prerequisites for building PPA source packages.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

info "=== PPA Build Environment Setup ==="
echo

# Check for required tools
MISSING=()
for cmd in dpkg-buildpackage dput dh debuild git curl tar; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING+=("$cmd")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    warn "Missing tools: ${MISSING[*]}"
    info "Installing build dependencies..."
    sudo apt-get update
    sudo apt-get install -y \
        build-essential \
        cargo \
        curl \
        debhelper \
        devscripts \
        dput \
        dpkg-dev \
        git \
        rustc
    info "Build tools installed."
else
    info "All required tools found."
fi

echo

# Check vendoring toolchains. Podman 6.1.1 requires Go 1.25.x and
# Netavark/Aardvark 2.1.0 require Rust 1.88.x. Noble's distro toolchains are
# too old, so install official x86_64 toolchains in the VM for vendoring.
info "Checking vendoring toolchains..."
if [[ -d /usr/local/go/bin ]]; then
    export PATH="/usr/local/go/bin:$PATH"
fi
GO_VER=$(go version 2>/dev/null | grep -oP 'go\K\d+\.\d+\.\d+' || true)
if [[ -z "$GO_VER" || "$GO_VER" != 1.25.* ]] || ! dpkg --compare-versions "$GO_VER" ge "1.25.14"; then
    warn "Go version is ${GO_VER:-missing}; expected Go 1.25.14 for Podman 6.1.1."
    warn "Install the x86_64 official Go 1.25.x tarball under /usr/local/go."
else
    info "Go version: $GO_VER"
fi
CARGO_VER=$(cargo --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || true)
if [[ -z "$CARGO_VER" || "$CARGO_VER" != 1.88.* ]]; then
    warn "cargo version is ${CARGO_VER:-missing}; expected Rust/Cargo 1.88.x for Netavark/Aardvark 2.1.0."
    warn "Install the x86_64 official Rust 1.88 standalone toolchain."
else
    info "cargo version: $CARGO_VER"
fi

echo

# Check GPG key
info "Checking GPG keys..."
if gpg --list-secret-keys 2>/dev/null | grep -q 'sec'; then
    info "GPG secret key found:"
    gpg --list-secret-keys --keyid-format long 2>/dev/null | grep -A1 '^sec'
else
    warn "No GPG secret key found."
    warn "You need a GPG key registered with Launchpad to sign packages."
    warn "Generate one with: gpg --full-generate-key"
    warn "Then upload to Launchpad: https://launchpad.net/~/+editpgpkeys"
fi

echo

# Check/create dput config
if [[ ! -f ~/.dput.cf ]]; then
    info "Creating default ~/.dput.cf for Launchpad..."
    cat > ~/.dput.cf <<'EOF'
[DEFAULT]
default_host_main = unset

[unset]
fqdn = SPECIFY.A" .DEFAULT" .IN" .dput.cf
incoming = /

[ppa]
fqdn = ppa.launchpad.net
method = ftp
incoming = ~%(ppa)s/ubuntu
login = anonymous
allow_unsigned_uploads = 0
EOF
    info "Created ~/.dput.cf"
else
    info "~/.dput.cf already exists."
fi

echo
info "=== Setup complete ==="
info ""
info "Next steps:"
info "  1. Run: ./download-sources.sh"
info "  2. Run: ./build-source-packages.sh --sign YOUR_GPG_KEY_ID"
info "  3. Run: ./upload-ppa.sh ppa:yourusername/podman"
