"""The flat cartoon sprites laid out the way Forge Master: Idle RPG lays out
its main screen, measured from its App Store screenshots and scaled to a
390x844 phone at 2x.

Top half: a bright side-on field with a dirt lane, the hero on the left
facing a mob on the right, trees and ink grass marks, a power banner, the
floor title with progress nodes, and the portrait and currency pills floating
over the field. Bottom half: a pale panel with a 5x2 grid of item slots, the
centrepiece (here a treasure chest instead of an anvil) with its buttons,
and a dark icon tab bar. Only the composition follows the reference; every
shape is drawn in tools/art/build_flat_cartoon.py or below.

Run: python3 tools/art/build_forge_layout.py (after build_flat_cartoon.py)
"""
import math
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_flat_cartoon as flat  # noqa: E402

ROOT = flat.ROOT
OUT = flat.OUT
REVIEW = flat.REVIEW
JUA = ROOT / "assets/fonts/Jua-Regular.ttf"
INK = flat.INK
LINE = flat.LINE
banded = flat.banded

GRASS = "#16c464"
GRASS_DARK = "#10a452"
DIRT = "#eaa15c"
DIRT_DARK = "#cf8444"

EXTRA = {
    "tree": '<ellipse cx="32" cy="58" rx="17" ry="4.5" fill="#0f9a4c"/>'
    + banded("trt", '<path d="M28 58 L29 42 L22 34 L26 32 L31 39 L34 30 L38 31 L35 42 L37 58 Z" fill="{fill}" {line}/>', "#e0782a", "#c0621e", 33)
    + banded("trc", '<path d="M14 30 Q8 22 15 16 Q15 7 25 8 Q31 2 39 7 Q49 6 50 15 Q57 21 51 29 Q51 37 41 36 Q34 41 27 36 Q16 38 14 30 Z" fill="{fill}" {line}/>', "#97d655", "#7cbf40", 36)
    + '<path d="M20 20 Q22 13 28 13" fill="none" stroke="#b7e87e" stroke-width="3" stroke-linecap="round"/>',
    "rock": '<ellipse cx="32" cy="56" rx="18" ry="4" fill="#0f9a4c"/>'
    + banded("roc", '<path d="M13 54 L17 36 L28 27 L42 30 L51 42 L50 54 Z" fill="{fill}" {line}/>', "#b9c0cc", "#97a0af", 36),
    "bones": f'<g transform="rotate(-20 32 40)"><rect x="12" y="37" width="40" height="7" rx="3.5" fill="#f4efe2" {LINE}/>'
    + f'<circle cx="12" cy="37" r="4.5" fill="#f4efe2" {LINE}/><circle cx="12" cy="44" r="4.5" fill="#f4efe2" {LINE}/>'
    + f'<circle cx="52" cy="37" r="4.5" fill="#f4efe2" {LINE}/><circle cx="52" cy="44" r="4.5" fill="#f4efe2" {LINE}/></g>'
    + f'<path d="M22 22 Q22 12 32 12 Q42 12 42 22 L42 27 Q42 30 38 30 L26 30 Q22 30 22 27 Z" fill="#f4efe2" {LINE}/>'
    + f'<rect x="26.5" y="18" width="3" height="6" rx="1.5" fill="{INK}"/><rect x="33.5" y="18" width="3" height="6" rx="1.5" fill="{INK}"/>',
    "pillar": '<ellipse cx="32" cy="58" rx="16" ry="4" fill="#0f9a4c"/>'
    + banded("pib", '<rect x="21" y="18" width="22" height="38" rx="2" fill="{fill}" {line}/>', "#c9ced8", "#a8afbd", 35)
    + f'<path d="M26 22 L26 52 M32 22 L32 52 M38 22 L38 52" stroke="#a8afbd" stroke-width="2.5"/>'
    + f'<rect x="17" y="50" width="30" height="7" rx="2" fill="#b3b9c6" {LINE}/>'
    + f'<path d="M17 20 L22 12 L30 16 L36 9 L47 15 L47 21 L17 21 Z" fill="#dde1e8" {LINE}/>',
    "sword": '<g transform="rotate(-45 32 32)">'
    + banded("swb", '<path d="M28 6 L32 2 L36 6 L36 40 L28 40 Z" fill="{fill}" {line}/>', "#eef3f8", "#c9d3de", 32)
    + f'<rect x="19" y="39" width="26" height="7" rx="3.5" fill="#f5c84a" {LINE}/><rect x="28.5" y="46" width="7" height="13" rx="3" fill="#8a5a30" {LINE}/></g>',
    "helmet": banded("heh", '<path d="M13 40 Q12 12 32 11 Q52 12 51 40 Z" fill="{fill}" {line}/>', "#c9d2de", "#a7b2c1", 36)
    + f'<rect x="9" y="38" width="46" height="9" rx="4.5" fill="#a7b2c1" {LINE}/>'
    + f'<path d="M30 12 Q22 0 12 4 Q20 7 24 15 Z" fill="#e0453a" {LINE}/>',
    "armor": banded("arm", '<path d="M16 14 L26 10 Q32 16 38 10 L48 14 L54 26 L46 30 L46 54 L18 54 L18 30 L10 26 Z" fill="{fill}" {line}/>', "#c47d40", "#a7652f", 38)
    + f'<path d="M32 18 L32 54" stroke="{INK}" stroke-width="3"/><circle cx="32" cy="30" r="2.5" fill="#f5c84a" {LINE}/><circle cx="32" cy="42" r="2.5" fill="#f5c84a" {LINE}/>',
    "shield": banded("shs", '<path d="M32 6 L52 13 Q52 44 32 58 Q12 44 12 13 Z" fill="{fill}" {line}/>', "#3f9ad8", "#2f82bf", 34)
    + f'<path d="M32 16 L32 48 M20 26 L44 26" stroke="#f5c84a" stroke-width="5" stroke-linecap="round"/>',
    "ring": banded("rir", '<circle cx="32" cy="38" r="16" fill="{fill}" {line}/>', "#f5c84a", "#dca832", 38)
    + f'<circle cx="32" cy="38" r="9" fill="#f0f0f0" {LINE}/>'
    + banded("rig", '<path d="M24 20 L32 8 L40 20 L32 26 Z" fill="{fill}" {line}/>', "#6ee0f0", "#3fc0d8", 32),
    "boots": banded("bob", '<path d="M18 8 L34 8 L34 38 L52 44 Q55 46 54 54 L14 54 Q12 46 18 40 Z" fill="{fill}" {line}/>', "#8a5a30", "#704826", 34)
    + f'<rect x="16" y="8" width="20" height="7" rx="2" fill="#a8703e" {LINE}/>',
    "crown": banded("crc", '<path d="M10 46 L8 18 L22 30 L32 12 L42 30 L56 18 L54 46 Z" fill="{fill}" {line}/>', "#f5c84a", "#dca832", 38)
    + f'<rect x="10" y="44" width="44" height="8" rx="3" fill="#dca832" {LINE}/>',
    "gem": banded("gem", '<path d="M32 6 L56 30 L32 58 L8 30 Z" fill="{fill}" {line}/>', "#ff6fae", "#e84d92", 34)
    + '<path d="M32 16 L44 30 L32 46 L20 30 Z" fill="#ffb3d4"/>' + f'<path d="M32 6 L56 30 L32 58 L8 30 Z" fill="none" {LINE}/>',
    "plus": f'<rect x="6" y="6" width="52" height="52" rx="12" fill="#3fd35a" {LINE}/><path d="M32 18 L32 46 M18 32 L46 32" stroke="#fff" stroke-width="8" stroke-linecap="round"/>',
    "big_chest": flat.PROPS["chest"],
}


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(JUA), size)


def say(draw, xy, text, size, fill="#ffffff", stroke=6, anchor="la"):
    draw.text(xy, text, font=font(size), fill=fill, stroke_width=stroke, stroke_fill=INK, anchor=anchor)


def wavy(y: float, width: int, seed: int, amp: float = 5) -> list:
    return [(x, y + amp * math.sin(x / 47 + seed) + amp * 0.6 * math.sin(x / 19 + seed * 2)) for x in range(-10, width + 11, 10)]


def doodle(draw, x, y, s=1.0):
    draw.line([(x, y), (x, y - 16 * s), (x + 9 * s, y - 5 * s), (x + 14 * s, y - 14 * s), (x + 8 * s, y + 2 * s)], fill=INK, width=3, joint="curve")


def splat(draw, x, y, r, color):
    draw.ellipse((x - r * 1.8, y - r * 0.7, x + r * 1.8, y + r * 0.7), fill=color)
    for dx, dy, rr in ((-r * 2.4, 0, r * 0.3), (r * 2.3, 2, r * 0.25), (r * 1.3, -r * 0.8, r * 0.2), (-r * 1.2, r * 0.8, r * 0.22)):
        draw.ellipse((x + dx - rr * 1.6, y + dy - rr, x + dx + rr * 1.6, y + dy + rr), fill=color)


def pill(draw, box, fill=(20, 60, 40, 150)):
    draw.rounded_rectangle(box, (box[3] - box[1]) // 2, fill=fill, outline=INK, width=5)


def main() -> None:
    jobs = []
    for name, body in EXTRA.items():
        source = OUT / "svg" / f"{name}.svg"
        source.write_text(flat.svg(body))
        jobs.append((source, OUT / "png" / f"{name}.png", 3))
    flat.rasterise(jobs)
    art = {path.stem: Image.open(path).convert("RGBA") for path in (OUT / "png").glob("*.png")}

    width, height = 780, 1688
    screen = Image.new("RGBA", (width, height), GRASS)
    draw = ImageDraw.Draw(screen, "RGBA")

    def put(name, cx, bottom, size, flip=False):
        image = art[name].resize((size, size), Image.LANCZOS)
        if flip:
            image = image.transpose(Image.FLIP_LEFT_RIGHT)
        screen.alpha_composite(image, (int(cx - size / 2), int(bottom - size * 0.92)))

    # --- the field -----------------------------------------------------------
    world_bottom = 905
    lane_top, lane_bottom = 452, 636
    top_edge, bottom_edge = wavy(lane_top, width, 1), wavy(lane_bottom, width, 4)
    draw.polygon(top_edge + bottom_edge[::-1], fill=DIRT)
    draw.line(top_edge, fill=INK, width=4)
    draw.line(bottom_edge, fill=INK, width=4)
    for x, y, r in ((170, 548, 18), (420, 560, 22), (640, 520, 14)):
        splat(draw, x, y, r, DIRT_DARK)
    for x, y in ((190, 390), (620, 356), (110, 820), (440, 760), (700, 700), (330, 700)):
        doodle(draw, x, y)
    put("tree", 330, 452, 170)
    put("tree", 390, 450, 150)
    put("tree", 700, 440, 160)
    put("tree", 290, 862, 170)
    put("tree", 740, 880, 150)
    put("rock", 36, 400, 110)
    put("bones", 70, 760, 120)
    put("pillar", 560, 430, 120)

    # The fight on the lane: hero left facing right, the mob right facing left.
    hero_x, lane_mid = 270, 572
    put("hero", hero_x, lane_mid, 96)
    draw.rounded_rectangle((hero_x - 30, lane_mid - 104, hero_x + 30, lane_mid - 92), 6, fill="#e8413a", outline=INK, width=3)
    mob = [("skeleton", 520, 520), ("skeleton", 610, 512), ("goblin", 565, 574), ("skeleton", 505, 618),
           ("rat", 610, 626), ("orc", 675, 580)]
    for name, x, y in mob:
        put(name, x, y, 92 if name != "orc" else 104, flip=True)
    glow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((690, 590, 790, 690), fill=(255, 255, 255, 200))
    screen.alpha_composite(glow.filter(ImageFilter.GaussianBlur(18)))
    put("scroll", 740, 670, 80)
    say(draw, (766, 682), "새 두루마리", 22, anchor="ra", stroke=5)

    # Power banner over the field.
    draw.rounded_rectangle((18, 262, width - 18, 330), 14, fill=(10, 70, 30, 150), outline=INK, width=5)
    screen.alpha_composite(art["attack"].resize((54, 54), Image.LANCZOS), (262, 270))
    say(draw, (324, 296), "+1.2k 경험치", 36, "#7dff6e", 6, "lm")

    # Floor title and wave nodes.
    say(draw, (width // 2, 132), "지하 1층  2-4", 42, anchor="mm")
    draw.line((292, 176, 488, 176), fill=INK, width=14)
    draw.line((292, 176, 488, 176), fill="#3a8fe0", width=6)
    for i, x in enumerate((292, 390, 488)):
        draw.ellipse((x - 15, 161, x + 15, 191), fill="#8fd4ff" if i < 2 else "#d8f1ff", outline=INK, width=5)

    # Portrait and currency pills floating over the field.
    pill(draw, (16, 22, 266, 98), (15, 70, 35, 170))
    draw.rounded_rectangle((20, 24, 94, 96), 12, fill="#3a3d4c", outline=INK, width=5)
    head = art["hero"].resize((96, 96), Image.LANCZOS).crop((12, 4, 84, 76))
    screen.alpha_composite(head, (21, 26))
    say(draw, (104, 30), "아린", 26, stroke=5)
    screen.alpha_composite(art["attack"].resize((32, 32), Image.LANCZOS), (102, 62))
    say(draw, (138, 60), "29.1k", 26, "#ffffff", 5)
    for i, (icon, value) in enumerate((("crown", "6.05m"), ("gem", "9.98m"))):
        x0 = 440 + i * 170
        pill(draw, (x0, 34, x0 + 150, 86), (25, 30, 40, 170))
        screen.alpha_composite(art[icon].resize((62, 62), Image.LANCZOS), (x0 - 14, 28))
        screen.alpha_composite(art["plus"].resize((30, 30), Image.LANCZOS), (x0 + 8, 66))
        say(draw, (x0 + 95, 60), value, 26, anchor="mm", stroke=5)

    # --- the lower panel ---------------------------------------------------
    draw.rectangle((0, world_bottom, width, height), fill="#f1f1f1")
    draw.line((0, world_bottom, width, world_bottom), fill=INK, width=5)
    slots = [("helmet", "Lv.6", "g"), ("armor", "Lv.13", "g"), ("boots", "Lv.9", "g"), ("ring", "Lv.7", "y"), ("shield", "Lv.17", "g"),
             ("sword", "Lv.9", "g"), ("potion", "Lv.15", "g"), ("scroll", "Lv.3", "y"), (None, "", ""), (None, "", "")]
    size, gap = 120, 16
    left = (width - 5 * size - 4 * gap) // 2
    for i, (icon, level, tone) in enumerate(slots):
        x0 = left + (i % 5) * (size + gap)
        y0 = 944 + (i // 5) * (size + gap)
        if icon is None:
            if i == 8:
                for j in range(0, size, 22):
                    draw.line((x0 + j, y0, x0 + min(size, j + 12), y0), fill="#9aa0ad", width=4)
                    draw.line((x0 + j, y0 + size, x0 + min(size, j + 12), y0 + size), fill="#9aa0ad", width=4)
                    draw.line((x0, y0 + j, x0, y0 + min(size, j + 12)), fill="#9aa0ad", width=4)
                    draw.line((x0 + size, y0 + j, x0 + size, y0 + min(size, j + 12)), fill="#9aa0ad", width=4)
                draw.ellipse((x0 + size - 26, y0 + 10, x0 + size - 8, y0 + 28), fill="#e8413a", outline=INK, width=3)
            continue
        face = "#6fe07f" if tone == "g" else "#f6e35e"
        border = "#3cb454" if tone == "g" else "#d6b82e"
        draw.rounded_rectangle((x0, y0, x0 + size, y0 + size), 14, fill=INK)
        draw.rounded_rectangle((x0 + 5, y0 + 5, x0 + size - 5, y0 + size - 5), 10, fill=border)
        draw.rounded_rectangle((x0 + 9, y0 + 9, x0 + size - 9, y0 + size - 9), 8, fill=face)
        screen.alpha_composite(art[icon].resize((92, 92), Image.LANCZOS), (x0 + 14, y0 + 6))
        say(draw, (x0 + size // 2, y0 + size - 22), level, 26, anchor="mm", stroke=5)

    # Centrepiece: the chest you open, with its level button and an auto toggle.
    halo = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    ImageDraw.Draw(halo).ellipse((140, 1230, 460, 1480), fill=(255, 255, 255, 230))
    screen.alpha_composite(halo.filter(ImageFilter.GaussianBlur(30)))
    put("big_chest", 300, 1470, 240)
    flat.chunky(draw, (476, 1352, 640, 1440), "#3a8fe0", "#2a6cb0", 16, 5)
    say(draw, (558, 1380), "열기", 24, anchor="mm", stroke=4)
    say(draw, (558, 1414), "Lv 15", 30, anchor="mm", stroke=5)
    flat.chunky(draw, (652, 1352, 740, 1440), "#c9ccd4", "#9fa3ae", 16, 5)
    say(draw, (696, 1376), "Auto", 20, anchor="mm", stroke=4)
    screen.alpha_composite(art["wait"].resize((40, 40), Image.LANCZOS), (676, 1392))

    # Tab bar: icons only, a red dot where something is new.
    bar_top = 1528
    draw.rectangle((0, bar_top, width, height), fill="#3b3f52")
    draw.line((0, bar_top, width, bar_top), fill=INK, width=5)
    for i, (icon, dot) in enumerate((("attack", False), ("wait", False), ("search", True), ("tactics", False), ("bag", True))):
        cx = 78 + i * 156
        if i == 4:
            draw.rounded_rectangle((cx - 66, bar_top + 18, cx + 66, height - 18), 18, fill="#565b72", outline=INK, width=4)
        screen.alpha_composite(art[icon].resize((96, 96), Image.LANCZOS), (cx - 48, bar_top + 26))
        if dot:
            draw.ellipse((cx + 26, bar_top + 22, cx + 46, bar_top + 42), fill="#e8413a", outline=INK, width=3)

    screen.convert("RGB").save(REVIEW / "forge-layout-780x1688.png")


if __name__ == "__main__":
    main()
