"""The last zone and UI art: temple and crypt material sheets, banner frames,
a title ribbon and the victory picture.

- materials: `assets/zones-v1/tiles/<theme>-materials.png`, 1254 px, the same
  16 cells in the same places as `assets/topdown/flat-v1/ruins-materials.png`
  so `floor1-ink-v2/catalog.json` slices them unchanged;
- frames: nine-patch banner frames (level-up, soul stone, boss, victory),
  192 px with a 56 px corner margin, for a StyleBoxTexture;
- ribbon: a title ribbon, stretched only in its middle third;
- victory: the result card's picture.

Run: python3 tools/art/build_ui_extras.py
"""
import math
import random
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_flat_cartoon as flat  # noqa: E402
import build_paperdoll as doll  # noqa: E402
from build_gear import rrect, circle, WOOD, STEEL, GOLD  # noqa: E402
import build_zone_assets as zone  # noqa: E402

ROOT = flat.ROOT
INK = flat.INK
OUT = ROOT / "assets/zones-v1"
UI = ROOT / "assets/ui/frames-v1"
REVIEW = ROOT / "docs/art/zones-v1"
FONT = ROOT / "assets/fonts/Jua-Regular.ttf"
SHEET = 1254
CELLS = {"floor_a": [6, 6, 302, 302], "floor_b": [320, 6, 301, 302], "floor_c": [633, 6, 301, 302], "floor_d": [946, 6, 302, 302],
         "front": [6, 320, 302, 301], "top": [320, 320, 301, 301], "wood": [633, 320, 301, 301], "metal": [946, 320, 302, 301],
         "water": [6, 633, 302, 301], "water_ripple": [320, 633, 301, 301], "mud": [633, 633, 301, 301], "moss": [946, 633, 302, 301],
         "rubble": [6, 946, 302, 302], "dirt": [320, 946, 301, 302], "embers": [633, 946, 301, 302], "damp": [946, 946, 302, 302]}
EDGE = "#10141a"


def rect(x, y, w, h, fill, extra=""):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}" {extra}/>'


def stones(x, y, w, h, face, light, dark, rng, rows=3, cracks=0):
    """A flagstone pattern: offset rows of rounded blocks with a lit top edge."""
    out = [rect(x, y, w, h, dark)]
    rh = h / rows
    for r in range(rows):
        offset = (r % 2) * rng.uniform(40, 90)
        cx = x - offset
        while cx < x + w:
            bw = rng.uniform(90, 150)
            x0, x1 = max(x + 4, cx + 5), min(x + w - 4, cx + bw - 5)
            y0, y1 = y + r * rh + 5, y + (r + 1) * rh - 5
            if x1 - x0 > 20:
                out.append(f'<path d="{rrect(x0, y0, x1, y1, 8)}" fill="{face}"/>')
                out.append(f'<path d="M{x0 + 8} {y0 + 5} L{x1 - 8} {y0 + 5}" stroke="{light}" stroke-width="5" stroke-linecap="round" opacity="0.7"/>')
            cx += bw
    for _ in range(cracks):
        sx, sy = rng.uniform(x + 40, x + w - 40), rng.uniform(y + 30, y + h - 60)
        out.append(f'<path d="M{sx:.0f} {sy:.0f} l{rng.uniform(-20, 20):.0f} 25 l{rng.uniform(-15, 15):.0f} 25" fill="none" stroke="{EDGE}" stroke-width="4"/>')
    return "".join(out)


def planks(x, y, w, h, face, dark, rng, rot=False):
    out = [rect(x, y, w, h, dark)]
    n = 4
    pw = w / n
    for i in range(n):
        px = x + i * pw
        out.append(rect(px + 4, y, pw - 8, h, face))
        out.append(f'<path d="M{px + pw / 2:.0f} {y + 10} L{px + pw / 2:.0f} {y + h - 10}" stroke="{dark}" stroke-width="3" opacity="0.5"/>')
        if rot:
            out.append(f'<ellipse cx="{px + pw / 2:.0f}" cy="{y + rng.uniform(60, h - 60):.0f}" rx="18" ry="30" fill="{dark}" opacity="0.6"/>')
    return "".join(out)


def grate(x, y, w, h, frame, bar, spot):
    out = [rect(x, y, w, h, frame)]
    for i in range(1, 6):
        gx = x + i * w / 6
        out.append(f'<path d="M{gx:.0f} {y + 20} L{gx:.0f} {y + h - 20}" stroke="{bar}" stroke-width="12"/>')
    out.append(f'<path d="M{x + 20} {y + h / 2} L{x + w - 20} {y + h / 2}" stroke="{bar}" stroke-width="12"/>')
    for sx, sy in ((x + 20, y + 20), (x + w - 20, y + 20), (x + 20, y + h - 20), (x + w - 20, y + h - 20)):
        out.append(f'<circle cx="{sx}" cy="{sy}" r="7" fill="{bar}"/>')
    out.append(f'<ellipse cx="{x + w * 0.7:.0f}" cy="{y + h * 0.3:.0f}" rx="40" ry="26" fill="{spot}" opacity="0.7"/>')
    return "".join(out)


def water(x, y, w, h, deep, shallow, ripple, rng, rings=False, tiles=None):
    out = [rect(x, y, w, h, deep)]
    if tiles:
        for i in range(3):
            for j in range(3):
                out.append(f'<path d="{rrect(x + 10 + i * w / 3, y + 10 + j * h / 3, x + (i + 1) * w / 3 - 10, y + (j + 1) * h / 3 - 10, 8)}" fill="{tiles}" opacity="0.35"/>')
    for _ in range(4):
        cx, cy = rng.uniform(x + 30, x + w - 90), rng.uniform(y + 30, y + h - 30)
        out.append(f'<path d="M{cx:.0f} {cy:.0f} q20 -10 40 0 t40 0" fill="none" stroke="{shallow}" stroke-width="5" stroke-linecap="round" opacity="0.8"/>')
    if rings:
        cx, cy = x + w / 2, y + h / 2
        for r in (26, 48, 70):
            out.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{r * 1.3}" ry="{r * 0.55}" fill="none" stroke="{ripple}" stroke-width="5" opacity="{0.9 - r / 120:.2f}"/>')
    return "".join(out)


def blotches(x, y, w, h, base, spots, rng, n=10):
    out = [rect(x, y, w, h, base)]
    for _ in range(n):
        out.append(f'<ellipse cx="{rng.uniform(x + 20, x + w - 20):.0f}" cy="{rng.uniform(y + 20, y + h - 20):.0f}" rx="{rng.uniform(20, 55):.0f}" '
                   f'ry="{rng.uniform(14, 36):.0f}" fill="{rng.choice(spots)}" opacity="0.85"/>')
    return "".join(out)


def rocks(x, y, w, h, base, face, shade, rng, n=9, bone=None):
    out = [rect(x, y, w, h, base)]
    for _ in range(n):
        cx, cy, r = rng.uniform(x + 30, x + w - 30), rng.uniform(y + 30, y + h - 30), rng.uniform(14, 38)
        pts = [(cx + r * math.cos(a) * rng.uniform(0.7, 1.1), cy + r * math.sin(a) * rng.uniform(0.7, 1.1)) for a in [i * math.pi / 3 for i in range(6)]]
        d = "M" + " L".join(f"{px:.0f} {py:.0f}" for px, py in pts) + " Z"
        out.append(f'<path d="{d}" fill="{shade}" transform="translate(3 4)"/><path d="{d}" fill="{face}" stroke="{EDGE}" stroke-width="3" stroke-linejoin="round"/>')
    if bone:
        for _ in range(5):
            cx, cy, a = rng.uniform(x + 40, x + w - 40), rng.uniform(y + 40, y + h - 40), rng.uniform(0, math.pi)
            dx, dy = 30 * math.cos(a), 30 * math.sin(a)
            out.append(f'<path d="M{cx - dx:.0f} {cy - dy:.0f} L{cx + dx:.0f} {cy + dy:.0f}" stroke="{EDGE}" stroke-width="15" stroke-linecap="round"/>'
                       f'<path d="M{cx - dx:.0f} {cy - dy:.0f} L{cx + dx:.0f} {cy + dy:.0f}" stroke="{bone}" stroke-width="9" stroke-linecap="round"/>'
                       + "".join(f'<circle cx="{cx + s * dx:.0f}" cy="{cy + s * dy:.0f}" r="8" fill="{bone}" stroke="{EDGE}" stroke-width="3"/>' for s in (-1, 1)))
    return "".join(out)


def glow_bits(x, y, w, h, base_svg, glow, core, rng, n=6):
    out = [base_svg]
    for _ in range(n):
        cx, cy = rng.uniform(x + 30, x + w - 30), rng.uniform(y + 30, y + h - 30)
        out.append(f'<ellipse cx="{cx:.0f}" cy="{cy:.0f}" rx="9" ry="5" fill="{glow}" opacity="0.6"/><ellipse cx="{cx:.0f}" cy="{cy:.0f}" rx="4" ry="2.4" fill="{core}"/>')
    return "".join(out)


def wall_front(x, y, w, h, face, light, dark, ledge, rng):
    return (rect(x, y, w, h, dark) + stones(x, y + 60, w, h - 60, face, light, dark, rng, rows=4)
            + rect(x, y, w, 60, ledge) + f'<path d="M{x + 10} {y + 12} L{x + w - 10} {y + 12}" stroke="{light}" stroke-width="7" stroke-linecap="round"/>'
            + rect(x, y + 56, w, 8, dark))


PALETTES = {
    "temple": {"floor": ("#40605f", "#5c7f7e", "#243a3a"), "wall": ("#2f4549", "#4a6567", "#1c2c2e", "#6d8f90"),
               "wood": ("#5a5a3e", "#3a3a28"), "metal": ("#3a4a3e", "#7aa088", "#58c098"), "water": ("#1f5a62", "#6fc0c4", "#bff0ec", "#3d7a7c"),
               "mud": ("#5e5a3e", ["#4e4a30", "#6e6a4a"]), "moss": "#56834a", "rubble": ("#2c3c3c", "#7a9090", "#4a6060", None),
               "dirt": ("#8a7a56", ["#9a8a64", "#7a6a48"]), "embers": ("#7ff0e0", "#e8fffc"), "damp": "#3a6e78"},
    "crypt": {"floor": ("#3e3848", "#5a5266", "#221e28"), "wall": ("#2c2735", "#453e52", "#18151d", "#665c75"),
              "wood": ("#4a3a3a", "#2c2222"), "metal": ("#3a3434", "#7a5a4a", "#9a4a3a"), "water": ("#1a1822", "#4a4260", "#8a80a8", None),
              "mud": ("#3a3030", ["#2c2424", "#4a3e3a"]), "moss": "#9a9a78", "rubble": ("#2a2530", "#8a8494", "#5c566a", "#e2d8bc"),
              "dirt": ("#4a3e36", ["#5a4c42", "#3a302a"]), "embers": ("#b070f0", "#f0e0ff"), "damp": "#4a3050"},
}


def materials_svg(theme):
    p = PALETTES[theme]
    rng = random.Random(len(theme) * 97)
    face, light, dark = p["floor"]
    wf, wl, wd, ledge = p["wall"]
    body = [rect(0, 0, SHEET, SHEET, "#0e1116")]
    for key, (x, y, w, h) in CELLS.items():
        start = len(body)
        body.append(f'<clipPath id="c_{key}"><rect x="{x}" y="{y}" width="{w}" height="{h}"/></clipPath><g clip-path="url(#c_{key})">')
        if key.startswith("floor"):
            body.append(stones(x, y, w, h, face, light, dark, rng, rows=3, cracks=1 if key in ("floor_b", "floor_c") else 0))
            if theme == "temple" and key == "floor_d":
                body.append(blotches(x, y, 0, 0, face, [p["moss"]], rng, 0) + "".join(
                    f'<ellipse cx="{x + rng.uniform(40, w - 40):.0f}" cy="{y + rng.uniform(40, h - 40):.0f}" rx="30" ry="18" fill="{p["moss"]}" opacity="0.8"/>' for _ in range(4)))
            if theme == "crypt" and key == "floor_d":
                body.append(zone.rune_ring(x + w / 2, y + h / 2, "#5c5470").replace('r="130"', 'r="100"').replace('r="84"', 'r="64"'))
        elif key == "front":
            body.append(wall_front(x, y, w, h, wf, wl, wd, ledge, rng))
        elif key == "top":
            body.append(stones(x, y, w, h, ledge, "#ffffff", wd, rng, rows=2))
        elif key == "wood":
            body.append(planks(x, y, w, h, *p["wood"], rng, rot=True))
        elif key == "metal":
            body.append(grate(x, y, w, h, *p["metal"]))
        elif key in ("water", "water_ripple"):
            deep, shallow, ripple, tiles = p["water"]
            body.append(water(x, y, w, h, deep, shallow, ripple, rng, rings=key == "water_ripple", tiles=tiles))
        elif key == "mud":
            body.append(blotches(x, y, w, h, p["mud"][0], p["mud"][1], rng))
        elif key == "moss":
            body.append(stones(x, y, w, h, face, light, dark, rng, rows=3) + "".join(
                f'<ellipse cx="{x + rng.uniform(30, w - 30):.0f}" cy="{y + rng.uniform(30, h - 30):.0f}" rx="{rng.uniform(26, 50):.0f}" ry="{rng.uniform(12, 24):.0f}" fill="{p["moss"]}"/>'
                for _ in range(7)))
        elif key == "rubble":
            base, rock_face, rock_shade, bone = p["rubble"]
            body.append(rocks(x, y, w, h, base, rock_face, rock_shade, rng, bone=bone))
        elif key == "dirt":
            body.append(blotches(x, y, w, h, p["dirt"][0], p["dirt"][1], rng, 8))
        elif key == "embers":
            glow, core = p["embers"]
            body.append(glow_bits(x, y, w, h, stones(x, y, w, h, face, light, dark, rng, rows=3), glow, core, rng))
        elif key == "damp":
            body.append(stones(x, y, w, h, face, light, dark, rng, rows=3) + f'<ellipse cx="{x + w / 2}" cy="{y + h / 2}" rx="{w * 0.4}" ry="{h * 0.3}" fill="{p["damp"]}" opacity="0.55"/>')
        body.append("</g>")
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{SHEET}" height="{SHEET}" viewBox="0 0 {SHEET} {SHEET}">{"".join(body)}</svg>'


# --- banner frames (nine-patch, 192 px, margin 56) --------------------------------

FRAMES = {
    # rim, inner, ground, corner ornament colour
    "level": ("#f2c64b", "#8a6a1c", "#15181c", "#fff1b0"),
    "essence": ("#b98af0", "#5a3a8a", "#14111c", "#efdcff"),
    "boss": ("#e0453a", "#6a1a1a", "#160c0c", "#efe6cc"),
    "victory": ("#f6c64a", "#3a8a6a", "#10181a", "#fff6c8"),
}


def frame_svg(kind):
    rim, inner, ground, orn = FRAMES[kind]
    size = 192
    body = [f'<path d="{rrect(4, 4, 188, 188, 22)}" fill="{INK}"/>',
            f'<path d="{rrect(8, 8, 184, 184, 19)}" fill="{rim}"/>',
            f'<path d="{rrect(15, 15, 177, 177, 14)}" fill="{inner}"/>',
            f'<path d="{rrect(20, 20, 172, 172, 11)}" fill="{ground}"/>',
            f'<path d="M26 14 L80 14" stroke="#ffffff" stroke-width="3" stroke-linecap="round" opacity="0.55"/>']
    for cx, cy in ((22, 22), (170, 22), (22, 170), (170, 170)):
        if kind == "boss":
            body.append(f'<ellipse cx="{cx}" cy="{cy}" rx="13" ry="12" fill="{orn}" stroke="{INK}" stroke-width="3"/>'
                        f'<circle cx="{cx - 4.5}" cy="{cy - 1}" r="3" fill="{INK}"/><circle cx="{cx + 4.5}" cy="{cy - 1}" r="3" fill="{INK}"/>')
        elif kind == "essence":
            gem = [(cx, cy - 14), (cx + 10, cy - 5), (cx + 8, cy + 8), (cx, cy + 14), (cx - 8, cy + 8), (cx - 10, cy - 5)]
            body.append(f'<path d="M{" L".join(f"{a:.1f} {b:.1f}" for a, b in gem)} Z" fill="{orn}" stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>')
        else:
            r = 12
            star = [(cx + (r if i % 2 == 0 else r * 0.42) * math.cos(-math.pi / 2 + i * math.pi / 4),
                     cy + (r if i % 2 == 0 else r * 0.42) * math.sin(-math.pi / 2 + i * math.pi / 4)) for i in range(8)]
            body.append(f'<path d="M{" L".join(f"{a:.1f} {b:.1f}" for a, b in star)} Z" fill="{orn}" stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>')
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">{"".join(body)}</svg>'


def ribbon_svg(colour, shade):
    """A title ribbon 384 x 96: tails on both ends; stretch only x 128..256."""
    w, h = 384, 96
    body = [f'<path d="M4 30 L60 30 L60 78 L4 78 L22 54 Z" fill="{shade}" stroke="{INK}" stroke-width="4" stroke-linejoin="round"/>',
            f'<path d="M380 30 L324 30 L324 78 L380 78 L362 54 Z" fill="{shade}" stroke="{INK}" stroke-width="4" stroke-linejoin="round"/>',
            f'<path d="{rrect(40, 16, 344, 70, 10)}" fill="{colour}" stroke="{INK}" stroke-width="4"/>',
            f'<path d="M56 26 L328 26" stroke="#ffffff" stroke-width="4" stroke-linecap="round" opacity="0.5"/>',
            f'<path d="M40 60 L344 60" stroke="{shade}" stroke-width="6" opacity="0.7"/>']
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{"".join(body)}</svg>'


def victory_svg():
    """The result card's picture: crossed sword and staff behind a crowned soul
    stone, a laurel, and light breaking over the crypt's stairs."""
    w, h = 360, 240
    rays = "".join(f'<path d="M180 120 L{180 + 260 * math.cos(a):.0f} {120 + 260 * math.sin(a):.0f} L{180 + 260 * math.cos(a + 0.16):.0f} {120 + 260 * math.sin(a + 0.16):.0f} Z" fill="#fff1b0" opacity="0.35"/>'
                   for a in [i * math.pi / 8 for i in range(16)])
    sky = f'<rect width="{w}" height="{h}" fill="#f2b85a"/>' + rays
    steps = "".join(f'<path d="M{40 + i * 30} {200 + i * 0} L{320 - i * 30} {200} L{320 - i * 30} {240} L{40 + i * 30} {240} Z" fill="{["#5a5266", "#4a4458", "#3c3748"][i]}" transform="translate(0 {-i * 14})" stroke="{INK}" stroke-width="3"/>'
                    for i in range(3))
    sword = (f'<g transform="rotate(-35 180 110)"><path d="M174 30 L186 30 L186 150 L180 162 L174 150 Z" fill="{STEEL[0]}" stroke="{INK}" stroke-width="4" stroke-linejoin="round"/>'
             f'<path d="M158 150 L202 150" stroke="{INK}" stroke-width="12" stroke-linecap="round"/><path d="M158 150 L202 150" stroke="{GOLD[0]}" stroke-width="6" stroke-linecap="round"/>'
             f'<path d="M180 150 L180 180" stroke="{INK}" stroke-width="12" stroke-linecap="round"/><path d="M180 150 L180 180" stroke="{WOOD[0]}" stroke-width="6" stroke-linecap="round"/></g>')
    staff = (f'<g transform="rotate(35 180 110)"><path d="M180 40 L180 190" stroke="{INK}" stroke-width="12" stroke-linecap="round"/>'
             f'<path d="M180 40 L180 190" stroke="{WOOD[0]}" stroke-width="6" stroke-linecap="round"/>'
             f'<circle cx="180" cy="36" r="12" fill="#7ff0e0" stroke="{INK}" stroke-width="4"/></g>')
    laurel = ""
    for side in (-1, 1):
        for i in range(6):
            a = math.pi / 2 + side * (0.5 + i * 0.32)
            cx, cy = 180 + 70 * math.cos(a) * -1 if False else 180 + side * (46 + 18 * math.sin(i * 0.5)), 150 - i * 16
            laurel += (f'<ellipse cx="{cx:.0f}" cy="{cy:.0f}" rx="13" ry="7" fill="#6aa04a" stroke="{INK}" stroke-width="3" '
                       f'transform="rotate({side * (30 + i * 8)} {cx:.0f} {cy:.0f})"/>')
    gem_pts = [(180, 68), (206, 88), (202, 122), (180, 140), (158, 122), (154, 88)]
    gem = (f'<path d="M{" L".join(f"{a} {b}" for a, b in gem_pts)} Z" fill="#9a66d6" stroke="{INK}" stroke-width="5" stroke-linejoin="round"/>'
           f'<path d="M154 88 L180 100 L206 88 L180 68 Z" fill="#cfa8f4"/><path d="M165 94 L172 86" stroke="#ffffff" stroke-width="5" stroke-linecap="round"/>')
    crown = f'<path d="M156 66 L156 44 L168 56 L180 38 L192 56 L204 44 L204 66 Z" fill="{GOLD[0]}" stroke="{INK}" stroke-width="4" stroke-linejoin="round"/>'
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{sky}{steps}{staff}{sword}{laurel}{gem}{crown}</svg>'


def main() -> None:
    tiles = OUT / "tiles"
    (tiles / "svg").mkdir(parents=True, exist_ok=True)
    (UI / "svg").mkdir(parents=True, exist_ok=True)
    jobs = []
    for theme in PALETTES:
        source = tiles / "svg" / f"{theme}-materials.svg"
        source.write_text(materials_svg(theme))
        jobs.append((source, tiles / f"{theme}-materials.png", 1))
    pieces = {**{f"banner_{k}": frame_svg(k) for k in FRAMES},
              "ribbon_gold": ribbon_svg("#f2c64b", "#c29a2a"), "ribbon_purple": ribbon_svg("#9a66d6", "#7446ae"),
              "ribbon_red": ribbon_svg("#d0492e", "#a8361f"), "victory": victory_svg()}
    for name, body in pieces.items():
        source = UI / "svg" / f"{name}.svg"
        source.write_text(body)
        jobs.append((source, UI / f"{name}.png", 2 if name != "victory" else 1))
    flat.rasterise(jobs)
    review(pieces)


def review(pieces) -> None:
    font = ImageFont.truetype(str(FONT), 16)
    img = Image.new("RGB", (2 * 520 + 30, 560), "#e9a25c")
    draw = ImageDraw.Draw(img)
    for i, theme in enumerate(PALETTES):
        pic = Image.open(OUT / "tiles" / f"{theme}-materials.png").convert("RGB").resize((500, 500), Image.LANCZOS)
        img.paste(pic, (10 + i * 520, 10))
        draw.text((10 + i * 520 + 250, 535), f"{theme}-materials", font=font, fill=INK, anchor="mm")
    img.save(REVIEW / "materials.png")

    sheet = Image.new("RGBA", (1100, 620), "#3a3440")
    draw = ImageDraw.Draw(sheet)
    x = 20
    for kind in FRAMES:
        # a nine-patch stretched to a banner-ish size, the way the game will draw it
        src = Image.open(UI / f"banner_{kind}.png").convert("RGBA")
        m = 112  # 56 px at 2x
        W, H = 250, 300
        out = Image.new("RGBA", (W, H))
        s = src.size[0]
        cols = [(0, m, 0, m), (m, s - m, m, W - m), (s - m, s, W - m, W)]
        rows = [(0, m, 0, m), (m, s - m, m, H - m), (s - m, s, H - m, H)]
        for sx0, sx1, dx0, dx1 in cols:
            for sy0, sy1, dy0, dy1 in rows:
                part = src.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0), Image.LANCZOS)
                out.alpha_composite(part, (dx0, dy0))
        sheet.alpha_composite(out.resize((W // 1, H // 1)), (x, 20))
        draw.text((x + W // 2, 335), kind, font=font, fill="#f0e8d8", anchor="mm")
        x += W + 20
    y = 360
    for i, name in enumerate(("ribbon_gold", "ribbon_purple", "ribbon_red")):
        pic = Image.open(UI / f"{name}.png").convert("RGBA").resize((300, 75), Image.LANCZOS)
        sheet.alpha_composite(pic, (20, y + i * 80))
    pic = Image.open(UI / "victory.png").convert("RGBA")
    sheet.alpha_composite(pic, (400, 360))
    sheet.convert("RGB").save(REVIEW / "ui-frames.png")


if __name__ == "__main__":
    main()
