#!/usr/bin/env python3
"""One-off rebalance of data/content/attack_wait_effects.json (2026-09-28).
See docs/balance/soulstone-wait-balance.md for the reasons and the probe."""
import json, collections
P = "data/content/attack_wait_effects.json"
d = json.load(open(P), object_pairs_hook=collections.OrderedDict)
E = d["effects"]
changed = []
def edit(effect_id, **kw):
    """kw may itself contain a field called `key`; None removes a field."""
    if effect_id not in E:
        print("missing effect", effect_id); return
    e = E[effect_id]; before = dict(e)
    for k, v in kw.items():
        if v is None: e.pop(k, None)
        else: e[k] = v
    changed.append((effect_id, {k: before.get(k) for k in kw}, kw))

# 1. Purple area statuses: two targets, every other turn (was: everyone in range, every wait).
area = {"fire_wait": ("화상", 3), "poison_wait": ("중독", 3), "ice_wait": ("둔화", 3), "water_wait": ("젖음", 3),
        "hex_wait": ("약화", 3), "air_wait": ("전하", 3), "bleed_wait": ("출혈", 1)}
for key, (word, radius) in area.items():
    edit(key, radius=radius, count=2, cooldown=200, text=f"대기 시 {radius}칸 안 적 2명 {word} · 재사용 2턴")
edit("mental_wait", radius=3, count=1, cooldown=300, text="대기 시 3칸 안 적 1명 혼란 · 재사용 3턴")

# 2. Wait-then-strike: worth giving up an action.
edit("focus_wait", percent=50, text="조준: 대기 후 다음 공격 피해 +50%")
edit("crush_prep", percent=50, text="대기 후 다음 공격 강타 · 피해 +50%·밀치기")
edit("wind_prep", percent=30, text="대기 후 다음 공격 돌풍 · 피해 +30%·밀치기")
# 도마뱀 눈 no longer copies 코볼트 심장: the lizard is the evasion tank.
edit("wind_dodge", op="prepare", key="step", percent=None, mods={"dodge": 20}, text="대기 시 회피 +20")

# 3. Wait defences: a stance should be worth a turn.
for key in ("defense_defense", "vital_defense"):
    edit(key, reduction=30, text="대기 시 받는 피해 30% 감소")
edit("fury_defense", reduction=35, text="대기 시 받는 피해 35% 감소")
for key in ("volley_defense", "evasion_defense", "wind_ranged"):
    edit(key, mods={"dodge": 15}, text="대기 시 회피 +15")
for key in ("wind_defense", "focus_defense"):
    edit(key, mods={"dodge": 20}, text="대기 시 회피 +20")
edit("ice_defense", mods={"armour": 6}, text="대기 시 방어 +6")

# 4. Copies turned into their own thing.
edit("heal_chain", op="heal_ally", key=None, reduction=None, radius=2, heal=5, cooldown=200, combat=True,
     text="대기 시 2칸 안 가장 다친 아군 HP 5 회복 · 재사용 2턴")          # 물의 정령 물방울
edit("water_cleanse", op="ally_guard", key=None, radius=1, reduction=20,
     text="대기 시 곁의 아군 받는 피해 20% 감소")                           # 물의 정령 물살
edit("regen_struck", heal=3, pulses=3, cooldown=400, text="대기 시 큰 재생 · 재사용 4턴")  # 딱정벌레 핵
edit("reflect_kill", op="drain", heal=None, percent=20, cap=5, text="실제 피해 20% 회복 · 최대 5")  # 흡혈 박쥐 심장

json.dump(d, open(P, "w"), ensure_ascii=False, indent=2)
open(P, "a").write("\n")
for key, before, after in changed:
    print(key, before, "->", after)
