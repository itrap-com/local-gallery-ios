#!/usr/bin/env python3
"""Draw the 1024 px app icon: an amber sun over two mountains on near-black.

Stdlib only. App Store icons must have no alpha channel, so this writes an 8-bit RGB PNG.
Run once after changing the design; the PNG is committed.
"""
import struct
import sys
import zlib
from pathlib import Path

SIZE = 1024
SS = 2  # supersampling per axis, for smooth edges

BACKGROUND = (14, 14, 16)
AMBER = (255, 154, 61)
FAR = (58, 58, 66)
NEAR = (92, 92, 102)

SUN = (640.0, 380.0, 168.0)  # cx, cy, r
FAR_MOUNTAIN = ((40.0, 1024.0), (430.0, 470.0), (860.0, 1024.0))
NEAR_MOUNTAIN = ((360.0, 1024.0), (720.0, 560.0), (1110.0, 1024.0))


def inside_triangle(px, py, tri):
    (x1, y1), (x2, y2), (x3, y3) = tri

    def side(ax, ay, bx, by):
        return (px - bx) * (ay - by) - (ax - bx) * (py - by)

    d1 = side(x1, y1, x2, y2)
    d2 = side(x2, y2, x3, y3)
    d3 = side(x3, y3, x1, y1)
    neg = d1 < 0 or d2 < 0 or d3 < 0
    pos = d1 > 0 or d2 > 0 or d3 > 0
    return not (neg and pos)


def color_at(x, y):
    if inside_triangle(x, y, NEAR_MOUNTAIN):
        return NEAR
    if inside_triangle(x, y, FAR_MOUNTAIN):
        return FAR
    cx, cy, r = SUN
    if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
        return AMBER
    return BACKGROUND


def render():
    rows = bytearray()
    step = 1.0 / SS
    for y in range(SIZE):
        rows.append(0)  # PNG filter: none
        for x in range(SIZE):
            r = g = b = 0
            for sy in range(SS):
                for sx in range(SS):
                    cr, cg, cb = color_at(x + (sx + 0.5) * step, y + (sy + 0.5) * step)
                    r += cr
                    g += cg
                    b += cb
            n = SS * SS
            rows += bytes((r // n, g // n, b // n))
    return bytes(rows)


def png(raw):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)  # 8-bit RGB, no alpha
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else (
        Path(__file__).resolve().parent.parent / "LocalGallery/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
    )
    out.write_bytes(png(render()))
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
