# System report

Two small tools that answer one question: **what is different now?**

`bsdnas-system-report` writes down what a system is — versions, hardware,
storage layout, packages, services and the checksums of the files that decide
how it behaves. `bsdnas-report-diff` compares two of those files and prints the
changes.

They serve two jobs at once:

* **Before an update.** The system takes a report of itself first, so that if
  something breaks afterwards there is something to compare against, instead of
  guessing what the update touched.
* **Support.** Anyone running a TrueNAS-derived system can take a report and
  send it, so that a conversation starts from facts rather than from
  "it stopped working". The tool runs on a stock TrueNAS CORE 13.x as well as
  on BSDnas.

## Use

```
bsdnas-system-report                 # writes bsdnas-report-<date>.txt
bsdnas-system-report -o before.txt   # name it yourself
bsdnas-system-report --stdout        # to standard output
bsdnas-system-report --verify        # also verify every packaged file (slow)
bsdnas-system-report --no-checksums  # skip hashing configuration files

bsdnas-report-diff before.txt after.txt
```

A report takes about four seconds and comes out around 240 KB. `--verify` runs
`pkg check -s`, which re-reads and hashes every file of every package — that is
hundreds of thousands of files and several minutes, worth it when hunting a
broken upgrade and pointless otherwise.

The file is one document: a short human summary on top, the JSON below it. Both
tools read the JSON out of the file, so the summary never gets in the way.

## What is in it

Versions (product, kernel, OpenZFS), hardware (board, CPU, memory, disk models
and sizes), storage (pools with their features, datasets, boot environments,
partitioning), the installed packages with versions, running services, and the
shape of the configuration — how many shares, tasks and interfaces exist, not
what they are called.

Configuration files are recorded as **SHA256 plus size and date**. The hash is
the point: in configuration files an edit that leaves the size unchanged is the
normal case, and sizes and dates alone would miss it. The diff says so out
loud when it sees one:

```
  ~ /conf/base/etc/hostid   (same size, different content)
```

Note that on BSDnas the file that matters is the one under `/conf/base/etc` —
that template is what becomes `/etc` on every boot.

## What is deliberately not in it

No passwords, keys, certificates, share names, dataset paths outside the pool
layout, user names, e-mail addresses or any file contents. `master.passwd`,
the configuration database and the contents of `ssh`, `ssl` and `pam.d`
directories are skipped by an explicit list — including copies left behind as
`.pkgsave` or `.bak`, because a shadow copy of a password file is still a
password file. The hostname is stored as a truncated hash, enough to tell two
machines apart without naming either.

Everything collected lands in the file you can read before sending it anywhere.
There is no separate channel and no field that is not in the file.
