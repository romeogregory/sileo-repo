#!/usr/bin/env python3
"""Index a Cydia/Sileo repo: scan repo/debs/*.deb and regenerate Packages + Release.

A repo is just static files. This script produces the ones a package manager
reads, so the whole thing can be served by GitHub Pages, nginx, or `python -m
http.server` with no application code behind it.

Usage:
    python tools/build_repo.py            # indexes ./repo
    python tools/build_repo.py --root repo --serve 8080
"""
from __future__ import annotations

import argparse
import bz2
import gzip
import hashlib
import io
import lzma
import sys
import tarfile
from pathlib import Path

AR_MAGIC = b"!<arch>\n"

# Order matters only for readability; Sileo picks whichever it supports first.
DECOMPRESSORS = {
    "control.tar.gz": gzip.decompress,
    "control.tar.xz": lzma.decompress,
    "control.tar.bz2": bz2.decompress,
}

DEFAULT_RELEASE = """Origin: {name}
Label: {name}
Suite: stable
Version: 1.0
Codename: ios
Architectures: {arches}
Components: main
Description: {name}
"""

# Fields a package manager needs from us, not from the .deb's own control file.
COMPUTED = ("Filename", "Size", "MD5sum", "SHA1", "SHA256")


def read_ar_members(blob: bytes):
    """Yield (name, data) for each member of an ar archive."""
    if not blob.startswith(AR_MAGIC):
        raise ValueError("not an ar archive (bad magic)")
    offset = len(AR_MAGIC)
    while offset + 60 <= len(blob):
        header = blob[offset : offset + 60]
        name = header[0:16].decode("ascii", "replace").strip().rstrip("/")
        try:
            size = int(header[48:58].decode("ascii").strip())
        except ValueError:
            break
        start = offset + 60
        yield name, blob[start : start + size]
        offset = start + size + (size % 2)  # members pad to even boundaries


def control_from_deb(deb_path: Path) -> str:
    blob = deb_path.read_bytes()
    for name, data in read_ar_members(blob):
        decompress = DECOMPRESSORS.get(name)
        if not decompress:
            if name.startswith("control.tar"):
                raise ValueError(f"{deb_path.name}: unsupported compression '{name}'")
            continue
        with tarfile.open(fileobj=io.BytesIO(decompress(data))) as tar:
            for member in tar.getmembers():
                if member.name.lstrip("./") == "control":
                    fh = tar.extractfile(member)
                    if fh is None:
                        break
                    return fh.read().decode("utf-8", "replace")
    raise ValueError(f"{deb_path.name}: no control file found")


def strip_computed(control: str) -> list[str]:
    """Drop fields we recompute, so a stale value in a .deb can't poison the index."""
    lines, skipping = [], False
    for line in control.splitlines():
        if line[:1] in " \t":
            if not skipping:
                lines.append(line)
            continue
        skipping = line.split(":", 1)[0].strip() in COMPUTED
        if not skipping and line.strip():
            lines.append(line)
    return lines


def stanza_for(deb: Path, root: Path) -> tuple[str, str]:
    blob = deb.read_bytes()
    lines = strip_computed(control_from_deb(deb))
    arch = next(
        (l.split(":", 1)[1].strip() for l in lines if l.startswith("Architecture:")),
        "iphoneos-arm64",
    )
    lines += [
        f"Filename: ./{deb.relative_to(root).as_posix()}",
        f"Size: {len(blob)}",
        f"MD5sum: {hashlib.md5(blob).hexdigest()}",
        f"SHA1: {hashlib.sha1(blob).hexdigest()}",
        f"SHA256: {hashlib.sha256(blob).hexdigest()}",
    ]
    return "\n".join(lines) + "\n", arch


def write_indexes(root: Path, packages: str) -> None:
    raw = packages.encode("utf-8")
    (root / "Packages").write_bytes(raw)
    with gzip.GzipFile(filename="", fileobj=(root / "Packages.gz").open("wb"),
                       mode="wb", mtime=0) as fh:
        fh.write(raw)
    (root / "Packages.bz2").write_bytes(bz2.compress(raw))
    (root / "Packages.xz").write_bytes(lzma.compress(raw))


def sync_release(root: Path, arches: set[str], name: str) -> None:
    arch_line = f"Architectures: {' '.join(sorted(arches)) or 'iphoneos-arm64'}"
    release = root / "Release"
    if not release.is_file():
        release.write_text(
            DEFAULT_RELEASE.format(name=name, arches=arch_line.split(": ", 1)[1]),
            encoding="utf-8",
        )
        print(f"  created {release} (edit Origin/Label/Description to taste)")
        return
    # Preserve hand-edited metadata; only keep Architectures truthful.
    lines = release.read_text(encoding="utf-8").splitlines()
    out, replaced = [], False
    for line in lines:
        if line.startswith("Architectures:"):
            out.append(arch_line)
            replaced = True
        else:
            out.append(line)
    if not replaced:
        out.append(arch_line)
    release.write_text("\n".join(out) + "\n", encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser(description="Generate Packages/Release for a Sileo repo.")
    ap.add_argument("--root", default="repo", help="repo root (default: repo)")
    ap.add_argument("--name", default="Romeo's Repo", help="name used if Release is missing")
    ap.add_argument("--serve", type=int, metavar="PORT",
                    help="after indexing, serve the repo over HTTP for LAN testing")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    if not root.is_dir():
        sys.exit(f"error: repo root not found: {root}")

    debs = sorted(root.rglob("*.deb"))
    stanzas, arches = [], set()
    for deb in debs:
        try:
            stanza, arch = stanza_for(deb, root)
        except ValueError as exc:
            print(f"  skipped: {exc}", file=sys.stderr)
            continue
        stanzas.append(stanza)
        arches.add(arch)
        print(f"  indexed {deb.name}  [{arch}]")

    write_indexes(root, "\n".join(stanzas))
    sync_release(root, arches, args.name)

    if not (root / "CydiaIcon.png").is_file():
        print("  warning: no CydiaIcon.png - Sileo will show a blank repo tile")
    print(f"\n{len(stanzas)} package(s) indexed in {root}")

    if args.serve:
        import http.server, socketserver, functools
        handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(root))
        with socketserver.TCPServer(("0.0.0.0", args.serve), handler) as httpd:
            print(f"serving on http://0.0.0.0:{args.serve}  (Ctrl+C to stop)")
            httpd.serve_forever()


if __name__ == "__main__":
    main()
