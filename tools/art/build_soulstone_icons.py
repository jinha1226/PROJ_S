#!/usr/bin/env python3
"""Soul stone icons v1: twelve effect glyphs, two link badges, three trigger
frames (red = on attack, purple = on wait, green = when struck) and one sample
stone per colour. Everything is plain SVG on a 128 grid so the set stays
consistent and every piece can be recoloured or recombined by code.

    python3 tools/art/build_soulstone_icons.py

Writes assets/soulstone-icons-v1/{effects,badges,frames,samples}/*.svg.
"""
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / "assets" / "soulstone-icons-v1"
INK = "#15121a"  # the outline every shape shares
W = 5            # outline width on the 128 grid

FRAMES = {
    "red": {"rim": "#d9473b", "glow": "#5a1d1a", "name": "때릴 때"},
    "purple": {"rim": "#9d5fd9", "glow": "#3b2356", "name": "대기할 때"},
    "green": {"rim": "#4fb56c", "glow": "#1d4a2c", "name": "맞을 때"},
}


def svg(body: str, size: int = 128) -> str:
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
            f'viewBox="0 0 128 128">{body}</svg>')


def outlined(shape: str, fill: str, extra: str = "") -> str:
    """A shape drawn twice: a wide ink stroke under, the fill on top."""
    return (f'<{shape} fill="{INK}" stroke="{INK}" stroke-width="{W*2}" stroke-linejoin="round" stroke-linecap="round" {extra}/>'
            f'<{shape} fill="{fill}" {extra}/>')


def line(d: str, colour: str, width: float) -> str:
    return (f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="{width+W*2}" stroke-linecap="round" stroke-linejoin="round"/>'
            f'<path d="{d}" fill="none" stroke="{colour}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"/>')


def shine(d: str, opacity: float = 0.45) -> str:
    return f'<path d="{d}" fill="none" stroke="#ffffff" stroke-opacity="{opacity}" stroke-width="5" stroke-linecap="round"/>'


# ── the twelve effects ──────────────────────────────────────────────────

def bleed() -> str:
    drop = 'path d="M64 22 C64 22 38 56 38 74 C38 90 50 102 64 102 C78 102 90 90 90 74 C90 56 64 22 64 22 Z"'
    return (outlined(drop, "#c9303c")
            + '<path d="M64 30 C60 38 46 58 45 72" fill="none" stroke="#e85a64" stroke-width="6" stroke-linecap="round"/>'
            + shine("M52 78 C52 86 57 92 63 94", 0.5)
            + outlined('circle cx="92" cy="98" r="7"', "#c9303c"))


def poison() -> str:
    drop = 'path d="M60 24 C60 24 36 58 36 76 C36 92 47 102 60 102 C73 102 84 92 84 76 C84 58 60 24 60 24 Z"'
    return (outlined(drop, "#5cb83c")
            + '<path d="M60 32 C56 40 44 60 43 74" fill="none" stroke="#8fe06a" stroke-width="6" stroke-linecap="round"/>'
            + outlined('circle cx="92" cy="58" r="9"', "#5cb83c") + shine("M88 55 L90 53", 0.6)
            + outlined('circle cx="96" cy="84" r="6"', "#5cb83c")
            + outlined('circle cx="84" cy="34" r="5"', "#5cb83c"))


def burn() -> str:
    outer = 'path d="M64 18 C70 36 92 44 92 72 C92 92 80 106 64 106 C48 106 36 92 36 74 C36 58 46 50 50 40 C54 52 58 56 62 56 C60 44 58 30 64 18 Z"'
    inner = 'path d="M64 58 C68 68 80 74 80 86 C80 96 73 102 64 102 C55 102 48 96 48 87 C48 78 56 74 58 66 C60 72 62 74 64 74 C63 70 62 64 64 58 Z"'
    return outlined(outer, "#f07a2a") + f'<{inner} fill="#ffd24a"/>' + shine("M46 76 C46 86 51 94 57 98", 0.35)


def freeze() -> str:
    arms = ""
    import math
    for i in range(6):
        a = math.radians(i * 60 - 90)
        x2, y2 = 64 + 40 * math.cos(a), 64 + 40 * math.sin(a)
        arms += f"M64 64 L{x2:.1f} {y2:.1f} "
        for r, s in ((24, 12), (34, 9)):
            bx, by = 64 + r * math.cos(a), 64 + r * math.sin(a)
            for side in (-1, 1):
                b = a + side * math.radians(45)
                arms += f"M{bx:.1f} {by:.1f} L{bx + s*math.cos(b):.1f} {by + s*math.sin(b):.1f} "
    return line(arms, "#9fdcff", 6) + outlined('circle cx="64" cy="64" r="8"', "#dff4ff")


def shock() -> str:
    bolt = 'path d="M72 16 L36 70 L60 70 L50 112 L94 52 L68 52 L80 16 Z"'
    return outlined(bolt, "#ffd84a") + '<path d="M70 24 L48 62" stroke="#fff6c2" stroke-width="5" stroke-linecap="round"/>'


def curse() -> str:
    eye = 'path d="M16 64 C32 38 96 38 112 64 C96 90 32 90 16 64 Z"'
    return (outlined(eye, "#e6dcf2")
            + outlined('circle cx="64" cy="64" r="20"', "#9b5fd6")
            + f'<ellipse cx="64" cy="64" rx="6" ry="15" fill="{INK}"/>'
            + '<circle cx="71" cy="56" r="4" fill="#ffffff" fill-opacity="0.7"/>'
            + line("M40 36 L34 26 M64 30 L64 18 M88 36 L94 26", "#9b5fd6", 4))


def extra_strike() -> str:
    blade_a = "M30 98 L90 30"
    blade_b = "M98 98 L38 30"
    return (line(blade_a, "#dfe4ea", 9) + line(blade_b, "#dfe4ea", 9)
            + line("M22 90 L38 106", "#b3823f", 8) + line("M106 90 L90 106", "#b3823f", 8)
            + line("M28 96 L22 102", "#6e4a22", 7) + line("M100 96 L106 102", "#6e4a22", 7)
            + shine("M40 88 L84 38", 0.5))


def crit() -> str:
    return (outlined('circle cx="64" cy="64" r="42"', "#f3efe6")
            + outlined('circle cx="64" cy="64" r="28"', "#d9473b")
            + outlined('circle cx="64" cy="64" r="13"', "#f3efe6")
            + f'<circle cx="64" cy="64" r="5" fill="#d9473b"/>'
            + line("M64 10 L64 30 M64 98 L64 118 M10 64 L30 64 M98 64 L118 64", INK, 3))


def heal() -> str:
    heart = 'path d="M64 104 C28 80 18 64 18 48 C18 34 29 24 42 24 C52 24 60 30 64 38 C68 30 76 24 86 24 C99 24 110 34 110 48 C110 64 100 80 64 104 Z"'
    return outlined(heart, "#ff5d7a") + shine("M32 46 C32 38 38 34 44 34", 0.55) + line("M64 52 L64 80 M50 66 L78 66", "#ffffff", 7)


def guard() -> str:
    shield = 'path d="M64 16 L104 30 C104 66 90 94 64 110 C38 94 24 66 24 30 Z"'
    rim = 'path d="M64 30 L92 40 C91 66 82 86 64 98 C46 86 37 66 36 40 Z"'
    return outlined(shield, "#7fa6c9") + f'<{rim} fill="#a9c7e2"/>' + line("M64 34 L64 94", "#7fa6c9", 5) + shine("M42 44 C42 58 46 70 52 80", 0.5)


def thorns() -> str:
    """A ring of thorns: spikes pointing out, the way a blow comes back."""
    import math
    spikes = ""
    for i in range(8):
        a = math.radians(i * 45 - 90)
        tip = (64 + 50 * math.cos(a), 64 + 50 * math.sin(a))
        l = (64 + 30 * math.cos(a - 0.32), 64 + 30 * math.sin(a - 0.32))
        r = (64 + 30 * math.cos(a + 0.32), 64 + 30 * math.sin(a + 0.32))
        spikes += outlined(f'path d="M{l[0]:.1f} {l[1]:.1f} L{tip[0]:.1f} {tip[1]:.1f} L{r[0]:.1f} {r[1]:.1f} Z"', "#c9d98f")
    return (spikes + outlined('circle cx="64" cy="64" r="32"', "#5b8a3f")
            + f'<circle cx="64" cy="64" r="17" fill="#1d1a22"/>'
            + '<path d="M44 52 C48 42 56 36 66 34" fill="none" stroke="#9cc46c" stroke-width="5" stroke-linecap="round"/>')


def summon() -> str:
    skull = 'path d="M64 18 C36 18 24 38 24 58 C24 72 32 80 40 84 L40 100 L88 100 L88 84 C96 80 104 72 104 58 C104 38 92 18 64 18 Z"'
    return (outlined(skull, "#ece6d8")
            + f'<ellipse cx="48" cy="60" rx="11" ry="12" fill="{INK}"/><ellipse cx="80" cy="60" rx="11" ry="12" fill="{INK}"/>'
            + f'<path d="M64 70 L58 82 L70 82 Z" fill="{INK}"/>'
            + line("M52 100 L52 90 M64 100 L64 90 M76 100 L76 90", INK, 2)
            + '<circle cx="48" cy="60" r="4" fill="#8fe06a"/><circle cx="80" cy="60" r="4" fill="#8fe06a"/>'
            + shine("M36 50 C36 38 44 30 54 28", 0.5))


EFFECTS = {
    "bleed": ("출혈", bleed), "poison": ("중독", poison), "burn": ("화상", burn),
    "freeze": ("빙결·둔화", freeze), "shock": ("감전", shock), "curse": ("약화·저주", curse),
    "extra_strike": ("추가 공격", extra_strike), "crit": ("치명타·조준", crit), "heal": ("회복", heal),
    "guard": ("보호·방어", guard), "thorns": ("반사·반격", thorns), "summon": ("소환", summon),
}

# ── badges, frames, stones ──────────────────────────────────────────────

def badge_boost() -> str:
    return outlined('circle cx="102" cy="102" r="20"', "#f3c34a") + line("M102 92 L102 112 M92 102 L112 102", "#ffffff", 5)


def badge_burst() -> str:
    import math
    pts = []
    for i in range(16):
        r = 22 if i % 2 == 0 else 11
        a = math.radians(i * 22.5 - 90)
        pts.append(f"{102 + r*math.cos(a):.1f} {102 + r*math.sin(a):.1f}")
    return outlined(f'path d="M{" L".join(pts)} Z"', "#ff8a2a") + '<circle cx="102" cy="102" r="6" fill="#fff1b8"/>'


BADGES = {"boost": ("키운다 +", badge_boost), "burst": ("터뜨린다 ✸", badge_burst)}


def frame(colour: str) -> str:
    c = FRAMES[colour]
    return (f'<rect x="6" y="6" width="116" height="116" rx="24" fill="{INK}"/>'
            f'<rect x="11" y="11" width="106" height="106" rx="20" fill="{c["rim"]}"/>'
            f'<rect x="19" y="19" width="90" height="90" rx="14" fill="#221f27"/>'
            f'<path d="M24 30 C24 25 27 22 32 22 L70 22" fill="none" stroke="#ffffff" stroke-opacity="0.18" stroke-width="4" stroke-linecap="round"/>')


def stone(colour: str, effect: str, badge: str = "") -> str:
    glyph = EFFECTS[effect][1]()
    body = frame(colour) + f'<g transform="translate(64 64) scale(0.76) translate(-64 -64)">{glyph}</g>'
    if badge:
        body += f'<g transform="translate(100 100) scale(0.72) translate(-102 -102)">{BADGES[badge][1]()}</g>'
    return svg(body)


# One sample stone per colour (design doc §4): red bleeds on hit, purple
# burns from a wait, green reflects when struck. Plus the badge ladder for
# red bleed so the "apply / boost / burst" marks can be compared.
SAMPLES = {
    "red_bleed": ("red", "bleed", ""),
    "purple_burn": ("purple", "burn", ""),
    "green_thorns": ("green", "thorns", ""),
    "red_bleed_boost": ("red", "bleed", "boost"),
    "red_bleed_burst": ("red", "bleed", "burst"),
}


def main() -> None:
    for sub in ("effects", "badges", "frames", "samples"):
        (OUT / sub).mkdir(parents=True, exist_ok=True)
    for key, (_, draw) in EFFECTS.items():
        (OUT / "effects" / f"{key}.svg").write_text(svg(draw()), encoding="utf-8")
    for key, (_, draw) in BADGES.items():
        (OUT / "badges" / f"{key}.svg").write_text(svg(draw()), encoding="utf-8")
    for key in FRAMES:
        (OUT / "frames" / f"{key}.svg").write_text(svg(frame(key)), encoding="utf-8")
    for key, (colour, effect, badge) in SAMPLES.items():
        (OUT / "samples" / f"{key}.svg").write_text(stone(colour, effect, badge), encoding="utf-8")
    print(f"wrote {len(EFFECTS)} effects, {len(BADGES)} badges, {len(FRAMES)} frames, {len(SAMPLES)} samples to {OUT}")


if __name__ == "__main__":
    main()
