# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal Cydia/Sileo package repository plus the tooling to build packages for
it. The published artifact is **static files only** — there is no server-side
code, no database, and no runtime. A package manager fetches `Release`,
`Packages`, and `.deb` files over HTTPS; that is the entire protocol.

Deployed at `https://romeogregory.github.io/sileo-repo/` via GitHub Pages.

## Target device — this constrains almost every decision

iPhone X (A11) on iOS 16.7.15, jailbroken with **palera1n in rootless mode**.

Consequences that are easy to get wrong:

- `Architecture` must be `iphoneos-arm64` (rootless). `iphoneos-arm` is rootful
  and `iphoneos-arm64e` is roothide — both install and then silently do nothing.
- Payloads install under **`/var/jb`**, not `/`.
- Compiled tweaks depend on **`ellekit`**, not `mobilesubstrate`. ElleKit is the
  substrate palera1n rootless ships instead of Cydia Substrate.
- `Depends: firmware (>= 15.0)` is the floor used here.

## Getting the device jailbroken (hard-won; do not re-derive)

Bringing this device up cost several hours. The two facts that mattered:

**A11 + iOS 16 requires a full device reset, not just passcode-off.** From
palera1n's README: *"on A11 (iPhone X, 8, 8 Plus), you must disable your passcode
while in the jailbroken state — on iOS 16, you need to reset your device before
proceeding."* Disabling a passcode does not undo the keybag and data-protection
keys the Secure Enclave provisioned when one was first set. palera1n needs a
device where a passcode has **never** been set since the last reset.

The failure mode is silent and misleading: checkm8 reports `Checkmate!`, PongoOS
boots, the kernel patches and boots (palera1n splash appears), the installer
prints `Installing jailbreak → Done! 100%` — and then nothing exists. No Sileo,
no loader app, and `issh` fails with `kex_exchange_identification: Connection
closed by remote host`, which means the USB tunnel opened but no SSH daemon is
listening. Every stage upstream of the SEP succeeds; only activation fails.
Erase All Content and Settings, then skip the passcode during setup, and it
works. Do not restore a backup before jailbreaking — an encrypted backup
restores the passcode and puts the device straight back into the broken state.

**palera1n v2.4 does not work on this device; v3.0.0-beta.2 does.** v2.4 exits
silently after `Booting Kernel...` and never reaches an install stage. v3.0.0-beta.2
(`palen1x-v3.0.0-beta.2-x86_64.iso`) reaches the installer and also ships the TUI,
which v2.4 lacks — v2.4 is CLI-only and drops to a bash prompt by design. In v2.4
the flag mapping is `-f` rootful / `-l` rootless (**not** `-f` force-revert).

Windows has no supported palera1n path, so this runs from a palen1x USB stick
flashed with Rufus in **DD Image mode** (ISO mode produces a stick that boots to
an emergency shell). Secure Boot must be disabled to boot it.

Consequences for day-to-day work here: the device is **semi-tethered**, so it
comes up stock after every restart and needs the palen1x boot step (~2 min)
before it can install anything from this repo. And a passcode must never be set
on it again.

## Commands

```bash
# Build a .deb from a source tree in src/
python tools/make_deb.py src/com.romeo.hello -o repo/debs

# Regenerate Packages(.gz/.bz2/.xz) and sync Release. Run after ANY change
# to repo/debs/ — the index, not the directory, is what Sileo trusts.
python tools/build_repo.py

# Serve the repo over HTTP for LAN testing against a real device
python tools/build_repo.py --serve 8080

# Compile a tweak. Theos cannot run natively on Windows, so this is the only
# supported path. Build the image once (~3GB, mostly toolchain + iOS SDK).
docker build -f docker/theos.Dockerfile -t theos-builder .
docker run --rm -v "%cd%:/work" theos-builder tweaks/Pseudonym

# Regenerate the 128x128 repo tile
python tools/make_icon.py repo/CydiaIcon.png

# Publish: CI rebuilds the index and deploys Pages (~15s)
git push
```

There is **no test suite**. Verification is done by structural inspection:
parse the `.deb`'s `ar` members and assert the order is `debian-binary` →
`control.tar.gz` → `data.tar.gz`, then confirm a served `.deb`'s SHA256 matches
the `SHA256:` line in `Packages`. That hash match is the check that matters — a
mismatch is the usual cause of a repo that looks healthy but fails at install.

## Architecture

**Two decoupled stages.** `make_deb.py` turns `src/<pkgid>/` into a `.deb`;
`build_repo.py` turns `repo/debs/*.deb` into an index. They share no code and no
state — `build_repo.py` reads metadata back out of the built `.deb` files and has
no knowledge of `src/`. This means externally-obtained `.deb` files can be
dropped into `repo/debs/` and indexed with no source tree at all.

**Why the tooling is pure Python.** This is a Windows box with no WSL Linux
distro, so `dpkg-deb` and `dpkg-scanpackages` are unavailable. `make_deb.py`
writes the `ar` archive and both tars itself; `build_repo.py` parses `ar` headers
and control tarballs itself. Do not rewrite either to shell out to `dpkg` — that
would break the primary workflow. Docker is installed for the Theos path, but
its daemon is frequently not running.

**Path re-rooting.** `src/<pkgid>/payload/` is laid out as the *logical* tree
(`usr/share/hello/...`). `make_deb.py --prefix` (default `/var/jb`) re-roots it
at build time. Payload trees must not contain `var/jb` themselves.

**CI is authoritative for the published index.** `.github/workflows/pages.yml`
re-runs `build_repo.py` on the runner before uploading, then fails if
`repo/Packages` is empty. Locally-generated index files are committed for
convenience but are always regenerated on deploy, so a forgotten local re-index
cannot publish a stale index.

**Deterministic builds.** `make_deb.py` pins mtime/uid/gid to 0 and sorts tar
entries, so identical input yields a byte-identical `.deb`. Useful for diffing,
but it means a rebuilt package with an unchanged `Version` has an unchanged
hash — see below.

**Ownership is `root:wheel`**, not `root:root`. These packages install on Darwin.

## Gotchas

- **Bump `Version` on every rebuild.** Sileo caches by name+version; reusing a
  version means the change is never fetched. Comparison uses dpkg ordering, so
  `1.0.10` > `1.0.9`.
- **`.gitattributes` LF enforcement is load-bearing**, not cosmetic. A CRLF
  `Makefile` breaks `make` inside the Theos container, and CRLF in `Packages`
  can trip APT-style parsers. Binaries (`.deb`, `.png`, `.gz`, `.bz2`, `.xz`)
  are marked `binary` and must stay that way.
- **`gh api` needs endpoints without a leading slash** in this environment. Git
  Bash rewrites `/repos/...` into a filesystem path and the call fails. Use
  `gh api repos/owner/name/pages`.
- **`THEOS_PACKAGE_SCHEME = rootless`** in `tweaks/*/Makefile` is what makes
  Theos emit `iphoneos-arm64` with `/var/jb` paths. Removing it produces a
  rootful package that will not work on this device.
- Maintainer scripts in `DEBIAN/` are shipped mode 755 with CRLF stripped
  automatically. Packages installing into `/var/jb/Applications` need a
  `postinst` running `uicache --all` or SpringBoard will not show the icon.

## Verified vs unverified

**Verified.** The `.deb` structure (`ar` member order, `root:wheel` ownership,
`/var/jb` re-rooting), the generated index, and HTTPS delivery from GitHub Pages
— including that the served `.deb`'s SHA256 matches the `SHA256:` line in
`Packages`. The device is jailbroken and Sileo is installed.

Sileo on the device adds `https://romeogregory.github.io/sileo-repo/` as a
source, resolves the index, and lists Hello World — so the generated `Release`
and `Packages` are valid to a real package manager, not just to `build_repo.py`.

Note that the repo root returns **404** in a browser: there is no `index.html`
and none is needed, since Sileo requests `/Release` and `/Packages` directly.
That 404 is not a fault.

**Not verified.** No package has actually been installed yet, so dpkg unpacking a
payload to `/var/jb` is still unproven. To close it: install Hello World, then
confirm over `issh` (user `root`, password `alpine`) that
`/var/jb/usr/share/hello/hello.txt` exists.

Both tweaks now compile. `docker/theos.Dockerfile` is the build environment;
three things about it are non-obvious and cost time to rediscover:

- Theos refuses to install or run as root, but its installer shells out to
  `sudo`, so the image needs an unprivileged user that *has* sudo.
- `install-theos` prompts before fetching the toolchain, which a Docker build
  cannot answer — the toolchain and SDK are pinned by URL instead.
- Sources are copied into the container before building. Windows bind mounts
  expose directories as 0777 and `dpkg-deb` rejects a `DEBIAN` directory
  outside 0755-0775, so building in place fails on Windows hosts only.

Theos reads maintainer scripts from `layout/DEBIAN/`, not `DEBIAN/`, and drops
them silently if `rsync` is missing from the image.

The `ERROR: Failed to convert input file.` line during packaging is benign:
`libplist-utils` cannot parse the old-style ASCII plist that Logos filters use,
and the file is copied unmodified regardless.
