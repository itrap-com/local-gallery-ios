#!/usr/bin/env python3
"""Render the 1024 px iOS app icon from the Android adaptive icon's vector paths.

Source: ../local-gallery/app/src/main/res/drawable/ic_launcher_{background,foreground}.xml
(108-unit canvas). Android shows the central 72 units, so this renders that window, giving the
same framing as the Android launcher. Stdlib only; writes an 8-bit RGB PNG with no alpha, as the
App Store requires. Run once after changing the design; the PNG is committed.
"""
import math
import struct
import sys
import zlib
from pathlib import Path

SIZE = 1024
SS = 3  # supersamples per axis
VIEW_MIN, VIEW_SPAN = 18.0, 72.0  # Android's visible adaptive-icon window


def hexrgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def gradient(stops, t):
    t = max(0.0, min(1.0, t))
    for (o0, c0), (o1, c1) in zip(stops, stops[1:]):
        if t <= o1:
            f = (t - o0) / (o1 - o0) if o1 > o0 else 0.0
            return tuple(a + (b - a) * f for a, b in zip(c0, c1))
    return stops[-1][1]


BG = [(0.0, hexrgb("3A2913")), (0.7, hexrgb("1A1108")), (1.0, hexrgb("0C0805"))]
BLOOM = [(0.0, hexrgb("FFF4D8")), (0.42, hexrgb("FFB253")), (1.0, hexrgb("EF7A18"))]
BLADE = hexrgb("160E05")
CORE = hexrgb("FFF4D8")
RING = hexrgb("4A3417")
WHITE = (255.0, 255.0, 255.0)

BLADES = [
    ((62, 30.3), (62, 77.7)), ((37.5, 72.8), (78.5, 49.1)), ((29.5, 49.1), (70.5, 72.8)),
    ((46, 30.3), (46, 77.7)), ((70.5, 35.2), (29.5, 58.9)), ((78.5, 58.9), (37.5, 35.2)),
]
GLINT_A, GLINT_B = (34.0, 41.0), (45.0, 31.0)


def seg_dist(px, py, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def arc_center(a, b, r):
    # Centre of the SVG arc "A r,r 0 0 1": small arc, sweeping clockwise on screen (y down).
    mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
    dx, dy = b[0] - a[0], b[1] - a[1]
    chord = math.hypot(dx, dy)
    h = math.sqrt(r * r - (chord / 2) ** 2)
    return mx - dy / chord * h, my + dx / chord * h


GLINT_C = arc_center(GLINT_A, GLINT_B, 29.0)
GA = math.atan2(GLINT_A[1] - GLINT_C[1], GLINT_A[0] - GLINT_C[0])
GB = math.atan2(GLINT_B[1] - GLINT_C[1], GLINT_B[0] - GLINT_C[0])


def color_at(x, y):
    c = gradient(BG, math.hypot(x - 54, y - 48) / 60.0)
    d = math.hypot(x - 54, y - 54)
    if d <= 25:
        c = gradient(BLOOM, d / 25.0)
    if any(seg_dist(x, y, a, b) <= 2.5 for a, b in BLADES):
        c = BLADE
    if d <= 5:
        c = CORE
    if abs(d - 29) <= 0.8:
        c = RING
    dg = math.hypot(x - GLINT_C[0], y - GLINT_C[1])
    on_arc = abs(dg - 29) <= 1.0 and GA <= math.atan2(y - GLINT_C[1], x - GLINT_C[0]) <= GB
    cap = math.hypot(x - GLINT_A[0], y - GLINT_A[1]) <= 1 or math.hypot(x - GLINT_B[0], y - GLINT_B[1]) <= 1
    if on_arc or cap:
        c = tuple(v + (w - v) * 0.32 for v, w in zip(c, WHITE))
    return c


def render():
    rows = bytearray()
    scale = VIEW_SPAN / SIZE
    n = SS * SS
    for py in range(SIZE):
        rows.append(0)
        for px in range(SIZE):
            r = g = b = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    cr, cg, cb = color_at(VIEW_MIN + (px + (sx + 0.5) / SS) * scale,
                                          VIEW_MIN + (py + (sy + 0.5) / SS) * scale)
                    r += cr
                    g += cg
                    b += cb
            rows += bytes((round(r / n), round(g / n), round(b / n)))
    return bytes(rows)


def png(raw):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else (
        Path(__file__).resolve().parent.parent / "LocalGallery/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
    )
    out.write_bytes(png(render()))
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
