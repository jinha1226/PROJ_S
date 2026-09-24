"""Build exact 48 px, nearest-neighbour 9-slice button frames and a review sheet."""

from pathlib import Path
from PIL import Image, ImageColor, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
FRAME = 48
MARGIN = 10
STATES = [
    ("기본", "#0a0c0e", "#68492b", "#b48346", "#443018", "#1b1b1b", "#252321"),
    ("강조", "#0a0c0e", "#a87839", "#f1bd68", "#71471d", "#29211a", "#3b2b1d"),
    ("누름", "#080a0d", "#654026", "#b77b3e", "#d29b54", "#15171a", "#27201c"),
    ("비활성", "#0b0d10", "#3d4144", "#686b69", "#34383b", "#1b1d20", "#222428"),
    ("위험", "#0a0b0d", "#7c4333", "#d37d55", "#4b2923", "#221a1a", "#34201d"),
    ("선택", "#090b0e", "#ae7b39", "#ffd078", "#724a22", "#2a2118", "#3b2b1b"),
]


def inside(x: int, y: int, inset: int) -> bool:
    u = min(x - inset, FRAME - 1 - inset - x)
    v = min(y - inset, FRAME - 1 - inset - y)
    return u >= 0 and v >= 0 and (u + v >= 5 if u < 5 and v < 5 else True)


def make_frame(colors: tuple[str, ...], state: int) -> Image.Image:
    outline, border, light, shade, fill, upper = [ImageColor.getrgb(color) + (255,) for color in colors]
    img = Image.new("RGBA", (FRAME, FRAME))
    pixels = img.load()
    for y in range(FRAME):
        for x in range(FRAME):
            if not inside(x, y, 0):
                continue
            if not inside(x, y, 2):
                color = outline
            elif not inside(x, y, 5):
                upper_edge = min(y, x) <= min(FRAME - 1 - y, FRAME - 1 - x)
                color = light if upper_edge != (state == 2) else border
            elif not inside(x, y, 7):
                color = shade if y > FRAME // 2 or x > FRAME // 2 else border
            elif not inside(x, y, 9):
                color = outline
            else:
                color = upper if y < 14 else fill
            pixels[x, y] = color
    draw = ImageDraw.Draw(img)
    # Four square metal pins belong entirely to the fixed 10 px corners.
    for x in (5, 41):
        for y in (5, 41):
            draw.rectangle((x, y, x + 1, y + 1), fill=light if state != 3 else border)
            draw.point((x + 1, y + 1), fill=shade)
    return img


def nine_slice(frame: Image.Image, width: int, height: int) -> Image.Image:
    out = Image.new("RGBA", (width, height))
    m = MARGIN
    slices = [
        ((0, 0, m, m), (0, 0, m, m)),
        ((m, 0, FRAME - m, m), (m, 0, width - m, m)),
        ((FRAME - m, 0, FRAME, m), (width - m, 0, width, m)),
        ((0, m, m, FRAME - m), (0, m, m, height - m)),
        ((m, m, FRAME - m, FRAME - m), (m, m, width - m, height - m)),
        ((FRAME - m, m, FRAME, FRAME - m), (width - m, m, width, height - m)),
        ((0, FRAME - m, m, FRAME), (0, height - m, m, height)),
        ((m, FRAME - m, FRAME - m, FRAME), (m, height - m, width - m, height)),
        ((FRAME - m, FRAME - m, FRAME, FRAME), (width - m, height - m, width, height)),
    ]
    for source, target in slices:
        part = frame.crop(source).resize((target[2] - target[0], target[3] - target[1]), Image.Resampling.NEAREST)
        out.alpha_composite(part, (target[0], target[1]))
    return out


def main() -> None:
    frames = [make_frame(state[1:], index) for index, state in enumerate(STATES)]
    sheet = Image.new("RGBA", (FRAME * len(frames), FRAME))
    for index, frame in enumerate(frames):
        sheet.alpha_composite(frame, (FRAME * index, 0))
    asset = ROOT / "assets/ui/button-frames-8bit-v2.png"
    sheet.save(asset)

    preview = Image.new("RGBA", (402, 190), "#111315")
    draw = ImageDraw.Draw(preview)
    font = ImageFont.truetype(str(ROOT / "assets/fonts/Galmuri11.ttf"), 13)
    for index, (name, *_colors) in enumerate(STATES):
        x = 6 + (index % 3) * 132
        y = 8 + (index // 3) * 72
        preview.alpha_composite(nine_slice(frames[index], 122, 46), (x, y))
        draw.text((x + 33, y + 14), name, font=font, fill="#e9d3aa")
    for index, label in enumerate(("공격", "대기", "탐색", "전술", "가방")):
        x = 6 + index * 79
        preview.alpha_composite(nine_slice(frames[0], 74, 44), (x, 144))
        draw.text((x + 20, 156), label, font=font, fill="#e9d3aa")
    enlarged = preview.resize((preview.width * 2, preview.height * 2), Image.Resampling.NEAREST)
    enlarged.save(ROOT / "docs/mockups/button-frames-8bit-v2-preview.png")


if __name__ == "__main__":
    main()
