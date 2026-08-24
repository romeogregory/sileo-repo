#!/usr/bin/env python3
"""Build an iOS .deb package in pure Python. No dpkg, no WSL, no Linux.

A .deb is an `ar` archive holding exactly three members, in order:
    debian-binary      -> the text "2.0\n"
    control.tar.gz     -> package metadata (./control, ./postinst, ...)
    data.tar.gz        -> the payload, as it lands on the device

Usage:
    python tools/make_deb.py src/com.romeo.hello -o repo/debs
"""
from __future__ import annotations

import argparse
import gzip
import io
import os
import sys
import tarfile
from pathlib import Path

AR_MAGIC = b"!<arch>\n"
FIXED_MTIME = 0  # deterministic builds: same input -> byte-identical .deb

# Maintainer scripts dpkg will run. Anything else in DEBIAN/ is metadata.
MAINTAINER_SCRIPTS = ("preinst", "postinst", "prerm", "postrm", "extrainst_")

# Payload paths that must be executable regardless of extension.
EXEC_DIRS = ("bin/", "sbin/", "libexec/")
EXEC_SUFFIXES = (".dylib", ".sh", ".bundle")


def ar_member(name: str, data: bytes) -> bytes:
    """Wrap `data` in a 60-byte ar header, padded to an even boundary."""
    header = (
        name.encode().ljust(16)
        + str(FIXED_MTIME).encode().ljust(12)
        + b"0".ljust(6)         # uid
        + b"0".ljust(6)         # gid
        + b"100644".ljust(8)    # mode
        + str(len(data)).encode().ljust(10)
        + b"`\n"
    )
    if len(header) != 60:
        raise ValueError(f"malformed ar header for {name!r}")
    return header + data + (b"\n" if len(data) % 2 else b"")


def is_executable(rel_path: str) -> bool:
    return rel_path.endswith(EXEC_SUFFIXES) or any(
        f"/{d}" in f"/{rel_path}" for d in EXEC_DIRS
    )


def tar_gz(entries: list[tuple[str, bytes | None, int]]) -> bytes:
    """Build a gzipped tar. Each entry is (name, data_or_None_for_dir, mode)."""
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.GNU_FORMAT) as tar:
        for name, data, mode in sorted(entries, key=lambda e: e[0]):
            info = tarfile.TarInfo(name)
            info.mtime = FIXED_MTIME
            info.uid = info.gid = 0
            info.uname, info.gname = "root", "wheel"  # Darwin, not Linux
            info.mode = mode
            if data is None:
                info.type = tarfile.DIRTYPE
                tar.addfile(info)
            else:
                info.size = len(data)
                tar.addfile(info, io.BytesIO(data))
    # mtime=0 keeps the gzip header deterministic too
    out = io.BytesIO()
    with gzip.GzipFile(fileobj=out, mode="wb", mtime=FIXED_MTIME) as gz:
        gz.write(raw.getvalue())
    return out.getvalue()


def collect_payload(payload_dir: Path, prefix: str) -> tuple[list, int]:
    """Walk the payload tree, re-rooting it under `prefix`. Returns (entries, bytes)."""
    entries: list[tuple[str, bytes | None, int]] = []
    seen_dirs: set[str] = set()
    total = 0

    def ensure_dirs(rel: str) -> None:
        parts = rel.split("/")
        for i in range(1, len(parts)):
            d = "/".join(parts[:i])
            if d and d not in seen_dirs:
                seen_dirs.add(d)
                entries.append((f"./{d}", None, 0o755))

    prefix = prefix.strip("/")
    if prefix:
        ensure_dirs(f"{prefix}/.")

    for path in sorted(payload_dir.rglob("*")):
        rel = path.relative_to(payload_dir).as_posix()
        target = f"{prefix}/{rel}" if prefix else rel
        if path.is_dir():
            if target not in seen_dirs:
                seen_dirs.add(target)
                entries.append((f"./{target}", None, 0o755))
            continue
        ensure_dirs(target)
        data = path.read_bytes()
        total += len(data)
        entries.append((f"./{target}", data, 0o755 if is_executable(rel) else 0o644))

    return entries, total


def parse_control(text: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    key = None
    for line in text.splitlines():
        if not line.strip():
            continue
        if line[0] in " \t" and key:          # folded continuation line
            fields[key] += "\n" + line.rstrip()
        elif ":" in line:
            key, _, value = line.partition(":")
            key = key.strip()
            fields[key] = value.strip()
    return fields


def build(src: Path, out_dir: Path, prefix: str) -> Path:
    debian = src / "DEBIAN"
    control_path = debian / "control"
    if not control_path.is_file():
        sys.exit(f"error: no control file at {control_path}")

    fields = parse_control(control_path.read_text(encoding="utf-8"))
    for required in ("Package", "Version", "Architecture"):
        if not fields.get(required):
            sys.exit(f"error: control is missing required field: {required}")

    payload_dir = src / "payload"
    if payload_dir.is_dir():
        data_entries, payload_bytes = collect_payload(payload_dir, prefix)
    else:
        data_entries, payload_bytes = [], 0
        print("  note: no payload/ directory - building a metadata-only package")

    # dpkg reports this in Sileo's UI; keep it honest.
    fields.setdefault("Installed-Size", str(max(1, payload_bytes // 1024)))
    control_text = "".join(f"{k}: {v}\n" for k, v in fields.items())

    control_entries: list[tuple[str, bytes | None, int]] = [
        ("./control", control_text.encode("utf-8"), 0o644)
    ]
    for script in MAINTAINER_SCRIPTS:
        p = debian / script
        if p.is_file():
            body = p.read_bytes().replace(b"\r\n", b"\n")  # CRLF breaks shebangs
            control_entries.append((f"./{script}", body, 0o755))
            print(f"  + maintainer script: {script}")

    deb = (
        AR_MAGIC
        + ar_member("debian-binary", b"2.0\n")
        + ar_member("control.tar.gz", tar_gz(control_entries))
        + ar_member("data.tar.gz", tar_gz(data_entries))
    )

    out_dir.mkdir(parents=True, exist_ok=True)
    name = f"{fields['Package']}_{fields['Version']}_{fields['Architecture']}.deb"
    dest = out_dir / name
    dest.write_bytes(deb)
    return dest


def main() -> None:
    ap = argparse.ArgumentParser(description="Build an iOS .deb without dpkg.")
    ap.add_argument("source", nargs="+", help="package source dir(s) containing DEBIAN/")
    ap.add_argument("-o", "--output", default="repo/debs", help="where to write .deb files")
    ap.add_argument(
        "--prefix",
        default="/var/jb",
        help="on-device install prefix; '/var/jb' for rootless, '' for rootful",
    )
    args = ap.parse_args()

    out_dir = Path(args.output)
    for src in args.source:
        src_path = Path(src)
        if not src_path.is_dir():
            sys.exit(f"error: not a directory: {src_path}")
        print(f"building {src_path.name}")
        dest = build(src_path, out_dir, args.prefix)
        print(f"  -> {dest} ({dest.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
