# Upgrading TrueNAS CORE 13.3 to bsdnas on FreeBSD 15

This document describes what has been verified on the test bench, not what is
assumed. Every statement here comes from a measurement; where no check was made,
that is said plainly.

## What has been verified

The official iX image `TrueNAS-13.3-U1.2` was installed on the test machine, set up
(a mirror pool, a dataset, an SMB share, an iocage jail) and upgraded with the bsdnas image
based on FreeBSD stable/15.

Result:

| check | result |
|---|---|
| the system comes up | yes, `state: READY` |
| the configuration survives | pools, shares, users, password -- all present |
| a pool created by OpenZFS 2.2 | imports and works on 2.4.3 |
| datasets | present |
| an SMB share from 13.3 | works, `enabled` |
| an iocage jail with a 13.3 userland | starts on the 15 kernel, data intact |

A single step changes: FreeBSD 13.3 -> stable/15, OpenZFS 2.2 -> 2.4.3,
Samba 4.20 -> 4.23, Python in ports 3.9 -> 3.11, the configuration schema generation.

A full upgrade cycle on the bench takes about 15 minutes.

## The upgrade procedure

1. **Back up the configuration** from the web interface
   (System -> General -> Save Config). That is a separate file; it does not depend on
   the state of the boot device.
2. Boot from the bsdnas image.
3. `Install/Upgrade` -> pick the boot device -> **`Upgrade Install`**.
4. `Install in new boot environment` -- the new boot environment is created next to
   the old one, the previous environment stays in the list and can be rolled back to from the menu
   the loader.
5. Wait for it to finish, remove the medium, boot from the disk.

The first boot takes longer than usual: the configuration database is migrating. On the bench
the system answered 60-90 seconds after the console menu appeared.

## About `zpool upgrade` -- read this before, not after

After the upgrade the system reports that new features are available for the pool. **Do not rush.**

What the check established:

* Immediately after `zpool upgrade` the pool **remains importable** by the old OpenZFS 2.2.
  Verified: the 13.3 installer sees the upgraded pool as `ONLINE` and offers
  an import with `-f`, without a single word about incompatibility.
* The reason: `zpool upgrade` moves features to `enabled`, not to `active`.
  Immediately after the operation there are zero active features.
* The old system loses access once any new feature becomes `active`,
  that is, when it actually starts being used: deduplication, long names,
  raidz expansion and the like.
* **A feature becomes active as a side effect of ordinary use
  and is never announced.**

The practical conclusion: a rollback window after `zpool upgrade` does exist, but it closes
silently, so it must not be relied upon.

A sensible order:

1. update the system;
2. make sure everything works -- shares, tasks, jails;
3. live with it for as long as it takes to be confident;
4. and only then run `zpool upgrade`, knowingly giving up the option of
   going back to 13.3.

The boot pool (`boot-pool`) does not need a separate upgrade.

## Jails

Jails with a FreeBSD 13 userland run on the 15 kernel: the kernel configuration enables
`COMPAT_FREEBSD13` and `COMPAT_FREEBSD14`. Verified: a `13.3-RELEASE-p8` jail
starts after the upgrade, commands inside it run, files are intact.

Worth knowing separately: **the FreeBSD 13.x branch has been removed from the main mirror**
(`download.freebsd.org` returns 404 for 13.3 and 13.5). On a system still
on 13.3, a new jail can no longer be created the normal way: iocage cannot find the release.
Existing ones keep working. The way around it for 13.3 is the archive server:

```
iocage fetch -r 13.3-RELEASE -s archive.freebsd.org -d old-releases/amd64
```

This is one of the reasons why staying on 13.3 is inconvenient: the platform is
functionally frozen.

## Known rough edges

* **The SSH service does not come up by itself after the upgrade** — enable it
  again in the web interface or through the API.
* The iX iocage plugin index is no longer updated; plugins can only be installed
  from a private index or by hand.
* The hardware RAID utilities `arcconf`, `megacli` and `tw_cli` are not part of
  the build: their distfiles have disappeared both from the vendors and from
  `distcache.FreeBSD.org`. For a ZFS-based NAS, hardware RAID is contraindicated
  anyway.

## What was not tested

An honest list of what this document does not answer:

* upgrades from versions older than 13.3 (13.0, 12.x, 11.x);
* systems with HA (dual controller), GELI encryption, iSCSI under load, domain
  authentication;
* pools with raidz, cache and logs on separate devices — a mirror was tested;
* behaviour under real load and at volumes larger than those on the bench.
