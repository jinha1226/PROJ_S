#!/usr/bin/env python3
"""Idempotently add the attack/wait soulstone display metadata.

The six retaliation preparations are authored as direct STRUCK effects here;
the runtime migration is implemented separately in attack_wait.gd.
"""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data/content/attack_wait_effects.json"
REVIEW = ROOT / "docs/superpowers/plans/2026-09-28-three-colour-review.md"

REACTIONS = {
    "fire_defense",
    "poison_defense",
    "bleed_defense",
    "air_defense",
    "hex_defense",
    "reflect_defense",
}
ELEMENT_ICONS = {
    "bleed": "bleed",
    "poison": "poison",
    "fire": "burn",
    "ice": "freeze",
    "air": "shock",
}
FAMILY_ICONS = {
    "mental": "curse",
    "hex": "curse",
    "death": "curse",
    "water": "wet",
    "rapid": "extra_strike",
    "volley": "extra_strike",
    "focus": "crit",
    "vital": "crit",
    "fury": "crit",
    "evasion": "guard",
    "wind": "push",
    "crush": "push",
    "defense": "guard",
    "bless": "guard",
    "heal": "heal",
    "regen": "heal",
    "reflect": "thorns",
    "summon": "summon",
}
ICON_EXCEPTIONS = {
    "water_air": "shock",
    "water_cleanse": "guard",
    "water_defense": "guard",
    "water_wait": "guard",
    "wind_defense": "guard",
    "wind_ranged": "guard",
    "crush_defense": "guard",
    "evasion_counter": "extra_strike",
    "evasion_hit": "crit",
    "death_wait": "summon",
    "death_chain": "summon",
    "death_defense": "guard",
    "bless_kill": "heal",
    "heal_chain": "guard",
    "summon_defense": "summon",
    "reflect_kill": "heal",
    "fury_kill": "heal",
    "bleed_kill": "heal",
    "hex_death": "curse",
}


def icon_for(key: str, effect: dict) -> str:
    if key in ICON_EXCEPTIONS:
        return ICON_EXCEPTIONS[key]
    op = effect.get("op", "")
    if op == "summon" or op.startswith("pet_"):
        return "summon"
    if op in {"heal_self", "heal_ally", "regen", "drain", "cleanse"}:
        return "heal"
    if op in {"extra"}:
        return "extra_strike"
    if op in {"aim", "attack_prep", "attack_bonus"}:
        return "crit"
    if op in {"ally_guard", "bless"}:
        return "guard"
    family = effect.get("family", "")
    return ELEMENT_ICONS.get(family, FAMILY_ICONS.get(family, ""))


def main() -> None:
    data = json.loads(DATA.read_text(encoding="utf-8"))
    unknown = []
    review_rows = []
    for key, effect in data["effects"].items():
        if key in REACTIONS:
            if effect.get("event") not in {"WAIT", "STRUCK"}:
                raise ValueError(f"retaliation changed unexpectedly: {key}")
            if effect["event"] == "WAIT":
                if not effect.get("reaction"):
                    raise ValueError(f"retaliation has no reaction: {key}")
                effect["event"] = "STRUCK"
                effect["op"] = effect.pop("reaction")
                effect.pop("key", None)
                effect["text"] = effect["text"].replace("대기 후 인접 피격 시", "인접 피격 시").replace(
                    "대기 후 피격 시", "피격 시"
                )
            if key == "fire_defense":
                effect["centre"] = "owner"
            review_rows.append((key, effect["op"], effect["text"]))
        effect["colour"] = {
            "ATTACK": "red", "HIT": "red", "WAIT": "purple", "STRUCK": "green"
        }.get(effect["event"], "")
        effect["icon"] = icon_for(key, effect)
        effect["badge"] = (
            "burst"
            if effect.get("role") == "CHAIN" and effect.get("op") in {"burst", "spread", "status_area", "lightning"}
            else "boost" if effect.get("role") == "CHAIN" else ""
        )
        if not effect["colour"] or not effect["icon"]:
            unknown.append(key)
    if unknown:
        raise ValueError("unmapped effects: " + ", ".join(unknown))
    # These are starting rewards for the new profile; legacy role rewards live
    # in bestiary.gd and are unchanged.
    data["role_stats"] = {
        "red": {"atk": 4},
        "purple": {"atk": 2, "speed": 5},
        "green": {"hp": 20, "ac": 3},
    }
    DATA.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# 3색 영혼석 이전 검토",
        "",
        "2026-09-28 · `tools/migrate_soulstone_colours.py` 출력. 6개 피격 준비 효과를 준비 없이 직접 피격 발동으로 바꾼다.",
        "",
        "| 효과 | 새 연산 | 새 문구 |",
        "| --- | --- | --- |",
    ]
    lines.extend(f"| `{key}` | `{op}` | {text} |" for key, op, text in review_rows)
    lines += [
        "",
        "## 아이콘 의미 확인",
        "",
        "- 물·젖음은 전용 아이콘이 없어서 빙결, `water_air`는 감전을 쓴다. 물 효과의 고유 그림이 필요하면 12개 체계를 확장해야 한다.",
        "- 밀치기(`wind`, `crush`)는 전용 아이콘이 없어서 추가 공격을 쓴다. 방어 준비형은 보호 아이콘을 쓴다.",
        "- `death_wait`·`death_chain`은 실제 해골 소환이므로 저주 대신 소환 아이콘을 쓴다.",
        "- `fire_defense`는 피격 지점 중심 화염막, `reflect_defense`는 실제 받은 피해를 반사한다. 회피·막기 때의 초록 발동을 이 여섯 효과에 자동 적용하지 않는다.",
        "",
        "## 초기 색별 고정 보정",
        "",
        "빨강 공격력 +4, 보라 공격력 +2·행동 속도 +5%, 초록 최대 HP +20·방어 +3. 이 수치는 전투 재측정 전의 임시값이다. 기존 `legacy` 역할 보정은 그대로다.",
        "",
    ]
    REVIEW.write_text("\n".join(lines), encoding="utf-8")
    print(f"migrated {len(data['effects'])} effects; retaliation={len(review_rows)}; unknown={len(unknown)}")


if __name__ == "__main__":
    main()
