#!/usr/bin/env python3
"""Generate CydiaIcon.png - the 128x128 tile Sileo shows for the repo.

Pure stdlib PNG writer, so there is no Pillow dependency. Replace the output
with any 128x128 PNG of your own whenever you like; nothing depends on this
script at build time.
"""
from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path

SIZE = 128
BG = (18, 20, 28)
ACCENT = (91, 140, 255)
INNER = (232, 238, 255)


def chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def pixel(x: int, y: int) -> tuple[int, int, int]:
    cx = cy = (SIZE - 1) / 2
    dist = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
    if dist < 20:
        return INNER
    if 38 <= dist <= 50:
        return ACCENT
    return BG


def main() -> None:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "repo/CydiaIcon.png")
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)  # filter type 0 (None) for this scanline
        for x in range(SIZE):
            rows.extend(pixel(x, y))

    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(rows), 9))
        + chunk(b"IEND", b"")
    )
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(png)
    print(f"wrote {out} ({len(png):,} bytes, {SIZE}x{SIZE})")


if __name__ == "__main__":
    main()
