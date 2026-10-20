"""Draws every Morsel icon variant from one geometry (logo concept A2) and renders PNGs.

    python3 tool/brand_icons.py          # writes assets/brand/*.svg and *.png
    dart run flutter_launcher_icons      # then installs them into android/, ios/, web/

PNGs are rendered with headless Google Chrome, which keeps transparency.
"""

import pathlib
import subprocess
import tempfile
import time

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "brand"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

PLUM, LILAC, OAT, WHITE, INK = "#6A3D8F", "#CFAEEA", "#FAF7F2", "#FFFFFF", "#1E1A1F"

# Logo geometry on a 1024 grid: the scanner frame, a barcode whose lower half runs
# out of the frame, and two eyes on top looking down at the bars.
BRACKETS = [
    "M150 270 V200 A50 50 0 0 1 200 150 H270",
    "M754 150 H824 A50 50 0 0 1 874 200 V270",
    "M150 640 V710 A50 50 0 0 0 200 760 H270",
    "M754 760 H824 A50 50 0 0 0 874 710 V640",
]
BARS = [(300, 40), (362, 18), (404, 54), (480, 22), (526, 40), (588, 18), (630, 50), (702, 22)]
BARS_TOP, BARS_BOTTOM = 520, 1400
EYES = [(432, 448), (592, 448)]
EYE_RX, EYE_RY, RING = 80, 74, 8
PUPIL, PUPIL_R, GLINT, GLINT_R = (8, 26), 36, (19, 14), 11

# Android's adaptive-icon safe zone is a 66 dp circle on a 108 dp layer, so the
# foreground layers shrink the art to fit while the bars still run off the bottom.
ADAPTIVE = "translate(512 500) scale(0.608) translate(-512 -455)"


def brackets(color):
    paths = "".join(f'<path d="{d}"/>' for d in BRACKETS)
    return f'<g fill="none" stroke="{color}" stroke-width="40" stroke-linecap="round">{paths}</g>'


def bars(color, extra=""):
    rects = "".join(
        f'<rect x="{x}" y="{BARS_TOP}" width="{w}" height="{BARS_BOTTOM - BARS_TOP}" rx="{min(10, w / 2)}"/>'
        for x, w in BARS
    )
    return f'<g fill="{color}"{extra}>{rects}</g>'


def eyes_colour(ring):
    whites = "".join(
        f'<ellipse cx="{x}" cy="{y}" rx="{EYE_RX}" ry="{EYE_RY}"/>' for x, y in EYES
    )
    pupils = "".join(f'<circle cx="{x + PUPIL[0]}" cy="{y + PUPIL[1]}" r="{PUPIL_R}"/>' for x, y in EYES)
    glints = "".join(f'<circle cx="{x + GLINT[0]}" cy="{y + GLINT[1]}" r="{GLINT_R}"/>' for x, y in EYES)
    return (
        f'<g fill="{WHITE}" stroke="{ring}" stroke-width="{RING * 2}">{whites}</g>'
        f'<g fill="{INK}">{pupils}</g><g fill="{WHITE}">{glints}</g>'
    )


def silhouette():
    """One colour with alpha only: gaps and pupils are cut out, not painted."""
    gaps = "".join(
        f'<ellipse cx="{x}" cy="{y}" rx="{EYE_RX + RING}" ry="{EYE_RY + RING}" fill="#000"/>'
        for x, y in EYES
    )
    holes = "".join(f'<circle cx="{x + PUPIL[0]}" cy="{y + PUPIL[1]}" r="{PUPIL_R}" fill="#000"/>' for x, y in EYES)
    glints = "".join(f'<circle cx="{x + GLINT[0]}" cy="{y + GLINT[1]}" r="{GLINT_R}" fill="#fff"/>' for x, y in EYES)
    whites = "".join(
        f'<ellipse cx="{x}" cy="{y}" rx="{EYE_RX}" ry="{EYE_RY}"/>' for x, y in EYES
    )
    area = 'maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1400"'
    return (
        f'<defs><mask id="gap" {area}><rect width="1024" height="1400" fill="#fff"/>{gaps}</mask>'
        f'<mask id="pupils" {area}><rect width="1024" height="1400" fill="#fff"/>{holes}{glints}</mask></defs>'
        + brackets(WHITE)
        + bars(WHITE, ' mask="url(#gap)"')
        + f'<g fill="{WHITE}" mask="url(#pupils)">{whites}</g>'
    )


def colour_art(ring=PLUM):
    return brackets(LILAC) + bars(OAT) + eyes_colour(ring)


def svg(body, tile=None, transform=None):
    """tile: None (transparent), "square" (full bleed) or "rounded"."""
    art = f'<g transform="{transform}">{body}</g>' if transform else body
    if tile is None:
        content = art
    else:
        rx = ' rx="232"' if tile == "rounded" else ""
        content = (
            f'<defs><clipPath id="tile"><rect width="1024" height="1024"{rx}/></clipPath></defs>'
            f'<g clip-path="url(#tile)"><rect width="1024" height="1024" fill="{PLUM}"/>{art}</g>'
        )
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" '
        f'width="1024" height="1024" role="img" aria-label="Morsel">{content}</svg>\n'
    )


VARIANTS = {
    # iOS (it rounds the corners itself) and the web.
    "icon": svg(colour_art(), tile="square"),
    # Android before 8.0, and in-app / store use.
    "icon-rounded": svg(colour_art(), tile="rounded"),
    # Android 8+ adaptive icon foreground; the plum background is a colour layer.
    "icon-foreground": svg(colour_art(), transform=ADAPTIVE),
    # Android 13+ themed icon.
    "icon-monochrome": svg(silhouette(), transform=ADAPTIVE),
    # iOS 18+ dark and tinted appearances (the system supplies the background).
    "icon-dark": svg(colour_art()),
    "icon-tinted": svg(silhouette()),
}


def render(svg_path, png_path, profile):
    """Headless Chrome writes the screenshot but on macOS often never exits, so wait
    for the file instead of the process, then stop it."""
    png_path.unlink(missing_ok=True)
    chrome = subprocess.Popen(
        [
            CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--user-data-dir={profile}",
            "--default-background-color=00000000", "--window-size=1024,1024",
            f"--screenshot={png_path}", svg_path.as_uri(),
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        for _ in range(300):
            if chrome.poll() is not None or (png_path.exists() and png_path.stat().st_size > 0):
                time.sleep(0.5)  # let the write finish
                break
            time.sleep(0.1)
    finally:
        chrome.kill()
        chrome.wait()
    if not png_path.exists():
        raise SystemExit(f"Chrome produced no {png_path.name}")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    profile = tempfile.mkdtemp(prefix="brand-icons-")  # headless Chrome needs a writable profile
    for name, source in VARIANTS.items():
        svg_path = OUT / f"{name}.svg"
        svg_path.write_text(source)
        render(svg_path, OUT / f"{name}.png", profile)
        print(f"{name}: {svg_path.name} + {name}.png")


if __name__ == "__main__":
    main()
