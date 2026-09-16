"""Crop/normalize approved transparent equipment; never redraw species bases."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art/sources/fantasy_equipment_overlays_v1"
DEST = ROOT / "assets/fantasy_pawns_v1/equipment"

def main():
    DEST.mkdir(parents=True, exist_ok=True)
    for name in ("leather", "iron_helmet"):
        image = Image.open(SOURCE / f"{name}.png").convert("RGBA")
        alpha = image.getchannel("A")
        assert alpha.getextrema() == (0, 255), f"{name}: transparency missing"
        image = image.crop(alpha.point(lambda v: 255 if v >= 32 else 0).getbbox())
        image.thumbnail((256, 256), Image.Resampling.LANCZOS)
        image.save(DEST / f"{name}.png")

if __name__ == "__main__":
    main()
