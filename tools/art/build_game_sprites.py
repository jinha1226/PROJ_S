"""The sprites the game draws: the south-facing paper-doll cast and monsters.

Party and NPC looks follow `mobile_art.gd`'s ACTOR_IDS, monsters follow its
MONSTER_IDS (the floor_monsters.json species), and bosses follow the boss
`pattern` (0 mire, 1 bomber, 2 giant). Each is rasterised from SVG at 192 px.

Run: python3 tools/art/build_game_sprites.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_flat_cartoon as flat  # noqa: E402
import build_monsters as mon  # noqa: E402

OUT = flat.ROOT / "assets/sprites-v1"
SKIN = {"light": ("#f6c79a", "#e0a574"), "tan": ("#d99a6c", "#bf7f52"), "dark": ("#9a6444", "#7e4f34")}
THIN, STANDARD, HULK = (10.0, 8.5, 0.5, 31, 10.5), (13.0, 11.0, 1.0, 31, 11.0), (17.0, 12.0, 1.0, 30, 11.5)
SHORT = (15.0, 12.5, 1.5, 34, 10.8)

# ACTOR_IDS order: human, dwarf, elf, orc, wolf, mage, merchant, wanderer.
ACTORS = {
    "human": lambda: mon.humanoid("ahuman", "south", STANDARD, SKIN["light"], ("#4f6fb5", "#3e5a97")),
    "dwarf": lambda: mon.humanoid("adwarf", "south", SHORT, SKIN["tan"], ("#8a5a33", "#6f4526"), beard=("#b8642e", "#984f22")),
    "elf": lambda: mon.humanoid("aelf", "south", THIN, SKIN["light"], ("#6b8f4e", "#56763d"), ears="pointy", ear_scale=0.55),
    "orc": lambda: mon.humanoid("aorc", "south", HULK, ("#86a94c", "#6d8e3a"), ("#6a5a48", "#554737"), tusks=True),
    "wolf": lambda: mon.humanoid("awolf", "south", STANDARD, ("#a8acb4", "#8a8f99"), ("#5a4a3a", "#473a2d"),
                                 ears="pointy", ear_scale=0.6, snout=("#8a8f99", "#6f747e")),
    "mage": lambda: mon.humanoid("amage", "south", THIN, SKIN["light"], ("#7a52b0", "#62408f")),
    "merchant": lambda: mon.humanoid("amerchant", "south", STANDARD, SKIN["tan"], ("#b04a3e", "#903a30")),
    "wanderer": lambda: mon.humanoid("awanderer", "south", THIN, SKIN["dark"], ("#8a8f9c", "#707584")),
}
MONSTERS = ["dcss_rat", "dcss_frilled_lizard", "kobold", "goblin", "dcss_hobgoblin", "dcss_orc", "dcss_gnoll", "dcss_river_rat"]
BOSSES = ["boss_mire", "boss_bomber", "boss_giant"]


def main() -> None:
    jobs = []
    for group, entries in (("actors", {k: v() for k, v in ACTORS.items()}),
                           ("monsters", {k: mon.MONSTERS[k][1]("south") for k in MONSTERS}),
                           ("bosses", {k: mon.MONSTERS[k][1]("south") for k in BOSSES})):
        folder = OUT / group
        (folder / "svg").mkdir(parents=True, exist_ok=True)
        for name, body in entries.items():
            source = folder / "svg" / f"{name}.svg"
            source.write_text(body)
            jobs.append((source, folder / f"{name}.png", 3))
    flat.rasterise(jobs)


if __name__ == "__main__":
    main()
