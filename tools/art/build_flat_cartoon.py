"""Flat cartoon samples in the manner of Forge Master: Idle RPG.

Everything is vector: each sprite and the room are SVG written below, with a
thick uniform black outline, flat fills, at most one flat shade per shape,
bean-shaped figures with dot eyes, and a flat drop shadow. Godot's own SVG
renderer rasterises them (the same path the game would use to import SVG),
then PIL lays out the screen and the chunky outlined UI.

Run: python3 tools/art/build_flat_cartoon.py
Writes SVG sources and PNGs to assets/flat-cartoon-v1/ and the review screen
to docs/art/flat-cartoon-v1/.
"""
import subprocess
import tempfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/flat-cartoon-v1"
REVIEW = ROOT / "docs/art/flat-cartoon-v1"
BOLD = Path("/usr/share/fonts/truetype/nanum/NanumSquareRoundB.ttf")
if not BOLD.exists():
    BOLD = ROOT / "assets/fonts/NanumSquareR.ttf"

INK = "#1c1b22"
LINE = f'stroke="{INK}" stroke-width="3" stroke-linejoin="round" stroke-linecap="round"'


def svg(body: str, size: int = 64) -> str:
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">{body}</svg>'


def blob(cx, cy, r, fill, shade, uid):
    """One Forge Master blob: a flat circle whose lower-left is a darker crescent
    (the shade circle, with the fill circle nudged up-right over it)."""
    return (f'<clipPath id="{uid}"><circle cx="{cx}" cy="{cy}" r="{r}"/></clipPath>'
            f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{shade}"/>'
            f'<circle cx="{cx + r * 0.22}" cy="{cy - r * 0.22}" r="{r}" fill="{fill}" clip-path="url(#{uid})"/>'
            f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" {LINE}/>')


def pills(cx, cy, gap=5.2, rx=1.8, ry=3.3):
    """The eyes: two tall pills, set toward the way the figure faces (right)."""
    return (f'<ellipse cx="{cx - gap / 2}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{INK}"/>'
            f'<ellipse cx="{cx + gap / 2}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{INK}"/>')


def figure(uid, body, head, eyes="", hat="", weapon="", mark="", head_r=14.5, body_r=12.5):
    """Head over body, no limbs: the whole Forge Master figure. The weapon
    floats across the body in front of everything."""
    body_fill, body_shade = body
    head_fill, head_shade = head
    return ('<ellipse cx="31" cy="58" rx="14" ry="3.6" fill="#000" fill-opacity="0.2"/>'
            + blob(31, 45, body_r, body_fill, body_shade, uid + "b") + mark
            + blob(32, 27, head_r, head_fill, head_shade, uid + "h") + eyes + hat + weapon)


STITCH = f'<path d="M27 47 L31 51 M31 47 L27 51" stroke="{INK}" stroke-width="1.6" stroke-linecap="round"/>'
SKIN = ("#f6c79a", "#e0a574")

SPRITES = {
    "hero": figure(
        "hero", ("#5d6b82", "#48546a"), SKIN, pills(37, 32.5, 5.2, 1.8, 3.0),
        hat=(f'<path d="M16.5 25 Q16 10 32 10 Q48 10 47.5 25 Z" fill="#c9d2de" {LINE}/>'
             '<path d="M36 11 Q47 13 47.5 25 L40 25 Z" fill="#aeb8c6"/>'
             f'<path d="M16.5 25 Q16 10 32 10 Q48 10 47.5 25 Z" fill="none" {LINE}/>'
             f'<rect x="14" y="23" width="36" height="5" rx="2.5" fill="#aeb8c6" {LINE}/>'
             f'<path d="M30 11 Q24 2 16 5 Q22 7 25 13 Z" fill="#e0453a" {LINE}/>'),
        weapon=(f'<g transform="rotate(-12 34 44)"><rect x="34" y="41" width="27" height="5.5" rx="1.5" fill="#e8eef5" {LINE}/>'
                f'<rect x="31" y="36.5" width="5" height="14.5" rx="2" fill="#f2c64b" {LINE}/>'
                f'<rect x="21" y="41.5" width="11" height="4.5" rx="2" fill="#7a4a26" {LINE}/></g>'),
        mark=f'<path d="M20 41 Q31 47 42 41" fill="none" stroke="#c0392f" stroke-width="5" stroke-linecap="round"/>'),

    "goblin": figure(
        "goblin", ("#8a5a33", "#6f4526"), ("#78c24c", "#5ea338"), pills(37, 29),
        hat=(f'<path d="M19 26 L5 18 L18 34 Z" fill="#78c24c" {LINE}/>'
             f'<path d="M45 22 L58 12 L47 31 Z" fill="#78c24c" {LINE}/>'),
        weapon=(f'<g transform="rotate(-18 36 46)"><path d="M36 43 L56 44 L36 48 Z" fill="#dfe6ef" {LINE}/>'
                f'<rect x="27" y="43" width="10" height="4.5" rx="2" fill="#5a3a22" {LINE}/></g>'),
        mark=STITCH, head_r=13),

    "skeleton": ('<ellipse cx="31" cy="58" rx="14" ry="3.6" fill="#000" fill-opacity="0.2"/>'
        + blob(31, 45, 12.5, "#b8433b", "#963229", "skb") + STITCH
        + '<clipPath id="skh"><path d="M19 27 Q19 12 33 12 Q47 12 47 27 L47 33 Q47 38 42 38 L24 38 Q19 38 19 33 Z"/></clipPath>'
        + '<path d="M19 27 Q19 12 33 12 Q47 12 47 27 L47 33 Q47 38 42 38 L24 38 Q19 38 19 33 Z" fill="#e2d8bd"/>'
        + '<path d="M22 24 Q22 14 36 13 Q49 14 49 27 L49 35 Q49 36 44 36 L24 36 Q22 36 22 33 Z" fill="#f4ecd6" clip-path="url(#skh)"/>'
        + f'<path d="M19 27 Q19 12 33 12 Q47 12 47 27 L47 33 Q47 38 42 38 L24 38 Q19 38 19 33 Z" fill="none" {LINE}/>'
        + f'<rect x="33.4" y="22" width="3.4" height="8" rx="1.7" fill="{INK}"/><rect x="39.6" y="22" width="3.4" height="8" rx="1.7" fill="{INK}"/>'
        + f'<g transform="rotate(-14 30 46)"><path d="M10 43 Q9 39 13 39 L50 41 Q53 43.5 50 46 L13 47 Q9 47 10 43 Z" fill="#a8703e" {LINE}/>'
        + f'<path d="M20 40 L16 34 Q15 32 17 32 L22 39" fill="#a8703e" {LINE}/>'
        + '<ellipse cx="12.5" cy="43" rx="1.6" ry="2.6" fill="#d9a870"/></g>'),

    "rat": ('<ellipse cx="32" cy="58" rx="17" ry="3.6" fill="#000" fill-opacity="0.2"/>'
        + f'<path d="M15 50 Q4 50 5 40" fill="none" stroke="{INK}" stroke-width="6" stroke-linecap="round"/>'
        + '<path d="M15 50 Q4 50 5 40" fill="none" stroke="#e9a0a6" stroke-width="2.6" stroke-linecap="round"/>'
        + blob(28, 46, 12, "#8f8f9c", "#737382", "ratb")
        + blob(40, 40, 10.5, "#9d9daa", "#80808e", "rath")
        + f'<circle cx="36" cy="29" r="5" fill="#e9a0a6" {LINE}/>'
        + f'<ellipse cx="44" cy="38" rx="1.7" ry="3" fill="{INK}"/>'
        + f'<circle cx="50.5" cy="42" r="2.2" fill="#e9a0a6" {LINE}/>'),

    "orc": figure(
        "orc", ("#4d3a2c", "#3a2b20"), ("#86a94c", "#6d8e3a"), pills(38, 30, 5.6, 1.9, 3.1),
        hat=(f'<path d="M31 25 L36 27 M41 27 L46 25" stroke="{INK}" stroke-width="2.4" stroke-linecap="round"/>'
             f'<path d="M34 37 L35.5 32.5 L37.5 37 Z M42 37 L43 32.5 L45 37 Z" fill="#fbf6e6" {LINE}/>'),
        weapon=(f'<g transform="rotate(-20 34 46)"><rect x="14" y="43" width="42" height="4.5" rx="2" fill="#8a5a33" {LINE}/>'
                f'<path d="M50 44 Q50 32 60 30 Q63 40 60 50 Q56 56 50 49 Z" fill="#c9d1dc" {LINE}/></g>'),
        mark=STITCH, head_r=16, body_r=14),
}

GROUND = '<ellipse cx="32" cy="{cy}" rx="{rx}" ry="3.6" fill="#000" fill-opacity="0.16"/>'


def banded(uid, shape, fill, shade, split):
    """Forge Master's prop shading, read off its barrel: the flat fill, a
    darker vertical band on the right from `split` onward, then the outline."""
    return (f'<clipPath id="{uid}">{shape.format(fill="#000", line="")}</clipPath>'
            + shape.format(fill=fill, line="")
            + f'<rect x="{split}" y="0" width="64" height="64" fill="{shade}" clip-path="url(#{uid})"/>'
            + shape.format(fill="none", line=LINE))


PROPS = {
    "chest": GROUND.format(cy=56, rx=20)
    + banded("chb", '<rect x="12" y="31" width="40" height="23" rx="3" fill="{fill}" {line}/>', "#c47d40", "#a7652f", 41)
    + banded("chl", '<rect x="10" y="20" width="44" height="13" rx="5" fill="{fill}" {line}/>', "#d68f4e", "#b8743a", 42)
    + f'<path d="M20 20 L20 54 M44 20 L44 54" stroke="{INK}" stroke-width="3"/>'
    + f'<rect x="27.5" y="28" width="9" height="10" rx="2.5" fill="#f5c84a" {LINE}/>',
    "barrel": GROUND.format(cy=56, rx=14)
    + banded("bab", '<path d="M19 20 L19 52 Q19 56 32 56 Q45 56 45 52 L45 20 Z" fill="{fill}" {line}/>', "#3f9ad8", "#2f82bf", 34)
    + f'<path d="M19 31 Q32 35 45 31 M19 42 Q32 46 45 42" fill="none" {LINE}/>'
    + banded("bat", '<ellipse cx="32" cy="20" rx="13" ry="4.5" fill="{fill}" {line}/>', "#5bb1e8", "#4a9fd8", 34),
    "torch": banded("tos", '<rect x="28.5" y="30" width="7" height="24" rx="2" fill="{fill}" {line}/>', "#a8703e", "#8a5a30", 32)
    + banded("toc", '<path d="M21 27 L43 27 L39 34 L25 34 Z" fill="{fill}" {line}/>', "#b8c2cf", "#98a3b2", 34)
    + f'<path d="M32 4 Q43 15 41 23 Q39 30 32 30 Q25 30 23 23 Q21 15 32 4 Z" fill="#ff8a2a" {LINE}/>'
    + '<path d="M32 13 Q37 19 36.5 24 Q35 28 32 28 Q29 28 27.5 24 Q27 19 32 13 Z" fill="#ffd84a"/>',
    "potion": GROUND.format(cy=57, rx=12)
    + banded("pon", '<rect x="27" y="13" width="10" height="13" rx="2" fill="{fill}" {line}/>', "#e4eef7", "#c9d6e3", 33)
    + f'<rect x="25.5" y="8" width="13" height="7" rx="2.5" fill="#a8703e" {LINE}/>'
    + banded("pob", '<circle cx="32" cy="40" r="15" fill="{fill}" {line}/>', "#ec4a3f", "#c9352c", 36)
    + '<ellipse cx="25.5" cy="35" rx="2.6" ry="4.4" fill="#fff" fill-opacity="0.8"/>',
    "scroll": GROUND.format(cy=57, rx=18)
    + banded("scp", '<rect x="15" y="17" width="34" height="33" rx="2" fill="{fill}" {line}/>', "#f6e8c4", "#e5d2a6", 38)
    + '<path d="M21 26 L41 26 M21 33 L37 33 M21 40 L39 40" stroke="#b39a6a" stroke-width="3" stroke-linecap="round"/>'
    + banded("sct", '<rect x="11" y="12" width="42" height="8" rx="4" fill="{fill}" {line}/>', "#dcc28a", "#c4a76e", 40)
    + banded("scb", '<rect x="11" y="47" width="42" height="8" rx="4" fill="{fill}" {line}/>', "#dcc28a", "#c4a76e", 40),
}

ICONS = {
    "attack": '<g transform="rotate(45 32 32)">'
    + banded("at1", '<rect x="28.5" y="5" width="7" height="37" rx="2" fill="{fill}" {line}/>', "#eef3f8", "#c9d3de", 32)
    + f'<rect x="20" y="40" width="24" height="6.5" rx="3" fill="#f5c84a" {LINE}/><rect x="28.5" y="46" width="7" height="12" rx="2.5" fill="#8a5a30" {LINE}/></g>'
    + '<g transform="rotate(-45 32 32)">'
    + banded("at2", '<rect x="28.5" y="5" width="7" height="37" rx="2" fill="{fill}" {line}/>', "#eef3f8", "#c9d3de", 32)
    + f'<rect x="20" y="40" width="24" height="6.5" rx="3" fill="#f5c84a" {LINE}/><rect x="28.5" y="46" width="7" height="12" rx="2.5" fill="#8a5a30" {LINE}/></g>',
    "wait": f'<rect x="15" y="6" width="34" height="7" rx="3.5" fill="#a8703e" {LINE}/><rect x="15" y="51" width="34" height="7" rx="3.5" fill="#a8703e" {LINE}/>'
    + banded("wag", '<path d="M19 13 L45 13 Q45 26 32 32 Q45 38 45 51 L19 51 Q19 38 32 32 Q19 26 19 13 Z" fill="{fill}" {line}/>', "#e6f5ff", "#c6e2f5", 36)
    + '<path d="M24.5 19 L39.5 19 Q36.5 26.5 32 28.5 Q27.5 26.5 24.5 19 Z M23.5 49 Q23.5 41 32 38.5 Q40.5 41 40.5 49 Z" fill="#f5c84a"/>',
    "search": f'<rect x="38" y="35" width="9" height="23" rx="3.5" transform="rotate(-45 42.5 46.5)" fill="#a8703e" {LINE}/>'
    + banded("seg", '<circle cx="26" cy="26" r="17" fill="{fill}" {line}/>', "#a8ddff", "#86c6ef", 31)
    + '<path d="M17 21 A10 10 0 0 1 25 14" fill="none" stroke="#fff" stroke-width="4.5" stroke-linecap="round"/>',
    "tactics": banded("tap", '<rect x="13" y="6" width="6" height="52" rx="2.5" fill="{fill}" {line}/>', "#a8703e", "#8a5a30", 16)
    + banded("taf", '<path d="M19 9 L53 13 L45 23 L53 33 L19 30 Z" fill="{fill}" {line}/>', "#ec4a3f", "#c9352c", 40),
    "bag": f'<path d="M22 20 Q22 7 32 7 Q42 7 42 20" fill="none" stroke="{INK}" stroke-width="7.5" stroke-linecap="round"/>'
    + '<path d="M22 20 Q22 7 32 7 Q42 7 42 20" fill="none" stroke="#a8703e" stroke-width="3" stroke-linecap="round"/>'
    + banded("bgb", '<rect x="11" y="17" width="42" height="40" rx="10" fill="{fill}" {line}/>', "#c47d40", "#a7652f", 40)
    + f'<rect x="19" y="32" width="26" height="16" rx="4.5" fill="#a7652f" {LINE}/>'
    + f'<rect x="28.5" y="27" width="7" height="9" rx="2.5" fill="#f5c84a" {LINE}/>',
    "food": banded("fom", '<path d="M18 47 Q7 41 13 28 Q21 13 38 15 Q55 19 51 36 Q47 49 30 49 Z" fill="{fill}" {line}/>', "#d56e3f", "#b85a30", 38)
    + f'<rect x="40" y="40" width="8" height="19" rx="3.5" transform="rotate(-40 44 48)" fill="#f6eedc" {LINE}/>',
    "gold": banded("gog", '<circle cx="32" cy="32" r="21" fill="{fill}" {line}/>', "#f5c84a", "#dca832", 38)
    + '<circle cx="32" cy="32" r="12.5" fill="none" stroke="#c9922a" stroke-width="4"/>',
}


def room_svg(width: int, height: int, cols: int, rows: int) -> str:
    """The room the Forge Master way: one flat floor colour with no grid, a
    darker splat or two, ink grass marks and pebbles; a flat back wall with a
    few big blocks drawn as thin darker lines; bold ink only on the big edges."""
    tile = width / cols
    wall_h = tile * 1.6
    x0, x1 = tile * 0.5, width - tile * 0.5
    floor_bottom = height - tile * 0.5
    parts = [f'<rect width="{width}" height="{height}" fill="#2a2b36"/>',
             f'<rect x="{x0}" y="{wall_h}" width="{x1 - x0}" height="{floor_bottom - wall_h}" fill="#d8b98a"/>']
    for cx, cy, r in ((0.3, 0.55, 26), (0.66, 0.78, 22), (0.5, 0.36, 18)):
        px, py = width * cx, height * cy
        parts.append(f'<ellipse cx="{px}" cy="{py}" rx="{r * 1.9}" ry="{r * 0.8}" fill="#c4a372"/>')
        for dx, dy, rr in ((-r * 2.4, -2, 5), (r * 2.3, 3, 4), (r * 1.2, -r * 0.9, 3.5), (-r * 1.1, r * 0.95, 3)):
            parts.append(f'<ellipse cx="{px + dx}" cy="{py + dy}" rx="{rr * 1.5}" ry="{rr}" fill="#c4a372"/>')
    for fx, fy in ((0.24, 0.42), (0.74, 0.5), (0.44, 0.84), (0.16, 0.7), (0.84, 0.3), (0.58, 0.62)):
        px, py = width * fx, height * fy
        parts.append(f'<path d="M{px} {py} l0 -14 l8 10 l4 -9 l-6 16" fill="none" stroke="{INK}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>')
    for fx, fy, r in ((0.36, 0.3, 7), (0.62, 0.7, 6), (0.2, 0.52, 5), (0.8, 0.86, 6)):
        px, py = width * fx, height * fy
        parts.append(f'<ellipse cx="{px}" cy="{py}" rx="{r * 1.4}" ry="{r}" fill="#b0a08a" {LINE}/>')
    parts.append(f'<rect x="{x0}" y="{wall_h}" width="{x1 - x0}" height="{floor_bottom - wall_h}" fill="none" stroke="{INK}" stroke-width="5"/>')
    # Back wall: flat slate, a lighter cap, big blocks as thin darker lines.
    top = tile * 0.2
    parts.append(f'<rect x="{x0}" y="{top}" width="{x1 - x0}" height="{wall_h - top}" fill="#6c7288"/>')
    parts.append(f'<rect x="{x0}" y="{top}" width="{x1 - x0}" height="{tile * 0.28}" fill="#858ba0"/>')
    mid = top + (wall_h - top) * 0.55
    parts.append(f'<path d="M{x0} {mid} L{x1} {mid}" stroke="#595e72" stroke-width="4"/>')
    for i, x in enumerate(range(int(x0 + tile * 1.1), int(x1), int(tile * 1.4))):
        y_a, y_b = (top + tile * 0.28, mid) if i % 2 == 0 else (mid, wall_h)
        parts.append(f'<path d="M{x} {y_a} L{x} {y_b}" stroke="#595e72" stroke-width="4"/>')
        xb = x + tile * 0.7
        parts.append(f'<path d="M{xb} {mid if i % 2 == 0 else top + tile * 0.28} L{xb} {wall_h if i % 2 == 0 else mid}" stroke="#595e72" stroke-width="4"/>')
    parts.append(f'<rect x="{x0}" y="{top}" width="{x1 - x0}" height="{wall_h - top}" fill="none" stroke="{INK}" stroke-width="5"/>')
    cx = width / 2
    parts.append(f'<path d="M{cx - tile * 0.72} {wall_h} L{cx - tile * 0.72} {tile * 0.95} Q{cx - tile * 0.72} {tile * 0.42} {cx} {tile * 0.42} Q{cx + tile * 0.72} {tile * 0.42} {cx + tile * 0.72} {tile * 0.95} L{cx + tile * 0.72} {wall_h} Z" fill="#23242e" stroke="{INK}" stroke-width="5" stroke-linejoin="round"/>')
    for i in range(3):
        y = tile * 1.0 + i * tile * 0.19
        parts.append(f'<rect x="{cx - tile * 0.5 + i * 5}" y="{y}" width="{tile - i * 10}" height="{tile * 0.11}" rx="3" fill="#6c7288"/>')
    return svg("".join(parts)).replace('width="64" height="64" viewBox="0 0 64 64"', f'width="{width}" height="{height}" viewBox="0 0 {width} {height}"')


RASTER = """extends SceneTree
func _initialize():
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var img := Image.new()
		img.load_svg_from_string(FileAccess.get_file_as_string(args[i]), float(args[i + 2]))
		img.save_png(args[i + 1])
		i += 3
	quit()
"""


def rasterise(jobs: list) -> None:
    """Godot's SVG renderer, in one headless run for every (svg, png, scale)."""
    with tempfile.TemporaryDirectory() as tmp:
        script = Path(tmp) / "raster.gd"
        script.write_text(RASTER)
        args = []
        for source, target, scale in jobs:
            args += [str(source), str(target), str(scale)]
        subprocess.run(["godot", "--headless", "--path", str(ROOT), "--script", str(script), "--", *args],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(BOLD), size)


def outlined(draw, xy, text, size, fill="#ffffff", stroke=6, anchor="la"):
    draw.text(xy, text, font=font(size), fill=fill, stroke_width=stroke, stroke_fill=INK, anchor=anchor)


def chunky(draw, box, fill, lip, radius=18, width=5):
    """A Forge Master button: black rim, a darker bottom lip, a pale top band."""
    x0, y0, x1, y1 = box
    draw.rounded_rectangle(box, radius, fill=INK)
    draw.rounded_rectangle((x0 + width, y0 + width, x1 - width, y1 - width), radius - width, fill=lip)
    draw.rounded_rectangle((x0 + width, y0 + width, x1 - width, y1 - width - 9), radius - width, fill=fill)
    draw.rounded_rectangle((x0 + width + 8, y0 + width + 5, x1 - width - 8, y0 + width + 12), 4, fill=(255, 255, 255, 70))


def bar(draw, box, value, maximum, fill, back="#3a3b46"):
    x0, y0, x1, y1 = box
    draw.rounded_rectangle(box, (y1 - y0) // 2, fill=INK)
    draw.rounded_rectangle((x0 + 4, y0 + 4, x1 - 4, y1 - 4), (y1 - y0 - 8) // 2, fill=back)
    inner = x0 + 4 + (x1 - x0 - 8) * value // maximum
    draw.rounded_rectangle((x0 + 4, y0 + 4, inner, y1 - 4), (y1 - y0 - 8) // 2, fill=fill)


def main() -> None:
    for path in (OUT / "svg", OUT / "png", REVIEW):
        path.mkdir(parents=True, exist_ok=True)
    jobs = []
    for group in (SPRITES, PROPS, ICONS):
        for name, body in group.items():
            source = OUT / "svg" / f"{name}.svg"
            source.write_text(svg(body))
            jobs.append((source, OUT / "png" / f"{name}.png", 3))
    width, height = 780, 1688
    cols, rows = 9, 10
    room = OUT / "svg" / "room.svg"
    room.write_text(room_svg(width, 960, cols, rows))
    jobs.append((room, OUT / "png" / "room.png", 1))
    rasterise(jobs)

    screen = Image.new("RGBA", (width, height), "#2a2b36")
    draw = ImageDraw.Draw(screen, "RGBA")
    art = {path.stem: Image.open(path).convert("RGBA") for path in (OUT / "png").glob("*.png")}

    # Top bar: portrait pill with power, and food / gold pills.
    draw.rectangle((0, 0, width, 120), fill="#3a3c4c")
    draw.line((0, 120, width, 120), fill=INK, width=5)
    chunky(draw, (18, 22, 330, 102), "#4d5064", "#3a3c4c", 22)
    draw.rounded_rectangle((28, 30, 94, 94), 14, fill="#6d8fd8", outline=INK, width=5)
    screen.alpha_composite(art["hero"].resize((72, 72)), (25, 26))
    outlined(draw, (108, 32), "아린", 30)
    screen.alpha_composite(art["attack"].resize((34, 34)), (106, 62))
    outlined(draw, (146, 66), "4.82k", 24, "#f2c64b", 5)
    for i, (icon, value) in enumerate((("food", "2"), ("gold", "1.2k"))):
        x0 = 380 + i * 200
        chunky(draw, (x0, 38, x0 + 180, 94), "#4d5064", "#3a3c4c", 26)
        screen.alpha_composite(art[icon].resize((70, 70)), (x0 - 18, 30))
        outlined(draw, (x0 + 110, 66), value, 30, anchor="mm")

    # Floor title with the progress nodes the reference uses for waves.
    outlined(draw, (width // 2, 158), "지하 1층 · 42턴", 38, anchor="mm")
    draw.line((250, 204, 530, 204), fill=INK, width=12)
    draw.line((250, 204, 530, 204), fill="#4a8fd6", width=5)
    for i, x in enumerate((250, 390, 530)):
        draw.ellipse((x - 14, 190, x + 14, 218), fill="#9fd8ff" if i < 2 else "#ffffff", outline=INK, width=5)

    # The room and everything in it.
    top = 236
    screen.alpha_composite(art["room"], (0, top))
    tile = width / cols

    def place(name, col, row, size=150):
        image = art[name].resize((size, size))
        x = int(tile * 0.5 + col * tile + tile / 2 - size / 2)
        y = int(top + tile * 1.6 + row * tile + tile * 0.6 - size * 0.85)
        screen.alpha_composite(image, (x, y))
        return x, y

    place("torch", 1.2, -1.15, 110)
    place("torch", 5.8, -1.15, 110)
    place("chest", 0.3, 4.2, 140)
    place("barrel", 7.0, 1.0, 130)
    place("barrel", 7.2, 2.0, 130)
    place("potion", 4.6, 5.2, 110)
    place("scroll", 1.8, 6.1, 110)
    foes = [("orc", 5.3, 0.8, 9, 14), ("goblin", 6.1, 2.6, 6, 10), ("skeleton", 4.6, 3.4, 4, 10), ("rat", 1.4, 2.6, 5, 8)]
    for name, col, row, hp, maximum in foes:
        x, y = place(name, col, row)
        bar(draw, (x + 42, y - 4, x + 108, y + 12), hp, maximum, "#e8413a")
    place("hero", 3.2, 2.6, 160)

    # Log card.
    log_top = top + 960 + 16
    chunky(draw, (18, log_top, width - 18, log_top + 150), "#ffffff", "#d7dae4", 22)
    lines = [("해골이 일어섰다!", INK), ("고블린이 다가온다!", INK), ("붉은 물약을 발견했다.", "#d8352f")]
    for i, (text, color) in enumerate(lines):
        draw.text((44, log_top + 22 + i * 38), text, font=font(28), fill=color)

    # Hero card: HP / MP / stress.
    card_top = log_top + 166
    for i, (label, value, maximum, fill) in enumerate((("HP", 38, 55, "#e8413a"), ("MP", 12, 18, "#4a8fd6"), ("스트레스", 8, 100, "#9a5bd6"))):
        x0 = 18 + i * 250
        outlined(draw, (x0 + 4, card_top), label, 24)
        bar(draw, (x0, card_top + 34, x0 + 238, card_top + 64), value, maximum, fill)

    # Action buttons: five coloured chunky buttons with icons and labels.
    button_top = card_top + 84
    colours = [("attack", "공격", "#e8413a", "#b02a25"), ("wait", "대기", "#f2c64b", "#c29a2c"),
               ("search", "탐색", "#58c25a", "#3b9140"), ("tactics", "전술", "#9a5bd6", "#7340a8"),
               ("bag", "가방", "#4a8fd6", "#2f6aad")]
    for i, (icon, label, fill, lip) in enumerate(colours):
        x0 = 14 + i * 152
        chunky(draw, (x0, button_top, x0 + 142, height - 20), fill, lip, 22, 6)
        screen.alpha_composite(art[icon].resize((88, 88)), (x0 + 27, button_top + 10))
        outlined(draw, (x0 + 71, height - 60), label, 32, anchor="mm")

    screen.convert("RGB").save(REVIEW / "gameplay-v2-780x1688.png")
    board = Image.new("RGBA", (7 * 170 + 20, 3 * 180 + 20), "#e9ecf2")
    for r, group in enumerate((SPRITES, PROPS, ICONS)):
        for c, name in enumerate(group):
            board.alpha_composite(art[name].resize((160, 160)), (15 + c * 170, 15 + r * 180))
    board.convert("RGB").save(REVIEW / "sprite-sheet.png")


if __name__ == "__main__":
    main()
