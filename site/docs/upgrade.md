# Upgrading from TrueNAS CORE 13.3

This page describes what was measured on a test machine, not what is expected
to happen. Where something was not tested, it says so.

## What was tested

The official iX image `TrueNAS-13.3-U1.2` was installed on a test machine and
configured with a mirrored pool, a dataset, an SMB share and an iocage jail,
then upgraded with a BSDnas image built from FreeBSD `stable/15`.

| check | result |
|---|---|
| system comes up | yes, `state: READY` |
| configuration preserved | pools, shares, users, passwords intact |
| pool created by OpenZFS 2.2 | imports and works on 2.4.3 |
| datasets | intact |
| SMB share from 13.3 | works, `enabled` |
| iocage jail with 13.3 userland | starts on the FreeBSD 15 kernel, data intact |

One run changes FreeBSD 13.3 → `stable/15`, OpenZFS 2.2 → 2.4.3, Samba
4.20 → 4.23, the ports Python 3.9 → 3.11, and the configuration schema
generation. The whole cycle takes about fifteen minutes on the test stand.

## Procedure

1. **Save a configuration backup** from the web interface
   (System → General → Save Config). It is a separate file and does not depend
   on the state of the boot device.
2. Boot the BSDnas image.
3. `Install/Upgrade` → select the boot device → **`Upgrade Install`**.
4. `Install in new boot environment` — the new boot environment is created
   alongside the old one, which stays in the boot loader menu and remains
   available for rollback.
5. When it finishes, remove the media and boot from disk.

The first boot takes longer than usual while the configuration database
migrates. On the test stand the system answered 60–90 seconds after the console
menu appeared.

## About `zpool upgrade` — read this first

After the upgrade the system will report that new features are available for
the pool. **Do not rush.**

What was established by measurement:

* Immediately after `zpool upgrade` the pool **is still importable** by the old
  OpenZFS 2.2. Verified: the 13.3 installer sees the upgraded pool as `ONLINE`
  and offers to import it with `-f`, without a single word about incompatible
  features.
* The reason: `zpool upgrade` moves features to the `enabled` state, not
  `active`. Immediately after the operation the number of active features is
  zero.
* The old system loses access when any new feature becomes `active` — that is,
  when it is actually used: deduplication, long names, raidz expansion and
  similar.
* **A feature becomes active as a side effect of ordinary work, and this is
  never announced.**

So the rollback window after `zpool upgrade` does exist, but it closes
silently, and it cannot be relied on.

A sensible order:

1. upgrade the system;
2. confirm everything works — shares, tasks, jails;
3. live with it as long as you need to be confident;
4. only then run `zpool upgrade`, deliberately giving up the ability to return
   to 13.3.

The boot pool does not need a separate upgrade.

## Jails

Jails with a FreeBSD 13 userland run on the FreeBSD 15 kernel:
`COMPAT_FREEBSD13` and `COMPAT_FREEBSD14` are enabled in the kernel
configuration. Verified — a `13.3-RELEASE-p8` jail starts after the upgrade,
commands run inside it, files are intact.

Worth knowing separately: **the FreeBSD 13.x branch has been removed from the
main mirror** (`download.freebsd.org` returns 404 for 13.3 and 13.5). On a
system still running 13.3 you can no longer create a new jail the normal way —
iocage finds no release. Existing jails keep working. The workaround on 13.3 is
the archive server:

```
iocage fetch -r 13.3-RELEASE -s archive.freebsd.org -d old-releases/amd64
```

This is one of the reasons staying on 13.3 is uncomfortable: the platform is
functionally frozen.

## Known rough edges

* **The SSH service does not come up by itself after an upgrade** — enable it
  again from the web interface or the API.
* The iocage plugin index from iX is no longer updated; plugins must come from
  your own index or be installed manually.
* The hardware RAID utilities `arcconf`, `megacli` and `tw_cli` are not
  included: their distribution files disappeared both from the vendors and from
  `distcache.FreeBSD.org`. Hardware RAID is inadvisable under ZFS anyway.

## What was not tested

An honest list of what this page does not answer:

* upgrades from versions older than 13.3 (13.0, 12.x, 11.x);
* systems with HA (dual controller), GELI encryption, iSCSI under load, or
  domain authentication;
* pools with raidz, or with cache and log on separate devices — a mirror was
  tested;
* behaviour under real load and at sizes larger than the test stand.
