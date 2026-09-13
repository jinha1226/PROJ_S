"""Build a balance reference from a local DCSS checkout; no runtime code is imported.

Usage: python3 tools/build_dcss_balance_catalog.py --source /tmp/dcss-balance-source-0341 \
    --item-properties /tmp/dcss-0.34.1/item-prop.cc
Requires PyYAML. Numeric reference entries are not automatically enabled content.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import yaml

SOURCE_COMMIT = "1eebc1a2892e1c89776a0d7a10691f8dac8d9796"
ACTIVE_SPECIES = {"goblin", "kobold"}
WEAPON_MAP = {
    "short sword": "SHORT_SWORD", "rapier": "THRUSTING_SWORD",
    "hand axe": "HAND_AXE", "mace": "MACE", "spear": "SPEAR",
    "shortbow": "BOW", "arbalest": "CROSSBOW",
}


def build(source, item_properties):
    actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
    if actual != SOURCE_COMMIT:
        raise ValueError("DCSS checkout must be the pinned 0.34.1 commit")
    monsters = []
    for path in sorted((source / "crawl-ref/source/dat/mons").glob("*.yaml")):
        if path.stem.startswith("TEST"):
            continue
        row = yaml.safe_load(path.read_text())
        if not isinstance(row, dict) or not isinstance(row.get("name"), str):
            raise ValueError(f"Invalid monster definition: {path}")
        facts = {key: row[key] for key in ["hd", "hp_10x", "ac", "ev", "speed", "exp", "will", "will_per_hd", "resists", "spells", "energy", "flags", "uses"] if key in row}
        # Only numeric melee values and their categorical effects, not behavior implementations.
        facts["attacks"] = [{key: attack[key] for key in ["type", "damage", "flavour"] if key in attack}
                            for attack in row.get("attacks") or []]
        monsters.append({"id": path.stem, "name": row["name"], "source": str(path.relative_to(source)),
                         "reference": facts, "game_species_id": path.stem if path.stem in ACTIVE_SPECIES else None,
                         "status": "adapted_existing" if path.stem in ACTIVE_SPECIES else "reference_only"})
    text = item_properties.read_text()
    weapons = []
    seen = set()
    for match in re.finditer(r'\{\s*(WPN_\w+),\s*"([^"]+)",\s*(-?\d+),\s*(-?\d+),\s*(\d+)\s*,', text):
        enum, name, damage, accuracy, delay = match.groups()
        if enum in seen:
            raise ValueError(f"Duplicate weapon reference: {enum}")
        seen.add(enum)
        weapons.append({"id": enum, "name": name, "reference": {"base_damage": int(damage), "accuracy_bonus": int(accuracy), "delay_aut": int(delay)},
                        "source": "crawl-ref/source/item-prop.cc", "game_weapon_id": WEAPON_MAP.get(name),
                        "status": "adapted_existing" if name in WEAPON_MAP else "legacy_reference" if name.startswith("old ") else "reference_only"})
    armors = []
    for match in re.finditer(r'\{\s*(ARM_\w+),\s*"([^"]+)",\s*(\d+),\s*(-?\d+),\s*(\d+)\s*,', text):
        enum, name, ac, ev_penalty, price = match.groups()
        armors.append({"id": enum, "name": name, "reference": {"ac": int(ac), "encumbrance": abs(int(ev_penalty)) // 10},
                       "source": "crawl-ref/source/item-prop.cc", "status": "reference_only"})
    # Macro-generated dragon armor is outside the explicit-entry parser; mark coverage precisely.
    if not monsters or not weapons:
        raise ValueError("Source definitions were not found")
    return {"reference_version": 1, "source_tag": "0.34.1", "source_commit": SOURCE_COMMIT,
            "source_url": "https://github.com/crawl/crawl/tree/0.34.1", "runtime_enabled": False,
            "coverage": {"monsters": "All named monster YAML definitions, excluding TEST fixtures; includes cant_spawn and special forms.",
                         "weapons": "All explicit weapon table entries; old entries classified as legacy references.",
                         "armor": "Explicit numeric armor table entries only; macro-generated dragon armor excluded."},
            "counts": {"monsters": len(monsters), "weapons": len(weapons), "armor_explicit": len(armors)},
            "monsters": monsters, "weapons": weapons, "armor_explicit": armors}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--item-properties", required=True, type=Path)
    parser.add_argument("--output", type=Path, default=Path("data/reference/dcss-0.34.1-catalog.json"))
    args = parser.parse_args()
    catalog = build(args.source, args.item_properties)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(catalog["counts"]))


if __name__ == "__main__":
    main()
