#!/usr/bin/env python3
"""One-off change to data/content/attack_wait_effects.json (2026-09-28):
green (struck) conversions, the wait-effect rebalance, the two new icons and
a stale text. Reasons and the probe: docs/balance/soulstone-wait-balance.md.

    python3 tools/rebalance_attack_wait_2026_09_28.py

Idempotent: every edit sets absolute values.
"""
import json, collections
P = "data/content/attack_wait_effects.json"
d = json.load(open(P), object_pairs_hook=collections.OrderedDict)
E = d["effects"]
changed = []


def edit(effect_id, **kw):
    """kw may itself contain a field called `key`; None removes a field."""
    if effect_id not in E:
        raise SystemExit("missing effect " + effect_id)
    e = E[effect_id]; before = {k: e.get(k) for k in kw}
    for k, v in kw.items():
        if v is None: e.pop(k, None)
        else: e[k] = v
    changed.append((effect_id, before, kw))


GREEN = dict(event="STRUCK", colour="green")

# 1. Green: defences that should switch on when struck, not when waiting.
#    "Until my next action" guards refresh rather than stack, so several hits
#    in one enemy round do not pile them up; heals keep a cooldown.
edit("defense_defense", **GREEN, op="prepare", key="stance", reduction=30, icon="guard",
     text="맞으면 내 다음 행동까지 받는 피해 30% 감소")                               # 고블린 방패병 팔뼈
edit("vital_defense", **GREEN, op="prepare", key="guard", reduction=30, icon="guard",
     text="맞으면 내 다음 행동까지 받는 피해 30% 감소")                               # 도마뱀 꼬리(의지 변형)
edit("ice_defense", **GREEN, op="prepare", key="ice_armour", mods={"armour": 6}, icon="guard",
     text="맞으면 내 다음 행동까지 방어 +6")                                         # 바위 딱정벌레 껍질
edit("regen_struck", **GREEN, op="regen", heal=2, pulses=3, cooldown=300, combat=True, icon="heal",
     text="맞으면 재생 · 재사용 3턴")                                                # 바위 딱정벌레 핵
edit("crush_defense", **GREEN, op="prepare", key="steadfast", push_resist=True, icon="guard",
     text="맞으면 내 다음 행동까지 밀리지 않음")                                     # 바위 딱정벌레 날개
edit("evasion_defense", **GREEN, outcomes=["dodge"], op="prepare", key="step_guard", mods={"dodge": 15}, icon="guard",
     text="피하면 내 다음 행동까지 회피 +15")                                        # 코볼트 가죽
edit("wind_ranged", **GREEN, op="prepare", key="gust_guard", mods={"dodge": 15}, icon="guard",
     text="맞으면 내 다음 행동까지 회피 +15")                                        # 망령 기사 핵
edit("wind_defense", **GREEN, op="prepare", key="wind_wall", mods={"dodge": 20}, icon="guard",
     text="맞으면 내 다음 행동까지 회피 +20")                                        # 망령 기사 갑주(전기 변형)
edit("fury_defense", **GREEN, op="attack_prep", key="rage", percent=30, reduction=None, icon="crit",
     text="맞으면 다음 공격 피해 +30%")                                              # 오크 심장
edit("wind_dodge", **GREEN, outcomes=["dodge"], op="attack_prep", key="counter_eye", percent=30, icon="crit",
     text="피하면 다음 공격 피해 +30%")                                              # 목도리 도마뱀 눈
edit("death_defense", **GREEN, op="prepare", key="bone_share", share=25, needs_pet=True, icon="summon",
     text="맞을 때 소환수가 있으면 내 다음 행동까지 피해 25% 분담")                    # 해골 병사 갈비뼈
edit("reflect_defense", text="맞으면 받은 피해 30% 반사")                           # 망령 기사 갑주: stale "대기 후"

# 2. Purple area statuses: two targets, every other turn (was: everyone in range, every wait).
area = {"fire_wait": ("화상", 3), "poison_wait": ("중독", 3), "ice_wait": ("둔화", 3), "water_wait": ("젖음", 3),
        "hex_wait": ("약화", 3), "air_wait": ("전하", 3), "bleed_wait": ("출혈", 1)}
for key, (word, radius) in area.items():
    edit(key, radius=radius, count=2, cooldown=200, text=f"대기 시 {radius}칸 안 적 2명 {word} · 재사용 2턴")
edit("mental_wait", radius=3, count=1, cooldown=300, text="대기 시 3칸 안 적 1명 혼란 · 재사용 3턴")

# 3. Wait-then-strike worth an action.
edit("focus_wait", percent=50, text="조준: 대기 후 다음 공격 피해 +50%")
edit("crush_prep", percent=50, icon="push", text="대기 후 다음 공격 강타 · 피해 +50%·밀치기")
edit("wind_prep", percent=30, icon="push", text="대기 후 다음 공격 돌풍 · 피해 +30%·밀치기")

# 4. Waiting ranged cover a little wider.
edit("volley_defense", mods={"dodge": 15}, text="대기 시 회피 +15")                 # 해골 궁수 등뼈
edit("focus_defense", mods={"dodge": 20}, text="대기 시 회피 +20")                   # 고블린 궁수 눈

# 5. Copies turned into their own thing.
edit("heal_chain", op="heal_ally", key=None, reduction=None, radius=2, heal=5, cooldown=200, combat=True, icon="heal",
     text="대기 시 2칸 안 가장 다친 아군 HP 5 회복 · 재사용 2턴")                    # 물의 정령 물방울
edit("water_cleanse", op="ally_guard", key=None, radius=1, reduction=20,
     text="대기 시 곁의 아군 받는 피해 20% 감소")                                   # 물의 정령 물살
edit("reflect_kill", op="drain", heal=None, percent=20, cap=5, text="실제 피해 20% 회복 · 최대 5")  # 흡혈 박쥐 심장

# 6. The two new icons: water and knockback.
for key in ("water_hit", "water_wait"):
    edit(key, icon="wet")
for key in ("wind_hit", "crush_hit"):
    edit(key, icon="push")

json.dump(d, open(P, "w"), ensure_ascii=False, indent=2)
open(P, "a").write("\n")
for key, before, after in changed:
    print(key, before, "->", after)
