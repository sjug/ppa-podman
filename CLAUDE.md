# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Debian packaging for a Launchpad PPA (`ppa:sejug/podman`) that provides Podman and all dependencies for Ubuntu arm64. The target is a DGX Spark (hostname `buddy`, Ubuntu 24.04 Noble, aarch64).

The PPA exists because Noble's repos only have Podman 4.9.3 and Ubuntu Pro's ESM has the same version at priority 510.

## Architecture

Each subdirectory is a standalone Debian source package with a `debian/` directory:

- **C packages** (conmon, crun, passt): standard make/autotools builds
- **Rust packages** (netavark, aardvark-dns): cargo builds with vendored deps, require `rust-toolchain-1.88` from the PPA
- **Go packages** (podman, podman-docker): make builds with vendored deps, require `go-toolchain-1.25` from the PPA
- **Config package** (containers-common): no compilation, ships storage.conf/registries.conf/etc
- **Toolchain packages**: repackage official Go 1.25.x and Rust 1.88 aarch64 standalone binaries as .debs

## Launchpad setup (one-time)

1. **Create a Launchpad account** at https://launchpad.net/ using your email
2. **Generate a GPG key**: `gpg --batch --gen-key` (RSA 4096, no passphrase for automation)
3. **Upload key to Ubuntu keyserver**: `gpg --keyserver keyserver.ubuntu.com --send-keys KEYID`
4. **Register key on Launchpad**: https://launchpad.net/~sejug/+editpgpkeys — paste the fingerprint. Launchpad sends an encrypted confirmation email; decrypt with `gpg --decrypt` and click the link.
5. **Create the PPA**: https://launchpad.net/~sejug/+activate-ppa — name it `podman`
6. **Configure architectures**: https://launchpad.net/~sejug/+archive/ubuntu/podman/+edit — enable arm64, disable amd64

## Build VM setup

Source packages are built in a QEMU/KVM Ubuntu Noble VM (x86_64 host with KVM accel). SSH on port 2222.

### Creating the VM from scratch

Requires `qemu-full` and `cdrtools` (for `mkisofs`) on the host.

```bash
mkdir -p vm

# Download Ubuntu Noble cloud image
curl -sSL -o noble-server-cloudimg-amd64.img \
  "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"

# Create VM disk backed by cloud image
qemu-img create -f qcow2 -b "$(pwd)/noble-server-cloudimg-amd64.img" -F qcow2 vm/ppa-builder.qcow2 20G
```

Create `vm/meta-data`:
```yaml
instance-id: ppa-builder-001
local-hostname: ppa-builder
```

Create `vm/user-data` (replace the username and SSH key; do not commit your real local username):
```yaml
#cloud-config
hostname: ppa-builder
users:
  - name: YOUR_VM_USER
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 YOUR_SSH_PUBLIC_KEY
package_update: true
packages:
  - build-essential
  - cargo
  - curl
  - debhelper
  - devscripts
  - dpkg-dev
  - dput
  - git
  - libapparmor-dev
  - libassuan-dev
  - libbtrfs-dev
  - libcap-dev
  - libglib2.0-dev
  - libgpgme-dev
  - libseccomp-dev
  - libsqlite3-dev
  - libssl-dev
  - libsystemd-dev
  - libtool
  - libjson-c-dev
  - go-md2man
  - pkg-config
  - protobuf-compiler
  - python3
  - rustc
  - autoconf
  - automake
  - bash-completion
runcmd:
  - echo "Build VM ready" > /tmp/vm-ready
```

Create the seed ISO and boot:
```bash
mkisofs -output vm/seed.iso -volid cidata -joliet -rock vm/user-data vm/meta-data
```

### Booting the VM

```bash
cd vm && qemu-system-x86_64 -name ppa-builder -machine type=q35,accel=kvm \
  -cpu host -smp 16 -m 32768 -drive file=ppa-builder.qcow2,if=virtio \
  -drive file=seed.iso,if=virtio,format=raw \
  -net nic -net user,hostfwd=tcp::2222-:22 -display none -daemonize
```

### Host/VM workspace layout

Keep machine-specific usernames and absolute paths out of committed files. In
docs, scripts, and examples use placeholders such as `$HOME`, `~/ppa-podman`,
and `YOUR_VM_USER` rather than `/home/alice/...` or a local login name.

Typical local layout:
- host checkout: `$HOME/git/ppa-podman`
- VM working tree: `~/ppa-podman`

The VM copy only needs to be a synced working tree for packaging builds; it
does not need to be a Git checkout.

### SSH/SCP notes

```bash
ssh -p 2222 YOUR_VM_USER@localhost
scp -P 2222 some-file YOUR_VM_USER@localhost:~/ppa-podman/
```

Important: `scp` uses uppercase `-P` for the port. `host:2222:path` is parsed
as part of the remote path, not the port.

If the VM is recreated and SSH reports a changed host key:

```bash
ssh-keygen -R '[localhost]:2222'
```

### Installing Go 1.25.x and Rust 1.88 on the VM (required for vendoring)

The VM's distro toolchains are too old for Podman 6. Install official x86_64
standalone toolchains on the VM before running `download-sources.sh`. Use the
latest Go 1.25.x patch release (currently 1.25.12) and Rust 1.88.x to match the
Launchpad arm64 toolchain packages.

```bash
ssh -p 2222 YOUR_VM_USER@localhost

# Go 1.25.x
sudo rm -rf /usr/local/go
curl -sSL "https://go.dev/dl/go1.25.12.linux-amd64.tar.gz" | sudo tar -C /usr/local -xz

# Rust 1.88
curl -sSL "https://static.rust-lang.org/dist/rust-1.88.0-x86_64-unknown-linux-gnu.tar.xz" | tar xJ
cd rust-1.88.0-x86_64-unknown-linux-gnu && sudo ./install.sh --prefix=/usr/local
```

After this, `go mod vendor` uses `/usr/local/go/bin/go` (1.25.x) and
`cargo vendor` uses `/usr/local/bin/cargo` (1.88.x), producing dependency trees
that match what Launchpad builds with.

### Copying GPG key into the VM

The signing key lives on the host. Export and import into the VM:

```bash
gpg --export-secret-keys KEYID > /tmp/ppa-key.asc
scp -P 2222 /tmp/ppa-key.asc YOUR_VM_USER@localhost:/tmp/
ssh -p 2222 YOUR_VM_USER@localhost "gpg --batch --import /tmp/ppa-key.asc && rm /tmp/ppa-key.asc"
rm /tmp/ppa-key.asc
```

## Build workflow

```bash
# Scripts (run inside VM)
./scripts/setup-ppa.sh                              # install build tools
./scripts/download-sources.sh                        # fetch + vendor deps
./scripts/build-source-packages.sh --sign GPGKEYID   # build .dsc/.changes
./scripts/upload-ppa.sh ppa:YOUR_LAUNCHPAD_USER/podman
```

### Single-package update workflow

For routine maintenance, prefer targeted builds and uploads:

```bash
./scripts/download-sources.sh --only crun
./scripts/build-source-packages.sh --only crun --sign GPGKEYID
dput ppa:YOUR_LAUNCHPAD_USER/podman crun/crun_<version>_source.changes
```

## Critical gotchas learned from building this PPA

- **Vendoring must use the target toolchain versions.** Noble has older Go/Rust toolchains; Podman 6 needs Go 1.25.x and Netavark/Aardvark 2.1.0 need Rust 1.88.x. Install official x86_64 Go/Rust toolchains on the build VM before running `go mod vendor` or `cargo vendor`.

- **Launchpad rejects re-uploads of orig tarballs with the same filename but different contents.** If you re-vendor and need a new orig tarball, change the upstream version string (e.g., append `+ds` suffix: `netavark_2.0.0+ds.orig.tar.gz`).

- **PPA architecture must be explicitly configured.** Default is amd64 only. Enable arm64 and disable amd64 at `https://launchpad.net/~sejug/+archive/ubuntu/podman/+edit`. Packages uploaded before arm64 was enabled won't get arm64 builds — they need a version bump and re-upload.

- **ESM overrides PPA priority.** Ubuntu Pro's ESM repo has priority 510 vs PPA's 500. An APT pin file is required: `/etc/apt/preferences.d/podman-ppa` with `Pin-Priority: 1001`.

- **Pre-built toolchains need debhelper no-op overrides.** Use `override_dh_dwz` and `override_dh_strip` for prebuilt binaries. For Go, also disable `dh_strip_nondeterminism` because the upstream source tree contains intentionally malformed zip testdata that the normalizer cannot parse, and disable `dh_shlibdeps` because the source tree includes cross-architecture ELF testdata that `dpkg-shlibdeps` treats as package binaries.

- **`make install` for podman requires rootlessport and quadlet.** The build target must be `make podman rootlessport quadlet docs`, not just `make podman docs`.

- **Podman 6 completions should not be regenerated on Launchpad.** The upstream tarball already ships generated completions. `make completions` runs the built `podman` binary, and Podman 6 refuses to run on Launchpad's cgroup-v1 build hosts (`Cgroups v1 not supported`). If skipping completions, build `podman-remote` explicitly because `make install` still installs it.

- **podman-docker needs `make docker-docs`** to generate docker-* man pages before `make install.docker-docs`.

- **`scripts/upload-ppa.sh` uploads every `*_source.changes` file it finds.** Use `dput` with an explicit `.changes` file for routine single-package uploads, or run the helper only in a clean workspace.

- **Upload new build-dependency stacks in stages.** For Podman 6, upload `go-toolchain`/`rust-toolchain` first and wait for them to publish, then upload `netavark`/`aardvark-dns`, then `podman`/`podman-docker`. Launchpad builders only see published PPA binaries, not source uploads that are still building.

## Maintainer identity

Packaging files use placeholder `Podman PPA Maintainer <maintainer@ppa>`. Real identity is in `.env` (gitignored), substituted by `build-source-packages.sh` at build time. See `.env.example`.

## GPG key

Key ID `2142A1C783073BEE` registered with Launchpad under user `sejug`. Revocation cert at `~/.gnupg/openpgp-revocs.d/C482160FE67107B6053AA7372142A1C783073BEE.rev`.

## Version bumping

To re-upload a package with packaging changes only (no upstream version change), bump the Debian revision in `debian/changelog` (e.g., `ppa1` → `ppa2`), rebuild the source package, and `dput`.

## Upgrading to a new upstream version

When a new upstream release comes out (e.g., podman 6.0.2):

1. **Update `scripts/download-sources.sh`** — change the version in the relevant `pkg_*()` function
2. **Update `debian/changelog`** — prepend a new version entry (e.g., `6.0.2-1ppa1~noble1`). Do NOT replace old entries — they are history.
3. **Update `scripts/build-source-packages.sh`** — change the version/tarball in the `build_quilt_package` line
4. **Update `debian/control`** if build deps changed upstream (check Arch PKGBUILD diff for hints)
5. **Update `README.md`** — version table, title, description, directory tree
6. **Run `download-sources.sh`** to fetch and vendor the new source
7. **Build and upload** as normal

For **podman**: remember that `podman-docker` shares the same upstream source. Both `download-sources.sh` and `build-source-packages.sh` must be updated together. The tarball for `podman-docker` is named `podman-docker_<ver>.orig.tar.gz` (not `podman_<ver>.orig.tar.gz`).

For Rust packages (netavark, aardvark-dns), also check:
- Does the new version require a newer Rust MSRV? Check `rust-version` in `Cargo.toml`. If it exceeds the packaged Rust version, the rust-toolchain package needs updating too.
- If re-vendoring with the same upstream version, you must change the orig tarball filename (append/change `+ds` suffix) because Launchpad rejects different contents with the same filename.

For toolchain packages, update the download URL and checksum in `download-sources.sh`, bump `debian/changelog`, and update `debian/rules` if the tarball filename changes. Download the new aarch64 standalone for Launchpad source packaging and also install the matching x86_64 version on the build VM for vendoring.
