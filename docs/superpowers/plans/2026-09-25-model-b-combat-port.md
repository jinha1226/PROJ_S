# Model B 전투 이식 Implementation Plan

**Goal:** 오토배틀러를 버리고 DCSS식 주인공 수동 조작 + tick 시간 + Model B 전투 수학·사용 기반 숙련을 하강 Run에 이식한다. 동료·NPC는 기존 AI로 자기 차례에 스스로 움직인다.

**Architecture:** 원본(`/mnt/d/SS` 커밋 `47d46b8`, `game/crawl/*.gd`, `data/content/crawl.json`)의 함수를 파일 단위로 옮겨 `Session` 계약에 붙인다. 새로 쓰는 것은 스케줄러 글루(`Kernel.advance` 재사용), `Session.submit`, 파티 전원 적용, 숙련 5×2 화면뿐이다. 원본을 읽는 명령: `git -C /mnt/d/SS show 47d46b8:game/crawl/world.gd` (읽기 전용; `/mnt/d/SS`와 `/mnt/d/SS/new` 작업 트리는 수정하지 않는다).

**Tech Stack:** Godot 4.6 GDScript, 헤드리스 테스트(`godot --headless --path . --script res://tests/<name>.gd`), 임포트 검사(`godot --headless --path . --editor --import --quit`), CI 목록 `.github/workflows/deploy-pages.yml`.

**Spec:** `docs/superpowers/specs/2026-09-25-model-b-combat-port-design.md` (규범). 충돌 시 스펙이 이긴다.

## 구현 중 개정 (2026-09-24)

새 Run(`Session.new_run`)과 아레나는 수동 입력·tick 스케줄러·Model B 전투 수치로 전환한다. 동료와 NPC는 각자의 `ready_at`에 기존 판단기를 호출한다. 기존 자동전투·투자형 성장 코드는 계약 회귀와 과거 시뮬레이터가 아직 참조하므로 이번 이식에서는 호환 경로로 남긴다. 화면에서는 자동전투 버튼을 숨기고 새 Run에서 해당 경로를 호출하지 않는다. 삭제는 회귀 스위트와 시뮬레이터가 `submit`으로 모두 옮겨진 뒤 별도 정리 작업으로 한다.

수치 밸런스는 통과 판정 대신 첫 기준선을 기록한다. 이식 단계의 검증은 새 전투·스케줄러·숙련·주문·화면 입력 테스트와 기존 CI 회귀로 한다. 심부 솔로 조우의 승률은 `docs/balance/model-b-gates.md`에 별도 기록한다.

수동 화면은 후속 플레이 피드백에 따라 바꾼다. 주인공 상태줄과 지도를 중심에 두고 파티 카드·태세 설정·물자 아이콘 줄·전투 재생을 새 Run에서 숨긴다. 적 탭 한 번으로 공격하고, 길게 누르기/우클릭으로 공격 미리보기를 연다. 준비한 주문만 표시하며 아레나는 1인으로 시작한다. 아래의 "적 탭 → 미리보기 → 확정" 절차보다 이 입력 규칙이 우선한다.

## Global Constraints

- Godot 창을 띄우지 않는다. 헤드리스만.
- 전투 AI의 판단 코드(`stances.gd`, `utility.gd`, `lookahead.gd`, `tactical_action_selector.gd`, `parts_candidates.gd`, `tactic_rules.gd`, `npc_ai.gd`, `npc_modes.gd`, `tactics_profiles.json`)는 **§4 재정의(라운드 → tick/구간)와 피해 조회의 함수 교체**(`Growth.power` → `CombatStats`)만 허용한다. 후보 생성·가중치는 바꾸지 않는다.
- 결정론: 모든 굴림은 `Hexaco.sample(seed, lane, name, modulus)`. `RandomNumberGenerator`는 시드 명시 없이 쓰지 않는다.
- 계약 스위트는 지우지 않는다: 삭제가 허용된 스위트는 `autobattle`(→ `companions`로 대체)뿐이다. 다른 파일에서 지운 `check(`마다 같은 파일에 새 흐름 검사를 넣고 Task 6의 표에 before/after를 적는다. 기준 수: stances 113 · utility 154 · parts 338 · protect 38 · skill_rule_conditions 962 · npc_roster 83 · npc_sense 18 · npc_behaviour 57 · recruit 133 · mobile_hud 61 · solo_floor 81.
- 밸런스 수치는 원본 값을 **출발값**으로만 쓴다. 전투 수학이 바뀌므로 옛 승률을 합격선으로 쓰지 않는다(Task 6이 새 기준선을 기록).
- 커밋은 `jinha1226 <jinha1226@gmail.com>`, 트레일러 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## 파일 구조

| 파일 | 책임 | Task |
| --- | --- | --- |
| `data/content/combat.json` (신규) | 무기·방어구·반지·주문·종족·이동 비용·전리품 표 (`crawl.json`에서) | 1, 4 |
| `expedition/combat_stats.gd` (신규) | `stats(s, actor)` 실효값 한 번 계산 | 1 |
| `expedition/combat_rules.gd` (신규) | `attack/damage/move_time`, 명중·방패·AC·브랜드·특성·저항 | 1 |
| `expedition/mastery.gd` (신규) | 축·rank·XP·기여 분배·해금·효과 조회 (Task 1은 `rank` 스텁) | 1, 3 |
| `data/content/mastery.json` (신규) | 10축 보상·융합 (`progression_data.gd`에서), `effect_id` 있는 행만 활성 | 3 |
| `expedition/mastery_effects.gd` (신규) | `sword`·`fire` 이정표 4+4, 융합 2 | 3 |
| `expedition/scheduler.gd` (신규) | `advance(s, cost)`, `act(s, actor)`, 환경 tick | 2 |
| `expedition/spells.gd` (신규) | 학파별 첫 주문 5종 효과·실패율·MP | 4 |
| `expedition/session.gd` | `submit`, `time/turn_serial/ready_at`, 오토배틀 제거, `after_damage`, `on_kill`, 장비·주문 API | 1–4 |
| `expedition/monster_ai.gd`, `boss_ai.gd` | 행동 비용, `resolve_at` 예고 | 2 |
| `expedition/abilities.gd`, `parts_candidates.gd`, `floor_tactics_adapter.gd`, `character_ui.gd` | `Growth.power` → `CombatStats` | 1 |
| `expedition/growth.gd` | 삭제 | 3 |
| `expedition/main.gd`, `battle_hud.gd`, `board.gd` | HUD 정리, 행동 미리보기·경고, 준비 주문, 숙련 그리드, 장비 창 | 2, 5 |
| `expedition/sim/bot_policy.gd`, `encounter_runner.gd` | 봇이 `submit`으로 주인공을 움직임 | 6 |
| `tests/{combat_stats,combat_rules,scheduler,companions,mastery,spells,mastery_ui}.gd` (신규) | §7 | 1–5 |

---

### Task 1: 데이터 · 실효 스탯 · 전투 규칙 (아직 라운드제)

**Files:**
- Create: `data/content/combat.json`, `expedition/combat_stats.gd`, `expedition/combat_rules.gd`, `expedition/mastery.gd`(스텁), `tests/combat_stats.gd`, `tests/combat_rules.gd`
- Modify: `expedition/session.gd`(`make_actor` 장비·MP·`skill_xp`, `act_as` ATTACK, `attack_preview`, `damage` → `after_damage` 분리, `grant_gear`), `expedition/abilities.gd`(`power`), `expedition/parts_candidates.gd`(PUSH 피해), `expedition/floor_tactics_adapter.gd`(`basic_power`), `expedition/character_ui.gd`(상태 탭 문구), `data/content/floor_monsters.json`(`speed/ac/ev/res`), `expedition/continuous_floor.gd mint_enemy`(필드 복사)

**Interfaces:**
- Produces: `CombatStats.stats(s, actor) -> {damage, delay, ac, ev, sh, enc, range, brand, trait, res, power}`; `CombatRules.attack(s, source, target) -> Dictionary{hit: bool, evaded, blocked, damage: int}`; `CombatRules.damage(s, source, target, raw, element) -> int`(실제 감소량); `CombatRules.move_time(s, actor, cell) -> int`; `Mastery.rank(actor, axis) -> int`, `Mastery.AXES`, `Mastery.weapon_axis(weapon_type) -> String`; 액터 필드 `gear = {"weapon":{}, "armour":{}, "shield":{}, "ring":{}}`, `species_id`, `mp/max_mp`, `skill_xp: {axis: int}`, `statuses: {}`; 몬스터 필드 `speed, ac, ev, res`.
- Consumes: `Turns.physical(raw, accuracy_milli, evasion, armor, penetration)`(`sim/turn_engine.gd`), `Hexaco.sample`.

- [ ] **Step 1: `data/content/combat.json`.** `git -C /mnt/d/SS show 47d46b8:data/content/crawl.json`에서 `weapons`(7)·`armours`(4)·`rings`(6)·`spells`(12)·`species`(3) 객체를 그대로 옮기고 다음을 추가한다:

```json
"move_cost": {"stone": 100, "rubble": 120, "water": 140, "wood": 100, "metal": 100},
"loot": {"gear_by_depth": {"1": ["dagger","robe"], "2": ["sword","spear","leather"], "3": ["axe","mace","bow","leather","ring:poison"], "5": ["mail","ring:fire","ring:ice","staff"], "7": ["plate","ring:power","ring:ev"]}},
"kill_xp": {"base": 18, "per_depth": 8}
```

- [ ] **Step 2: 실패하는 테스트 — `tests/combat_stats.gd`**

```gdscript
extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Stats = preload("res://expedition/combat_stats.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func hero(seed: int = 3) -> Dictionary:
	var s = Session.new(seed,false,false,true,1); s.depart(); Fixture.arena(s,8)
	return {"s":s,"h":s.party[0]}

func run() -> void:
	var f := hero(); var s = f.s; var h: Dictionary = f.h
	check(h.gear.weapon.get("type","") == "sword" and h.gear.armour.get("type","") == "robe","the hero starts with a longsword and a robe")
	check(h.species_id == "human" and h.max_mp == 18 and h.mp == 18,"species human: mp 18")
	var st: Dictionary = Stats.stats(s,h)
	check(st.damage == 10+12/6 and st.delay == 120 and st.range == 1 and st.trait == "balanced","sword: damage 10 + str/6, delay 120")
	check(st.ac == 1 and st.ev == 12/3 and st.sh == 0 and st.enc == 0,"robe: ac 1; ev dex/3; no shield")
	h.gear.armour = {"type":"mail","enchant":0}
	st = Stats.stats(s,h)
	check(st.ac == 7 and st.ev == 4-3 and st.enc == maxi(0,7-12/5),"mail: ac +6, ev -3, enc 7 - str/5")
	h.gear.shield = {"type":"shield"}
	check(Stats.stats(s,h).sh == 15 and Stats.stats(s,h).enc == st.enc+2,"shield: 15%% block, +2 enc")
	h.gear.weapon = {"type":"bow","enchant":1}
	st = Stats.stats(s,h)
	check(st.sh == 0 and st.range == 6 and st.trait == "ranged" and st.damage == 9+1+12/6,"a bow ignores the shield, reaches 6, enchant +1")
	h.skill_xp.bow = 25*9 # rank 3
	check(Stats.stats(s,h).damage == st.damage+3 and Stats.stats(s,h).delay == 125-12,"rank 3: damage +3, delay -12")
	h.gear.ring = {"type":"fire"}
	check(int(Stats.stats(s,h).res.get("fire",0)) == 60,"fire ring: 60%% resistance")
	h.statuses = {"ward":true}; check(Stats.stats(s,h).ac == Stats.stats(s,h).ac and Stats.stats(s,h).ac >= 7+6,"ward +6 ac")
	# Everyone goes through the same function: a companion and an npc.
	var t = Session.new(4,true,true,true,3); t.depart()
	check(Stats.stats(t,t.party[1]).damage > 0 and Stats.stats(t,t.npcs[0]).damage > 0,"companions and npcs have stats")
	# Enemies read their catalog fields.
	var foe: Dictionary = s.enemies[0]; foe.hp = 10
	check(Stats.stats(s,foe).ac == int(foe.get("ac",0)) and Stats.stats(s,foe).ev == int(foe.get("ev",3)) and Stats.stats(s,foe).delay == 100,"monster stats come from the catalog fields")
	check(s.enemies.all(func(e): return e.has("speed") and e.has("ac") and e.has("ev") and e.has("res")),"minted enemies carry speed/ac/ev/res")
	print("Combat stats: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
```

- [ ] **Step 3: 실패하는 테스트 — `tests/combat_rules.gd`**

```gdscript
extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Rules = preload("res://expedition/combat_rules.gd")
const Stats = preload("res://expedition/combat_stats.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func duel(seed: int, weapon: String = "sword") -> Dictionary:
	var s = Session.new(seed,false,false,true,1); s.depart(); Fixture.arena(s,8)
	var h: Dictionary = s.party[0]; h.gear.weapon = {"type":weapon,"enchant":0}
	var foe: Dictionary = s.enemies[0]; foe.hp = 40; foe.max_hp = 40; foe.pos = h.pos+Vector2i(1,0); foe.alert = true; foe.ev = 0; foe.ac = 0; foe.res = {}
	s.floor_state.observe(s)
	return {"s":s,"h":h,"foe":foe}

func run() -> void:
	# Determinism: same seed, same outcome.
	var a := duel(11); var b := duel(11)
	check(Rules.attack(a.s,a.h,a.foe).damage == Rules.attack(b.s,b.h,b.foe).damage,"deterministic attack")
	# Evasion band: ev 20 → 40% dodge over 100 seeds.
	var dodged := 0
	for seed in range(100):
		var d := duel(100+seed); d.foe.ev = 20
		if Rules.attack(d.s,d.h,d.foe).evaded: dodged += 1
	check(dodged >= 25 and dodged <= 55,"ev 20 dodges about 40%% (%d/100)" % dodged)
	# Shield: 15% block after the dodge check.
	var blocked := 0
	for seed in range(100):
		var d := duel(300+seed); d.foe.ev = 0; d.foe["sh"] = 15
		if Rules.attack(d.s,d.h,d.foe).blocked: blocked += 1
	check(blocked >= 5 and blocked <= 28,"sh 15 blocks about 15%% (%d/100)" % blocked)
	# AC absorbs 0..ac; pierce halves it.
	var totals := {"sword":0,"mace":0}
	for seed in range(60):
		for w in totals:
			var d := duel(500+seed,w); d.foe.ac = 10
			totals[w] += Rules.attack(d.s,d.h,d.foe).damage
	check(totals.mace > totals.sword,"pierce (mace) beats ac 10 more often than a sword")
	# Cleave hits a second adjacent foe.
	var c := duel(700,"axe"); var other: Dictionary = c.s.enemies[1]; other.hp = 40; other.max_hp = 40; other.pos = c.h.pos+Vector2i(0,1); other.ev = 0; other.ac = 0; other.res = {}; c.s.floor_state.observe(c.s)
	Rules.attack(c.s,c.h,c.foe)
	check(other.hp < 40,"axe cleaves the neighbour")
	# Fire brand adds fire damage, resisted by the ring.
	var e := duel(800); e.h.gear.weapon = {"type":"sword","brand":"fire"}; e.foe.ev = 0
	var hp: int = e.foe.hp; Rules.attack(e.s,e.h,e.foe); var plain: int = hp-e.foe.hp
	var g := duel(800); g.h.gear.weapon = {"type":"sword","brand":"fire"}; g.foe.ev = 0; g.foe.res = {"fire":100}
	hp = g.foe.hp; Rules.attack(g.s,g.h,g.foe)
	check(plain > hp-g.foe.hp,"fire resistance removes the brand's extra damage")
	# damage() routes to after_damage: stress, memory, npc death, kills and drops still happen.
	var k := duel(900); k.foe.hp = 1
	var score: int = k.s.score
	Rules.damage(k.s,k.h,k.foe,5,"physical")
	check(k.foe.hp == 0 and k.s.score > score,"a kill still scores through after_damage")
	# Session.act_as("ATTACK") and attack_preview use the same math.
	var p := duel(950); var preview: Dictionary = p.s.attack_preview(p.foe.pos)
	check(preview.has("hit") and preview.has("damage_min") and preview.has("damage_max") and preview.has("time") and preview.time == Stats.stats(p.s,p.h).delay,"preview reports hit%%, damage range and time")
	var before: int = p.foe.hp; p.h.ap = 1
	check(p.s.act_as(p.h,"ATTACK",p.foe.pos,false),"attack executes")
	check(p.foe.hp == before or (before-p.foe.hp >= preview.damage_min and before-p.foe.hp <= preview.damage_max),"real damage inside the preview range (or dodged)")
	# move_time: water is slower, minimum 40.
	var m := duel(960); var wet: Vector2i = m.h.pos+Vector2i(-1,0); m.s.tile(wet).terrain = "water"
	check(Rules.move_time(m.s,m.h,wet) == 140 and Rules.move_time(m.s,m.h,m.h.pos+Vector2i(0,-1)) == 100,"water 140, stone 100")
	print("Combat rules: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
```

- [ ] **Step 4: 실패 확인** (두 스위트 모두 preload 실패로 끝나야 한다).

- [ ] **Step 5: `expedition/mastery.gd` 스텁**

```gdscript
extends RefCounted
## Use-based mastery: ten axes, rank 0..10 from xp. Task 3 fills the rest.
const AXES := ["sword","spear","mace","axe","bow","fire","ice","air","hex","summon"]
const NAMES := {"sword":"검술","spear":"창술","mace":"둔기술","axe":"도끼술","bow":"궁술","fire":"화염술","ice":"냉기술","air":"기류술","hex":"변이·제어","summon":"소환술"}
static func weapon_axis(weapon_type: String) -> String:
	match weapon_type:
		"sword","dagger": return "sword"
		"spear": return "spear"
		"mace","staff": return "mace"
		"axe": return "axe"
		"bow": return "bow"
	return "sword"
static func rank(actor: Dictionary, axis: String) -> int:
	return clampi(int(sqrt(float(int(actor.get("skill_xp",{}).get(axis,0)))/25.0)),0,10)
static func next_xp(rank_value: int) -> int:
	return 25*(rank_value+1)*(rank_value+1)
```

- [ ] **Step 6: `expedition/combat_stats.gd`** — 원본 `world.stats` 복사 후 스펙 §1의 수정. 골격:

```gdscript
extends RefCounted
const Mastery = preload("res://expedition/mastery.gd")
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/combat.json"))
static func species(actor: Dictionary) -> Dictionary: return content.species.get(str(actor.get("species_id","human")),content.species.human)
## Effective numbers for anyone: hero, companion, npc, monster. One place, one order:
## catalog → gear → species → mastery → statuses.
static func stats(s, actor: Dictionary) -> Dictionary:
	var r := {"damage":int(actor.get("power",7)),"delay":100,"ac":int(actor.get("ac",0)),"ev":int(actor.get("ev",3)),"sh":int(actor.get("sh",0)),"enc":0,"range":1,"brand":"","trait":"","res":actor.get("res",{}).duplicate(),"power":0}
	if not actor.get("enemy",false):
		var spec := species(actor); var gear: Dictionary = actor.get("gear",{})
		r.damage = 0; r.ac = 0; r.ev = 0
		var w: Dictionary = content.weapons.get(str(gear.get("weapon",{}).get("type","")),{})
		if not w.is_empty():
			var axis := Mastery.weapon_axis(str(gear.weapon.type)); var rk := Mastery.rank(actor,axis)
			r.damage = int(w.damage)+int(gear.weapon.get("enchant",0))+rk+int(spec.str)/6
			r.delay = maxi(60,int(w.delay)-rk*4); r.range = int(w.range); r.trait = str(w.trait); r.brand = str(gear.weapon.get("brand",""))
			if w.trait == "focus": r.power += 4
		else:
			r.damage = 4+int(spec.str)/6   # unarmed
		var ar: Dictionary = content.armours.get(str(gear.get("armour",{}).get("type","")),{})
		if not ar.is_empty():
			r.ac += int(ar.ac)+int(gear.armour.get("enchant",0)); r.enc = maxi(0,int(ar.enc)-int(spec.str)/5); r.ev -= int(ar.ev_penalty)
		r.ev += int(spec.dex)/3
		if not gear.get("shield",{}).is_empty() and r.trait not in ["ranged","focus"]: r.sh = 15; r.enc += 2
		var ring: Dictionary = content.rings.get(str(gear.get("ring",{}).get("type","")),{})
		if not ring.is_empty():
			if ring.stat in ["ev","power"]: r[ring.stat] += int(ring.value)
			else: r.res[ring.stat] = int(ring.value)
	var st: Dictionary = actor.get("statuses",{})
	if st.has("ward"): r.ac += 6
	if st.has("rage"): r.damage += 8
	if st.has("corrode"): r.ac = maxi(0,r.ac-4)
	return r
```

원본의 `skill_rank("defense")/`survival`` 항은 축이 없어졌으므로 뺀다(스펙 §5.3: 방어 축 없음). 몬스터는 `power`(현행 `ROLES[role].damage`를 `mint_enemy`가 `power`로 복사)·`speed`·`ac`·`ev`·`res`를 카탈로그에서 받는다.

- [ ] **Step 7: `expedition/combat_rules.gd`** — 원본 `attack/damage/movement_time` 복사 후 스펙 §1의 수정:

```gdscript
extends RefCounted
const Stats = preload("res://expedition/combat_stats.gd")
const Turns = preload("res://sim/turn_engine.gd")
static func roll(s, source: Dictionary, lane: String, modulus: int) -> int:
	return s.Hexaco.sample(s.seed_value,int(s.get("time",s.world_time))*7+int(source.id),lane,modulus)
static func attack(s, source: Dictionary, target: Dictionary) -> Dictionary:
	var out := {"hit":false,"evaded":false,"blocked":false,"damage":0}
	if target.hp <= 0: return out
	var offense := Stats.stats(s,source); var defense := Stats.stats(s,target)
	if roll(s,source,"dodge",100) < clampi(int(defense.ev)*2,5,45): out.evaded = true; s.message(target.name+" 회피"); return out
	if roll(s,source,"block",100) < int(defense.sh): out.blocked = true; s.message(target.name+" 방패 방어"); return out
	var raw: int = int(offense.damage)
	if offense.trait == "stab" and (target.get("statuses",{}).has("confuse") or not target.get("alert",true)): raw *= 2
	var ac: int = int(defense.ac)/2 if offense.trait == "pierce" else int(defense.ac)
	var physical: Dictionary = Turns.physical(raw,950,0,roll(s,source,"absorb",ac+1))
	out.hit = true; out.damage = damage(s,source,target,int(physical.damage),"physical")
	if source.hp <= 0 or target.hp <= 0: return out
	match str(offense.brand):
		"fire","ice": out.damage += damage(s,source,target,4,str(offense.brand))
		"venom": if int(defense.res.get("poison",0)) < 100: target.statuses["poison"] = int(s.get("time",0))+300
		"drain": source.hp = mini(int(source.max_hp),int(source.hp)+3)
	if offense.trait == "cleave":
		for a in s.party+s.npcs+s.enemies:
			if a.id != target.id and a.hp > 0 and bool(a.get("enemy",false)) != bool(source.get("enemy",false)) and s.melee_reach(source.pos,a.pos): damage(s,source,a,maxi(1,raw/2-int(Stats.stats(s,a).ac)),"physical")
	return out
## Resistances, then the session's own bookkeeping (stress, memories, npc death, kills, drops).
static func damage(s, source: Dictionary, target: Dictionary, raw: int, element: String) -> int:
	if target.hp <= 0 or raw <= 0: return 0
	var amount: int = raw
	if element != "physical": amount = maxi(0,raw*(100-int(Stats.stats(s,target).res.get(element,0)))/100)
	return s.after_damage(target,amount,int(source.get("id",999)),element)
static func move_time(s, actor: Dictionary, cell: Vector2i) -> int:
	var value: int = maxi(int(actor.get("speed",100)),int(Stats.content.move_cost.get(str(s.tile(cell).terrain),100)))
	var st: Dictionary = actor.get("statuses",{})
	if st.has("slow"): value = value*3/2
	if st.has("haste"): value = value*2/3
	return maxi(40,value)
```

- [ ] **Step 8: `session.gd` 접합.**
- `make_actor`: 파티원에 `"species_id":"human","gear":{"weapon":{},"armour":{},"shield":{},"ring":{}},"mp":18,"max_mp":18,"skill_xp":{},"statuses":{},"spells":[],"prepared":[]`; `hp/max_hp`는 종족 `hp`(인간 72 → **현행 55 유지**: 스펙 §0.6 "출발값"이므로 종족 HP는 Task 6 재측정 전까지 55로 두고 `combat.json.species.human.hp`를 55로 고쳐 둔다). `depart()`에서 주인공에 `gear.weapon = {"type":"sword","enchant":0}`, `gear.armour = {"type":"robe","enchant":0}`. NPC(`npc_roster.generate`)에도 같은 필드와 시작 무기(스펙 §6: X ≥ 600 → axe/mace, C ≥ 600 → spear/bow, else sword).
- `damage(target, amount, source, form)`의 본문을 **`after_damage(target, amount, source, form) -> int`**로 이름을 바꾸고(스트레스·기억·NPC 사망·점수·드롭·`on_hit` 인터럽트·`noise`는 그대로), 기존 `damage()`는 `return CombatRules.damage(self, actor_by_id(source), target, amount, form)`로 남긴다(호출처 호환: 불·독·파츠는 이 경로).
- `act_as` ATTACK 분기(506행): `TurnCore.physical(Growth.power(...))` → `var r := CombatRules.attack(self,actor,victim)`; 원거리 무기(`Stats.stats(actor).range > 1`)는 `distance ≤ range`와 `MonsterAI.line` 사선 검사로 `melee_reach` 대신. `attack_preview`(440행): `{"hit": 100-clampi(ev*2,5,45)... , "block": sh, "damage_min": raw*(...)...}` — 명중% = `100 − dodge% − block%`, 피해 범위 = `[max(0, raw − ac), raw]`(관통이면 ac/2), `time = delay`.
- `abilities.power(s, actor, def)`: `s.Growth.power(actor,def.axis,int(def.damage))` → `int(def.damage) + (Mastery.rank(actor, "bow") if def.axis == "RANGED" else Mastery.rank(actor,"hex") if def.axis == "MAGIC" else Mastery.rank(actor, Mastery.weapon_axis(str(actor.get("gear",{}).get("weapon",{}).get("type","sword")))))`; 적은 `int(def.damage)`. `parts_candidates` PUSH 피해와 `floor_tactics_adapter.basic_power`는 `Stats.stats(s,actor).damage`. `character_ui` 상태 탭은 `Stats.stats` 값(피해·지연·AC·EV)을 표시. `session.damage`의 `Growth.incoming` 줄 삭제(AC가 대신).
- `floor_monsters.json` 8종에 `speed/ac/ev/res`(스펙 §1 매핑) 추가; `mint_enemy`가 복사하고 `power = ROLES[role].damage`.
- `grant_gear(item: Dictionary)`: `gear_bag.append(item)`(가방; 장착은 Task 4).

- [ ] **Step 9: 실행.** `combat_stats`, `combat_rules`, 그리고 `stances`(113)·`utility`(154)·`parts`(338)·`protect`(38)·`skill_rule_conditions`(962)·`autobattle`(108)·`npc_*`·`recruit`·`arena_mode`·`solo_floor`·`mobile_hud`. 수치가 바뀌어 깨지는 검사는 **기대값이 옛 `Growth.power(18)`에 묶인 것만** 새 수학으로 고치고 보고서에 목록을 적는다(검사 삭제 금지).

- [ ] **Step 10: 커밋** `feat(combat): Model B effective stats and attack rules for everyone; gear, mp and mastery fields`

---

### Task 1b: 모임 화면 · 종족 · 시작 장비 (명부 30명)

**Files:**
- Modify: `expedition/npc_roster.gd`(`COUNT := 30`, `DUOS := 6`, 종족·무기 배정), `expedition/session.gd`(`begin_run(species_id, kit_id)`; `depart()`는 그대로 1층 진입), `data/content/combat.json`(`kits` 표), `expedition/main.gd`(`GatherScreen`), `data/content/npc_names.json`(이름 40개로)
- Test: `tests/gather.gd`(신규), `tests/npc_roster.gd`(30명·6쌍으로 갱신, 검사 수 유지)

**Interfaces:**
- Produces: `combat.json.kits`(스펙 §6 표: `{id, axis, weapon, spell}`), `Session.begin_run(species_id, kit_id) -> bool`(IDLE에서만; 주인공 `species_id`·`gear.weapon`·`gear.armour = robe`·(마법 kit이면) `spells/prepared`에 첫 주문·HP/MP를 종족값으로, 그 뒤 `depart()`), `NpcRoster.kit_for(profile, seed_lane) -> String`, 노드 `GatherScreen/GatherToken%d/SpeciesPick/KitPick/Descend`.
- 판정: 종족 HP는 T1의 55 고정을 유지하되 종족 간 차이는 원본 비율로 스케일(인간 55, 드워프 66, 엘프 43; MP 18/12/26).

- [ ] **Step 1: 실패하는 테스트 — `tests/gather.gd`**: `Session.new` 직후 `phase == "IDLE"`, `roster.size() == 30`, 2인 조 6쌍, 종족 3종 모두 등장, 무기 10종 모두 등장(시드 5개 합쳐서), 마법 무기 NPC는 `spells.size() == 1 and prepared == spells`; `begin_run("dwarf","axe")` → 주인공 `species_id dwarf`, `gear.weapon.type == "axe"`, `max_hp 66`, `depth == 1`, `phase == "EXPLORE"`; `begin_run("elf","fire")` → `spells == ["bolt"]`, `prepared == ["bolt"]`, `mp == 26`; 잘못된 id 거부; 씬: `GatherScreen`에 토큰 31개, `SpeciesPick`·`KitPick` 선택 후 `Descend` → HUD; 결과 화면 `NewRun` → 다시 `GatherScreen`.
- [ ] **Step 2: 구현.** `npc_roster.generate`가 `species_id`(시드)·kit(성격 가중, 스펙 §6)을 배정하고 `gear/spells/prepared`를 채운다. `main.gd`: `new_run()` → 세션 생성만(IDLE) + `GatherScreen`; `Descend` 버튼이 `begin_run`. 토큰 탭 → 기존 NPC 팝업 재사용(영입 버튼 없이). 배치(`place`)는 30명 중 3~5명이므로 `UNMET` 우선 규칙 그대로.
- [ ] **Step 3: 실행·커밋** `feat(run): the gathering — thirty on the roster, species and starting kit chosen before floor one`

---

### Task 2: tick 스케줄러 · `Session.submit` · 오토배틀 제거 · 라운드 재정의

**Files:**
- Create: `expedition/scheduler.gd`, `tests/scheduler.gd`, `tests/companions.gd`
- Modify: `expedition/session.gd`, `monster_ai.gd`, `boss_ai.gd`, `abilities.gd`(쿨다운 tick), `tactic_rules.gd`·`lookahead.gd`(`resolve_at`), `stances.gd`·`npc_modes.gd`·`npc_recruit.gd`·`npc_ai.gd`(§4 lane·tick), `main.gd`(HUD), `sim/bot_policy.gd`, `tests/floor_fixture.gd`, 라운드를 세는 기존 스위트
- Delete: `tests/autobattle.gd`

**Interfaces:**
- Produces: `s.time: int`(tick), `s.turn_serial: int`(주인공 행동 번호), 액터 `ready_at`, `Session.submit(kind: String, target: Vector2i, value: String = "") -> bool`, `Session.action_cost(actor, kind, target, value) -> int`, `Scheduler.advance(s, cost)`, `Scheduler.act(s, actor)`, `Scheduler.double_movers(s, cost) -> Array`(경고용), `intents[].resolve_at`, `Fixture.hero_turn(s, kind, target)`.
- `submit`은 입력 유효성을 먼저 확인한 뒤 `Scheduler.flush_ready(s)`로 현재 tick에 이미 준비된 환경·액터를 순서대로 해소한다. 끝 시각에 준비된 행동을 다음 주인공 행동보다 늦게 처리하면 한 번의 무료 선공이 생기므로, `flush_ready`는 유효한 입력 직전에만 실행한다. `tests/scheduler.gd`는 `WAIT 100 → 다음 입력`에서 tick 100 적이 먼저 행동하는 경우도 검사한다.
- Removes: `auto`, `auto_step`, `auto_stop_reason`, `remember_round`, `command_choice`, `party_command`, `command_target`, `end_battle_orders`, `reservation_*`, `round_number`(→ `turn_serial`), `ap`(→ `ready_at`), `action_budget`, `end_round`(→ `Scheduler.environment_tick`), HUD의 `AutoToggle/SpeedToggle/RetreatToggle/StopBanner`.

- [ ] **Step 1: 실패하는 테스트 — `tests/scheduler.gd`**

```gdscript
extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Scheduler = preload("res://expedition/scheduler.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func field(seed: int, party: int = 1) -> Dictionary:
	var s = Session.new(seed,party > 1,party > 1,true,party); s.depart(); var c := Fixture.arena(s,10)
	Fixture.equip_basics(s)
	return {"s":s,"c":c,"h":s.party[0]}

func foe_at(s, p: Vector2i, speed: int = 100) -> Dictionary:
	var foe: Dictionary = s.enemies.filter(func(e): return e.hp <= 0)[0]
	foe.hp = 30; foe.max_hp = 30; foe.pos = p; foe.alert = true; foe.role = "MELEE"; foe.speed = speed; foe.ready_at = s.time+speed; foe.charging = false; foe.cast_recovery = 0; foe.part_id = ""
	s.floor_state.observe(s); return foe

func run() -> void:
	timing(); fast_slow(); two_enemies(); telegraph(); companions_turn(); camp_freezes(); stops(); determinism(); warning()
	print("Scheduler: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func timing() -> void:
	var f := field(1); var s = f.s
	check(s.time == 0 and s.turn_serial == 0 and s.party[0].ready_at == 0,"fresh run at tick 0")
	check(s.submit("WAIT",f.h.pos) and s.time == 100 and s.turn_serial == 1 and f.h.ready_at == 100,"a wait costs 100")
	var wet: Vector2i = f.h.pos+Vector2i(1,0); s.tile(wet).terrain = "water"
	check(s.submit("MOVE",wet) and s.time == 240,"stepping into water costs 140")

func fast_slow() -> void:
	# A dagger (75) lets the hero swing before a speed-100 foe answers; a mace (145) lets it answer once.
	var f := field(2); var s = f.s; var h: Dictionary = f.h; var foe := foe_at(s,h.pos+Vector2i(1,0))
	h.gear.weapon = {"type":"dagger"}; var hp: int = h.hp
	s.submit("ATTACK",foe.pos)
	check(s.time == 75 and h.hp == hp,"dagger: 75 ticks, the foe has not acted yet")
	s.submit("ATTACK",foe.pos)
	check(s.time == 150 and h.hp < hp,"second dagger swing: the foe acted once at tick 100")
	var g := field(3); var t = g.s; var m: Dictionary = g.h; var foe2 := foe_at(t,m.pos+Vector2i(1,0)); m.gear.weapon = {"type":"mace"}
	var hp2: int = m.hp; t.submit("ATTACK",foe2.pos)
	check(t.time == 145 and m.hp < hp2,"mace: 145 ticks, the foe answered once")

func two_enemies() -> void:
	var f := field(4); var s = f.s; var h: Dictionary = f.h
	var a := foe_at(s,h.pos+Vector2i(1,0),100); var b := foe_at(s,h.pos+Vector2i(-1,0),50)
	b.ready_at = s.time # 이미 준비된 적은 [현재 시각, 행동 종료) 안에서 두 번 행동한다.
	h.gear.weapon = {"type":"mace"}
	var hp: int = h.hp; s.submit("ATTACK",a.pos)
	check(h.hp < hp and b.ready_at >= 200,"an already-ready foe acts at ticks 0 and 100 during a 145-tick attack")

func telegraph() -> void:
	var f := field(5); var s = f.s; var h: Dictionary = f.h; var foe := foe_at(s,h.pos+Vector2i(2,0))
	foe.role = "CASTER"; foe.charging = true; foe.cast_id = ""; foe.cast_cell = h.pos; foe.cast_left = 2
	s.plan_enemies()
	var intent: Dictionary = s.intents.filter(func(i): return i.id == foe.id)[0]
	check(intent.has("resolve_at") and intent.resolve_at == s.time+200,"a two-turn telegraph resolves at +200")
	check(s.Rules.lethal_threat(s,h) < 14,"not a threat for this turn yet")
	s.submit("WAIT",h.pos)
	check(s.Rules.lethal_threat(s,h) >= 14,"next turn it is")

func companions_turn() -> void:
	var f := field(6,3); var s = f.s; var h: Dictionary = f.h
	var foe := foe_at(s,s.party[1].pos+Vector2i(1,0))
	var hp: int = foe.hp; s.submit("WAIT",h.pos)
	check(foe.hp < hp,"a companion acts on its own during the hero's wait")
	check(s.party[1].ready_at > 0,"the companion's ready_at advanced by its action cost")

func camp_freezes() -> void:
	var f := field(7); var s = f.s; s.food = 3
	var t0: int = s.time; check(s.camp() and s.end_camp() and s.time == t0,"camping does not spend time")

func stops() -> void:
	var f := field(8); var s = f.s; var h: Dictionary = f.h
	var far: Vector2i = h.pos+Vector2i(6,0)
	check(s.start_route(far),"route planned")
	var foe := foe_at(s,h.pos+Vector2i(8,0)); foe.alert = false
	var steps := 0
	while s.route_step() and steps < 10: steps += 1
	check(s.phase == "BATTLE" and s.distance(h.pos,foe.pos) <= 5 and not s.route_active(),"auto-walk stops the exact action a foe comes into view")

func determinism() -> void:
	var a := field(9,3); var b := field(9,3)
	for i in range(6): a.s.submit("WAIT",a.h.pos); b.s.submit("WAIT",b.h.pos)
	check(a.s.log_lines == b.s.log_lines and a.s.time == b.s.time,"same seed and inputs replay identically")

func warning() -> void:
	var f := field(10); var s = f.s; var h: Dictionary = f.h; var foe := foe_at(s,h.pos+Vector2i(1,0),60)
	h.gear.weapon = {"type":"mace"}
	var movers: Array = Scheduler.double_movers(s,s.action_cost(h,"ATTACK",foe.pos,""))
	check(movers.size() == 1 and movers[0].id == foe.id,"a 145-tick swing lets a speed-60 foe act twice: warned")
```

- [ ] **Step 2: 실패하는 테스트 — `tests/companions.gd`** (autobattle 대체; 검사 수 ≥ 108 목표는 Task 6 표에서 확인). 내용: 동료가 자기 차례에 `Tactics.choose`로 행동(태세별 3장면), 명령이 없음(`party_command` 없음), 실수 판정이 `turn_serial` lane으로(같은 시드 재현), 후퇴선(HP 낮은 동료가 스스로 물러남), `battle_stats`가 `turn_serial` 차이로 라운드를 셈, 기존 `autobattle.gd`의 `stats()`·`formation()`·`knobs()` 검사 이식(자동 진행 관련 검사만 제외하고 같은 수 이상).

- [ ] **Step 3: 실패 확인.**

- [ ] **Step 4: `expedition/scheduler.gd`** — 원본 `world.advance` 글루 + 스펙 §3:

```gdscript
extends RefCounted
const Kernel = preload("res://sim/combat_kernel.gd")
const Rules = preload("res://expedition/combat_rules.gd")
const Tactics = preload("res://expedition/tactical_action_selector.gd")
const NpcAI = preload("res://expedition/npc_ai.gd")
const BOUNDARY := 100
static func actors(s) -> Array:
	return s.party.slice(1).filter(func(a): return a.hp > 0)+s.npcs.filter(func(n): return n.hp > 0 and n.awake)+s.enemies.filter(func(e): return e.hp > 0)
static func advance(s, cost: int) -> void:
	var end: int = s.time+cost
	s.party[0].ready_at = end
	Kernel.advance(end,func(limit: int) -> Dictionary:
		var best: Dictionary = {}
		if s.phase == "DEFEAT": return best
		if s.boundary <= limit: best = {"at":s.boundary,"id":-1}
		for a in actors(s):
			if int(a.get("ready_at",0)) >= limit: continue
			best = Kernel.earlier(best,maxi(s.time,int(a.get("ready_at",0))),int(a.id),limit)
		return best,
		func(event: Dictionary) -> bool:
			s.time = int(event.at)
			if int(event.id) == -1: environment_tick(s); s.boundary += BOUNDARY
			elif s.phase != "DEFEAT": act(s,s.actor_by_id(int(event.id)))
			return true)
	s.time = end
	if s.boundary <= s.time: s.boundary = (s.time/BOUNDARY+1)*BOUNDARY
	s.turn_serial += 1
	s.floor_state.observe(s)
	for npc in s.npcs: if npc.hp > 0: NpcAI.sense(s,npc)
	s.noise.clear()
	s.check_battle_end()
static func act(s, actor: Dictionary) -> void:
	if actor.is_empty() or actor.hp <= 0: return
	var cost := 100
	if actor.get("enemy",false):
		cost = s.Floor.MonsterAI.turn(s,actor)          # returns the cost it spent
	elif s.wanderer(actor):
		cost = NpcAI.turn(s,actor)                        # returns cost
	else:
		var choice: Dictionary = Tactics.choose(s,actor)
		s.perform(actor,choice)                           # act_as without chaining
		cost = s.action_cost(actor,str(choice.get("kind","WAIT")),choice.get("cell",actor.pos),"")
		s.note_explain(actor,choice); if str(choice.get("mistake","")) != "": s.note_mistake(actor,str(choice.mistake))
	actor.ready_at = s.time+maxi(40,cost)
static func environment_tick(s) -> void:
	# fire/wet decay and burn damage (moved from end_round), status expiry, part cooldowns −100, stress +2 while the party sees a foe
static func double_movers(s, cost: int) -> Array:
	var out: Array = []
	for e in s.party_enemies():
		var c: int = s.action_cost(e,"ATTACK",e.pos,"")
		if int(e.get("ready_at",0))+c < s.time+cost: out.append(e)
	return out
```

- [ ] **Step 5: `session.gd`.** `var time := 0`, `var boundary := 100`, `var turn_serial := 0`; `make_actor`에 `"ready_at":0`, `ap` 삭제. 새 적의 첫 `ready_at`은 `time + speed`, 기상한 NPC는 `ready_at = maxi(ready_at,time)`으로 보정한다. 스케줄 대상은 `[time,time+cost)`이며 끝 시각의 행동은 다음 구간으로 넘긴다. `double_movers`는 `ready_at + action_cost < time + cost`일 때 경고한다. `submit(kind, target, value)`: 검증·실행은 `act_as`(chain 없음), 비용은 `action_cost`(스펙 §2 표; ATTACK은 `Stats.stats().delay`, MOVE는 `CombatRules.move_time`, 파츠는 `def.get("delay",100)`, 느림/빠름 배율), 마지막에 `Scheduler.advance(self,cost)`. INTERACT(조사물·계단·NPC 대화)는 100, 하강·야영은 시간 정지. `auto_step/auto_stop_reason/remember_round/command_choice/companion_choice/reservation_*/end_battle_orders/action_budget/end_round/party_command/command_target/auto` 삭제; `end_round`의 불·물 tick과 쿨다운 감소는 `Scheduler.environment_tick`으로; `plan_enemies`는 그대로. `perform(actor, choice)`는 `act_as(actor,kind,cell,false)` 실패 시 WAIT. 경로 이동: `start_route(goal)/route_step()/route_active()`(기존 `exploration_navigation`을 세션 API로 감싸고, 한 `route_step`은 `submit("MOVE")` 한 번 = 정확히 한 행동; 시야에 적·NPC·조사물·계단이 들어오면 `route_step`이 false).
- `advance`는 `[time,end)`만 처리한다. `submit`이 유효한 입력으로 판정한 후, 실제 주인공 행동 전에 `flush_ready`가 `time`에 도달한 환경·액터를 처리한다. 환경 경계가 액터보다 우선이고 같은 시각 액터는 id 순서다. 무효 입력은 `flush_ready`도 호출하지 않는다.
- `monster_ai.turn`이 **비용을 반환**: 이동 `move_time`, 공격 100(역할 `delay`가 있으면 그것), 시전 100, 대기 100. `cast_left`는 tick(`cast_left·100`)으로: `plan()`이 `resolve_at = time + cast_left_ticks`를 intents에 넣고, `turn()`은 `time ≥ resolve_at`일 때 해소. `boss_ai`도 같은 방식(`fuse`).
- `tactic_rules.lethal_threat`·`lookahead.threat_after`: 예고는 `resolve_at <= s.time + 100`인 것만 이번 구간 위협.
- §4 lane·tick 치환: `stances.mistaken` lane `depth*100000 + turn_serial*100 + id`; `npc_recruit` lane 같음; `npc_modes` `COMMIT_ROUNDS` → `COMMIT_TICKS := 1000`(비교는 `s.time`); `npc_ai.SLEEP_AFTER` → 500 tick; `Recruit.COOLDOWN` → 2000 tick; `abilities` 쿨다운은 tick(`cooldown*100`, 환경 tick에서 −100); `battle_stats.rounds` = `turn_serial` 차이.
- `main.gd`: `auto_tick/toggle_auto/toggle_speed/toggle_retreat/check_stop/note_stop/StopBanner` 삭제; 탭 = `submit`; 적 탭 → `preview_attack`(명중%·피해 범위·시간·`double_movers` 경고 문구 "느린 행동: OO이 두 번 움직입니다") → 확정. `battle_hud.gd` 결과 카드는 유지.
- `sim/bot_policy.gd`·`encounter_runner.gd`: 봇은 `Tactics.choose(s, hero)`로 고른 행동을 `submit`한다(주인공을 AI가 조종하는 시뮬 모드 — 동료 AI를 주인공에 적용). `Fixture.fight_round(s)` → `Fixture.hero_turn(s)`(같은 방식 한 행동).

- [ ] **Step 6: 실행.** `scheduler`, `companions`, `stances`(113 — 라운드 lane 바뀐 검사는 `turn_serial`로 기대값 재도출), `utility`(154), `npc_sense`(18; 5라운드 → 500 tick), `npc_behaviour`(57), `recruit`(133; 쿨다운 tick), `parts`, `protect`, `skill_rule_conditions`, `companion_tactics`, `encounter_sim`, `arena_mode`, `solo_floor`, `mobile_hud`, `ui_smoke`, `integration`, `playthrough`, `boss_floor`, `camping`, `floor_descent`. 지운 검사와 새 검사를 보고서 표로.

- [ ] **Step 7: 커밋** `feat(time): tick scheduler and Session.submit; the hero acts by hand, companions on their own; auto-battle removed`

---

### Task 3: 사용 기반 숙련 10축

**Files:**
- Create: `data/content/mastery.json`, `expedition/mastery_effects.gd`, `tests/mastery.gd`
- Modify: `expedition/mastery.gd`(전체), `expedition/session.gd`(`on_kill`, 사용 기록, `after_damage`), `expedition/combat_rules.gd`·`spells.gd`(효과 훅), `expedition/character_ui.gd`(숙련 탭 데이터만; 그리드는 Task 5), `expedition/npc_roster.gd`(NPC 개인 XP 유지)
- Delete: `expedition/growth.gd`(호출처 전부 제거: `session.gd` 873/884행 레벨·투자, `character_ui` 투자 카드)

**Interfaces:**
- Produces: `Mastery.add_xp(s, actor, axis, base) -> int`, `Mastery.record(actor, enemy_id, axis)`, `Mastery.award(s, enemy_id, kill_xp)`, `Mastery.unlocked(actor, axis) -> Array[{level, name, effect_id}]`, `Mastery.fusions(actor) -> Array`, `Mastery.aptitude(actor, axis) -> int`, `Mastery.catchup(actor, axis) -> bool`; `MasteryEffects.on_attack(s, source, target, result)`, `on_dodge(s, actor, attacker)`, `on_spell_hit(s, caster, target, school)`, `damage_bonus(s, actor) -> int`; `Session.on_kill(target, source_id)`; 액터 `level, level_xp`(HP/MP만).

- [ ] **Step 1: `data/content/mastery.json`.** `git -C /mnt/d/SS show 47d46b8:game/crawl/progression_data.gd`의 `LEVEL_REWARDS`(10축 × 10 이름)와 `FUSIONS`를 JSON으로. 각 축 배열의 원소는 `{"level": n, "name": "...", "effect_id": ""}`; `sword` Lv3/5/7/10에 `deep_cut/riposte/combo/swordmaster`, `fire` Lv3/5/7/10에 `ember/flare/heat/inferno`; 융합 `sword_fire`·`fire_sword`에 `effect_id`(각각 `flame_edge`, `blade_dance`), 나머지는 `""`. `"thresholds": "25*(r+1)^2"`, `"catchup_levels": 2`.

- [ ] **Step 2: 실패하는 테스트 — `tests/mastery.gd`**: rank 공식(0/25/100/225 → 0/1/2/3; 2500 → 10 상한), `next_xp`, 적성(`elf` `melee 75` → sword XP 75%), 기여 분배(두 파티원이 3:1로 교전한 적 처치 → `18+depth·8`을 3:1로, 각자 축 비율로; 합계 정확, 한 번만), 허공 공격은 기록 없음, 따라잡기(새 축 Lv1·2 요구 절반, 무료 이전 없음), NPC 개인 XP(파티 밖 처치 → 명부 행에 유지 → 영입 후 그대로), `sword` 4효과와 `fire` 4효과 각각 동작·이중 적용 없음, `sword_fire`(공격 +4 화염, tier2 +8)·`fire_sword`(주문 명중 인접 검 피해 절반), 효과 없는 행은 `unlocked`에 없음, `growth.gd` 부재(`ResourceLoader.exists("res://expedition/growth.gd") == false`), 레벨 XP는 HP/MP만.

- [ ] **Step 3: 구현.** `usage_world.gd`의 `add_skill_xp/record_usage/award_usage_xp/refresh_unlocks/fusion_tier/aptitude_for`를 캐릭터별로 옮긴다(스펙 §1 표). `CombatRules.attack`가 명중·회피·방패 어느 경우든 `Mastery.record(source, target.id, axis)`; `after_damage`에서 처치 시 `on_kill(target, source)` → `Mastery.award(self, target.id, kill_xp)`(교전 기록이 있는 파티원·NPC 전원). 파츠 사용은 축 규칙(§5.2). `MasteryEffects`는 `CombatRules.attack` 안의 두 훅과 `Spells`의 한 훅에서만 호출. `growth.gd` 삭제와 호출처 정리; 레벨은 `level_xp` 누적으로 `max_hp += 4, max_mp += 2`.

- [ ] **Step 4: 실행·커밋** `feat(mastery): ten use-based axes with contribution XP; sword and fire milestones; two fusions; growth removed`

---

### Task 4: 주문 · 장비 드롭 · 야영 장착

**Files:**
- Create: `expedition/spells.gd`, `tests/spells.gd`
- Modify: `expedition/session.gd`(`cast`, `equip_gear/unequip_gear`, `prepare_spell`, `gear_bag`), `expedition/curios.gd`·`data/content/exploration_curios.json`(장비·주문서 결과), `expedition/boss_ai.gd`(보스 드롭에 주문서), `data/content/combat.json`(`loot`), `expedition/abilities.gd`(파츠와 주문의 HUD 구분은 Task 5)

**Interfaces:**
- Produces: `Spells.cast(s, caster, id, target) -> bool`, `Spells.failure(s, caster, id) -> int`, `Spells.cells(s, caster, id, target) -> Array`; 활성 주문은 학파별 하나 `bolt/cone/cloud/confuse/hound`(시작 장비가 요구); `Session.cast(id, target)`(주인공, 비용 100), `Session.equip_gear(index, item) / unequip_gear(index, slot)`(CAMP에서만), `Session.prepare_spell(index, id, on: bool)`(CAMP, 최대 3), 액터 `spells/prepared/mp`.

- [ ] **Step 1: 실패하는 테스트 — `tests/spells.gd`**: `bolt`(fire, 단일, 사거리 6, 화염 16, MP 3), `cone`(ice, 부채꼴 3칸 냉기 피해 + `slow`), `cloud`(air, 반경 1 구름 3턴, 전기 피해), `confuse`(hex, 상태 `confuse`, 저항 `will`), `hound`(summon, 아군 소환수 1, 300 tick 지속 — 소환수는 `s.npcs`가 아니라 `s.summons`에, `friends()`에 포함); 실패율 공식(`8 + level·9 + enc·5 − rank·5 − INT`, 0~85)과 실패 시 MP만 소비; MP 부족 거부; 준비 3개 상한·야영에서만 변경; 주문서 획득(`DEAD_ADVENTURER` 20%, 보스 100%)으로 `spells` 증가; 장비 획득(`BROKEN_CHEST` 50% → `gear_bag`), 야영에서 장착·해제·양손/방패 금지; 몬스터 `res`로 저항.

- [ ] **Step 2: 구현.** 원본 `world.cast/spell_cells/failure` 복사 후 `DATA` → `combat.json`, `rng` → `Hexaco.sample`, 시전자 일반화(동료·NPC도 `prepared`가 있으면 `Tactics`의 파츠 후보처럼 — **이번 Task에서는 주인공만** 시전; 동료 시전은 범위 밖). 조사물 결과에 `gear`/`spellbook` 확률 필드. `equip_gear`는 `Stats.stats`의 양손/방패 규칙을 검증.

- [ ] **Step 3: 실행·커밋** `feat(spells): five spells with mp and failure; gear and spellbooks drop; equipment changes at camp`

---

### Task 5: 모바일 UI — 행동 미리보기 · 준비 주문 · 숙련 5×2 · 장비 창

**Files:**
- Create: `tests/mastery_ui.gd`
- Modify: `expedition/main.gd`, `expedition/character_ui.gd`, `expedition/battle_hud.gd`, `expedition/board.gd`(적 탭 미리보기 표시)

**Interfaces:**
- 노드: `ActionPreview`(명중%·피해 범위·시간·경고 줄, `ConfirmAttack`), `SpellBar`(`Spell%d` ×3), `MasteryGrid`(`MasteryIcon_<axis>` ×10, rank 숫자·진행 바), `MasteryDetail`(`MasteryLevel%d` ×10, `[획득]/[다음]/[잠김]`, `MasteryBack`), `GearScreen`(야영: 슬롯 4, `GearOption%d`, 현재 대비 Δ피해·Δ시간·ΔAC·ΔEV·Δ저항 표시, `GearEquip`), `PrepareScreen`(주문 준비 토글). 상세의 Lv1~10은 모든 축에서 현재·다음 rank의 공통 수치 보정(무기 피해/지연 또는 주문 위력/실패율)을 보여준다. 고유 효과 ID가 없는 레벨은 빈 보상 행만 숨긴다.

- [ ] **Step 1: 실패하는 테스트 — `tests/mastery_ui.gd`**: 씬 인스턴스 → 새 Run → 적 탭 시 `ActionPreview`에 명중·피해·시간 문구, 느린 무기면 경고 문구; `SpellBar`에 준비 주문 3개만; 캐릭터 → 숙련 탭에 아이콘 10개, 탭 → 모든 축의 상세 Lv1~10에 수치 보정·상태 표시, 효과 ID가 없는 고유 보상 행 비표시, 뒤로 → 같은 캐릭터 그리드; 야영 화면에 `GearScreen`, 후보 장비의 Δ표시, 장착 반영; 320·390px 폭에서 잘림 없음(각 아이콘 ≥ 44px 터치); 같은 입력에 창 두 번 열리지 않음.

- [ ] **Step 2: 구현.** 숙련은 5×2 그리드, 버튼 최소 논리 폭 52px·높이 64px·간격 6px로 둔다. Godot의 `canvas_items` 축소 뒤에도 320px 물리 화면에서 버튼 폭 44px 이상이어야 한다. 미리보기는 `attack_preview`와 `Scheduler.double_movers`만 읽는다(별도 계산 없음). `character_ui.mastery()`의 4축 투자 카드를 새 Run 경로에서 교체.

- [ ] **Step 3: 실행·커밋** `feat(ui): action preview with timing warning, spell bar, mastery grid and detail, camp gear screen`

---

### Task 6: 게이트 재측정 · 문서 · CI

**Files:**
- Modify: `.github/workflows/deploy-pages.yml`(` combat_stats combat_rules scheduler companions mastery spells mastery_ui` 추가, `autobattle` 제거), `docs/balance/model-b-gates.md`(신규), `docs/balance-method.ko.md`, `README.md`, `docs/superpowers/specs/2026-09-25-model-b-combat-port-design.md`(상태), `tests/solo_balance.gd`·`stance_gate.gd`·`ranged_probe.gd`·`encounter_sim.gd`·`skill_value.gd`·`action_economy.gd`(봇 `submit` 경로 확인)

- [ ] **Step 1: 시뮬 봇.** `encounter_runner`가 주인공을 `Tactics.choose`+`submit`으로 움직이는지 확인(Task 2), 결과에 `time`·`turn_serial` 기록.
- [ ] **Step 2: 기준선.** 종족 HP 55(현행)와 원본 72 두 설정으로 `solo_balance`·`stance_gate`·`ranged_probe`·`encounter_sim`을 돌려 `model-b-gates.md`에 표로 기록. 합격선은 정하지 않고 "다음 튜닝 라운드의 출발값"으로 명시. 명백한 지배·사장 선택지(예: 단검이 항상 이김)는 기록.
- [ ] **Step 3: 테스트 이주 표.** 모든 스위트의 before/after `check(` 수. `autobattle`(108) ↔ `companions`(≥ 108).
- [ ] **Step 4: 문서.** README·balance-method에 수동 조작·tick·숙련을 반영; 스펙 상태 "구현됨".
- [ ] **Step 5: 전체 CI + 임포트 통과. 커밋** `docs(balance): Model B combat baselines; CI list; test migration table`

---

## 자기 검토

- 스펙 커버리지: §0 결정(T1 수학·데이터, T1b 모임·종족·시작 장비, T2 오토배틀 제거·tick·구간, T3 숙련, T4 주문·드롭, T5 UI, T6 게이트) / §1.0 모임(T1b) / §1 이식표(T1·T2·T3·T4) / §2 비용표(T2) / §3 접합(T2) / §4 재정의표(T2) / §5 숙련(T3·T5) / §6 장비·주문(T4·T5) / §7 검증(T1~T6) / §8 순서(그대로).
- 이름 일관성: `CombatStats.stats`, `CombatRules.attack/damage/move_time`, `Session.after_damage/on_kill/submit/action_cost/perform/start_route/route_step/route_active/cast/equip_gear/unequip_gear/prepare_spell`, `Scheduler.advance/act/environment_tick/double_movers/actors`, `Mastery.AXES/NAMES/weapon_axis/rank/next_xp/add_xp/record/award/unlocked/fusions/aptitude/catchup`, `MasteryEffects.on_attack/on_dodge/on_spell_hit/damage_bonus`, `Spells.cast/failure/cells`, 액터 `gear/species_id/mp/max_mp/skill_xp/statuses/spells/prepared/ready_at/level/level_xp`, `s.time/boundary/turn_serial/gear_bag`, `intents[].resolve_at`.
- 위험: T2가 가장 크다(라운드 제거가 8개 스위트와 시뮬 봇에 닿음). T2 Step 5의 "삭제 목록"은 한 번에 지우지 말고 `submit` 경로가 초록이 된 뒤 지운다. T1에서 HP 55/종족 72 충돌은 55로 고정하고 T6이 비교한다. 동료 시전(주문)은 범위 밖으로 명시했다.
