# Personal Sileo Repo

A Cydia/Sileo repo is not a server. It is a directory of static files that a
package manager reads over HTTPS. Everything below builds that directory.

## Layout

```
repo/                 <- this whole folder is what gets served
  Release             generated: repo metadata
  Packages(.gz/.bz2/.xz)  generated: the package index
  CydiaIcon.png       128x128 tile Sileo shows for the repo
  debs/               the .deb files themselves
src/                  source trees for resource-only packages
  <pkgid>/DEBIAN/control
  <pkgid>/payload/    laid out as the LOGICAL tree, without /var/jb
tweaks/               Theos projects for compiled tweaks (needs Docker)
tools/
  make_deb.py         build a .deb, pure Python, no dpkg
  build_repo.py       regenerate Packages + Release
  make_icon.py        regenerate CydiaIcon.png
```

## Workflow

```bash
# 1. build one or more packages from src/
python tools/make_deb.py src/com.romeo.hello -o repo/debs

# 2. regenerate the index (run this after ANY change to repo/debs)
python tools/build_repo.py

# 3. test on the LAN before publishing
python tools/build_repo.py --serve 8080
#    then add http://<your-pc-lan-ip>:8080/ in Sileo
```

`make_deb.py` re-roots `payload/` under `/var/jb` automatically. Write
`payload/usr/share/hello/hello.txt` and it lands at
`/var/jb/usr/share/hello/hello.txt`. Pass `--prefix ''` for a rootful package.

## Architecture: the one field that will bite you

Rootful and rootless packages are not interchangeable, and the `Architecture`
field is what tells them apart. Get it wrong and the package either refuses to
install or installs and silently does nothing.

| `Architecture` | Scheme | Install prefix |
|---|---|---|
| `iphoneos-arm` | rootful (legacy Cydia era) | `/` |
| `iphoneos-arm64` | **rootless** — what you want | `/var/jb` |
| `iphoneos-arm64e` | roothide | randomized |

palera1n rootless on your iPhone X means **`iphoneos-arm64`** everywhere.

## control fields

Required: `Package` (reverse-DNS id), `Version`, `Architecture`.
Worth setting: `Name` (Sileo's display name — without it you get the raw id),
`Description`, `Author`, `Maintainer`, `Section`, `Depends`.

`Section: Tweaks` for anything hooking a process. A compiled tweak needs
`Depends: ellekit` — that is the substrate palera1n rootless ships instead of
the old Cydia Substrate.

`Installed-Size` is computed for you if you omit it.

## Maintainer scripts

Drop `postinst`, `prerm`, etc. into `DEBIAN/`. They are shipped mode 755, and
CRLF line endings are stripped automatically — Windows editors will otherwise
produce a shebang the device cannot execute.

The one you will actually need, for packages that install an app into
`/var/jb/Applications`, so SpringBoard picks up the icon:

```sh
#!/bin/sh
uicache --all
exit 0
```

## Hosting

Any static host with HTTPS works. GitHub Pages is the usual choice: push this
directory, enable Pages, and the repo URL is
`https://<user>.github.io/<reponame>/`.

Pages on a **private** repo requires a paid plan, so a personal tweak repo is
normally public. That is fine — a repo URL is meant to be handed out — but
remember anything you commit to `repo/debs/` is world-readable.

## Compiled tweaks

Theos needs a Unix toolchain, so it will not run natively on Windows. Docker
Desktop is already installed here; start it, then:

```bash
docker run --rm -it -v "%cd%:/work" -w /work debian:bookworm bash
# inside the container:
apt update && apt install -y build-essential git curl perl zsh fakeroot
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
cd tweaks/HelloTweak && make package
```

`make package` writes a .deb into `tweaks/HelloTweak/packages/`. Copy it into
`repo/debs/` and re-run `build_repo.py`.

The `THEOS_PACKAGE_SCHEME = rootless` line in the Makefile is what makes Theos
emit `iphoneos-arm64` with `/var/jb` paths. Remove it and you get a rootful
package that will not work on your setup.

## Gotchas

- **Re-run `build_repo.py` after every change to `repo/debs/`.** Sileo trusts
  the index, not the directory. A .deb present but unindexed is invisible; an
  indexed .deb whose hash no longer matches fails to install.
- **Bump `Version` for every rebuild.** Sileo caches by name+version, so
  reusing a version means your change is never fetched. Versions compare with
  dpkg ordering: `1.0.10` is newer than `1.0.9`.
- **Sileo caches aggressively.** Pull-to-refresh on the Sources tab; if a
  change still is not showing, remove and re-add the repo.
- **HTTPS for real use.** Plain HTTP works for LAN testing but Sileo warns.
- Only install tweaks you built or trust. A tweak is unsandboxed code running
  as root inside system processes — there is no review layer between a repo and
  your phone.
