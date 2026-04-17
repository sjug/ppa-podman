# Podman 5.8.2 PPA for Ubuntu 24.04 Noble (arm64)

Launchpad PPA packaging for Podman 5.8.2 and all dependencies for full
rootless container support on Ubuntu 24.04 Noble arm64 (DGX Spark).

**PPA:** [`ppa:sejug/podman`](https://launchpad.net/~sejug/+archive/ubuntu/podman)

## Packages

| Package | Version | Language | Purpose |
|---|---|---|---|
| podman | 5.8.2 | Go | Container management tool |
| podman-docker | 5.8.2 | Shell | Docker CLI emulation via podman |
| conmon | 2.2.1 | C | Container runtime monitor |
| crun | 1.26 | C | Fast OCI runtime |
| passt | 2026_01_20 | C | Rootless networking (pasta) |
| netavark | 1.17.2 | Rust | Container network stack |
| aardvark-dns | 1.17.0 | Rust | Container DNS server |
| containers-common | 1.0.0 | config | Shared config files |
| rust-toolchain-1.86 | 1.86.0 | binary | Rust compiler for arm64 builds |

### Design decisions

- **Rust 1.86 toolchain packaged in PPA**: Ubuntu Noble ships Rust 1.75, but
  netavark/aardvark-dns require Rust 1.86. The official Rust standalone binary
  for aarch64 is repackaged as a .deb.
- **Native rootless overlays**: `storage.conf` does not set `mount_program`,
  so the kernel's native overlay driver is used. No fuse-overlayfs dependency.
- **passt as default networking**: passt/pasta is the rootless network backend.
  slirp4netns is not required.
- **nftables over iptables**: netavark uses nftables by default.
- **AppArmor support**: podman is built with `libapparmor-dev` so AppArmor
  profiles work out of the box.
- **NVIDIA GPU support**: podman's postinst hook auto-generates the CDI
  specification (`/etc/cdi/nvidia.yaml`) if `nvidia-ctk` is present, with
  timestamped backups of existing configs.

### Already in Noble repos (not packaged here)

`catatonit`, `uidmap`, `libgpgme`, `libseccomp`, `sqlite3`, `golang-1.24-go`

## Using the PPA

```bash
# Add the PPA
sudo add-apt-repository ppa:sejug/podman
sudo apt update

# Pin PPA over ESM (if Ubuntu Pro is enabled)
sudo tee /etc/apt/preferences.d/podman-ppa <<'EOF'
Package: *
Pin: release o=LP-PPA-sejug-podman
Pin-Priority: 1001
EOF
sudo apt update

# Install
sudo apt install podman

# Optional: Docker CLI compatibility
sudo apt install podman-docker
```

### Post-install rootless setup

```bash
# Ensure subuid/subgid are configured
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER

# Verify
podman info
podman run --rm docker.io/library/ubuntu echo "Hello from rootless Podman!"
```

### NVIDIA GPU support

If `nvidia-container-toolkit` is installed, the CDI spec is generated
automatically on podman install/upgrade. To verify:

```bash
podman run --rm --gpus all ubuntu nvidia-smi -L
```

## Building from source

Prerequisites: QEMU/KVM VM running Ubuntu Noble with build tools installed.

### Maintainer identity

The debian packaging files use a placeholder maintainer (`Podman PPA Maintainer
<maintainer@ppa>`). The build script substitutes your real identity from a
gitignored `.env` file at build time. Copy the example and fill in your details:

```bash
cp .env.example .env
# Edit .env with your Launchpad-registered name and email:
# PPA_MAINTAINER="Your Name <your.email@example.com>"
```

This keeps your email out of the public git history while satisfying Launchpad's
signing requirements.

### Booting the build VM

All build steps run inside a QEMU/KVM Noble VM (SSH on port 2222). Boot it
from the host with:

```bash
cd vm && qemu-system-x86_64 -name ppa-builder -machine type=q35,accel=kvm \
  -cpu host -smp 16 -m 32768 -drive file=ppa-builder.qcow2,if=virtio \
  -drive file=seed.iso,if=virtio,format=raw \
  -net nic -net user,hostfwd=tcp::2222-:22 -display none -daemonize
```

Then `ssh -p 2222 $USER@localhost` to get a shell inside. See `CLAUDE.md`
for how to create the VM from scratch, install Rust 1.86, and copy in the
GPG signing key.

### Build steps

Run these inside the VM:

```bash
# 1. Install build tools
./scripts/setup-ppa.sh

# 2. Download upstream sources and vendor dependencies
./scripts/download-sources.sh

# 3. Build signed source packages (reads PPA_MAINTAINER from .env)
./scripts/build-source-packages.sh --sign YOUR_GPG_KEY_ID

# 4. Upload to your PPA
./scripts/upload-ppa.sh ppa:sejug/podman
```

## Directory Structure

```
ppa-podman/
├── README.md
├── scripts/
│   ├── setup-ppa.sh               # Install build prerequisites
│   ├── download-sources.sh         # Download & vendor upstream sources
│   ├── build-source-packages.sh    # Build .dsc/.changes
│   └── upload-ppa.sh              # Upload to Launchpad PPA
├── podman/debian/                  # podman 5.8.2
├── podman-docker/debian/           # podman-docker 5.8.2
├── conmon/debian/                  # conmon 2.2.1
├── crun/debian/                    # crun 1.26
├── passt/debian/                   # passt 2026_01_20
├── netavark/debian/                # netavark 1.17.2
├── aardvark-dns/debian/            # aardvark-dns 1.17.0
├── containers-common/              # config files + debian/
│   ├── storage.conf
│   ├── registries.conf
│   ├── containers.conf
│   ├── policy.json
│   ├── seccomp.json
│   └── shortnames.conf
└── rust-toolchain/debian/          # rust 1.86.0 (arm64 binary repackage)
```
