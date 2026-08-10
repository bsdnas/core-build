# Maintaining the fork

A fork lives exactly as long as somebody keeps watching upstream. The gap
between TrueNAS CORE 13.3 and FreeBSD 15 that had to be cleared up at the start
of the project did not arise from a hard technical problem — nobody had forward
ported the patches for a year. This document exists so that the story does not
repeat itself.

## The watcher

```
tools/watch-upstream.sh              report to the terminal
tools/watch-upstream.sh --quiet      stay silent when there is nothing new (for scheduling)
tools/watch-upstream.sh --ack        mark the current state as handled
```

Exit codes: `0` — nothing new, `10` — there is something to report, `1` — error.

The watcher changes nothing and opens no PRs. It reports; the decision is made
by a human. Handled items are marked with `--ack` and recorded in
`.upstream-seen` (a local file, not part of the repository). Without that, the
report is always "red", and such a report stops being read within a month.

Scheduled run, once a week:

```
0 9 * * 1 cd /usr/build && tools/watch-upstream.sh --quiet
```

## What to do for each signal

### The FreeBSD base has moved

Our patch set sits on top of `stable/15` in `bsdnas/os`, branch
`base/stable-15`. The model is rebase, not merge: it was precisely the
accumulated merges that made the original CORE tree unmanageable.

```
git fetch up                                    # freebsd/freebsd-src
git rebase --onto up/stable/15 <previous-base> base/stable-15
```

Resolve conflicts by hand, commit by commit. **Do not "resolve" conflicts by
filtering with regular expressions** — doing that once left both sides of a
conflict in the tree, and the build failed much later and in a completely
different place.

After the rebase — a full build and `tools/acceptance.sh install`, otherwise
the rebase is pointless.

### A security advisory has been published

FreeBSD advisories (`SA` — security, `EN` — errata) are applied to `stable/15`
by upstream, so an ordinary rebase of the patch set is usually enough. Separate
attention is needed when something we patched ourselves is affected: ZFS, the
kernel, the loader.

Whether the fix has reached our branch can be checked by the date of the commit
in `stable/15` relative to the date of the advisory.

### The next quarterly ports branch has opened

The ports branch is set in `build/profiles/freenas/repos.pyd`. Changing the
quarter changes the versions of hundreds of packages at once, so it must be
changed **only together with a full rebuild and acceptance run**, not "along the
way" with some other edit.

Worth remembering: ports disappear. `archivers/pxz` left the tree; the distfiles
of `arcconf`, `megacli` and `tw_cli` vanished both from the vendors and from
`distcache.FreeBSD.org`. When the quarter changes, the build may fail exactly
like that — this is not a breakage of the build system.

### A new OpenZFS has been released

The middleware contains a ready-made helper:

```
tools/update_openzfs_ports.py <version> <tag sha>
```

The port version is the release tag without the `zfs-` prefix (release
`zfs-2.4.3` → `PORTVERSION= 2.4.3`).

Updating OpenZFS is the riskiest of the four: it touches the on-disk data
format. The acceptance run must include importing a pool created by the previous
version.

## Disk space on the build machine

```
tools/prune-builds.sh            show what will be deleted
tools/prune-builds.sh --apply    delete, keeping the last 3 builds
```

Every `make release` leaves behind a directory of roughly 1.3 GB in
`_BE/release` plus an image next to the object directory, and nothing removes
them.

This is worth remembering because a full partition does not look like a full
partition. Once it showed up like this: the build ran for 4 hours 50 minutes and
failed on seven ports at once — `rust` after 3 hours 39 minutes, `grub2-efi`,
`lsof`, an Angular build with `NG6002` in primeng and so on. Each failure looked
like an independent breakage; the real cause was a single one — `ENOSPC` — and it
was visible only in `dmesg` (`filesystem full on /`) and in one line deep inside
the Angular log.

The rule: look at `df -h /` before a long build. Less than 40 GB free — clean up
first. The threshold is not abstract: `rust` alone needs a working directory of a
dozen gigabytes, and it builds last and for three and a half hours.

Give the build machine **at least 320 GB**. 120 GB is not workable — it is
enough for exactly one build with no margin. On a virtual machine the disk can
be extended on the fly; the build does not need to be interrupted:

```
qm disk resize <vmid> scsi0 +200G          # on the hypervisor
camcontrol reprobe da0                     # in the guest system
gpart recover da0 ; gpart resize -i 5 da0
growfs -y /dev/gpt/rootfs
```

`growfs` works on a mounted root — this requires neither unmounting nor a
reboot.

## How to interrupt a build correctly

Killing `make release` halfway through is not enough: poudriere mounts the source
tree into its jail via nullfs, and the mount survives the death of the process.
The next build fails a minute in when it tries to clean the directory:

```
rm: .../objs/jail/usr/src/...: Read-only file system
==> ERROR: Build failed
```

The error looks like a build breakage, although it is a leftover from the
previous run. So after a forced stop:

```
mount | grep /usr/build/freenas/_BE/objs      # see what is left
umount /usr/build/freenas/_BE/objs/jail/usr/src
jls                                           # poudriere jails must not be left hanging
```

and only then start again.

## Checks before committing

```
tools/check-sh.sh                    # shell script syntax (in middleware)
tools/acceptance.sh install <iso>    # clean installation
tools/acceptance.sh upgrade <iso>    # upgrade over a working system
```

## The rule about the source of truth

Edits are made **in one place** and propagate through GitHub. The build machine
is a consumer of the repositories, not a place to edit them: an edit made there
was once wiped out by a force push and lost.
