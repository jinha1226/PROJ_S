#!/usr/bin/env python3
"""Small deployment gate plus tests for changed modules; full checks are opt-in."""
import argparse
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
ALL = (ROOT / "tools/ci/full-suites.txt").read_text().split()
CORE = ["run_start", "ui_smoke", "mobile_hud", "layout_guard"]
LINKS = {
    "session": ["run_start", "start_kit", "attack_wait", "attack_wait_ui"],
    "start_screen": ["start_kit", "attack_wait_ui"],
    "stone_drop": ["stone_drop", "stone_drop_ui"],
    "stone_drop_card": ["stone_drop_ui"],
    "status_vfx": ["effect_vfx"],
    "battle_actor_visual": ["effect_vfx"],
    "attack_wait_effects": ["attack_wait", "attack_wait_ui"],
    "attack_wait": ["attack_wait", "attack_wait_ui"],
    "essence_tab": ["essence_ui"],
    "essence_summary": ["essence_ui"],
    "gear": ["gear_slots", "part_drops", "stone_drop"],
    "equipment": ["gear_slots"],
    "descent": ["floor_descent"],
    "camp": ["camping"],
    "combat": ["combat_basics"],
    "combat_rules": ["combat_basics"],
    "combat_stats": ["combat_basics"],
    "statuses": ["effect_vfx", "stats_resist"],
    "floor_monsters": ["monster_roles"],
    "tactical_action_selector": ["companion_tactics"],
}


def select(paths, full=False):
    if full:
        return ALL.copy()
    selected = set(CORE)
    for name in paths:
        path = Path(name)
        if path.suffix not in {".gd", ".json"}:
            continue
        stem = path.stem
        if stem in ALL:
            selected.add(stem)
        selected.update(LINKS.get(stem, []))
    return [name for name in ALL if name in selected]


def changed_paths(before):
    if not re.fullmatch(r"[0-9a-f]{40}", before):
        raise ValueError("Expected a commit SHA")
    # Checkout stays shallow; fetch just the previous push tip when necessary.
    if subprocess.run(["git", "cat-file", "-e", before + "^{commit}"],
                      cwd=ROOT, stdout=subprocess.DEVNULL,
                      stderr=subprocess.DEVNULL).returncode:
        subprocess.run(["git", "fetch", "--no-tags", "--depth=1", "origin", before],
                       cwd=ROOT, check=True)
    return subprocess.check_output(
        ["git", "diff", "--name-only", "--no-renames", before, "HEAD"],
        cwd=ROOT, text=True).splitlines()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--full", action="store_true")
    parser.add_argument("--before", default="")
    parser.add_argument("paths", nargs="*")
    args = parser.parse_args()
    paths = args.paths
    if args.before and args.before != "0" * 40 and not args.full:
        paths += changed_paths(args.before)
    suites = select(paths, args.full or args.before == "0" * 40)
    if any(not (ROOT / "tests" / (name + ".gd")).is_file() for name in suites):
        raise SystemExit("Selected suite does not exist")
    print(" ".join(suites))
