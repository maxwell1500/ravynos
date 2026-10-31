# Accounts

ravynOS keeps its account database in the classic flat files:

| file | contents | readable by |
| --- | --- | --- |
| `/etc/passwd` | `name:*:uid:gid:gecos:home:shell` | everyone |
| `/etc/master.passwd` | `name:hash:uid:gid:class:change:expire:gecos:home:shell` | root |
| `/etc/group` | `name:*:gid:members` | everyone |

`/etc/passwd` never carries a password: its field is `*`. The crypt(3) setting
lives only in `/etc/master.passwd`. `libsystem_pwdgrp` opens the master file
when the caller is root and `/etc/passwd` otherwise, so a privileged lookup
(WindowServer's login window calls `getpwnam()` and then
`crypt(password, pw_passwd)`) sees the hash while an ordinary process sees
`*`. Before this rule existed, every password login failed: the login path
read `*` and refused.

## Tools

`BSD/usr.sbin/usermgmt` builds one binary installed under four names:

```
useradd [-u uid] [-g group] [-c gecos] [-d home] [-s shell] [-m] [-p hash] name
usermod [-u uid] [-g group] [-c gecos] [-d home] [-s shell] [-l newname] name
userdel [-r] name
passwd  [-p hash] [name]
groupadd [-g gid] name
groupmod [-g gid] [-n newname] name
groupdel name
```

They take an exclusive lock on the account database, allocate the next free
uid (from 501) or gid, refuse duplicate names and uids, append the user to the
selected group's member list, and rewrite each database atomically (temp file
plus rename, with an open/truncate fallback). `useradd -m` creates the home
directory and `Desktop`, `Documents`, `Downloads`, `Library` inside it.
`userdel -r` removes the home, but only under `/Users/`.

`usermod -l` renames the entry in both databases and in every group member
list; `groupmod -n/-g` renames or renumbers a group. Only root may add, remove
or change accounts. `passwd` cannot yet be used by
an ordinary user to change their own password: that needs the binary to be
setuid root (which this FAT image cannot express) and the old password to be
verified against the shadow entry. Both arrive with the login window work.

## Password hashing

Hashes are produced with `crypt(3)` and verified with the same call, so the
login window and the tools cannot disagree. New passwords use SHA-512 crypt
(`$6$`) with a random 16-character salt:

    $6$abcdefghijklmnop$I1S/AlZROQgZ68X97iE7BNC3BG7ZzV553GQKNgAIJ19...

libsystem_c carries a self-contained SHA-512 (verified against the FIPS
vector for "abc") and the BSD `$6$` scheme, which matches OpenSSL's output
byte for byte. `crypt()` still falls back to DES for hashes written before
this change, so existing accounts keep working and are upgraded the next time
their password changes.

## Provisioning the test account

The image does not bake the `ravynos` account into `/etc`; the compat boot
script creates it with the system's own tool:

```
useradd -u 502 -g staff -c 'ravynOS Test User' -m -p <hash> ravynos
```

and the `passwd` fixture then proves that `getpwnam("ravynos")` returns uid
502, gid 20, `/Users/ravynos`, and a hash that verifies for `ravynos` and not
for a wrong password. The `accounts` fixture runs the whole add/change/delete
round trip (groupadd, useradd, passwd, usermod, groupmod, userdel -r,
groupdel) and fails if any
entry or the home directory survives deletion.

## Build layout note

The image's `/usr/lib/libSystem.B.dylib` must remain the merged umbrella
(about 1.1 MB). `build-libraries.sh Libsystem` also produces a 35 KB
`LC_REEXPORT`-only umbrella; with that one, dyld runs libc++'s initializer
before libc's and the boot panics with "initializer in image
(/usr/lib/libc++.1.dylib) that does not link with libSystem.dylib".
`/usr/lib/system/libsystem_c.dylib` is the freshly built component (it owns
`crypt`, `crypt_sha512` and `__DefaultRuneLocale`); do not copy the merged
umbrella over it, or the boot panics with "Symbol not found:
__DefaultRuneLocale".

## Limitations

* The 512 MiB/1 GiB development image is FAT, which stores no owner and one
  synthetic mode for every file. `useradd` sets modes and ownership and warns
  when the filesystem cannot record a uid. Enforcement of mode bits and
  `chown` semantics is Phase 5.4 on an HFS+ root; until then, "owned by" is a
  mount property, not a per-file fact.
* `passwd` has no PAM path; the in-tree PAM-free implementation above is the
  only one that runs.
