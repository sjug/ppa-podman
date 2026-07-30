# Podman 6.0.2 PPA for Ubuntu 24.04 Noble (arm64)

Launchpad PPA packaging for Podman 6.0.2 and all dependencies for full
rootless container support on Ubuntu 24.04 Noble arm64 (DGX Spark).

**PPA:** [`ppa:sejug/podman`](https://launchpad.net/~sejug/+archive/ubuntu/podman)

## Packages

| Package | Version | Language | Purpose |
|---|---|---|---|
| podman | 6.0.2 | Go | Container management tool |
| podman-docker | 6.0.2 | Shell | Docker CLI emulation via podman |
| conmon | 2.2.1 | C | Container runtime monitor |
| crun | 1.28 | C | Fast OCI runtime |
| passt | 2026_07_28 | C | Rootless networking (pasta) |
| netavark | 2.0.0 | Rust | Container network stack |
| aardvark-dns | 2.0.0 | Rust | Container DNS server |
| containers-common | common 0.68.1 | config | Shared config files |
| go-toolchain-1.25 | 1.25.12 | binary | Go compiler for arm64 builds |
| rust-toolchain-1.88 | 1.88.0 | binary | Rust compiler for arm64 builds |

### Design decisions

- **Go 1.25 toolchain packaged in PPA**: Podman 6 requires Go 1.25.x, newer
  than Noble provides. The latest Go 1.25.x standalone binary for aarch64 is
  repackaged as a .deb.
- **Rust 1.88 toolchain packaged in PPA**: Netavark/Aardvark 2.0.0 require
  Rust 1.88, newer than Noble provides. The official Rust standalone binary
  for aarch64 is repackaged as a .deb.
- **Native rootless overlays**: `storage.conf` does not set `mount_program`,
  so the kernel's native overlay driver is used. No fuse-overlayfs dependency.
- **passt as default networking**: passt/pasta is the rootless network backend.
  Podman 6 removed slirp4netns support.
- **nftables over iptables**: Podman 6 removed iptables support; netavark uses
  nftables.
- **AppArmor support**: podman is built with `libapparmor-dev` so AppArmor
  profiles work out of the box.
- **NVIDIA GPU support**: podman's postinst hook auto-generates the CDI
  specification (`/etc/cdi/nvidia.yaml`) if `nvidia-ctk` is present, with
  timestamped backups of existing configs. NVIDIA Container Toolkit is expected
  to come from NVIDIA's repositories.
- **Podman stack focus**: this PPA packages Podman and the runtime/networking
  stack it needs. Buildah and Skopeo are not packaged here.

### Already in Noble repos (not packaged here)

`catatonit`, `uidmap`, `libgpgme`, `libseccomp`, `sqlite3`

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

Then `ssh -p 2222 YOUR_VM_USER@localhost` to get a shell inside. See
`CLAUDE.md` for how to create the VM from scratch, install the Go/Rust
vendoring toolchains, and copy in the GPG signing key.

### Local path and SSH hygiene

Keep machine-specific usernames and absolute paths out of the git repo. In
committed docs, notes, and examples, use placeholders such as `$HOME`, `$USER`,
and `YOUR_VM_USER` rather than `/home/alice` or a local login name.

A typical local layout is:

- host checkout: `$HOME/git/ppa-podman`
- VM working tree: `~/ppa-podman`

The VM copy only needs to be a synced working tree for builds; it does not have
to be a Git checkout.

Useful commands:

```bash
ssh -p 2222 YOUR_VM_USER@localhost
scp -P 2222 some-file YOUR_VM_USER@localhost:~/ppa-podman/
ssh-keygen -R '[localhost]:2222'   # if the VM was recreated and the host key changed
```

Note: `scp` uses uppercase `-P` for the port. `host:2222:path` is parsed as
part of the remote path, not as the port number.

### Build steps

Before vendoring Podman 6 sources, install the official x86_64 Go 1.25.x and
Rust 1.88 toolchains in the VM. The arm64 toolchains are packaged in this PPA
for Launchpad builds.

Run these inside the VM:

```bash
# 1. Install build tools
./scripts/setup-ppa.sh

# 2. Download upstream sources and vendor dependencies
./scripts/download-sources.sh

# 3. Build signed source packages (reads PPA_MAINTAINER from .env)
./scripts/build-source-packages.sh --sign YOUR_GPG_KEY_ID

# 4. Upload to your PPA
./scripts/upload-ppa.sh ppa:YOUR_LAUNCHPAD_USER/podman
```

### Single-package update workflow

For routine maintenance, it is usually safer to update one package at a time:

```bash
./scripts/download-sources.sh --only crun
./scripts/build-source-packages.sh --only crun --sign YOUR_GPG_KEY_ID
dput ppa:YOUR_LAUNCHPAD_USER/podman crun/crun_<version>_source.changes
```

### Upload safety

`scripts/upload-ppa.sh` uploads every `*_source.changes` file it finds in the
workspace. Use it only in a clean tree, or upload the exact `.changes` file you
just built with `dput` when you only want to publish one package.

For major updates that introduce new build-dependency packages, upload in
stages and wait for each stage to publish before the next one:

1. `go-toolchain` and `rust-toolchain`
2. `netavark` and `aardvark-dns`
3. `podman` and `podman-docker`
4. independent packages such as `passt` and `containers-common`

## Directory Structure

```
ppa-podman/
├── README.md
├── scripts/
│   ├── setup-ppa.sh               # Install build prerequisites
│   ├── download-sources.sh         # Download & vendor upstream sources
│   ├── build-source-packages.sh    # Build .dsc/.changes
│   └── upload-ppa.sh              # Upload to Launchpad PPA
├── podman/debian/                  # podman 6.0.2
├── podman-docker/debian/           # podman-docker 6.0.2
├── conmon/debian/                  # conmon 2.2.1
├── crun/debian/                    # crun 1.28
├── passt/debian/                   # passt 2026_07_28
├── netavark/debian/                # netavark 2.0.0
├── aardvark-dns/debian/            # aardvark-dns 2.0.0
├── containers-common/              # config files + debian/
│   ├── storage.conf
│   ├── registries.conf
│   ├── containers.conf
│   ├── policy.json
│   ├── seccomp.json
│   └── shortnames.conf
├── go-toolchain/debian/            # go 1.25.x (arm64 binary repackage)
└── rust-toolchain/debian/          # rust 1.88.0 (arm64 binary repackage)
```
