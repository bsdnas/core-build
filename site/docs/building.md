# Building from source

The build produces an installable ISO from the same sources the project
maintains. It is the supported way to get an image at the moment, since no
release has been published yet.

## Build host

The build host must run the **same FreeBSD version as the target**. This is not
a stylistic preference — ignoring it produced three kernel panics during
development. The customisation stage chroots into the target root and runs
`zpool` there, which autoloads `openzfs.ko` from *inside* the chroot: the
freshly built module for one FreeBSD version gets loaded into the running
kernel of another, and the vnode operation vector layout does not match.

Practical requirements, measured rather than guessed:

| | |
|---|---|
| FreeBSD | `stable/15`, matching the target |
| CPU | any number of cores; more is faster |
| RAM | 32 GB is known to work — see the note below |
| Disk | **320 GB.** 120 GB is not enough |
| Swap | 16 GB on a real partition |

About memory, precisely: 16 GB with 1 GB swap **fails** — `rust` is killed by
the out-of-memory handler. 32 GB with 12 parallel builders completes; that is
the measurement the table reports. It is conservative today, because `rust`,
`llvm`, `gcc` and `node` now build on disk rather than in tmpfs, which removed
the largest consumer — but no build below 32 GB has been attempted. Memory
scales with the number of parallel builders (`-J`, half the cores by default).

About the disk: each `make release` leaves roughly 1.3 GB behind in
`_BE/release` and nothing removes it. When the partition filled during
development, the build failed after 4 hours 50 minutes on seven apparently
unrelated ports — the real cause was a single `ENOSPC`, visible only in
`dmesg`. Use `tools/prune-builds.sh` and check `df -h /` before starting.

## Building

```
pkg install -y git gmake
git clone https://github.com/bsdnas/core-build.git
cd core-build
git checkout bsdnas
make bootstrap-pkgs
make checkout
make release
```

`make checkout` pulls the other repositories — the FreeBSD base fork, the
middleware, the web interface — at the branches pinned in
`build/profiles/freenas/repos.pyd`. The ports tree is **not** forked: the
quarterly branch from FreeBSD upstream is used directly, with the NAS-specific
ports overlaid from the middleware repository.

A complete build takes a few hours. The result is an ISO in
`freenas/_BE/objs/`.

## Repository layout

| repository | what it is |
|---|---|
| [`core-build`](https://github.com/bsdnas/core-build) | the build system, profiles, tooling, documentation |
| [`os`](https://github.com/bsdnas/os) | FreeBSD base with the NAS patch set, rebased onto `stable/15` |
| [`middleware`](https://github.com/bsdnas/middleware) | middleware, installer, NAS ports |
| [`webui`](https://github.com/bsdnas/webui) | the web interface |

## Keeping up with upstream

The point of the project is that the fork does not fall behind, so the tooling
for that is part of the repository rather than someone's habit:

```
tools/watch-upstream.sh          report what moved upstream
tools/watch-upstream.sh --ack    mark the current state as reviewed
tools/prune-builds.sh --apply    remove old build artefacts
tools/acceptance.sh install      install in a VM and verify through the API
```

The watcher tracks four things: new commits on FreeBSD `stable/15` under the
patch set, FreeBSD security advisories, the opening of the next quarterly ports
branch, and OpenZFS releases. It reports; a human decides. It deliberately does
not open pull requests — conflict resolution during a rebase is not something
to automate, and getting it wrong once already cost a build.
