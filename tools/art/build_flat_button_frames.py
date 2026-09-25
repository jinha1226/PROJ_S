"""Build crisp 48px nine-slice button frames for the flat dungeon UI."""

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets/ui/button-frames-flat-v1.png"
CELL = 48
SCALE = 4
STATES = [
    ("#232a30", "#58616b"),  # normal
    ("#2b343b", "#84909a"),  # hover
    ("#1a2025", "#72808a"),  # pressed
    ("#1b2024", "#394249"),  # disabled
    ("#332425", "#b87570"),  # danger
    ("#292b2b", "#d2b671"),  # selected
]


def main() -> None:
    sheet = Image.new("RGBA", (CELL * len(STATES), CELL), (0, 0, 0, 0))
    for index, (fill, border) in enumerate(STATES):
        icon = Image.new("RGBA", (CELL * SCALE, CELL * SCALE), (0, 0, 0, 0))
        draw = ImageDraw.Draw(icon)
        draw.rounded_rectangle((3 * SCALE, 3 * SCALE, 45 * SCALE - 1, 45 * SCALE - 1), radius=6 * SCALE, fill="#11161a")
        draw.rounded_rectangle((4 * SCALE, 4 * SCALE, 44 * SCALE - 1, 44 * SCALE - 1), radius=5 * SCALE, fill=border)
        draw.rounded_rectangle((6 * SCALE, 6 * SCALE, 42 * SCALE - 1, 42 * SCALE - 1), radius=3 * SCALE, fill=fill)
        draw.line((9 * SCALE, 8 * SCALE, 39 * SCALE, 8 * SCALE), fill="#39434b" if index < 3 else fill, width=SCALE)
        sheet.alpha_composite(icon.resize((CELL, CELL), Image.Resampling.LANCZOS), (index * CELL, 0))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(OUTPUT)


if __name__ == "__main__":
    main()
