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
SHADOW = '<ellipse cx="32" cy="58" rx="15" ry="4" fill="#000" fill-opacity="0.22"/>'


def svg(body: str, size: int = 64) -> str:
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">{body}</svg>'


def bean(x0, y0, x1, y1, fill, shade):
    """A rounded body: flat fill, one flat shade on the right, outline on top."""
    r = (x1 - x0) / 2
    path = f"M{x0} {y0 + r} A{r} {r} 0 0 1 {x1} {y0 + r} L{x1} {y1 - 4} Q{x1} {y1} {x1 - 4} {y1} L{x0 + 4} {y1} Q{x0} {y1} {x0} {y1 - 4} Z"
    mid = x0 + (x1 - x0) * 0.62
    shade_path = f"M{mid} {y0 + 1} A{r} {r} 0 0 1 {x1} {y0 + r} L{x1} {y1 - 4} Q{x1} {y1} {x1 - 4} {y1} L{mid} {y1} Z"
    return (f'<path d="{path}" fill="{fill}"/><path d="{shade_path}" fill="{shade}"/>'
            f'<path d="{path}" fill="none" {LINE}/>')


def feet(color="#4a3325"):
    return (f'<rect x="23" y="51" width="7" height="6" rx="2.5" fill="{color}" {LINE}/>'
            f'<rect x="34" y="51" width="7" height="6" rx="2.5" fill="{color}" {LINE}/>')


def eyes(cx, cy, gap=7, r=2.2, color=INK):
    return f'<circle cx="{cx - gap / 2}" cy="{cy}" r="{r}" fill="{color}"/><circle cx="{cx + gap / 2}" cy="{cy}" r="{r}" fill="{color}"/>'


SPRITES = {
    "hero": SHADOW + feet() + bean(20, 30, 44, 54, "#3b72db", "#2c58b0")
    + f'<rect x="20" y="42" width="24" height="4" fill="#6b4524" {LINE}/>'
    + f'<rect x="30" y="41" width="5" height="6" rx="1" fill="#f2c64b" {LINE}/>'
    + f'<circle cx="32" cy="24" r="12" fill="#f5c28e" {LINE}/>'
    + f'<path d="M19 26 Q18 10 32 9 Q46 10 45 26 L41 26 Q41 17 32 17 Q23 17 23 26 Z" fill="#2c58b0" {LINE}/>'
    + eyes(33, 25)
    + f'<g transform="rotate(35 48 34)"><rect x="46" y="12" width="5" height="24" rx="1.5" fill="#dfe6ef" {LINE}/>'
    + f'<rect x="42" y="35" width="13" height="4" rx="2" fill="#f2c64b" {LINE}/>'
    + f'<rect x="46.5" y="39" width="4" height="7" rx="1.5" fill="#6b4524" {LINE}/></g>',

    "goblin": SHADOW + feet("#3a2a1c") + bean(21, 33, 43, 54, "#8a5a33", "#6f4526")
    + f'<path d="M22 22 L8 15 L20 30 Z" fill="#6cc04a" {LINE}/><path d="M42 22 L56 15 L44 30 Z" fill="#6cc04a" {LINE}/>'
    + f'<circle cx="32" cy="26" r="12" fill="#6cc04a" {LINE}/>'
    + '<path d="M36 16 A12 12 0 0 1 44 26 L38 26 Z" fill="#56a33a"/>'
    + f'<circle cx="32" cy="26" r="12" fill="none" {LINE}/>'
    + eyes(31, 26, 8, 2.4, "#1c1b22")
    + f'<path d="M27 32 Q32 35 37 32" fill="none" {LINE}/>'
    + f'<g transform="rotate(-25 48 40)"><path d="M45 26 Q52 26 51 34 L49 50 L45 50 L44 34 Z" fill="#a0683a" {LINE}/></g>',

    "skeleton": SHADOW + feet("#d8d2c0") + bean(22, 34, 42, 54, "#8e3a3a", "#722c2c")
    + f'<path d="M27 38 L37 38 M27 43 L37 43 M27 48 L37 48" {LINE}/>'
    + f'<circle cx="32" cy="24" r="12" fill="#f1ecdc" {LINE}/>'
    + f'<rect x="26" y="31" width="12" height="7" rx="2" fill="#f1ecdc" {LINE}/>'
    + '<path d="M36 13 A12 12 0 0 1 44 24 L38 26 Z" fill="#dcd5c0"/>'
    + f'<circle cx="32" cy="24" r="12" fill="none" {LINE}/>'
    + f'<ellipse cx="27.5" cy="24" rx="3" ry="3.4" fill="{INK}"/><ellipse cx="36.5" cy="24" rx="3" ry="3.4" fill="{INK}"/>'
    + f'<path d="M30 34 L30 38 M34 34 L34 38" {LINE}/>'
    + f'<g transform="rotate(30 48 40)"><rect x="45" y="26" width="5" height="22" rx="2.5" fill="#f1ecdc" {LINE}/>'
    + f'<circle cx="45.5" cy="26" r="3" fill="#f1ecdc" {LINE}/><circle cx="50" cy="26" r="3" fill="#f1ecdc" {LINE}/></g>',

    "rat": '<ellipse cx="32" cy="57" rx="18" ry="4" fill="#000" fill-opacity="0.22"/>'
    + f'<path d="M48 48 Q60 46 58 36" fill="none" stroke="{INK}" stroke-width="6" stroke-linecap="round"/>'
    + '<path d="M48 48 Q60 46 58 36" fill="none" stroke="#e9a0a6" stroke-width="3" stroke-linecap="round"/>'
    + f'<ellipse cx="34" cy="45" rx="16" ry="11" fill="#8a8a96" {LINE}/>'
    + '<path d="M34 34 A16 11 0 0 1 50 45 A16 11 0 0 1 36 56 Z" fill="#72727f"/>'
    + f'<ellipse cx="34" cy="45" rx="16" ry="11" fill="none" {LINE}/>'
    + f'<circle cx="20" cy="33" r="5" fill="#e9a0a6" {LINE}/>'
    + f'<path d="M26 40 Q12 38 9 46 Q12 51 22 51" fill="#8a8a96" {LINE}/>'
    + f'<circle cx="9" cy="46" r="2" fill="{INK}"/><circle cx="18" cy="44" r="2.2" fill="{INK}"/>'
    + f'<path d="M26 55 L26 58 M40 55 L40 58" {LINE}/>',

    "orc": SHADOW + feet("#3a2a1c") + bean(17, 30, 47, 55, "#6e8c3a", "#5a7430")
    + f'<rect x="17" y="42" width="30" height="5" fill="#5a3a22" {LINE}/>'
    + f'<path d="M17 34 Q14 30 18 28 L26 32 Z" fill="#9aa3b3" {LINE}/><path d="M47 34 Q50 30 46 28 L38 32 Z" fill="#9aa3b3" {LINE}/>'
    + f'<circle cx="32" cy="22" r="13" fill="#7fa447" {LINE}/>'
    + '<path d="M37 10 A13 13 0 0 1 45 22 L39 22 Z" fill="#6a8c3a"/>'
    + f'<circle cx="32" cy="22" r="13" fill="none" {LINE}/>'
    + f'<path d="M24 16 L30 18.5 M40 16 L34 18.5" {LINE}/>' + eyes(32, 23, 9, 2.2)
    + f'<path d="M26 31 L27 27 L29 31 M38 31 L37 27 L35 31" fill="#fbf6e6" {LINE}/>'
    + f'<g transform="rotate(20 52 30)"><rect x="50" y="14" width="4" height="34" rx="2" fill="#8a5a33" {LINE}/>'
    + f'<path d="M52 16 Q64 16 62 28 Q58 24 52 26 Z" fill="#c9d1dc" {LINE}/></g>',
}

PROPS = {
    "chest": '<ellipse cx="32" cy="55" rx="20" ry="4" fill="#000" fill-opacity="0.22"/>'
    + f'<rect x="12" y="30" width="40" height="24" rx="3" fill="#b0703a" {LINE}/>'
    + '<rect x="38" y="31.5" width="12.5" height="21" fill="#94592c"/>'
    + f'<rect x="12" y="30" width="40" height="24" rx="3" fill="none" {LINE}/>'
    + f'<path d="M12 30 Q12 18 32 18 Q52 18 52 30 Z" fill="#c8844a" {LINE}/>'
    + f'<rect x="12" y="29" width="40" height="5" fill="#f2c64b" {LINE}/>'
    + f'<rect x="28" y="31" width="8" height="9" rx="2" fill="#f2c64b" {LINE}/>',
    "barrel": '<ellipse cx="32" cy="56" rx="14" ry="4" fill="#000" fill-opacity="0.22"/>'
    + f'<path d="M20 22 Q17 38 20 54 L44 54 Q47 38 44 22 Z" fill="#4a8fd6" {LINE}/>'
    + f'<path d="M19 33 L45 33 M19 44 L45 44" {LINE}/>'
    + f'<ellipse cx="32" cy="22" rx="12" ry="4" fill="#78b2ec" {LINE}/>',
    "torch": f'<rect x="29" y="30" width="6" height="22" rx="2" fill="#8a5a33" {LINE}/>'
    + f'<path d="M22 28 L42 28 L38 34 L26 34 Z" fill="#9aa3b3" {LINE}/>'
    + f'<path d="M32 6 Q42 16 40 24 Q38 30 32 30 Q26 30 24 24 Q22 16 32 6 Z" fill="#ff8a2a" {LINE}/>'
    + '<path d="M32 14 Q37 20 36 25 Q34 28 32 28 Q30 28 28 25 Q27 20 32 14 Z" fill="#ffd84a"/>',
    "potion": '<ellipse cx="32" cy="56" rx="12" ry="3.5" fill="#000" fill-opacity="0.22"/>'
    + f'<rect x="27" y="14" width="10" height="12" rx="2" fill="#dbe7f2" {LINE}/>'
    + f'<rect x="26" y="10" width="12" height="6" rx="2" fill="#a0683a" {LINE}/>'
    + f'<circle cx="32" cy="40" r="15" fill="#e8413a" {LINE}/>'
    + '<path d="M38 27 A15 15 0 0 1 44 49 L32 45 Z" fill="#c12f2a"/>'
    + f'<circle cx="32" cy="40" r="15" fill="none" {LINE}/>'
    + '<ellipse cx="26" cy="34" rx="3" ry="4.5" fill="#fff" fill-opacity="0.75"/>',
    "scroll": '<ellipse cx="32" cy="55" rx="18" ry="3.5" fill="#000" fill-opacity="0.22"/>'
    + f'<rect x="15" y="18" width="34" height="32" rx="2" fill="#f4e6c2" {LINE}/>'
    + f'<path d="M21 27 L43 27 M21 34 L39 34 M21 41 L41 41" stroke="#b39a6a" stroke-width="3" stroke-linecap="round"/>'
    + f'<rect x="11" y="13" width="42" height="8" rx="4" fill="#d9c08a" {LINE}/>'
    + f'<rect x="11" y="47" width="42" height="8" rx="4" fill="#d9c08a" {LINE}/>',
}

ICONS = {
    "attack": f'<g transform="rotate(45 32 32)"><rect x="29" y="6" width="6" height="36" rx="2" fill="#e6ecf3" {LINE}/>'
    + f'<rect x="21" y="40" width="22" height="6" rx="3" fill="#f2c64b" {LINE}/><rect x="29" y="46" width="6" height="11" rx="2" fill="#6b4524" {LINE}/></g>'
    + f'<g transform="rotate(-45 32 32)"><rect x="29" y="6" width="6" height="36" rx="2" fill="#e6ecf3" {LINE}/>'
    + f'<rect x="21" y="40" width="22" height="6" rx="3" fill="#f2c64b" {LINE}/><rect x="29" y="46" width="6" height="11" rx="2" fill="#6b4524" {LINE}/></g>',
    "wait": f'<rect x="16" y="8" width="32" height="6" rx="3" fill="#8a5a33" {LINE}/><rect x="16" y="50" width="32" height="6" rx="3" fill="#8a5a33" {LINE}/>'
    + f'<path d="M20 14 L44 14 Q44 26 32 32 Q44 38 44 50 L20 50 Q20 38 32 32 Q20 26 20 14 Z" fill="#dff1ff" {LINE}/>'
    + '<path d="M25 20 L39 20 Q36 27 32 29 Q28 27 25 20 Z M24 48 Q24 41 32 38 Q40 41 40 48 Z" fill="#f2c64b"/>',
    "search": f'<rect x="38" y="36" width="8" height="22" rx="3" transform="rotate(-45 42 47)" fill="#8a5a33" {LINE}/>'
    + f'<circle cx="27" cy="27" r="16" fill="#9fd8ff" {LINE}/>'
    + '<path d="M19 21 A10 10 0 0 1 27 15" fill="none" stroke="#fff" stroke-width="4" stroke-linecap="round"/>',
    "tactics": f'<rect x="14" y="8" width="5" height="50" rx="2" fill="#8a5a33" {LINE}/>'
    + f'<path d="M19 10 L52 14 L44 23 L52 32 L19 30 Z" fill="#e8413a" {LINE}/>',
    "bag": f'<path d="M22 20 Q22 8 32 8 Q42 8 42 20" fill="none" stroke="{INK}" stroke-width="7" stroke-linecap="round"/>'
    + '<path d="M22 20 Q22 8 32 8 Q42 8 42 20" fill="none" stroke="#8a5a33" stroke-width="3" stroke-linecap="round"/>'
    + f'<rect x="12" y="18" width="40" height="38" rx="9" fill="#b0703a" {LINE}/>'
    + f'<rect x="20" y="32" width="24" height="15" rx="4" fill="#94592c" {LINE}/>'
    + f'<rect x="29" y="28" width="6" height="8" rx="2" fill="#f2c64b" {LINE}/>',
    "food": f'<path d="M18 46 Q8 40 14 28 Q22 14 38 16 Q54 20 50 36 Q46 48 30 48 Z" fill="#c8633a" {LINE}/>'
    + f'<rect x="40" y="40" width="7" height="18" rx="3" transform="rotate(-40 44 48)" fill="#f3ead6" {LINE}/>',
    "gold": f'<circle cx="32" cy="32" r="20" fill="#f2c64b" {LINE}/><circle cx="32" cy="32" r="12" fill="none" stroke="#d19a25" stroke-width="4"/>',
}


def room_svg(width: int, height: int, cols: int, rows: int) -> str:
    """The room: stone wall band with an arched stair, a flat floor with soft
    tile seams, side walls, and a few ink doodles for texture."""
    tile = width / cols
    wall_h = tile * 1.6
    parts = [f'<rect width="{width}" height="{height}" fill="#2a2b36"/>']
    parts.append(f'<rect x="{tile * 0.5}" y="{wall_h}" width="{width - tile}" height="{height - wall_h - tile * 0.5}" fill="#a9aebb"/>')
    for c in range(1, cols):
        x = tile * 0.5 + (c - 0.5) * tile
        parts.append(f'<path d="M{x} {wall_h} L{x} {height - tile * 0.5}" stroke="#979cab" stroke-width="3"/>')
    for r in range(1, rows):
        y = wall_h + r * tile - tile * 0.35
        if y < height - tile * 0.5:
            parts.append(f'<path d="M{tile * 0.5} {y} L{width - tile * 0.5} {y}" stroke="#979cab" stroke-width="3"/>')
    parts.append(f'<rect x="{tile * 0.5}" y="{wall_h}" width="{width - tile}" height="{height - wall_h - tile * 0.5}" fill="none" {LINE}/>')
    # Back wall: two courses of big flat blocks.
    parts.append(f'<rect x="{tile * 0.5}" y="{tile * 0.2}" width="{width - tile}" height="{wall_h - tile * 0.2}" fill="#7d8394" {LINE}/>')
    for course in range(2):
        y = tile * 0.2 + course * (wall_h - tile * 0.2) / 2
        h = (wall_h - tile * 0.2) / 2
        offset = 0 if course == 0 else tile * 0.6
        x = tile * 0.5 - offset
        while x < width - tile * 0.5:
            x0, x1 = max(x, tile * 0.5), min(x + tile * 1.2, width - tile * 0.5)
            parts.append(f'<rect x="{x0 + 3}" y="{y + 3}" width="{x1 - x0 - 6}" height="{h - 6}" rx="4" fill="#8e94a4" stroke="#686d7d" stroke-width="3"/>')
            x += tile * 1.2
    parts.append(f'<rect x="{tile * 0.5}" y="{tile * 0.2}" width="{width - tile}" height="{wall_h - tile * 0.2}" fill="none" {LINE}/>')
    # Arched stairwell in the middle of the back wall.
    cx = width / 2
    parts.append(f'<path d="M{cx - tile * 0.7} {wall_h} L{cx - tile * 0.7} {tile * 0.9} Q{cx - tile * 0.7} {tile * 0.35} {cx} {tile * 0.35} Q{cx + tile * 0.7} {tile * 0.35} {cx + tile * 0.7} {tile * 0.9} L{cx + tile * 0.7} {wall_h} Z" fill="#1f2029" {LINE}/>')
    for i in range(3):
        y = tile * 0.95 + i * tile * 0.2
        parts.append(f'<rect x="{cx - tile * 0.5 + i * 4}" y="{y}" width="{tile - i * 8}" height="{tile * 0.12}" rx="2" fill="#5c6070"/>')
    # Ink doodles and pebbles, the Forge Master way of texturing a flat plane.
    for x, y in ((0.28, 0.42), (0.7, 0.55), (0.45, 0.8), (0.18, 0.7), (0.82, 0.3)):
        px, py = width * x, height * y
        parts.append(f'<path d="M{px} {py} l4 -9 l4 9 l4 -12 l3 12" fill="none" stroke="{INK}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>')
    for x, y, r in ((0.35, 0.33, 6), (0.62, 0.72, 5), (0.22, 0.52, 4)):
        parts.append(f'<ellipse cx="{width * x}" cy="{height * y}" rx="{r * 1.5}" ry="{r}" fill="#8a8f9e" {LINE}/>')
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
        bar(draw, (x + 38, y + 20, x + 112, y + 38), hp, maximum, "#e8413a")
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

    screen.convert("RGB").save(REVIEW / "gameplay-780x1688.png")
    board = Image.new("RGBA", (7 * 170 + 20, 3 * 180 + 20), "#e9ecf2")
    for r, group in enumerate((SPRITES, PROPS, ICONS)):
        for c, name in enumerate(group):
            board.alpha_composite(art[name].resize((160, 160)), (15 + c * 170, 15 + r * 180))
    board.convert("RGB").save(REVIEW / "sprite-sheet.png")


if __name__ == "__main__":
    main()
