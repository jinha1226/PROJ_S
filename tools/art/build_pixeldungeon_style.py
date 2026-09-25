"""Pixel Dungeon-style samples: original sprites in that game's visual grammar.

Small figures (about 12 px wide) on 16 px tiles, a hard 1 px black outline,
two or three hand-placed tones per surface, earthy stone, and a map that
fades from lit to remembered to unknown. Every pixel is typed below; nothing
is traced from Pixel Dungeon's own assets.

Run: python3 tools/art/build_pixeldungeon_style.py
Writes game-size sheets to assets/pixel-dungeon-style-v1/ and enlarged
review images to docs/art/pixel-dungeon-style-v1/.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/pixel-dungeon-style-v1"
REVIEW = ROOT / "docs/art/pixel-dungeon-style-v1"
FONT = ROOT / "assets/fonts/Galmuri11.ttf"

PALETTE = {
    ".": None,
    "k": "#0c0806",
    # floor stone: seam, base, light, speck
    "A": "#27231f", "B": "#39342f", "C": "#48423b", "D": "#5d564c",
    # wall stone: mortar, base, light, top highlight
    "E": "#4a443a", "F": "#6e6756", "G": "#8b836f", "H": "#aaa189",
    # wood
    "n": "#3b2412", "m": "#6b4222", "o": "#9a6634", "j": "#c48f52",
    # skin
    "e": "#b8683f", "f": "#eaa878",
    # steel
    "1": "#353a47", "2": "#5c6576", "3": "#8e98aa", "4": "#c8cfda",
    # bone
    "5": "#a69d86", "W": "#ece6d2",
    # red
    "r": "#6e1616", "s": "#b52a22", "t": "#e8574a",
    # blue
    "a": "#1f2e6b", "b": "#3456b8", "c": "#6f95e8",
    # green
    "g": "#1f4a1e", "h": "#3f8a2e", "i": "#8cc84a",
    # gold
    "y": "#a87414", "z": "#f2cc3a",
    # hyena orange
    "Q": "#6e3a16", "O": "#c0702c", "P": "#e3a45a",
    # purple
    "p": "#4a2470", "q": "#8a4cc0",
    # pink
    "u": "#d68a8a",
    # water
    "v": "#173e5c", "w": "#2a6a92", "x": "#79bcdf",
}

CHARACTERS = {
    "hero": [
        "................",
        "................",
        ".....kkkkk......",
        "....kmmmmmk..k..",
        "...kmmoommmkk4k.",
        "...kmfffffmkk4k.",
        "...kfkffkffkk4k.",
        "...kefffffekk4k.",
        "...kkssssskkk4k.",
        "..k3kss3333kyyyk",
        "..kfk33333kkkfk.",
        "..kfk22222k.kfk.",
        "...kk2y222k..k..",
        "....knnknnk.....",
        "....k22kk22k....",
        "....kkk..kkk....",
    ],
    "rat": [
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "...kk.kk........",
        "..kuuk5uk.......",
        "..k5k55kkkkk....",
        ".k5555555555kk..",
        "kk5k55555555O5k.",
        "k55555555O55O5k.",
        ".kkk5555555555kk",
        "...kk5kkk5kkkukk",
        "....kk..kk..kuk.",
        ".............kk.",
    ],
    "gnoll": [
        "..........k.....",
        "...kk....k4k....",
        "..kPOk...k4k....",
        "..kOOkkkkk4k....",
        "..kOOOOOOk4k....",
        "..kOkOOQOk4k....",
        ".kPOOOOOOkfk....",
        ".kPkkOOQOkfk....",
        "..kkkOOOkknk....",
        "..kQOmmmmkkk....",
        ".kOkmmmmmmkOk...",
        ".kOkmyyymmkOk...",
        "..kkmmmmmmkk....",
        "...kOQk.kOQk....",
        "...kOOk.kOOk....",
        "...kkkk.kkkk....",
    ],
    "skeleton": [
        "................",
        "................",
        ".....kkkkkk.....",
        "....kWWWWWWk....",
        "...kWWWWWWW5k...",
        "...kWkkWWkk5k...",
        "...kWkkWWkk5k...",
        "....kWWkkW5k....",
        ".....kW5W5k.....",
        "....kkkWWkkk.k..",
        "...kWk5WW5kWk4k.",
        "...kWkkWWkkkk4k.",
        "......kW5k..kyk.",
        ".....kW5k5Wk.k..",
        ".....kWk.kWk....",
        ".....kk...kk....",
    ],
    "goblin": [
        "................",
        "................",
        "................",
        ".kk...kkkk...kk.",
        ".kik.khiiik.kik.",
        "..kikhiiiihkik..",
        "...khhhhhhhhk...",
        "...khkzhhzkhk...",
        "...khhhhhhhhk...",
        "....khkkkkhk.kk.",
        "...kmmhhhhmmkok.",
        "..khkmmmmmmkok..",
        "..khknnnnnnkk...",
        "...kkmmmmmmk....",
        "....kgk..kgk....",
        "....kk....kk....",
    ],
    "kobold": [
        "................",
        "................",
        "................",
        "....k......k....",
        "...kok....kok...",
        "...koookkkook...",
        "..kooooooooook..",
        "..koookoookook..",
        "..kooozooozook..",
        "...kjooooooojk..",
        "....kkkoookkk...",
        "...kmkooooomk.k.",
        "..kokmmmmmmkok4k",
        "...kkommmmokkk..",
        "....kok..kok....",
        "....kk....kk....",
    ],
}

ITEMS = {
    "potion_red": [
        "................",
        "................",
        "......kkkk......",
        "......kjok......",
        "......k44k......",
        ".....kk44kk.....",
        "....k4W4444k....",
        "...k4tsssss4k...",
        "...kWtsssssrk...",
        "...ktssssssrk...",
        "...kssssssrrk...",
        "....ksssrrrk....",
        ".....kkkkkk.....",
        "................",
        "................",
        "................",
    ],
    "potion_blue": [
        "................",
        "......kkkk......",
        "......kjok......",
        "......k44k......",
        "......k44k......",
        ".....k4WW4k.....",
        ".....k4cc4k.....",
        "....kWccbbak....",
        "....kcbbbbak....",
        "...kcbbbbbbak...",
        "...kbbbbbbaak...",
        "....kbbbaaak....",
        ".....kkkkkk.....",
        "................",
        "................",
        "................",
    ],
    "scroll": [
        "................",
        "................",
        "...kkkkkkkkk....",
        "..kWWWWWWWWjk...",
        "..kjffffffffk...",
        "...kfWWWWWWfk...",
        "...kfnnfnnnfk...",
        "...kfWWWWWWfk...",
        "...kfnnnfnnfk...",
        "...kfWWWWWWfk...",
        "..kjffffffffk...",
        "..kWWWWWWWWjk...",
        "...kkkkkkkkk....",
        "................",
        "................",
        "................",
    ],
    "food": [
        "................",
        "................",
        "................",
        "................",
        "....kkkkkkk.....",
        "...kjjjjjjjk....",
        "..kjooooooojk...",
        "..kjooooooomk...",
        "..kjoWoooWomk...",
        "..kmooooooomk...",
        "..kmmmmmmmmmk...",
        "...kkkkkkkkk....",
        "................",
        "................",
        "................",
        "................",
    ],
    "gold": [
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        ".......kkk......",
        "......kzzyk.....",
        "....kkkzyykkk...",
        "...kzzzkkkzzyk..",
        "..kzzyyzzzzyyyk.",
        "..kyyyyyyyyyyyk.",
        "...kkkkkkkkkkk..",
        "................",
        "................",
    ],
    "key": [
        "................",
        "................",
        "................",
        "................",
        "....kkk.........",
        "...kzyzk........",
        "...kykyk........",
        "...kzyzkkkkkkk..",
        "....kkkzzzzzzyk.",
        ".......kkkkyky k",
        "..........kyk.k.",
        "...........k....",
        "................",
        "................",
        "................",
        "................",
    ],
}

TILES = {
    "floor": [
        "CCCCCCCCCCCCCCCA",
        "CBBBBBBBBBBBBBBA",
        "CBBBBBBBDBBBBBBA",
        "CBBBBBBBBBBBBBBA",
        "CBBDBBBBBBBBBCBA",
        "CBBBBBBBBBBBBBBA",
        "CBBBBBBBBBDBBBBA",
        "CBBBBBBBBBBBBBBA",
        "CCCCCCCACCCCCCCA",
        "CBBBBBBACBBBBBBA",
        "CBBBBBBACBBBDBBA",
        "CBDBBBBACBBBBBBA",
        "CBBBBBBACBBBBBBA",
        "CBBBBCBACBBBBBBA",
        "CBBBBBBACBBBBBBA",
        "AAAAAAAAAAAAAAAA",
    ],
    "grass": [
        "CCCCCCCCCCCCCCCA",
        "CBBBgBBBBBBBBgBA",
        "CBBghBBBgBBBghBA",
        "CBghigBghBBBhigA",
        "CBBhBBBhigBBBhBA",
        "CgBBBBBBhBBgBBBA",
        "ChgBBgBBBBghBBBA",
        "CihBghBBBBhigBBA",
        "CCCChiCACCChCCCA",
        "CBBBBhBACBBBBBBA",
        "CBgBBBBACBBgBBBA",
        "ChigBBBACBghBBgA",
        "CBhBBgBACBhigBhA",
        "CBBBghBACBBhBBBA",
        "CBBBhigACBBBBBBA",
        "AAAAAAAAAAAAAAAA",
    ],
    "water": [
        "vvvvvvvvvvvvvvvv",
        "vwwwwvvvvvwwwwvv",
        "wwxxwwvvvwwxxwwv",
        "vwwwwvvvvvwwwwvv",
        "vvvvvvvvvvvvvvvv",
        "vvvvvwwwwvvvvvvv",
        "vvvvwwxxwwvvvvvv",
        "vvvvvwwwwvvvvvvv",
        "vvvvvvvvvvvvvvvv",
        "vwwwwvvvvvvwwwwv",
        "wwxxwwvvvvwwxxww",
        "vwwwwvvvvvvwwwwv",
        "vvvvvvvvvvvvvvvv",
        "vvvvvvwwwwvvvvvv",
        "vvvvvwwxxwwvvvvv",
        "vvvvvvwwwwvvvvvv",
    ],
    "wall": [
        "HHHHHHHHHHHHHHHH",
        "GGGGGGGEGGGGGGGE",
        "GFFFFFFEGFFFFFFE",
        "GFFFFFFEGFFFFFFE",
        "EEEEEEEEEEEEEEEE",
        "GGGEGGGGGGGEGGGG",
        "FFFEGFFFFFFEGFFF",
        "FFFEGFFFFFFEGFFF",
        "EEEEEEEEEEEEEEEE",
        "GGGGGGGEGGGGGGGE",
        "GFFFFFFEGFFFFFFE",
        "GFFFFFFEGFFFFFFE",
        "EEEEEEEEEEEEEEEE",
        "GGGEGGGGGGGEGGGG",
        "FFFEGFFFFFFEGFFF",
        "kkkkkkkkkkkkkkkk",
    ],
    "wall_top": [
        "EEEEEEEEEEEEEEEE",
        "EFFFFFFFFFFFFFFE",
        "EFGGFFFFFFFFGFFE",
        "EFFFFFFFFFFFFFFE",
        "EFFFFFFGFFFFFFFE",
        "EFFFFFFFFFFFFFFE",
        "EFFGFFFFFFFFFFFE",
        "EFFFFFFFFFFGFFFE",
        "EFFFFFFFFFFFFFFE",
        "EFFFFFGFFFFFFFFE",
        "EFFFFFFFFFFFFGFE",
        "EFFFFFFFFFFFFFFE",
        "EFGFFFFFFGFFFFFE",
        "EFFFFFFFFFFFFFFE",
        "EFFFFFFFFFFFFFFE",
        "EEEEEEEEEEEEEEEE",
    ],
    "door": [
        "HHHHHHHHHHHHHHHH",
        "GGGkkkkkkkkkkGGE",
        "GFkjjjojjjojjkFE",
        "GFkjoomjoomjokFE",
        "EEkjoomjoomjokEE",
        "GGkjoomjoomjokGG",
        "FFkjoomjoomjokFF",
        "FFkjoomjoomzykFF",
        "EEkjoomjoomyykEE",
        "GGkjoomjoomjokGG",
        "GFkjoomjoomjokFE",
        "GFkjoomjoomjokFE",
        "EEkjoomjoomjokEE",
        "GGkjoomjoomjokGG",
        "FFknnnnnnnnnnkFF",
        "kkkkkkkkkkkkkkkk",
    ],
    "stairs": [
        "kkkkkkkkkkkkkkkA",
        "kCCCCCCCCCCCCCkA",
        "kBBBBBBBBBBBBBkA",
        "kkkkkkkkkkkkkkkA",
        "kkCCCCCCCCCCCkkA",
        "kkBBBBBBBBBBBkkA",
        "kkkkkkkkkkkkkkkA",
        "kkkCCCCCCCCCkkkA",
        "kkkBBBBBBBBBkkkA",
        "kkkkkkkkkkkkkkkA",
        "kkkkCCCCCCCkkkkA",
        "kkkkBBBBBBBkkkkA",
        "kkkkkkkkkkkkkkkA",
        "kkkkkkkkkkkkkkkA",
        "kkkkkkkkkkkkkkkA",
        "AAAAAAAAAAAAAAAA",
    ],
}

PROPS = {
    "chest": [
        "................",
        "................",
        "................",
        "..kkkkkkkkkkkk..",
        ".kjoooooooooomk.",
        ".kjmmmmmmmmmmnk.",
        ".kkkkkkkkkkkkkk.",
        ".kjoyoookzkoymk.",
        ".kjoyooky yoymk.",
        ".kjoyoookkooymk.",
        ".kmmyyyyyyyyynk.",
        ".knnnnnnnnnnnnk.",
        "..kkkkkkkkkkkk..",
        "................",
        "................",
        "................",
    ],
    "torch": [
        "................",
        ".......k........",
        "......kzk.......",
        ".....kzOzk......",
        ".....kOzOk......",
        "....kOzWzOk.....",
        "....ksOzOsk.....",
        ".....ksssk......",
        "......kkk.......",
        ".....kmmmk......",
        "......kmk.......",
        "......kmk.......",
        ".....k2k2k......",
        "....k23332k.....",
        ".....kkkkk......",
        "................",
    ],
}

ICONS = {
    "wait": [
        "................",
        "...kkkkkkkkkk...",
        "...kmmmmmmmmk...",
        "....kWWWWWWk....",
        "....kWzzzz4k....",
        ".....kWzz4k.....",
        "......kWzk......",
        ".......kk.......",
        "......kW4k......",
        ".....kW..4k.....",
        "....kW..z.4k....",
        "....kWzzzz4k....",
        "...kmmmmmmmmk...",
        "...kkkkkkkkkk...",
        "................",
        "................",
    ],
    "search": [
        "................",
        "....kkkkk.......",
        "...kcWWcbk......",
        "..kcWcccbak.....",
        "..kWccccbak.....",
        "..kccccbbak.....",
        "..kcccbbaak.....",
        "...kbbaaak......",
        "....kkkkkkk.....",
        "........kmmk....",
        ".........kmmk...",
        "..........kmmk..",
        "...........kmmk.",
        "............kkk.",
        "................",
        "................",
    ],
    "bag": [
        "................",
        ".....kkkkkk.....",
        "....kmk..kmk....",
        "...kkkkkkkkkk...",
        "..kmoooooooomk..",
        "..komooooooomk..",
        "..kkkkkkkkkkkk..",
        "..kmokmyymkomk..",
        "..kmokmzymkomk..",
        "..kmokkkkkkomk..",
        "..kmoooooooomk..",
        "..knmmmmmmmmnk..",
        "..knnnnnnnnnnk..",
        "...kkkkkkkkkk...",
        "................",
        "................",
    ],
    "depth": [
        "................",
        "kkkkkkkkkkkkkkk.",
        "kHHHHHHHHHHHHHk.",
        "kkkkkkkkkkkkkkk.",
        "kkGGGGGGGGGGGkk.",
        "kkkkkkkkkkkkkkk.",
        "kkkFFFFFFFFFkkk.",
        "kkkkkkkkkkkkkkk.",
        "kkkkEEEEEEEkkkk.",
        "kkkkkkkkkkkkkkk.",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
    ],
    "danger": [
        "................",
        ".....kkkkkk.....",
        "....kttttttk....",
        "...ktttttttsk...",
        "...ktkktkkssk...",
        "...ktkktkkssk...",
        "...kttttksssk...",
        "....kttktssk....",
        ".....ksksk......",
        "......kkk.......",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
    ],
}


def rgba(ch: str):
    value = PALETTE.get(ch)
    if value is None:
        return (0, 0, 0, 0)
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


def rgb(ch: str):
    return rgba(ch)[:3]


def draw_grid(rows: list) -> Image.Image:
    image = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    for y, row in enumerate((rows + ["." * 16] * 16)[:16]):
        for x, ch in enumerate(row[:16].ljust(16, ".")):
            image.putpixel((x, y), rgba(ch if ch in PALETTE else "."))
    return image


def sheet(group: dict, columns: int) -> Image.Image:
    names = list(group)
    count = (len(names) + columns - 1) // columns
    image = Image.new("RGBA", (columns * 16, count * 16), (0, 0, 0, 0))
    for i, name in enumerate(names):
        image.paste(draw_grid(group[name]), ((i % columns) * 16, (i // columns) * 16))
    return image


def scale(image: Image.Image, factor: int) -> Image.Image:
    return image.resize((image.width * factor, image.height * factor), Image.NEAREST)


# --- screen ------------------------------------------------------------------

MAP = [
    "           ",
    "           ",
    "###########",
    "#.........#",
    "#.,,......#",
    "#,,,...~~.#",
    "#.,....~~.#",
    "#.........#",
    "#####+#####",
    "    #.#    ",
    "    #.#    ",
    "#####.#####",
    "#.........#",
    "#.........#",
    "#.........#",
    "#.,.......#",
    "#,,.....>.#",
    "#.........#",
    "###########",
    "           ",
    "           ",
    "           ",
    "           ",
]
HERO = (5, 14)
SIGHT = 5.5


def tile_for(tx: int, ty: int) -> str:
    ch = MAP[ty][tx]
    below = MAP[ty + 1][tx] if ty + 1 < len(MAP) else " "
    if ch == "#":
        return "wall" if below in ".,+>~" else "wall_top"
    return {".": "floor", ",": "grass", "~": "water", "+": "door", ">": "stairs"}.get(ch, "")


def darken(image: Image.Image, box, factor: float) -> None:
    px = image.load()
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b = px[x, y][:3]
            px[x, y] = (int(r * factor), int(g * factor * 0.95), int(b * factor * 1.05))


def chrome(draw, box, fill="#2a231d"):
    """Pixel Dungeon-like chrome: black rim, warm beige bevel, dark brown fill."""
    x0, y0, x1, y1 = box
    draw.rectangle(box, fill=rgb("k"))
    draw.rectangle([x0 + 1, y0 + 1, x1 - 1, y1 - 1], fill="#7a6650")
    draw.line([(x0 + 1, y0 + 1), (x1 - 1, y0 + 1)], fill="#a48c6c")
    draw.line([(x0 + 1, y0 + 1), (x0 + 1, y1 - 1)], fill="#a48c6c")
    draw.line([(x0 + 2, y1 - 1), (x1 - 1, y1 - 1)], fill="#4c3e30")
    draw.line([(x1 - 1, y0 + 2), (x1 - 1, y1 - 1)], fill="#4c3e30")
    draw.rectangle([x0 + 2, y0 + 2, x1 - 2, y1 - 2], fill=fill)


DIGITS = {
    "0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
    "2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "111", "001", "111"],
    "4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
    "6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"],
    "8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "111"],
    "/": ["001", "001", "010", "100", "100"],
}


def digits(draw, x, y, value, fill, shadow=True):
    for ch in value:
        for dy, row in enumerate(DIGITS[ch]):
            for dx, bit in enumerate(row):
                if bit == "1":
                    if shadow:
                        draw.point((x + dx + 1, y + dy + 1), fill=rgb("k"))
                    draw.point((x + dx, y + dy), fill=fill)
        x += 4


def shadow_text(draw, xy, value, fill, font):
    x, y = xy
    draw.text((x + 1, y + 1), value, font=font, fill=rgb("k"))
    draw.text((x, y), value, font=font, fill=fill)


def gameplay() -> Image.Image:
    width, height = 176, 368
    screen = Image.new("RGB", (width, height), rgb("k"))
    draw = ImageDraw.Draw(screen)
    draw.fontmode = "1"
    font = ImageFont.truetype(str(FONT), 12)

    tiles = {name: draw_grid(rows) for name, rows in TILES.items()}
    for ty, row in enumerate(MAP):
        for tx in range(len(row)):
            name = tile_for(tx, ty)
            if name:
                screen.paste(tiles[name], (tx * 16, ty * 16), tiles[name])

    def put(group, name, tx, ty):
        art = draw_grid(group[name])
        screen.paste(art, (tx * 16, ty * 16), art)

    put(PROPS, "torch", 2, 11)
    put(PROPS, "torch", 8, 11)
    put(PROPS, "chest", 1, 12)
    put(ITEMS, "potion_red", 3, 16)
    put(ITEMS, "scroll", 7, 13)
    put(ITEMS, "gold", 9, 17)
    put(ITEMS, "key", 3, 3)
    put(ITEMS, "food", 8, 4)
    put(CHARACTERS, "rat", 2, 14)
    put(CHARACTERS, "gnoll", 7, 12)
    put(CHARACTERS, "kobold", 8, 15)
    put(CHARACTERS, "hero", *HERO)

    # Fog: tiles out of sight are remembered at half light; the upper room has
    # been walked, the rest of the floor never has.
    for ty, row in enumerate(MAP):
        for tx, ch in enumerate(row):
            if ch == " ":
                continue
            dist = ((tx - HERO[0]) ** 2 + (ty - HERO[1]) ** 2) ** 0.5
            if dist > SIGHT or ty < 11:
                darken(screen, (tx * 16, ty * 16, tx * 16 + 16, ty * 16 + 16), 0.45)

    # Health bars sit on the sprite, the way the original shows a hurt enemy.
    for tx, ty, hp in ((2, 14, 5), (7, 12, 9), (8, 15, 12)):
        x, y = tx * 16 + 2, ty * 16 - 2
        draw.rectangle([x, y, x + 11, y + 1], fill=rgb("r"))
        draw.rectangle([x, y, x + 11 * hp // 14, y + 1], fill=rgb("t"))

    # Status pane: portrait, HP and XP bars, level; depth and danger on the right.
    chrome(draw, (0, 0, 111, 29))
    draw.rectangle([4, 4, 25, 25], fill=rgb("k"))
    draw.rectangle([5, 5, 24, 24], fill="#3a302a")
    hero = draw_grid(CHARACTERS["hero"]).crop((2, 1, 16, 15))
    screen.paste(hero, (8, 8), hero)
    draw.rectangle([29, 6, 106, 12], fill=rgb("k"))
    draw.rectangle([30, 7, 30 + 75 * 38 // 55, 11], fill=rgb("s"))
    draw.line([(30, 7), (30 + 75 * 38 // 55, 7)], fill=rgb("t"))
    digits(draw, 58, 7, "38/55", rgb("W"), shadow=False)
    draw.rectangle([29, 14, 106, 16], fill=rgb("k"))
    draw.rectangle([30, 15, 30 + 75 * 3 // 10, 15], fill=rgb("z"))
    shadow_text(draw, (30, 17), "아린", rgb("W"), font)
    draw.rectangle([90, 18, 105, 27], fill=rgb("k"))
    digits(draw, 94, 20, "3", rgb("z"), shadow=False)

    chrome(draw, (140, 0, 175, 17))
    depth = draw_grid(ICONS["depth"])
    screen.paste(depth, (143, 2), depth)
    digits(draw, 162, 6, "4", rgb("W"))
    chrome(draw, (148, 19, 175, 36))
    danger = draw_grid(ICONS["danger"])
    screen.paste(danger, (150, 21), danger)
    digits(draw, 166, 25, "3", rgb("t"))

    # Log over the map, newest last, with a 1 px black drop shadow.
    lines = [("놀이 모습을 드러냈다.", "#e0d6c0"), ("쥐가 이빨을 드러낸다.", "#e0d6c0"),
             ("붉은 물약을 발견했다.", "#f2cc3a")]
    for i, (body, tint) in enumerate(lines):
        shadow_text(draw, (4, 302 + i * 13), body, tint, font)

    # Toolbar: wait and search on the left, quick slots and the bag on the right,
    # and the attack prompt above it showing the nearest foe.
    bar_top = height - 26
    for i, icon in enumerate(("wait", "search")):
        x = i * 25
        chrome(draw, (x, bar_top, x + 24, height - 1))
        art = draw_grid(ICONS[icon])
        screen.paste(art, (x + 4, bar_top + 5), art)
    for i, (group, name) in enumerate(((ITEMS, "potion_red"), (ITEMS, "scroll"), (ICONS, "bag"))):
        x = width - 75 + i * 25
        chrome(draw, (x, bar_top, x + 24, height - 1))
        art = draw_grid(group[name])
        screen.paste(art, (x + 4, bar_top + 5), art)
    chrome(draw, (width - 26, bar_top - 27, width - 1, bar_top - 2), "#4a1a16")
    foe = draw_grid(CHARACTERS["gnoll"])
    screen.paste(foe, (width - 21, bar_top - 23), foe)
    return screen


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    sheets = {
        "characters": sheet(CHARACTERS, 6),
        "tiles": sheet(TILES, 7),
        "items": sheet(ITEMS, 6),
        "props": sheet(PROPS, 2),
        "icons": sheet(ICONS, 5),
    }
    for name, image in sheets.items():
        image.save(OUT / f"{name}.png")

    pad, zoom = 8, 7
    board_w = max(image.width for image in sheets.values()) * zoom + pad * 2
    board_h = sum(image.height * zoom + pad for image in sheets.values()) + pad
    board = Image.new("RGBA", (board_w, board_h), (26, 22, 20, 255))
    y = pad
    for image in sheets.values():
        big = scale(image, zoom)
        board.paste(big, (pad, y), big)
        y += big.height + pad
    board.save(REVIEW / "sprite-sheet-x7.png")

    screen = gameplay()
    screen.save(OUT / "gameplay-176x368.png")
    scale(screen, 4).save(REVIEW / "gameplay-x4.png")


if __name__ == "__main__":
    main()
