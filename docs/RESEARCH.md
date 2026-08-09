# TrueNAS CORE (FreeBSD): sources, project status and the path to a current FreeBSD

Research date: 2026-08-02.

## 1. What has been cloned into this project

```
truenas-core/          official iXsystems sources (latest CORE version)
  core-build/          https://github.com/truenas/core-build  (formerly truenas/build) — the build system
  middleware/          https://github.com/truenas/middleware, branch truenas/13.3-u1-stable
                       (formerly truenas/freenas: middleware + nas_ports + src)
  os/                  https://github.com/truenas/os, branch truenas/13.3-stable — the FreeBSD fork
                       (+ remote `upstream` = github.com/freebsd/freebsd-src)
  webui/               https://github.com/truenas/webui, branch truenas/13.3-stable
  freenas-pkgtools/    the update mechanism (freenas-update, manifests, trains)

forks/                 the live community fork, brought up to FreeBSD 15
  dravanet-core-build/ branch master-dravanet
  dravanet-middleware/ branch truenas/13.3-stable-dravanet
  dravanet-os/         branch freebsd/releng/15.0-dravanet (+ remote `up` = freebsd-src)

zvault/
  zvio-build/          build system of the zVault fork (frozen since May 2025)
```

No GitHub authentication is required anywhere — all the repositories are public.

## 2. Status of the official CORE

* The last release is **TrueNAS CORE 13.3-U1.2, 29 April 2025**, based on
  **FreeBSD 13.3-RELEASE-p2**. The iX documentation states outright:
  "13.3-U1.2 was the final release for the TrueNAS CORE 13.3 software train".
* The 13.0 branch ended at 13.0-U6.8 (the tags `TN-13.0-U6.3…U6.8` point at the
  same middleware commit — those were rebuilds only).
* The last commits in `truenas/middleware` (branch `truenas/13.3-u1-stable`) are
  from **November 2024**, in `core-build` (master) — **2024-11-18**. Development
  has not resumed.
* The official migration path according to iX is TrueNAS 25.10 (Goldeye), Linux.
* **FreeBSD 13 is out of support.** Current are stable/15 (EOL 2029-12-31),
  releng/15.1 (until 2027-03-31), releng/15.0 (until 2026-09-30), stable/14
  (until 2028-11-30), releng/14.4 (until 2026-12-31). In other words, stock CORE
  today runs on a base that receives no security patches.

## 3. How the CORE build is put together

The entry point is `core-build` (FreeBSD make + a Python DSL). The repository
manifest is `build/profiles/freenas/repos.pyd`; in the official 13.3 it pulls in:

| repo | branch |
|---|---|
| os (the FreeBSD fork) | truenas/13.3-stable |
| freenas (middleware) | truenas/13.3-stable |
| webui | truenas/13.3-stable |
| ports (fork of the ports tree) | truenas/13.3-stable |
| py-licenselib, freenas-pkgtools, py-bsd | master |
| iocage | truenas/13.0-stable |

Targets: `make checkout` → `make update` → `make release` (which covers `os`,
`ports`, `packages`, `freenas`, `cdrom`/`images`, `update`). The build machine is
FreeBSD 13.x, ~16 GB RAM, ~80 GB of disk. Artifacts: an ISO and an upgrade tar
(`build/tools/create-upgrade-distribution.py`, `build/tools/create-iso.py`).
There is no signing step in the build repository — signing and publishing of the
train were done separately on `update-master.tn.ixsystems.net` (targets
`update-push`, `release-push`). The layer of TrueNAS-specific ports (`freenas/*`:
freenas-files, freenas-migrate93, middlewared, openzfs, webui and so on) lives in
`middleware/nas_ports/` and is overlaid on top of the ports tree.

## 4. Who is carrying on the FreeBSD line

### 4.1 dravanet (Richard Kojedzinszky) — **the most alive option, already on FreeBSD 15.0**

A set of `dravanet/truenas-*` forks, active until **20 July 2026**. In the
`repos.pyd` of his build:

| repo | branch |
|---|---|
| os | `dravanet/truenas-os` → `freebsd/releng/15.0-dravanet` |
| freenas | `dravanet/truenas-middleware` → `truenas/13.3-stable-dravanet` |
| webui | `dravanet/truenas-webui` → `truenas/13.3-stable` |
| **ports** | **`freebsd/freebsd-ports` → `2026Q2`** (the ports tree fork has been thrown out) |
| py-bsd | `dravanet/py-bsd` → master |
| iocage | `freenas/iocage` → truenas/13.0-u6.3-stable |

Key milestones by commit:
`Build TrueNAS 13.3 based on FreeBSD releng/14.3` (2025-07-09) → `feat: freebsd 15 compatibility`
and `feat: build from FreeBSD 15.0` (2026-04-05) → `feat: update ports tree to 2026Q2` (2026-04-12).
On top of that: OpenZFS updated to **2.4.3**, Samba moved to upstream
**net/samba423**, py-libzfs brought up to 25.04, http2 in nginx, the limit on the
number of boot-pool disks removed.

He does not publish ready-made ISOs or releases — these are sources and a build
system, and you have to build it yourself.

### 4.2 zVault — effectively frozen

A fork of CORE 13.3 with the iX branding stripped out (the first release of
2025-02-25 was withdrawn following a copyright claim from iXsystems, then
reissued). Repositories `zvaultio/zvio-*`: the last pushes are from **May 2025**,
the last release is `zVault-13.3-MASTER-202505042329` (2025-05-04, prerelease).
An issue opened on 2025-05-17 asking about plans for moving to FreeBSD 14/15 is
still open, with no answer from the maintainers. On the roadmap, moving to
FreeBSD 14 was only the 4th step. There are no signs of life through 2026.

### 4.3 xiphis — a private rebase onto FreeBSD 13.5

`xiphis/freenas-os` branch `releng/13.5`, a complete set of forks, active until
**November 2025**. An intermediate option: it stays within 13.x (also EOL), but
is newer than 13.3.

### 4.4 JohnM549/OpenNAS, os-14.3

Branches `codex/update-to-freebsd-14.3` — an attempt at an automated (Codex)
forward port, December 2025. There is no separate community or releases, and the
quality has not been assessed.

### 4.5 XigmaNAS — not a CORE fork, but a live FreeBSD NAS

A different code line (NAS4Free/FreeNAS 7), but actively developed: stable
release 14.3.0.5.10432 of 2025-09-10, based on FreeBSD 14.3-RELEASE-P4. If what
is needed is a supported FreeBSD NAS rather than TrueNAS middleware
specifically, this is the most dependable option out of the box.

## 5. How hard it is to move CORE onto a current FreeBSD — measured against the repositories

**The base (os).** The difference of `truenas/13.3-stable` relative to the point
of divergence from upstream stable/13: 129 commits, 424 files. But the
overwhelming majority is not iX-specific work, it is vendor imports
(contrib/sendmail — 116 files, contrib/expat — 74, unbound, tzdata, caroot) and
cherry-picks of upstream fixes. What is genuinely iX's own:

* `usr.sbin/ixnvdimm` plus the NVDIMM driver (needed only by their HA hardware);
* CTL/isp improvements (mostly upstream already — the author, Alexander Motin,
  commits to FreeBSD as well);
* bhyve/vncserver (shortened RFB timeouts), the EFI serial console in the loader;
* `utimensat(2)` with an explicit birthtime, a sysctl for generation,
  `pmbr-datadisk`, and small things in the rc scripts.

Just how little that is can be seen from dravanet: on top of `releng/15.0` he has
only **7 commits, 12 files** (live reconfiguration of ctld, EINTR in ctld, the
generation sysctl, devd dependencies, force_depends in the mountd/nfsd rc
scripts, pmbr-datadisk). In other words, moving the base OS to FreeBSD 14/15 is
not "porting a kernel fork" but "forward porting a handful of patches".

**The bulk of the work is not in base, it is in the surrounding layer.** The
middleware delta at dravanet is 69 commits, 147 files: compatibility with the
newer Python versions in the ports tree, Samba 4.20→4.23, OpenZFS 2.2→2.4,
py-netif/py-bsd/py-libzfs, netsnmpagent, PAM without OPIE, ports that upstream
renamed or dropped (`www/novnc-websockify` → `devel/py-websockify`), the webui
build, and the behaviour of rc scripts on the newer sh. Plus giving up a private
ports fork in favour of the FreeBSD quarterly branches — a one-time expense, but
it removes the main source of rot.

## 6. A practical plan

### Option A (recommended) — take a ready, live fork

On a FreeBSD build machine (dravanet builds from a current base; the official
README still requires FreeBSD 13.x — this point has to be checked in place):

```sh
pkg install -y git
git clone -b master-dravanet https://github.com/dravanet/truenas-core-build /usr/build
cd /usr/build
make bootstrap-pkgs
python3 -m ensurepip && pip3 install six
make checkout
make release
```

The output is an ISO and an upgrade file in `freenas/_BE/release/`. From there,
either a clean installation from the ISO, or
`System → Update → Install manual update file` on an existing 13.x installation.

### Option B — your own rebase (if you need control or a different target version)

1. In `truenas-core/os`, take the range
   `merge-base(truenas/13.3-stable, upstream/stable/13)..truenas/13.3-stable`,
   discard the vendor and already-upstream commits, and apply the remaining 7–15
   patches to `upstream/releng/15.1` (or stable/14, if longer support is needed —
   EOL 2028-11-30).
2. Ports: do not carry `truenas/ports`; take a quarterly `freebsd-ports` branch
   (2026Q2/Q3) and overlay `middleware/nas_ports/` on top.
3. Middleware: use `dravanet-middleware` as a reference — almost all of the
   conflicts with the new ports tree have already been worked out there; put your
   own changes on top.
4. In `build/profiles/freenas/repos.pyd` set your own URLs and branches; in
   `kernel/TRUENAS.amd64` reconcile the module list with the new kernel.

### Delivery to existing installations

* One-off — a manual update tar through the GUI or `freenas-update`; there is no
  signing step in core-build.
* Ongoing — your own update train: `freenas-pkgtools` plus your own manifest
  server; the `update-push`/`release-push` targets in Makefile.inc1 are tailored
  to the iX infrastructure and have to be replaced with your own. Clients switch
  over by changing the train in `/data/update.conf` or in the update settings.

## 7. Risks and pitfalls

* **OpenZFS feature flags are irreversible.** 13.3 ships with OpenZFS 2.2,
  dravanet has 2.4.3. After `zpool upgrade`, going back to the official CORE or
  to an older build is impossible. Do not upgrade the pool until the new build
  has been verified; this also breaks the way back to older TrueNAS SCALE/CE
  versions.
* **Legal.** The code base is under the iX licence (`LICENSE.IX`), and the
  TrueNAS branding is a trademark. zVault has already received a copyright claim.
  For personal or internal use there is no problem; for publishing ISOs the
  branding and the proprietary pieces have to be stripped out.
* **iocage and plugins.** The iX plugin index is no longer updated; jails will
  have to be run off a private index (as was done in
  `zvaultio/iocage-plugin-index`) or moved to bastille.
* **releng/15.0 reaches EOL on 2026-09-30** — if the dravanet build is taken as
  is, a move to 15.1/stable/15 will soon be required. For "install and forget",
  aiming at stable/14 (until 2028) or stable/15 (until 2029) is more stable.
* **HA/Enterprise functionality** (ixnvdimm, failover) is neither supported nor
  tested in the community forks.
