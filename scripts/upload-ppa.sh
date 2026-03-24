#!/bin/bash
set -euo pipefail

# Upload all source packages to a Launchpad PPA.
# Usage: ./upload-ppa.sh ppa:username/ppa-name

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 ppa:<username>/<ppa-name>"
    echo "Example: $0 ppa:myuser/podman"
    exit 1
fi

PPA="$1"
BASEDIR="$(cd "$(dirname "$0")/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

info "Uploading to PPA: $PPA"
echo

# Find all _source.changes files
CHANGES_FILES=$(find "$BASEDIR" -name '*_source.changes' -type f | sort)

if [[ -z "$CHANGES_FILES" ]]; then
    error "No _source.changes files found. Run build-source-packages.sh first."
    exit 1
fi

info "Found source packages:"
echo "$CHANGES_FILES" | while read -r f; do
    echo "  $(basename "$f")"
done
echo

for changes in $CHANGES_FILES; do
    pkg=$(basename "$changes")
    info "Uploading: $pkg"
    dput "$PPA" "$changes"
    echo
done

info "=== All packages uploaded ==="
info "Check build status at: https://launchpad.net/~$(echo "$PPA" | sed 's|ppa:||;s|/.*||')/+archive/ubuntu/$(echo "$PPA" | sed 's|.*/||')/+packages"
