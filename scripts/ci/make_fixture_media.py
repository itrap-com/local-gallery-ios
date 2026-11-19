#!/usr/bin/env python3
"""Write synthetic media for the iOS evidence workflow: solid-color pictures, never real media.

    python3 scripts/ci/make_fixture_media.py <out-dir> <count>

Writes <count> PNGs built with zlib alone. Each is one solid color, the sizes cycle through common
photo shapes, and the files carry no metadata chunk at all (no EXIF, text or timestamp), so nothing
about a person, place or device is in them. Colors and sizes follow the file number, so every run
writes the same files.

Videos need ffmpeg. When it is on PATH, one two-second solid-color MP4 per hundred pictures (at
least one, at most 50) is written with its metadata stripped; otherwise videos are skipped. The
last line printed says which, for the CI job summary.
"""
import colorsys
import shutil
import struct
import subprocess
import sys
import zlib
from pathlib import Path

# Landscape and portrait 4:3, square, 16:9 both ways and a 3:1 panorama, each at three scales.
SHAPES = [(400, 300), (300, 400), (320, 320), (448, 252), (252, 448), (600, 200)]
SCALES = [1.0, 0.75, 1.5]
GOLDEN = 0.6180339887498949
VIDEO_CODECS = ["libx264", "h264_videotoolbox", "mpeg4"]


def color(n):
    """A distinct, mid-saturation color for item n."""
    hue = n * GOLDEN % 1.0
    saturation = 0.45 + 0.4 * (n * 7 % 10) / 9
    value = 0.55 + 0.4 * (n * 3 % 10) / 9
    return tuple(round(c * 255) for c in colorsys.hsv_to_rgb(hue, saturation, value))


def size(n):
    """Width and height for item n, both even so the same sizes suit yuv420p video."""
    width, height = SHAPES[n % len(SHAPES)]
    scale = SCALES[n // len(SHAPES) % len(SCALES)]
    return int(width * scale) // 2 * 2, int(height * scale) // 2 * 2


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def png(width, height, rgb):
    """A truecolor PNG holding one color: IHDR, IDAT and IEND, nothing else."""
    row = b"\x00" + bytes(rgb) * width  # filter type 0, then the pixels
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # 8-bit RGB, no interlace
    pixels = zlib.compress(row * height, 6)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", pixels) + chunk(b"IEND", b"")


def write_videos(out, count, ffmpeg):
    """Return (videos written, codec). Tries each available codec until one encodes every video."""
    listing = subprocess.run([ffmpeg, "-hide_banner", "-encoders"], capture_output=True, text=True).stdout
    for codec in (c for c in VIDEO_CODECS if f" {c} " in listing):
        written = 0
        for n in range(1, count + 1):
            width, height = (320, 240) if n % 2 else (240, 320)
            r, g, b = color(100_000 + n)
            source = f"color=c=0x{r:02x}{g:02x}{b:02x}:s={width}x{height}:d=2:r=30"
            result = subprocess.run(
                [ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i", source,
                 "-c:v", codec, "-pix_fmt", "yuv420p", "-map_metadata", "-1", "-fflags", "+bitexact",
                 "-movflags", "+faststart", str(out / f"fixture-video-{n:03d}.mp4")],
                capture_output=True,
            )
            if result.returncode != 0:
                break
            written += 1
        if written == count:
            return written, codec
        for partial in out.glob("fixture-video-*.mp4"):
            partial.unlink()
    return 0, None


def main(argv):
    if len(argv) != 3 or not argv[2].isdigit():
        print("usage: make_fixture_media.py <out-dir> <count>", file=sys.stderr)
        return 2
    out, count = Path(argv[1]), int(argv[2])
    out.mkdir(parents=True, exist_ok=True)
    digits = max(5, len(str(count)))
    for n in range(1, count + 1):
        width, height = size(n)
        (out / f"fixture-{n:0{digits}d}.png").write_bytes(png(width, height, color(n)))

    wanted = min(50, max(1, count // 100)) if count else 0
    ffmpeg = shutil.which("ffmpeg")
    if not wanted:
        videos = "videos: none (no pictures requested)"
    elif not ffmpeg:
        videos = "videos: skipped, ffmpeg is not installed on this runner"
    else:
        written, codec = write_videos(out, wanted, ffmpeg)
        videos = f"videos: {written} MP4 ({codec})" if written else "videos: skipped, ffmpeg could not encode H.264 or MPEG-4"
    print(f"- Fixture media: {count} solid-color PNGs; {videos}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
