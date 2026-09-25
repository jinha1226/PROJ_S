"""Dark fantasy 16-bit samples: hand-placed material masks, shaded by rule.

Each sprite below is typed pixel by pixel as a *material* mask (steel, bone,
crimson cloth ...). The script then lights every material from the top-left
with a five-step ramp, draws a selective outline (dark material colour on the
lit side, near-black on the shadow side), and the room is lit by torches in
dithered bands — the SNES-era recipe, with no image model and no downscaling.

Run: python3 tools/art/build_darkfantasy_16bit.py
Writes game-size sheets to assets/16bit/darkfantasy-v1/ and enlarged review
images to docs/art/16bit-darkfantasy-v1/.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/16bit/darkfantasy-v1"
REVIEW = ROOT / "docs/art/16bit-darkfantasy-v1"
FONT = ROOT / "assets/fonts/Galmuri11.ttf"


def hexes(*values):
    return [tuple(int(v.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)) for v in values]


# Five steps per material, darkest first. Desaturated, cold, with warm metal.
RAMPS = {
    "s": hexes("#161a24", "#2c3242", "#4a5368", "#7a8499", "#b6c0d2"),  # steel
    "x": hexes("#1c120e", "#3a2218", "#5e3622", "#8a5230", "#b07448"),  # rusted iron
    "b": hexes("#2e241e", "#5c4c3c", "#958066", "#c8b692", "#ece2c6"),  # bone
    "c": hexes("#220a10", "#461219", "#721c24", "#9c2f2c", "#c65540"),  # crimson cloth
    "g": hexes("#161e1a", "#2c3a32", "#4c6052", "#768a74", "#a6b69c"),  # ghoul skin
    "f": hexes("#141012", "#281e20", "#403232", "#62504a", "#8a7266"),  # dark fur
    "r": hexes("#110a1a", "#211432", "#35224e", "#4f3870", "#725a94"),  # cult robe
    "o": hexes("#161a0e", "#2a3418", "#465626", "#687a36", "#8ea250"),  # orc skin
    "l": hexes("#1a100a", "#342014", "#54361e", "#7a522c", "#a07444"),  # leather / wood
    "a": hexes("#24160a", "#50320e", "#8a5e16", "#c0902a", "#ecc868"),  # bronze / gold
    "h": hexes("#24120e", "#4c2a1e", "#7c4a34", "#aa7050", "#d49c78"),  # human skin
    "q": hexes("#2e1418", "#5a2a30", "#8c4a4e", "#b8706c", "#dc9a90"),  # raw pink
    "p": hexes("#2a2014", "#54442c", "#8a7650", "#bca97c", "#e4d6a8"),  # parchment
    "w": hexes("#120e08", "#241a10", "#3a2a18", "#5a4024", "#7c5a34"),  # dark wood
    "t": hexes("#0e1a18", "#183430", "#265a50", "#3a8a78", "#62c0a4"),  # venom teal
    "d": hexes("#0e0610", "#2a0a12", "#58101a", "#8c1a22", "#c43030"),  # blood / wine
    "u": hexes("#0a0c1a", "#141c3a", "#22306a", "#34509c", "#5a7cd0"),  # deep blue glass
}
# Colours that do not take light: voids and things that glow.
FIXED = {
    "K": hexes("#08060a")[0],
    "E": hexes("#ff4a26")[0],
    "V": hexes("#8cff6a")[0],
    "Y": hexes("#ffc850")[0],
    "Z": hexes("#fff2c0")[0],
    "O": hexes("#ff8a1e")[0],
}
EMISSIVE = {"E", "V", "Y", "Z", "O"}
INK = hexes("#07050a")[0]

CHARACTERS = {
    "knight": [
        "........................",
        "....................s...",
        "..........ssss......s...",
        "........ssssssss....s...",
        ".......ssssssssss...s...",
        ".......ssssssssss...s...",
        "......sssKKKKKKsss..s...",
        "......ssKKYKKYKKss..s...",
        "......sssKKKKKKsss..s...",
        ".......ssssssssss...s...",
        ".....cccsssssssccc.aaa..",
        "....ccsssssssssssccchh..",
        "...ccsssssaaassssscch...",
        "...ccssssssasssssscc....",
        "...ccllllllallllllcc....",
        "...ccssssssssssssscc....",
        "...cc.sssssssssss.cc....",
        "...cc.ssss..ssss..cc....",
        "...cc.ssss..ssss..cc....",
        "....c.ssss..ssss..c.....",
        "......ssss..ssss........",
        ".....lllll..lllll.......",
        ".....lllll..lllll.......",
        "........................",
    ],
    "skeleton": [
        "........................",
        "........................",
        ".........xxxxxx.........",
        "........xxxxxxxx........",
        ".......xxxxxxxxxx.......",
        ".......bbbbbbbbbb.......",
        ".......bKKbbbbKKb.......",
        ".......bKEbbbbEKb.......",
        ".......bbbbKKbbbb.......",
        "........bbbbbbbb........",
        ".........bKbKbK.........",
        "....www...bbbb....b.....",
        "...wwwww.bbbbbb..bb.....",
        "..wwwawwwbKbbKbbb.......",
        "..wwaaawwbbbbbbb.b......",
        "..wwwawwwbKbbKb..b......",
        "...wwwww..bbbb...s......",
        "....www...bKKb...s......",
        ".........bb..bb..s......",
        ".........b....b..s......",
        ".........b....b.........",
        "........bb....bb........",
        "........bb....bb........",
        "........................",
    ],
    "ghoul": [
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        ".........gggg...........",
        "........gggggg..........",
        ".......ggVggVgg.........",
        ".......gggggggg.........",
        "......gggKbbKggg........",
        ".....ggggggggggggg......",
        "....ggggggggggggggg.....",
        "...ggg.gggggggggg.ggg...",
        "..ggg..ggggcggggg..ggg..",
        "..gb...gggcccgggg...bg..",
        "..b.b..gggcccggg...b.b..",
        ".......gcccccccg........",
        ".......ccc.cc.ccc.......",
        "........gg....gg........",
        "........gg....gg........",
        ".......ggg....ggg.......",
        "......gggg....gggg......",
        "......b.b.....b.b.......",
        "........................",
    ],
    "rat": [
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "....ff..................",
        "...fqf.ff...............",
        "...ffffqf...............",
        "..fEfffff.fffff.........",
        ".fffffffffffffffff......",
        "bffffffffffffffffff.....",
        ".fffffffffffffffffff....",
        "..ffffffffffffffffff....",
        "...ffff.fffffff.ffff....",
        "....fff..ffff....fff.qq.",
        "....ff...ff......ffqq.q.",
        "....bb...bb.......b...q.",
        "......................q.",
        ".....................qq.",
        "........................",
    ],
    "cultist": [
        "........................",
        "........................",
        "..........rrrr..........",
        ".........rrrrrr.........",
        "........rrrrrrrr........",
        ".......rrrKKKKrrr.......",
        ".......rrKKKKKKrr.......",
        ".......rrKEKKEKrr.......",
        "..Z....rrKKKKKKrr.......",
        "..Y...rrrrKKKKrrrr......",
        "..b..rrrrrrrrrrrrrr.....",
        "..b.rrrrrrrarrrrrrrr....",
        "..hhrrrrrraaarrrrrrh....",
        "...rrrrrrrrarrrrrrrrs...",
        "...rrrrrrrrrrrrrrrrhs...",
        "....rrrrrrrrrrrrrrrr....",
        "....rrrrrrrrrrrrrrrr....",
        "...rrrrrrrrdrrrrrrrrr...",
        "...rrrrrrrrdrrrrrrrrr...",
        "..rrrrrrrrrdrrrrrrrrrr..",
        "..rrrrrrrrrrrrrrrrrrrr..",
        "..rrrrrrrrrrrrrrrrrrrr..",
        "...rrrrrrrrrrrrrrrrrr...",
        "........................",
    ],
    "orc": [
        "........................",
        "....................ss..",
        "........oooooo.....ssss.",
        ".......oooooooo....sssss",
        "......oooooooooo...ssss.",
        "......ooEooooEoo....ll..",
        "......oooooooooo....l...",
        "......oobooooboo....l...",
        ".......oooooooo.....l...",
        "....xxoooooooooxx...l...",
        "...xxxllllllllllxx..l...",
        "..ooxxllllllllllxxooh...",
        "..ooo.llllallll..oooh...",
        "..ooo.llllllllll..ool...",
        "..oo..llllllllll...ol...",
        "......llllllllll....l...",
        "......lllll.lllll...l...",
        "......oooo...oooo.......",
        "......oooo...oooo.......",
        "......oooo...oooo.......",
        ".....oooo....oooo.......",
        ".....xxxxx...xxxxx......",
        ".....xxxxx...xxxxx......",
        "........................",
    ],
}

ITEMS = {
    "potion_blood": [
        "................",
        "......llll......",
        "......llll......",
        ".......ss.......",
        ".......ss.......",
        "......ssss......",
        ".....sddddss....",
        "....sddddddds...",
        "...sdddddddddds.",
        "...sdddddddddds.",
        "...sdddddddddds.",
        "...sdddddddddds.",
        "....sddddddds...",
        ".....sssssss....",
        "................",
        "................",
    ],
    "potion_void": [
        "................",
        "......llll......",
        ".......ss.......",
        ".......ss.......",
        ".......ss.......",
        "......suus......",
        "......suus......",
        ".....suuuus.....",
        "....suuuuuus....",
        "...suuuuuuuus...",
        "...suuuuuuuus...",
        "...suuuuuuuus...",
        "....suuuuuus....",
        ".....ssssss.....",
        "................",
        "................",
    ],
    "potion_venom": [
        "................",
        "................",
        "......llll......",
        "......llll......",
        ".......ss.......",
        ".....ssssss.....",
        "....stttttts....",
        "...sttttttttts..",
        "...sttttttttts..",
        "....sttttttts...",
        ".....sttttts....",
        "......sttts.....",
        ".......sss......",
        "................",
        "................",
        "................",
    ],
    "scroll": [
        "................",
        "................",
        "..lllllllllll...",
        ".lpppppppppppl..",
        "..ppppppppppp...",
        "...pKKpKKKpp....",
        "...ppppppppp....",
        "...pKKKpKKpp....",
        "...ppppppppp....",
        "...pKpKKKKpp....",
        "...ppppdpppp....",
        "..pppppddpppp...",
        ".lpppppppppppl..",
        "..lllllllllll...",
        "................",
        "................",
    ],
}

PROPS = {
    "chest": [
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "...wwwwwwwwwwwwwwwwww...",
        "..wwxwwwwwwwwwwwwwxwww..",
        "..wwxwwwwwwwwwwwwwxwww..",
        "..wwxwwwwwwwwwwwwwxwww..",
        "..xxxxxxxxxxxxxxxxxxxx..",
        "..wwxwwwwwwaawwwwwxwww..",
        "..wwxwwwwwaKKawwwwxwww..",
        "..wwxwwwwwwaawwwwwxwww..",
        "..wwxwwwwwwwwwwwwwxwww..",
        "..wwxwwwwwwwwwwwwwxwww..",
        "..wwxwwwwwwwwwwwwwxwww..",
        "..xxxxxxxxxxxxxxxxxxxx..",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
    ],
    "brazier": [
        "........................",
        "........................",
        "..........Z.............",
        ".........ZYZ..Z.........",
        "........OYZYOZY.........",
        ".......OYYZZYYO.........",
        "......OOYYZYYYOO........",
        "......OYYYYYYYYO........",
        ".....xxxxxxxxxxxx.......",
        "....xxxxxxxxxxxxxx......",
        ".....xxxxxxxxxxxx.......",
        "......xxxxxxxxxx........",
        "........xxxxxx..........",
        ".........xxxx...........",
        ".........xxxx...........",
        ".........xxxx...........",
        ".........xxxx...........",
        "........xxxxxx..........",
        ".......xxxxxxxx.........",
        "......xxx....xxx........",
        ".....xxx......xxx.......",
        "........................",
        "........................",
        "........................",
    ],
    "bones": [
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "..........bbbbb.........",
        ".........bbbbbbb........",
        ".........bKbbbKb........",
        ".........bbbbbbb........",
        "..b.......bKbKb....b....",
        "...b......bbbbb...b.....",
        "....bbbbb........b......",
        ".....bbbbbbb.bbbbbbbb...",
        "..bb....bbbbbbb.....bb..",
        ".b.b.........bbbbbb.b...",
        "........................",
        "........................",
        "........................",
    ],
    "candles": [
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "......Z.................",
        ".....ZYZ........Z.......",
        ".....YOY.......ZYZ......",
        "......b........YOY......",
        ".....bbb........b.......",
        ".....bbb.......bbb..Z...",
        ".....bbb.......bbb.ZYZ..",
        ".....bbb.......bbb..b...",
        ".....bbb.......bbb.bbb..",
        ".....bbb..Z....bbb.bbb..",
        ".....bbb.ZYZ...bbb.bbb..",
        ".....bbb..b....bbb.bbb..",
        "....bbbbbbbbb.bbbbbbbbb.",
        "...dddddddddddddddddddd.",
        "........................",
        "........................",
        "........................",
    ],
}

ICONS = {
    "attack": [
        "................",
        ".ss..........ss.",
        ".sss........sss.",
        "..sss......sss..",
        "...sss....sss...",
        "....sss..sss....",
        ".....ssssss.....",
        "......ssss......",
        "......ssss......",
        ".....ssssss.....",
        "..aaass..ssaaa..",
        "...aa......aa...",
        "..lll......lll..",
        ".lll........lll.",
        ".aa..........aa.",
        "................",
    ],
    "wait": [
        "................",
        "...aaaaaaaaaa...",
        "....wwwwwwww....",
        "....bppppppb....",
        "....bpYYYYpb....",
        ".....bpYYpb.....",
        "......bYYb......",
        ".......bb.......",
        "......bppb......",
        ".....bp..pb.....",
        "....bp.Y..pb....",
        "....bpYYYYpb....",
        "....wwwwwwww....",
        "...aaaaaaaaaa...",
        "................",
        "................",
    ],
    "search": [
        "......aaaa......",
        ".....a....a.....",
        "......aaaa......",
        ".....xxxxxx.....",
        "....xxxxxxxx....",
        "....xaYYYYax....",
        "....xaYZZYax....",
        "....xaYZZYax....",
        "....xaYYYYax....",
        "....xaYYYYax....",
        "....xxxxxxxx....",
        ".....xxxxxx.....",
        "......xxxx......",
        "................",
        "................",
        "................",
    ],
    "tactics": [
        "................",
        "..l.............",
        "..lcccccccc.....",
        "..lccccccccc....",
        "..lcccaacccc....",
        "..lccaaaaccc....",
        "..lcccaaccc.....",
        "..lcccccccc.....",
        "..lccc..cc......",
        "..lcc....c......",
        "..l.............",
        "..l.............",
        "..l.............",
        ".lll............",
        "aaaaa...........",
        "................",
    ],
    "bag": [
        "................",
        "......llll......",
        ".....l....l.....",
        "....llllllll....",
        "...llllllllll...",
        "..llllllllllll..",
        "..lllllaalllll..",
        "..llllaKKallll..",
        "..lllllaalllll..",
        "..llllllllllll..",
        "..llllllllllll..",
        "..llllllllllll..",
        "...llllllllll...",
        "....llllllll....",
        "................",
        "................",
    ],
}


def normalise(rows: list, size: int) -> list:
    rows = [row[:size].ljust(size, ".") for row in rows]
    rows = (rows + ["." * size] * size)[:size]
    return rows


def shade(rows: list) -> tuple:
    """Material mask -> RGBA sprite and an emissive mask of the same size."""
    size = len(rows)
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow = Image.new("L", (size, size), 0)

    def at(x, y):
        return rows[y][x] if 0 <= x < size and 0 <= y < size else "."

    def run(x, y, dx, dy, ch):
        steps = 0
        while steps < 5 and at(x + dx * (steps + 1), y + dy * (steps + 1)) == ch:
            steps += 1
        return steps

    for y in range(size):
        for x in range(size):
            ch = rows[y][x]
            if ch == ".":
                continue
            if ch in FIXED:
                image.putpixel((x, y), FIXED[ch] + (255,))
                if ch in EMISSIVE:
                    glow.putpixel((x, y), 255)
                continue
            ramp = RAMPS[ch]
            lit_up = at(x, y - 1) != ch
            lit_left = at(x - 1, y) != ch
            score = 0
            if lit_up and lit_left:
                score += 2
            elif lit_up or lit_left:
                score += 1
            if at(x, y + 1) != ch:
                score -= 1
            if at(x + 1, y) != ch:
                score -= 1
            to_light = run(x, y, -1, -1, ch)
            to_shadow = run(x, y, 1, 1, ch)
            if to_light >= 2 and to_shadow >= 2:
                if to_shadow - to_light >= 3:
                    score += 1
                elif to_light - to_shadow >= 3:
                    score -= 1
            image.putpixel((x, y), ramp[max(0, min(4, 2 + score))] + (255,))

    # Selective outline: the lit side takes the material's darkest step, the
    # shadow side the shared ink.
    outline = image.copy()
    for y in range(size):
        for x in range(size):
            if rows[y][x] != ".":
                continue
            below, right = at(x, y + 1), at(x + 1, y)
            above, left = at(x, y - 1), at(x - 1, y)
            if below == "." and right == "." and above == "." and left == ".":
                continue
            lit_side = below if below != "." else right
            if lit_side != "." and above == "." and left == ".":
                colour = RAMPS[lit_side][0] if lit_side in RAMPS else INK
            else:
                colour = INK
            outline.putpixel((x, y), colour + (255,))
    return outline, glow


def sprite(rows: list, size: int) -> tuple:
    return shade(normalise(rows, size))


def sheet(group: dict, size: int, columns: int) -> Image.Image:
    names = list(group)
    count_rows = (len(names) + columns - 1) // columns
    image = Image.new("RGBA", (columns * size, count_rows * size), (0, 0, 0, 0))
    for i, name in enumerate(names):
        art, _ = sprite(group[name], size)
        image.paste(art, ((i % columns) * size, (i // columns) * size))
    return image


# --- tiles -------------------------------------------------------------------

STONE = hexes("#0e0d12", "#1b1a22", "#2a2832", "#3c3a46", "#56535f")
MOSS = hexes("#141c10", "#223018", "#34461e")
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def noise(x, y, seed):
    value = (x * 374761393 + y * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    value = (value ^ (value >> 13)) * 1274126177 & 0xFFFFFFFF
    return (value ^ (value >> 16)) & 0xFF


def floor_tile(seed: int) -> Image.Image:
    """Worn flagstones: two to three slabs, dark seams, lit top edges, moss in cracks."""
    tile = Image.new("RGBA", (24, 24), STONE[2] + (255,))
    px = tile.load()
    cut_y = 10 + seed % 5
    cut_x_top = 8 + (seed * 5) % 9
    cut_x_bottom = 5 + (seed * 3) % 13
    for y in range(24):
        for x in range(24):
            seam = y == cut_y or y == 23 or x == 23 or (y < cut_y and x == cut_x_top) or (y > cut_y and x == cut_x_bottom)
            lit = y == cut_y + 1 or y == 0 or (y < cut_y and x == cut_x_top + 1) or (y > cut_y and x == cut_x_bottom + 1) or x == 0
            grain = noise(x, y, seed)
            if seam:
                px[x, y] = STONE[0] + (255,)
                if grain < 40:
                    px[x, y] = MOSS[1] + (255,)
            elif lit:
                px[x, y] = STONE[3] + (255,)
            elif grain < 22:
                px[x, y] = STONE[1] + (255,)
            elif grain > 236:
                px[x, y] = STONE[3] + (255,)
    if seed % 3 == 0:
        for x, y in ((5, 5), (6, 6), (6, 7), (7, 8), (8, 8), (9, 9)):
            px[x, y] = STONE[0] + (255,)
            px[x + 1, y] = STONE[3] + (255,)
    return tile


def wall_face(seed: int) -> Image.Image:
    """Large irregular blocks: three courses, bevelled, a drip of damp."""
    tile = Image.new("RGBA", (24, 24), STONE[0] + (255,))
    draw = ImageDraw.Draw(tile)
    for course, (top, height) in enumerate(((0, 7), (8, 7), (16, 7))):
        offset = (seed * 7 + course * 11) % 12
        x = -offset
        while x < 24:
            width = 9 + noise(x, course, seed) % 6
            draw.rectangle([x + 1, top + 1, x + width - 1, top + height - 1], fill=STONE[2] + (255,))
            draw.line([(x + 1, top + 1), (x + width - 2, top + 1)], fill=STONE[4] + (255,))
            draw.line([(x + 1, top + 1), (x + 1, top + height - 2)], fill=STONE[3] + (255,))
            draw.line([(x + 2, top + height - 1), (x + width - 1, top + height - 1)], fill=STONE[1] + (255,))
            x += width
    px = tile.load()
    for y in range(24):
        for x in range(24):
            if px[x, y][:3] == STONE[2] and noise(x, y, seed + 9) < 18:
                px[x, y] = STONE[1] + (255,)
    drip = 4 + seed % 15
    for y in range(3, 12 + seed % 8):
        px[drip, y] = MOSS[0] + (255,)
    return tile


def wall_top(seed: int) -> Image.Image:
    """Seen from above: rubble-filled wall head, darker than the floor."""
    tile = Image.new("RGBA", (24, 24), STONE[0] + (255,))
    px = tile.load()
    for y in range(0, 24, 2):
        for x in range(0, 24, 2):
            if noise(x, y, seed + 3) < 34:
                for dx, dy in ((0, 0), (1, 0), (0, 1)):
                    px[x + dx, y + dy] = STONE[1] + (255,)
    return tile


def archway() -> Image.Image:
    tile = wall_face(4)
    draw = ImageDraw.Draw(tile)
    draw.rectangle([4, 6, 19, 23], fill=FIXED["K"] + (255,))
    draw.ellipse([4, 0, 19, 13], fill=FIXED["K"] + (255,))
    draw.arc([3, -1, 20, 14], 180, 360, fill=STONE[4] + (255,))
    for i, y in enumerate((12, 16, 20)):
        draw.line([(6 + i, y), (17 - i, y)], fill=STONE[2] + (255,))
    return tile


def blood(tile: Image.Image, seed: int) -> None:
    px = tile.load()
    for y in range(24):
        for x in range(24):
            dx, dy = x - 12, y - 13
            if dx * dx + dy * dy * 2 < 40 + noise(x, y, seed) % 30:
                px[x, y] = RAMPS["d"][1 if (x + y) % 2 else 2] + (255,)


# --- screen ------------------------------------------------------------------

def light_room(image: Image.Image, glow: Image.Image, lights: list, box) -> None:
    """Torchlight in dithered bands: brightness snaps to five levels, and the
    Bayer matrix decides which of two neighbouring levels each pixel takes."""
    x0, y0, x1, y1 = box
    px = image.load()
    gx = glow.load()
    levels = [0.3, 0.46, 0.64, 0.82, 1.0]
    for y in range(y0, y1):
        for x in range(x0, x1):
            if gx[x, y]:
                continue
            total, warm = 0.3, 0.0
            for lx, ly, radius, heat in lights:
                d2 = (x - lx) ** 2 + (y - ly) ** 2
                if d2 < radius * radius:
                    amount = (1 - (d2 ** 0.5) / radius) ** 1.3
                    total += amount
                    warm += amount * heat
            total = min(1.0, total)
            threshold = (BAYER[y % 4][x % 4] + 0.5) / 16
            level = levels[0]
            for i in range(len(levels) - 1):
                if total >= levels[i]:
                    span = levels[i + 1] - levels[i]
                    level = levels[i + 1] if (total - levels[i]) / span > threshold else levels[i]
            warm = min(1.0, warm)
            r, g, b = px[x, y][:3]
            px[x, y] = (min(255, int(r * level * (1 + 0.28 * warm))),
                        min(255, int(g * level * (1 + 0.08 * warm))),
                        int(b * level * (1 - 0.25 * warm)))


def frame(draw, box, fill=STONE[1]):
    """A panel with a bronze rim: dark inner edge, lit top-left, shaded bottom-right."""
    x0, y0, x1, y1 = box
    bronze = RAMPS["a"]
    draw.rectangle(box, fill=INK)
    draw.rectangle([x0 + 1, y0 + 1, x1 - 1, y1 - 1], fill=bronze[2])
    draw.line([(x0 + 1, y0 + 1), (x1 - 1, y0 + 1)], fill=bronze[3])
    draw.line([(x0 + 1, y0 + 1), (x0 + 1, y1 - 1)], fill=bronze[3])
    draw.line([(x0 + 2, y1 - 1), (x1 - 1, y1 - 1)], fill=bronze[1])
    draw.line([(x1 - 1, y0 + 2), (x1 - 1, y1 - 1)], fill=bronze[1])
    draw.rectangle([x0 + 2, y0 + 2, x1 - 2, y1 - 2], fill=INK)
    draw.rectangle([x0 + 3, y0 + 3, x1 - 3, y1 - 3], fill=fill)
    for cx, cy in ((x0 + 1, y0 + 1), (x1 - 1, y0 + 1), (x0 + 1, y1 - 1), (x1 - 1, y1 - 1)):
        draw.point((cx, cy), fill=bronze[4])


def gauge(draw, x, y, w, value, maximum, ramp):
    draw.rectangle([x, y, x + w - 1, y + 4], fill=INK)
    draw.rectangle([x + 1, y + 1, x + w - 2, y + 3], fill=STONE[0])
    inner = (w - 2) * value // maximum
    if inner > 0:
        draw.line([(x + 1, y + 1), (x + inner, y + 1)], fill=ramp[4])
        draw.line([(x + 1, y + 2), (x + inner, y + 2)], fill=ramp[3])
        draw.line([(x + 1, y + 3), (x + inner, y + 3)], fill=ramp[2])


def gameplay() -> Image.Image:
    width, height = 216, 384
    screen = Image.new("RGB", (width, height), INK)
    glow = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(screen)
    draw.fontmode = "1"
    font = ImageFont.truetype(str(FONT), 12)
    bone = RAMPS["b"]

    # Room: 9x9 tiles of 24px.
    top = 24
    layout = [
        "TTTTATTTT",
        "TFFFFFFFT",
        "T.......T",
        "T.......T",
        "T...x...T",
        "T.......T",
        "T.......T",
        "T.......T",
        "TTTTTTTTT",
    ]
    for ty, row in enumerate(layout):
        for tx, ch in enumerate(row):
            seed = tx * 7 + ty * 13
            if ch == "T":
                tile = wall_top(seed)
            elif ch == "A":
                tile = archway()
            elif ch == "F":
                tile = wall_face(seed)
            else:
                tile = floor_tile(seed)
                if ch == "x":
                    blood(tile, seed)
            screen.paste(tile, (tx * 24, top + ty * 24))
    # The wall face row also sits under the archway so the door reads as cut in.
    face = wall_face(2)
    screen.paste(face, (4 * 24, top + 24))
    draw.rectangle([4 * 24 + 4, top + 24, 4 * 24 + 19, top + 47], fill=FIXED["K"])

    def put(group, name, tx, ty, size=24, dx=0, dy=0):
        art, emissive = sprite(group[name], size)
        x, y = tx * 24 + dx, top + ty * 24 + dy
        screen.paste(art, (x, y), art)
        glow.paste(emissive, (x, y), emissive)

    def shadow(tx, ty, w=14):
        cx, cy = tx * 24 + 12, top + ty * 24 + 21
        for x in range(cx - w // 2, cx + w // 2):
            for y in (cy, cy + 1):
                if (x + y) % 2 == 0:
                    screen.putpixel((x, y), INK)

    put(PROPS, "brazier", 1, 1, dy=4)
    put(PROPS, "brazier", 7, 1, dy=4)
    put(PROPS, "chest", 1, 6)
    put(PROPS, "bones", 6, 7)
    put(PROPS, "candles", 7, 5)
    put(ITEMS, "potion_blood", 5, 6, 16, 4, 6)
    put(ITEMS, "scroll", 2, 7, 16, 4, 6)
    for name, tx, ty in (("skeleton", 5, 3), ("ghoul", 2, 4), ("cultist", 6, 2), ("rat", 3, 6), ("knight", 4, 5)):
        shadow(tx, ty)
        put(CHARACTERS, name, tx, ty)

    lights = [(1 * 24 + 12, top + 36, 96, 1.0), (7 * 24 + 12, top + 36, 96, 1.0),
              (4 * 24 + 12, top + 5 * 24 + 12, 80, 0.35), (7 * 24 + 10, top + 5 * 24 + 12, 44, 0.9)]
    light_room(screen, glow, lights, (0, top, width, top + 9 * 24))

    for tx, ty, hp in ((5, 3, 9), (2, 4, 12), (6, 2, 7), (3, 6, 4)):
        gauge(draw, tx * 24 + 4, top + ty * 24 - 2, 16, hp, 14, RAMPS["d"])

    # Header: minimap, floor, turn, food.
    frame(draw, (0, 0, width - 1, 23))
    draw.rectangle([5, 5, 34, 18], fill=INK)
    for x, y in ((8, 8), (13, 8), (18, 8), (18, 12), (23, 12), (28, 12), (28, 15)):
        draw.rectangle([x, y, x + 4, y + 2], fill=STONE[3])
    draw.rectangle([18, 12, 20, 14], fill=RAMPS["u"][4])
    draw.rectangle([28, 15, 30, 17], fill=RAMPS["d"][4])
    draw.text((64, 5), "지하 1층", font=font, fill=bone[4])
    draw.text((122, 5), "42턴", font=font, fill=RAMPS["a"][4])
    draw.text((162, 5), "식량 2", font=font, fill=bone[3])

    # Log.
    log_top = top + 9 * 24 + 2
    frame(draw, (0, log_top, width - 1, log_top + 56))
    lines = [("해골 전사가 일어섰다.", bone[3]), ("구울이 냄새를 맡았다.", bone[3]),
             ("아린이 한 칸 나아갔다.", RAMPS["u"][4]), ("핏빛 물약이 보인다.", RAMPS["d"][4])]
    for i, (body, tint) in enumerate(lines):
        y = log_top + 4 + i * 12
        draw.text((6, y), "42", font=font, fill=STONE[4])
        draw.text((24, y), body, font=font, fill=tint)

    # Status: portrait, name, level, three gauges.
    status_top = log_top + 59
    frame(draw, (0, status_top, width - 1, status_top + 40))
    draw.rectangle([5, status_top + 5, 34, status_top + 35], fill=INK)
    draw.rectangle([6, status_top + 6, 33, status_top + 34], fill=RAMPS["r"][1])
    portrait, portrait_glow = sprite(CHARACTERS["knight"], 24)
    portrait = portrait.crop((2, 1, 26, 25))
    screen.paste(portrait, (7, status_top + 9), portrait)
    draw.text((40, status_top + 5), "아린", font=font, fill=bone[4])
    draw.text((40, status_top + 21), "Lv 3", font=font, fill=RAMPS["a"][4])
    for row, (label, value, maximum, ramp) in enumerate((("HP", 38, 55, RAMPS["d"]), ("MP", 12, 18, RAMPS["u"]), ("SP", 8, 100, RAMPS["r"]))):
        y = status_top + 6 + row * 10
        draw.text((82, y - 3), label, font=font, fill=ramp[4])
        gauge(draw, 100, y + 1, 108, value, maximum, ramp)

    # Actions: iron plates with a bronze rim, bone icons and labels.
    button_top = status_top + 43
    labels = [("attack", "공격"), ("wait", "대기"), ("search", "탐색"), ("tactics", "전술"), ("bag", "가방")]
    for i, (icon, label) in enumerate(labels):
        x0 = i * 43 + 1
        frame(draw, (x0, button_top, x0 + 41, height - 1), STONE[2])
        draw.line([(x0 + 3, button_top + 3), (x0 + 38, button_top + 3)], fill=STONE[4])
        art, _ = sprite(ICONS[icon], 16)
        screen.paste(art, (x0 + 13, button_top + 5), art)
        draw.text((x0 + 9, button_top + 23), label, font=font, fill=bone[4])
    return screen


def scale(image: Image.Image, factor: int) -> Image.Image:
    return image.resize((image.width * factor, image.height * factor), Image.NEAREST)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    sheets = {
        "characters": sheet(CHARACTERS, 24, 6),
        "props": sheet(PROPS, 24, 4),
        "items": sheet(ITEMS, 16, 4),
        "icons": sheet(ICONS, 16, 5),
    }
    tiles = Image.new("RGBA", (24 * 6, 24))
    for i, tile in enumerate((floor_tile(0), floor_tile(4), wall_face(1), wall_face(5), wall_top(2), archway())):
        tiles.paste(tile, (i * 24, 0))
    sheets["tiles"] = tiles
    for name, image in sheets.items():
        image.save(OUT / f"{name}.png")

    pad = 10
    zoom = 5
    board_w = max(image.width for image in sheets.values()) * zoom + pad * 2
    board_h = sum(image.height * zoom + pad for image in sheets.values()) + pad
    board = Image.new("RGBA", (board_w, board_h), STONE[1] + (255,))
    y = pad
    for image in sheets.values():
        big = scale(image, zoom)
        board.paste(big, (pad, y), big)
        y += big.height + pad
    board.save(REVIEW / "sprite-sheet-x5.png")

    screen = gameplay()
    screen.save(OUT / "gameplay-216x384.png")
    scale(screen, 3).save(REVIEW / "gameplay-x3.png")


if __name__ == "__main__":
    main()
