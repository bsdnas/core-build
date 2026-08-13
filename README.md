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
