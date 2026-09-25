"""Hand-placed 8-bit sample sprites: every pixel below is authored on a 16x16
grid with one shared palette, no downscaling and no anti-aliasing.

Run: python3 tools/art/build_handmade_8bit.py
Writes the game-size sheets to assets/8bit/handmade-v1/ and the enlarged
review images to docs/art/8bit-handmade-v1/.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/8bit/handmade-v1"
REVIEW = ROOT / "docs/art/8bit-handmade-v1"
FONT = ROOT / "assets/fonts/Galmuri11.ttf"

# One palette for everything, NES-like: a near-black outline, four greys,
# and three steps per hue so each surface reads as shadow / base / light.
PALETTE = {
    ".": None,
    "k": "#140c1c", "K": "#2a2036",
    "1": "#34344a", "2": "#4e4e68", "3": "#7a7a94", "4": "#b4b4c6", "W": "#f0ecdc",
    "a": "#1c2a6a", "b": "#2f52c0", "c": "#6c94f0",
    "e": "#c06c48", "f": "#f0b484",
    "g": "#1e5424", "h": "#3c902e", "i": "#84c840",
    "n": "#4a2a1a", "m": "#7c4a28", "o": "#b47a40",
    "r": "#7c1a1c", "s": "#d0302a", "t": "#f47458",
    "y": "#c08c1c", "z": "#f8d83c",
    "p": "#4e2878", "q": "#9454cc",
    "O": "#f08828", "P": "#e8909a",
    "v": "#185c58", "T": "#34b0a4",
}

SPRITES = {
    "hero": [
        "..............k.",
        "......kkkk...k4k",
        "....kkbbbbkk.k4k",
        "...kbccbbbbbkk4k",
        "..kbcbbbbbbbak4k",
        "..kbbkkkkkkbak4k",
        "..kbkffffffkak4k",
        "..kbkfkffkfkakWk",
        "..kakeffffeekyyyk",
        "...kkkeeeekkkfk.",
        "..kaabbkkbbakfk.",
        ".kfkbbcbbbbakk..",
        ".kfkabbbbbaak...",
        "..kkkaabbaak....",
        "....knk..knk....",
        "....kk....kk....",
    ],
    "goblin": [
        "................",
        "................",
        ".kk...kkkk...kk.",
        ".kik.khiiik.kik.",
        "..kikhiiiihkik..",
        "...khhhhhhhhk...",
        "...khkzhhzkhk...",
        "...khhhhhhhhk...",
        "....khkkkkhk..k.",
        "...kmmhhhhmmkkok",
        "..khkmmmmmmkkok.",
        "..khknnnnnnkok..",
        "...kkmmmmmmkk...",
        "....khk..khk....",
        "....kgk..kgk....",
        "....kk....kk....",
    ],
    "skeleton": [
        "................",
        ".....kkkkkk.....",
        "....kWWWWWWk....",
        "...kWWWWWWW4k...",
        "...kWkkWWkk4k...",
        "...kWkkWWkk4k...",
        "...kWWWkWWW4k...",
        "....kW4W4W4k....",
        ".....kkkkkk..kk.",
        "....kWkWWkWk.kWk",
        "...kWkW4W4kWkW4k",
        "...kWkkWWkkkkWk.",
        "......kW4k...kk.",
        ".....kW4k4Wk....",
        ".....kWk.kWk....",
        ".....kk...kk....",
    ],
    "rat": [
        "................",
        "................",
        "................",
        "................",
        "...kk..kk.......",
        "..kPPkkPPk......",
        "..kPkkkkPkkkk...",
        ".k2222222222kk..",
        "k2zk222222222k..",
        "kP22222223223k..",
        ".kk2222232222k.k",
        "..kk222222222kkP",
        "...kk2kkk2kkkPk.",
        "....kk..kk.kPk..",
        "...........kk...",
        "................",
    ],
    "orc": [
        "................",
        "....kkkkkkk.....",
        "...khhhhhhhk....",
        "..khiihhhhhhk.k.",
        "..khkkhhhkkhkk4k",
        "..khzkhhhzkhk434k",
        "..khhhhhhhhhhk4k",
        "..khWkkkkkWhk.k.",
        "...khhhhhhhk.kyk",
        ".kk3kkkkkkk3kkyk",
        "k343nnmmmnn343yk",
        "k33knmmmmmnk33yk",
        ".kkkkmyyymkhkkyk",
        "...knnnnnnnk.kk.",
        "...khhk.khhk....",
        "...kkk...kkk....",
    ],
}

ITEMS = {
    "potion_red": [
        "................",
        "................",
        "......kkkk......",
        "......kook......",
        "......kmmk......",
        ".....kk44kk.....",
        "....k4WWW44k....",
        "...k4ttssss4k...",
        "...kWtsssssrk...",
        "...ktssssssrk...",
        "...ksssssssrk...",
        "...ksssssrrrk...",
        "....krrrrrrk....",
        ".....kkkkkk.....",
        "................",
        "................",
    ],
    "potion_blue": [
        "................",
        "................",
        "......kkkk......",
        "......kook......",
        "......kmmk......",
        "......k44k......",
        ".....k4WW4k.....",
        ".....k4cc4k.....",
        "....kWccbbak....",
        "....kcbbbbak....",
        "...kcbbbbbbak...",
        "...kbbbbbbaak...",
        "...kbbbbaaaak...",
        "....kaaaaaak....",
        ".....kkkkkk.....",
        "................",
    ],
    "potion_green": [
        "................",
        "................",
        "................",
        "......kkkk......",
        "......kook......",
        ".....kk44kk.....",
        "....k4W4444k....",
        "...kWiiiiiihk...",
        "...kiiihhhhgk...",
        "...kihhhhhhgk...",
        "....khhhhhgk....",
        ".....khhhgk.....",
        "......kggk......",
        ".......kk.......",
        "................",
        "................",
    ],
    "scroll": [
        "................",
        "................",
        "..kkkkkkkkkkk...",
        ".kWWWWWWWWWWok..",
        ".kofffffffffmk..",
        "..kkfWWWWWWWfk..",
        "...kfnnfnnnfk...",
        "...kfWWWWWWfk...",
        "...kfnnnfnnfk...",
        "...kfWWWWWWfk...",
        "...kfnnfnnnfk...",
        "..kfWWWWWWWWfk..",
        ".kofffffffffmk..",
        ".kWWWWWWWWWWok..",
        "..kkkkkkkkkkk...",
        "................",
    ],
}

PROPS = {
    "chest": [
        "................",
        "................",
        "................",
        "...kkkkkkkkkk...",
        "..kommmmmmmmok..",
        "..kmyooooooymk..",
        "..kmyooooooymk..",
        "..kkkkkkkkkkkk..",
        "..kmyzzkkzzymk..",
        "..knymmkzkmynk..",
        "..knymmmmmmynk..",
        "..knyyyyyyyynk..",
        "..knnnnnnnnnnk..",
        "...kkkkkkkkkk...",
        "................",
        "................",
    ],
    "pot": [
        "................",
        "................",
        ".....kkkkkk.....",
        "....kmoooomk....",
        ".....kmmmmk.....",
        "....kmoooomk....",
        "...kmooommmnk...",
        "..kmoootmmmmnk..",
        "..kmootmmmmmnk..",
        "..kmoommmmmnnk..",
        "..kmmmmmmmmnnk..",
        "...kmmmmmnnnk...",
        "....knnnnnnk....",
        ".....kkkkkk.....",
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
        ".....k343k......",
        "....k34443k.....",
        ".....kkkkk......",
        "................",
    ],
    "rubble": [
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        ".........kkk....",
        "...kkk..k343k...",
        "..k343k.k332k...",
        "..k3322kk222k...",
        "...k221k3kkk....",
        "....kkkk21k.....",
        "........kk......",
        "................",
    ],
}

ICONS = {
    "attack": [
        "................",
        ".kk..........kk.",
        ".kWk........kWk.",
        "..k4k......k4k..",
        "...k4k....k4k...",
        "....k4k..k4k....",
        ".....k4kk4k.....",
        "......k44k......",
        "......k44k......",
        ".....k4kk4k.....",
        "..kkk4k..k4kkk..",
        "..kyyk....kyyk..",
        "...kyk....kyk...",
        "..kmkyk..kykmk..",
        "..kkk.k..k.kkk..",
        "................",
    ],
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
    "tactics": [
        "................",
        "...kk...........",
        "...kmkkkkkkk....",
        "...kmksssssstk..",
        "...kmksssssssk..",
        "...kmkrsssssk...",
        "...kmkrrssssk...",
        "...kmkrrrrrssk..",
        "...kmkkkkkkkkk..",
        "...kmk..........",
        "...kmk..........",
        "...kmk..........",
        "...kmk..........",
        "..kmmmk.........",
        "..kkkkk.........",
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
}


def color(ch: str):
    value = PALETTE[ch]
    if value is None:
        return (0, 0, 0, 0)
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


def sprite(rows: list, name: str) -> Image.Image:
    image = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    assert len(rows) == 16, f"{name}: {len(rows)} rows"
    for y, row in enumerate(rows):
        row = row[:16].ljust(16, ".")
        for x, ch in enumerate(row):
            image.putpixel((x, y), color(ch))
    return image


def sheet(group: dict, columns: int) -> Image.Image:
    names = list(group)
    rows = (len(names) + columns - 1) // columns
    image = Image.new("RGBA", (columns * 16, rows * 16), (0, 0, 0, 0))
    for i, name in enumerate(names):
        image.paste(sprite(group[name], name), ((i % columns) * 16, (i // columns) * 16))
    return image


def rgb(ch: str):
    return color(ch)[:3]


def floor_tile(seed: int) -> Image.Image:
    """A flagstone: two slabs with a lit top-left edge and a dark seam."""
    tile = Image.new("RGBA", (16, 16), color("2"))
    draw = ImageDraw.Draw(tile)
    draw.line([(0, 0), (15, 0)], fill=color("1"))
    draw.line([(0, 0), (0, 15)], fill=color("1"))
    split = 7 + seed % 3
    draw.line([(1, split), (15, split)], fill=color("1"))
    draw.line([(1, 1), (14, 1)], fill=color("3"))
    draw.line([(1, split + 1), (14, split + 1)], fill=color("3"))
    if seed % 4 == 1:
        draw.point([(4, 4), (5, 5), (5, 6), (6, 6)], fill=color("1"))
    if seed % 4 == 3:
        draw.point([(10, 11), (11, 12), (12, 12)], fill=color("1"))
    return tile


def wall_front() -> Image.Image:
    """Brick face: staggered courses, lit upper lip on every brick."""
    tile = Image.new("RGBA", (16, 16), color("1"))
    draw = ImageDraw.Draw(tile)
    for course, y in enumerate((0, 5, 10)):
        offset = 0 if course % 2 == 0 else 4
        for x in range(-8 + offset, 16, 8):
            draw.rectangle([x + 1, y + 1, x + 7, y + 4], fill=color("2"))
            draw.line([(x + 1, y + 1), (x + 6, y + 1)], fill=color("3"))
    draw.line([(0, 15), (15, 15)], fill=color("k"))
    return tile


def wall_top() -> Image.Image:
    """The top of a wall block: one lit slab, bevelled, a few chips."""
    tile = Image.new("RGBA", (16, 16), color("3"))
    draw = ImageDraw.Draw(tile)
    draw.rectangle([0, 0, 15, 15], outline=color("k"))
    draw.line([(1, 1), (14, 1)], fill=color("4"))
    draw.line([(1, 1), (1, 14)], fill=color("4"))
    draw.line([(2, 14), (14, 14)], fill=color("2"))
    draw.line([(14, 2), (14, 14)], fill=color("2"))
    draw.point([(5, 5), (10, 9), (6, 11), (11, 4)], fill=color("2"))
    return tile


def stairs() -> Image.Image:
    """A dark stairwell cut into the wall with three lit treads."""
    tile = wall_front()
    draw = ImageDraw.Draw(tile)
    draw.rectangle([2, 2, 13, 15], fill=color("k"))
    for i, y in enumerate((5, 9, 13)):
        draw.line([(3 + i, y), (12 - i, y)], fill=color("3"))
        draw.line([(3 + i, y + 1), (12 - i, y + 1)], fill=color("1"))
    draw.line([(2, 2), (13, 2)], fill=color("4"))
    return tile


def scale(image: Image.Image, factor: int) -> Image.Image:
    return image.resize((image.width * factor, image.height * factor), Image.NEAREST)


# 7x7 status glyphs and a 3x5 digit font, so the small numbers stay on the grid.
GLYPHS = {
    "heart": [".kk.kk.", "kstkssk", "kssssrk", "kssssrk", ".ksssk.", "..ksk..", "...k..."],
    "drop": ["...k...", "..kck..", ".kccbk.", ".kcbbk.", "kcbbbak", "kbbbaak", ".kkkkk."],
    "mind": [".kkkkk.", "kqqqqpk", "kqkkkqk", "kqkqqqk", "kqkkkpk", ".kqqpk.", "..kkk.."],
}
DIGITS = {
    "0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
    "2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "111", "001", "111"],
    "4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
    "6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"],
    "8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "111"],
    "/": ["001", "001", "010", "100", "100"],
}


def glyph_image(name: str) -> Image.Image:
    rows = GLYPHS[name]
    image = Image.new("RGBA", (7, 7), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            image.putpixel((x, y), color(ch))
    return image


def small(draw, x, y, value, fill):
    for ch in value:
        for dy, row in enumerate(DIGITS[ch]):
            for dx, bit in enumerate(row):
                if bit == "1":
                    draw.point((x + dx, y + dy), fill=fill)
        x += 4


def text(draw, xy, value, fill, font):
    draw.text(xy, value, font=font, fill=fill)


def bar(draw, x, y, w, value, maximum, fill):
    draw.rectangle([x, y, x + w - 1, y + 3], fill=rgb("k"))
    inner = max(0, (w - 2) * value // maximum)
    if inner:
        draw.rectangle([x + 1, y + 1, x + inner, y + 2], fill=fill)


def panel(draw, box, fill="K"):
    x0, y0, x1, y1 = box
    draw.rectangle(box, fill=rgb(fill), outline=rgb("k"))
    draw.line([(x0 + 1, y0 + 1), (x1 - 1, y0 + 1)], fill=rgb("2"))


def gameplay() -> Image.Image:
    """A 176x304 phone screen built only from the sprites above."""
    width, height = 176, 304
    screen = Image.new("RGB", (width, height), rgb("k"))
    draw = ImageDraw.Draw(screen)
    draw.fontmode = "1"
    font = ImageFont.truetype(str(FONT), 12)

    # Header: minimap, floor and turn, food.
    panel(draw, (0, 0, 175, 19))
    draw.rectangle([3, 3, 28, 16], fill=rgb("k"), outline=rgb("2"))
    for x, y in ((6, 6), (10, 6), (14, 6), (14, 10), (18, 10), (22, 10), (22, 13)):
        draw.rectangle([x, y, x + 3, y + 2], fill=rgb("3"))
    draw.rectangle([14, 10, 16, 12], fill=rgb("c"))
    draw.rectangle([22, 13, 24, 15], fill=rgb("s"))
    text(draw, (52, 3), "1층", rgb("W"), font)
    text(draw, (78, 3), "42턴", rgb("z"), font)
    text(draw, (126, 3), "식량 2", rgb("W"), font)

    # Room: 11x9 tiles, walls on the edge, stairs in the top wall.
    top = 20
    cols, rows = 11, 9
    front, cap, down = wall_front(), wall_top(), stairs()
    for ty in range(rows):
        for tx in range(cols):
            x, y = tx * 16, top + ty * 16
            if ty == 0:
                tile = down if tx == 5 else cap
            elif ty == 1:
                tile = down.crop((0, 0, 16, 16)) if tx == 5 else front
                if tx == 5:
                    tile = floor_tile(0)
            elif tx in (0, cols - 1) or ty == rows - 1:
                tile = cap
            else:
                tile = floor_tile(tx * 7 + ty * 3)
            screen.paste(tile, (x, y), tile)
    for tx in (0, cols - 1):
        screen.paste(cap, (tx * 16, top + 16), cap)

    def put(name, group, tx, ty):
        image = sprite(group[name], name)
        screen.paste(image, (tx * 16, top + ty * 16), image)

    put("torch", PROPS, 2, 1)
    put("torch", PROPS, 8, 1)
    put("chest", PROPS, 2, 6)
    put("pot", PROPS, 9, 4)
    put("pot", PROPS, 9, 5)
    put("rubble", PROPS, 3, 3)
    put("rubble", PROPS, 7, 7)
    put("potion_red", ITEMS, 6, 6)
    put("scroll", ITEMS, 4, 7)
    put("hero", SPRITES, 5, 4)
    put("goblin", SPRITES, 8, 3)
    put("skeleton", SPRITES, 6, 5)
    put("rat", SPRITES, 2, 4)
    put("orc", SPRITES, 7, 2)
    for tx, ty, hp in ((8, 3, 9), (6, 5, 6), (2, 4, 12), (7, 2, 13)):
        bar(draw, tx * 16 + 2, top + ty * 16 - 4, 12, hp, 14, rgb("s"))

    # Log: four lines, the newest last.
    log_top = top + rows * 16 + 2
    panel(draw, (0, log_top, 175, log_top + 53))
    lines = [("고블린이 나타났다!", "W"), ("스켈레톤이 나타났다!", "W"),
             ("아린이 한 칸 이동했다.", "c"), ("붉은 물약이 보인다.", "t")]
    for i, (body, tint) in enumerate(lines):
        y = log_top + 3 + i * 12
        text(draw, (4, y), "42", rgb("3"), font)
        text(draw, (22, y), body, rgb(tint), font)

    # Status: portrait, name, HP / MP / stress.
    status_top = log_top + 56
    panel(draw, (0, status_top, 175, status_top + 33))
    draw.rectangle([3, status_top + 3, 28, status_top + 28], fill=rgb("a"), outline=rgb("k"))
    portrait = scale(sprite(SPRITES["hero"], "hero").crop((1, 0, 15, 14)), 1)
    screen.paste(portrait, (8, status_top + 8), portrait)
    text(draw, (33, status_top + 3), "아린", rgb("W"), font)
    text(draw, (33, status_top + 17), "Lv3", rgb("z"), font)
    for row, (glyph, value, maximum, fill, label) in enumerate((
            ("heart", 38, 55, "s", "38/55"), ("drop", 12, 18, "b", "12/18"), ("mind", 8, 100, "q", "8"))):
        y = status_top + 3 + row * 10
        mini = glyph_image(glyph)
        screen.paste(mini, (66, y), mini)
        bar(draw, 76, y + 2, 60, value, maximum, rgb(fill))
        small(draw, 140, y + 1, label, rgb("W"))

    # Actions: five buttons, a coloured face with an icon and a label.
    button_top = status_top + 36
    faces = [("attack", "공격", "s", "r"), ("wait", "대기", "y", "n"), ("search", "탐색", "h", "g"),
             ("tactics", "전술", "q", "p"), ("bag", "가방", "b", "a")]
    for i, (icon, label, face, shade) in enumerate(faces):
        x0 = 1 + i * 35
        x1 = x0 + 33
        draw.rectangle([x0, button_top, x1, height - 2], fill=rgb(face), outline=rgb("k"))
        draw.line([(x0 + 1, button_top + 1), (x1 - 1, button_top + 1)], fill=rgb("W"))
        draw.line([(x0 + 1, height - 3), (x1 - 1, height - 3)], fill=rgb(shade))
        image = sprite(ICONS[icon], icon)
        screen.paste(image, (x0 + 9, button_top + 3), image)
        text(draw, (x0 + 5, button_top + 20), label, rgb("W"), font)
    return screen


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    sheets = {
        "characters": sheet(SPRITES, 5),
        "items": sheet(ITEMS, 4),
        "props": sheet(PROPS, 4),
        "icons": sheet(ICONS, 5),
    }
    tiles = Image.new("RGBA", (64, 16))
    for i, tile in enumerate((floor_tile(0), floor_tile(1), wall_front(), wall_top())):
        tiles.paste(tile, (i * 16, 0))
    stair = stairs()
    tiles_full = Image.new("RGBA", (80, 16))
    tiles_full.paste(tiles, (0, 0))
    tiles_full.paste(stair, (64, 0))
    sheets["tiles"] = tiles_full
    for name, image in sheets.items():
        image.save(OUT / f"{name}.png")

    # Review board: every sheet at 6x on the room's own dark floor colour.
    pad = 8
    board_w = max(image.width for image in sheets.values()) * 6 + pad * 2
    board_h = sum(image.height * 6 + pad for image in sheets.values()) + pad
    board = Image.new("RGBA", (board_w, board_h), color("K"))
    y = pad
    for image in sheets.values():
        big = scale(image, 6)
        board.paste(big, (pad, y), big)
        y += big.height + pad
    board.save(REVIEW / "sprite-sheet-x6.png")

    screen = gameplay()
    screen.save(OUT / "gameplay-176x304.png")
    scale(screen, 4).save(REVIEW / "gameplay-x4.png")


if __name__ == "__main__":
    main()
