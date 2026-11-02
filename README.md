# Building BSDnas from source

BSDnas is a community fork that continues TrueNAS CORE on current FreeBSD.
TrueNAS CORE stopped at 13.3, on a FreeBSD release that has since been removed
from the FreeBSD mirrors; this tree builds the same system on FreeBSD
`stable/15` and keeps tracking it.

Documentation: <https://bsdnas.com/> — including
[what actually works and what was never tested](https://bsdnas.com/status/).

BSDnas is an independent fork. It is not produced, endorsed or supported by
iXsystems, Inc. TrueNAS is their trademark.

All commands below must be run as `root`.

## What BSDnas itself needs to run

**Not to be confused with the build requirements below.** The system is modest;
the machine that *builds* it is not.

| | measured |
|---|---|
| RAM to boot and run | **4 GB is enough**; 2 GB also reached `READY` on the stand |
| RAM in practice | more memory goes to the ZFS ARC cache and to whatever you run — it buys throughput, not the ability to boot |
| CPU | amd64, 64-bit |
| Boot device | dedicated; the installer takes the whole device |

The installer warns below 7 GB and continues. That warning is inherited from
TrueNAS and does not describe what the system needs. Full detail:
[Installing](https://bsdnas.com/install/).

## Requirements for a build host

* Hardware
  * amd64-compatible 64-bit Intel or AMD CPU
  * **RAM: 32 GB is known to work.** What was actually measured: 16 GB with
    1 GB swap fails — `rust` is killed by the out-of-memory handler; 32 GB with
    12 parallel builders completes. The figure is conservative now, because
    `rust`, `llvm`, `gcc` and `node` build on disk instead of tmpfs since then,
    which removed the largest consumer — but a build on less than 32 GB has not
    been tried. Memory scales with the number of parallel builders
    (`-J`, half the cores by default), so reduce it on a smaller machine.
  * Cores: any number works; more is faster. Give it swap on a real partition.
  * **320 GB of free disk space.** 120 GB is not enough: each `make release`
    leaves about 1.3 GB behind and nothing removes it

* Operating system
  * The build host must run **the same FreeBSD version as the target**
    (`stable/15`). This is not a stylistic preference — the customisation stage
    chroots into the target root and runs `zpool` there, which autoloads the
    freshly built `openzfs.ko` into the running kernel. Version mismatch
    panics the build host.

## Make targets

* `checkout` — clone the source repositories listed in
  `build/profiles/freenas/repos.pyd`
* `update` — `git pull` those repositories
* `release` — build the release: world, kernel, ports, packages, ISO and
  update files
* `clean` — remove built files

## Procedure

```
pkg install -y git
git clone https://github.com/bsdnas/core-build.git /usr/build
cd /usr/build
git checkout bsdnas
make bootstrap-pkgs
make checkout
make release
```

The result is an ISO in `freenas/_BE/objs/` and an update train directory in
`freenas/_BE/release/`.

Subsequent builds:

```
make update
make release
```

A clean build takes a few hours — poudriere has to build every port. Later
builds are much faster because only what changed is rebuilt.

### Signing the package repositories

An installed system updates from two pkg repositories the build produces: the
base packages (`freenas/_BE/objs/pkgbase-repo`) and the ports poudriere built.
It checks their catalogues with `signature_type: fingerprints` against the key
fingerprints its image carries, and refuses a catalogue that is not signed.

The build signs both when it is given the repository key, an RSA private key
in PEM:

```
env BSDNAS_PKG_SIGNING_KEY=/path/to/repo.key make release
```

The key stays on the build machine and is read only by
`tools/pkg-repo-sign.sh`, the signing command `pkg repo` calls. Without the
variable the build still works and the catalogues stay unsigned;
`tools/publish-pkgbase.sh` and `tools/publish-ports.sh` then refuse to publish
them. An already built repository can be signed in place:

```
pkg repo <dir> signing_command: tools/pkg-repo-sign.sh /path/to/repo.key
```

The fingerprint clients trust ships in the image from the middleware
repository, under `/usr/local/share/keys/bsdnas-pkg/trusted/`. Replacing the
key goes in that order: the new fingerprint is added to `trusted/` and shipped
first, the build switches to the new key after that, and the old fingerprint
moves to `revoked/` last.

Before anything is copied, both publish scripts check the catalogue the way a
client will, with `tools/verify-pkg-repo.sh`: every archive holds just its
catalogue file with a signature that verifies, all of them are signed by one
key, and that key's fingerprint is in `trusted/` and not in `revoked/`. The
fingerprints are the ones the clients ship, taken from

* `BSDNAS_PKG_FINGERPRINTS`, the path of a `bsdnas-pkg` directory holding
  `trusted/` (and `revoked/`), when it is set;
* otherwise the middleware checkout of the build tree,
  `freenas/_BE/freenas/src/freenas/usr/local/share/keys/bsdnas-pkg` -- what
  the image being published was built with.

With neither there, publishing stops; the check is never skipped. On a host
that is not the build machine, point the variable at a middleware checkout:

```
env BSDNAS_PKG_FINGERPRINTS=/path/to/middleware/src/freenas/usr/local/share/keys/bsdnas-pkg \
    tools/publish-ports.sh <user@host> <remote-path> <repo-dir>
```

The check unpacks the catalogue with `tar`. On FreeBSD that is bsdtar and
handles the zstd catalogues pkg writes; on Linux GNU tar needs the `zstd`
program for that, and without it the check fails -- and publishing with it.

## Tooling

| | |
|---|---|
| `tools/watch-upstream.sh` | report what moved upstream: FreeBSD `stable/15`, security advisories, the quarterly ports branch, OpenZFS |
| `tools/acceptance.sh` | install or upgrade in a virtual machine and verify the result through the API |
| `tools/prune-builds.sh` | remove old build artefacts before the disk fills up |
| `tools/sign-release.sh` | checksum and sign a release |

Maintenance procedures — rebasing the FreeBSD patch set, reacting to security
advisories, moving to the next quarterly ports branch — are in
[`docs/MAINTENANCE.md`](docs/MAINTENANCE.md).

## Repositories

| repository | what it is |
|---|---|
| [`core-build`](https://github.com/bsdnas/core-build) | this tree: build system, profiles, tooling, documentation |
| [`os`](https://github.com/bsdnas/os) | FreeBSD base with the NAS patch set, rebased onto `stable/15` |
| [`middleware`](https://github.com/bsdnas/middleware) | middleware, installer, NAS ports |
| [`webui`](https://github.com/bsdnas/webui) | the web interface |
| [`pkgtools`](https://github.com/bsdnas/pkgtools) | update client and package tooling |
