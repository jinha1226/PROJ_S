# 공격 형태·부상 구현 계획

> 실행 기록은 아래 완료 현황을 기준으로 한다. 단계별 체크리스트와 코드 예시는 최초 계획으로 보존하며, 실제 변경은 하나의 커밋으로 묶는다.

**Goal:** 무기·몬스터·파츠·주문·소환수·지속 피해에 공격 형태(베기·타격·찌르기)를 붙이고, 종족 피부·뼈 3단계에 따른 피해 보정, 부상 상태 3종(출혈·골절·급소 노출), 처치한 한 방의 형태 기록과 부위 판정(50/25/25)을 넣는다.

**Architecture:** 새 정적 모듈 `expedition/combat/forms.gd`가 형태 판정·몸 단계·피해 보정·부상·부위 판정을 전부 맡는다. 한 번의 공격이 도는 동안 세션 변수 `blow_form`에 "지금 이 피해의 형태"를 걸어 두고(`Forms.begin`/`Forms.end`), 기존 피해 경로(`CombatRules.attack`, `Abilities.strike_victim`, `Spells.cast`, `Statuses.tick`)는 이 값을 걸기만 한다. `Session.after_damage`가 대상에 `last_form`을 적고, `Gear.roll_part`가 그것으로 부위를 판정한다.

**Tech Stack:** Godot 4 GDScript. 테스트는 `extends SceneTree` 스크립트이며 `godot --headless --path . --script res://tests/<name>.gd`로 돌린다. 실패하면 종료 코드 1이고 로그에 `ERROR`가 찍힌다.

**Spec:** `docs/superpowers/specs/2026-09-26-damage-forms-part-stones-design.md` 2부(§4~§7). 1부는 방향 설명이므로 이 계획 범위 밖이다(부위 영혼석 데이터·효과, 새 종족은 ③·④).

## 완료 현황 (2026-09-26)

- [x] Task 1: 형태 모듈·무기 7종·소환수 5종·몬스터 30종의 몸 단계.
- [x] Task 2: 기본 공격·파츠·주문·지속 피해의 형태 전달, 엄호·광역·처치 기록.
- [x] Task 3: 출혈·골절·급소 노출, 실제 피해 대상의 부상·치명타 판정, 전 인물의 골절 행동 지연.
- [x] Task 4: 기존 드롭 확률을 유지하며 처치 형태로 `part_kind` 판정.
- [x] Task 5: 적 정보·무기 이름·상태 줄, UID 파일과 CI 목록.

검증: CI에 등록된 78개 스위트를 실행했다. 기존 부상 확률과 무기 이름 가정 때문에 실패한 4개는 해당 기능의 의도를 유지하도록 수정한 뒤 모두 통과했다. 수정 경로를 포함한 10개 스위트를 재실행해 통과를 확인했다. 다른 작업의 미커밋 변경을 제외한 커밋 대상 사본에서도 78개 스위트 전체가 통과했다. 새 전용 검사는 `damage_forms` 142개, `wounds` 42개, `part_drops` 7개다. Godot 프로젝트 가져오기와 `git diff --check`도 확인했다.

이번 단계는 **부위 종류를 기록하는 기반**까지다. 실제 부위별 영혼석 ID·114개 효과·새 8종은 후속 ②~④의 범위이며, [후속 설계 검토](../reviews/2026-09-26-part-stones-followup-review.md)에 필요한 계약 보정을 적었다.

## 구현 검토 반영 (2026-09-26)

- 엄호는 `Session.after_damage`의 `received` 결과에 실제 피해 대상을 돌려준다. 치명타·급소 노출 소모, 부상, 적중 반응·영혼석 상태 발동은 이 대상에 적용한다. `last_form`도 실제 피해가 1 이상 들어간 대상에만 기록한다.
- 도끼 광역 피해는 무보정 공격력의 절반에서 시작해 **각 대상의** 피부·방어로 계산한다. 첫 대상의 피부 보정을 재사용하지 않는다. 기본 공격과 미리보기도 엄호자의 몸·방어를 읽는다.
- 골절은 이동·자리 교환·기본 공격·물리 파츠 공격의 지연만 늘린다. 대기·주문·원소 파츠는 그대로다. 파티의 `action_cost`뿐 아니라 고정 비용을 쓰는 몬스터·독립 NPC의 `time/scheduler.gd`에도 적용하며 중복 적용하지 않는다.
- `tests/wounds.gd`의 준비 함수는 `Forms.force`를 초기화하지 않는다. 호출자가 지정한 0/15/25/99 경계 롤을 유지한다. 실제 주문 시전·엄호 부상·대상별 광역 피해·골절 만료·스케줄러 비용 검사를 추가한다.
- 초상화 상태 줄(`floor_hud.gd`)에 골절·급소 노출 한국어 이름을 추가한다. `combat_stats.gd`에도 형태를 반환한다.
- 새 모듈·테스트의 `.gd.uid`를 커밋하고, `crit`·`stone_effects` 기존 테스트도 CI 목록에 포함한다. 회귀 테스트는 종료 코드와 `SCRIPT ERROR`/`ERROR`를 함께 검사한다.

아래 단계별 코드 예시는 최초 계획의 출발점이다. 실제 구현은 위 보정을 반영한 각 파일과 회귀 테스트를 기준으로 검토한다.

## Global Constraints

- 형태 상수는 정확히 `"SLASH"`, `"IMPACT"`, `"PIERCE"`. 형태가 없으면 빈 문자열 `""`.
- 무기 형태: 검·도끼 `SLASH`, 철퇴·지팡이 `IMPACT`, 창·단검·활 `PIERCE`. 맨손 `IMPACT`.
- 몸 단계: 종족 행의 `skin`, `bone`은 `-1`(무름/약함), `0`(보통), `1`(질김/단단함). 파티원·NPC·소환수·종족 행이 없는 적은 둘 다 `0`.
- 피해 보정: 베기 `raw*(100-25*skin)/100`, 타격 `raw*(100-25*bone)/100`, 찌르기는 보정 없음. 결과 최소 1. 타격은 방어(AC)를 절반만 적용한다.
- 부상 확률: 베기 `20-10*skin`, 타격 `20-10*bone`, 찌르기 20(%). 명중해서 피해가 1 이상 들어간 1차 타격(`hit_form == "HIT"`)에만, 주문(`s.casting > 0`)과 출처 없는 피해(지속 피해)는 제외.
- 부상 상태: `bleed` 300 tick(기존 상태 그대로), `fracture` 300 tick(이동·자리 교환·물리 공격 지연 +25%, 보스는 +12%), `exposed` 200 tick(다음 치명타 판정 한 번에 치명타 확률 +25, 판정하면 풀림).
- 부위 판정: 부위 셋의 순서는 `["cut","broken","pierced"]`이고 각각 `SLASH`,`IMPACT`,`PIERCE`에 맞는다. 맞는 부위 50%, 다음 부위 25%, 그다음 25%. 형태 없음은 34/33/33. 롤은 `Hexaco.sample(s.seed_value, s.depth*10000+enemy.id, "essence_part", 100)`.
- 주문은 형태를 부위 판정에만 쓴다(피해 보정·부상 없음). 주문 모양: `bolt`·`line` = `PIERCE`, `burst`·`cone`·`wall` = `IMPACT`, 나머지 = `""`.
- 지속 피해 형태: `bleed` = `SLASH`, `poison` = `PIERCE`, `burn` = `IMPACT`.
- 2차 피해(`Reactions.SECONDARY` = `["EXTRA","REACTION","COUNTER","RETALIATE"]`)의 `last_form`은 `""`.
- 철퇴의 `"trait": "pierce"`는 없앤다(`""`로). 코드에서 `trait == "pierce"` 분기는 전부 형태 규칙으로 바꾼다.
- 기존 테스트의 검사 수를 줄이지 않는다.
- **작업 트리에 이 계획과 무관한 미커밋 변경이 있다**(예: `expedition/actors/monster_ai.gd`, `expedition/level/encounter_builder.gd`, `expedition/combat/combat_rules.gd`의 원거리 회피 보정, `docs/reference/`). 커밋할 때는 반드시 각 Task에 적힌 파일만 `git add <경로>`로 올린다. `git add -A`/`git add .` 금지. `monster_ai.gd`는 이 계획에서 고치지 않는다.
- 주석과 메시지는 주변 코드처럼 한국어 게임 용어 + 영어 주석 스타일(짧게)을 따른다.

## Review Focus

- **죽은 대상이나 이미 쓰러진 대상에게 들어가는 피해**: `after_damage`가 일찍 돌아가므로 `last_form`이 덮이지 않아야 한다. 처치한 한 방의 형태가 그대로 남는지 Task 2 테스트에서 확인한다(처치 뒤 추가 타격은 `last_form`을 바꾸지 않음).
- **엄호(`protected_by`)로 피해가 다른 인물에게 넘어갈 때**: `last_form`은 실제로 맞은 인물에 적힌다. Task 2 테스트에 넣는다.
- **한 공격 안의 반격·반사·반응 피해**: 바깥 공격의 `blow_form`이 걸려 있어도 2차 피해의 `last_form`은 `""`, 부상도 없다. Task 2·3 테스트에 넣는다.
- **`blow_form`이 새지 않음**: 공격·파츠·주문·지속 피해가 끝나면 `s.blow_form`이 원래 값(보통 `""`)으로 돌아와야 한다. 중간에 대상이 죽어도 마찬가지다. Task 2 테스트에 넣는다.
- **종족 행이 없는 적(보스, `species_id == ""`)과 소환수 종류가 표에 없는 경우**: 형태 `IMPACT`, 몸 단계 0으로 떨어지고 오류가 나지 않아야 한다. Task 1 테스트에 넣는다.

---

## File Structure

| 파일 | 책임 |
| --- | --- |
| `expedition/combat/forms.gd` (새) | 형태 상수, 형태 판정(`of_actor`/`of_part`/`of_spell`/`of_dot`), 몸 단계(`skin`/`bone`), 피해 보정(`scale`), `blow_form` 걸기(`begin`/`end`), 처치 형태(`kill_form`), 부상(`wound_chance`/`wound`), 골절 지연(`fracture_percent`), 부위 판정(`pick_part`), 화면 문구(`form_name`/`body_line`) |
| `data/content/combat.json` | `weapons[].form`, 철퇴 `trait` 정리, `summons[].form` |
| `data/content/floor_monsters.json` | 종족 행마다 `form`, `skin`, `bone` |
| `expedition/run/session.gd` | `var blow_form`, `const Forms`, `after_damage`의 `last_form`, `attack_preview` 형태 보정 |
| `expedition/combat/combat_rules.gd` | `attack`의 형태 보정·방어 절반·`blow_form`, `damage`의 부상 호출 |
| `expedition/items/abilities.gd` | `strike_victim`의 형태 보정·`blow_form` |
| `expedition/spells/spells.gd` | `cast`의 `blow_form` |
| `expedition/combat/statuses.gd` | `fracture`·`exposed`를 `HARMFUL`에, 지속 피해 `blow_form` |
| `expedition/progression/stone_effects.gd` | `HARMFUL` 갱신, `CRIT_FORMS`에 `PIERCE`, 급소 노출 치명타·소모, 골절 지연 |
| `expedition/items/gear.gd` | `roll_part`에서 부위 판정 기록(`enemy.part_kind`) |
| `expedition/ui/screens/popups.gd`, `character_folio.gd` | 적 정보 창 형태·몸 한 줄, 무기 이름에 형태 |
| `tests/damage_forms.gd`, `tests/wounds.gd`, `tests/part_drops.gd` (새) | 아래 Task별 |
| `.github/workflows/deploy-pages.yml` | 새 스위트 셋을 CI 목록에 |

---

### Task 1: 형태 모듈과 데이터

**Files:**
- Create: `expedition/combat/forms.gd`
- Modify: `data/content/combat.json` (`weapons`, `summons`)
- Modify: `data/content/floor_monsters.json` (`species[]` 30행)
- Test: `tests/damage_forms.gd` (새)

**Interfaces:**
- Consumes: 없음
- Produces (이후 Task가 쓰는 이름 그대로):
  - `const SLASH := "SLASH"`, `const IMPACT := "IMPACT"`, `const PIERCE := "PIERCE"`, `const FORMS := [SLASH, IMPACT, PIERCE]`, `const PARTS := ["cut","broken","pierced"]`
  - `static var force := -1` (테스트가 부상 롤을 고정: -1이면 실제 롤)
  - `static func species_row(species_id: String) -> Dictionary`
  - `static func of_actor(actor: Dictionary) -> String`
  - `static func of_part(def: Dictionary) -> String`
  - `static func of_spell(spell: Dictionary) -> String`
  - `static func of_dot(status: String) -> String`
  - `static func skin(actor: Dictionary) -> int`, `static func bone(actor: Dictionary) -> int`
  - `static func scale(raw: int, form: String, target: Dictionary) -> int`
  - `static func begin(s, form: String) -> String` (이전 값을 돌려줌), `static func end(s, previous: String) -> void`
  - `static func kill_form(s, form: String, secondary: Array) -> String`
  - `static func wound_chance(form: String, target: Dictionary) -> int`
  - `static func fracture_percent(actor: Dictionary) -> int`
  - `static func pick_part(form: String, roll: int) -> String`
  - `static func form_name(form: String) -> String`, `static func body_line(actor: Dictionary) -> String`
  - (`wound`는 Task 3에서 추가)

- [ ] **Step 1: 실패하는 테스트 작성** — `tests/damage_forms.gd`

```gdscript
extends SceneTree
## Damage forms (2026-09-26 damage forms spec §4): which form a blow has, the
## skin and bone steps a species carries, the ±25% they make, and where the
## killing blow's form is written.
const Forms = preload("res://expedition/combat/forms.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	lookups(); body_steps(); scaling(); parts(); words()
	print("Damage forms: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func member(weapon: String) -> Dictionary:
	return {"enemy":false,"gear":{"weapon":{} if weapon.is_empty() else {"type":weapon}}}

func lookups() -> void:
	for pair in [["sword","SLASH"],["axe","SLASH"],["mace","IMPACT"],["staff","IMPACT"],["spear","PIERCE"],["dagger","PIERCE"],["bow","PIERCE"],["","IMPACT"]]:
		check(Forms.of_actor(member(pair[0])) == pair[1],"%s swings %s" % [pair[0],pair[1]])
	check(Forms.of_actor({"enemy":true,"species_id":"dcss_orc"}) == "SLASH","an orc cleaves")
	check(Forms.of_actor({"enemy":true,"species_id":"ore_golem"}) == "IMPACT","a golem slams")
	check(Forms.of_actor({"enemy":true,"species_id":"dcss_rat"}) == "PIERCE","a rat bites")
	check(Forms.of_actor({"enemy":true,"species_id":""}) == "IMPACT","a monster with no row slams")
	check(Forms.of_actor({"enemy":true,"species_id":"no_such"}) == "IMPACT","an unknown species slams")
	check(Forms.of_actor({"enemy":false,"summoned":true,"summon_kind":"hound"}) == "PIERCE","a hound bites")
	check(Forms.of_actor({"enemy":false,"summoned":true,"summon_kind":"no_such"}) == "IMPACT","an unknown summon slams")
	check(Forms.of_part({"species":"kobold"}) == "PIERCE","a part follows its species")
	check(Forms.of_part({"species":"kobold","form":"IMPACT"}) == "IMPACT","a part's own form wins")
	check(Forms.of_part({"species":""}) == "IMPACT","a basic part slams")
	for pair in [["bolt","PIERCE"],["line","PIERCE"],["burst","IMPACT"],["cone","IMPACT"],["wall","IMPACT"],["mark",""],["self",""],["summon",""],["",""]]:
		check(Forms.of_spell({"shape":pair[0]}) == pair[1],"spell shape %s is %s" % [pair[0],pair[1]])
	for pair in [["bleed","SLASH"],["poison","PIERCE"],["burn","IMPACT"],["freeze",""]]:
		check(Forms.of_dot(pair[0]) == pair[1],"%s ticks as %s" % [pair[0],pair[1]])

func body_steps() -> void:
	var beetle := {"enemy":true,"species_id":"rock_beetle"}
	var skeleton := {"enemy":true,"species_id":"skeleton_soldier"}
	check(Forms.skin(beetle) == 1 and Forms.bone(beetle) == 1,"a beetle is tough and hard")
	check(Forms.skin(skeleton) == -1 and Forms.bone(skeleton) == -1,"a skeleton is soft and brittle")
	check(Forms.skin(member("sword")) == 0 and Forms.bone(member("sword")) == 0,"a member is ordinary")
	check(Forms.skin({"enemy":true,"species_id":""}) == 0,"no row is ordinary")
	for row in Forms.species_rows():
		check(str(row.get("form","")) in Forms.FORMS,"%s has a form" % row.species_id)
		check(int(row.get("skin",9)) in [-1,0,1] and int(row.get("bone",9)) in [-1,0,1],"%s has skin and bone steps" % row.species_id)

func scaling() -> void:
	var beetle := {"enemy":true,"species_id":"rock_beetle"}
	var skeleton := {"enemy":true,"species_id":"skeleton_soldier"}
	check(Forms.scale(100,"SLASH",beetle) == 75,"slash loses a quarter on tough skin")
	check(Forms.scale(100,"SLASH",skeleton) == 125,"slash gains a quarter on soft skin")
	check(Forms.scale(100,"IMPACT",beetle) == 75,"impact loses a quarter on hard bone")
	check(Forms.scale(100,"IMPACT",skeleton) == 125,"impact gains a quarter on brittle bone")
	check(Forms.scale(100,"PIERCE",beetle) == 100 and Forms.scale(100,"PIERCE",skeleton) == 100,"pierce ignores the body")
	check(Forms.scale(100,"",beetle) == 100,"no form, no change")
	check(Forms.scale(1,"SLASH",beetle) == 1,"never below one")
	check(Forms.wound_chance("SLASH",beetle) == 10 and Forms.wound_chance("SLASH",skeleton) == 30,"slash wounds by skin")
	check(Forms.wound_chance("IMPACT",beetle) == 10 and Forms.wound_chance("IMPACT",skeleton) == 30,"impact wounds by bone")
	check(Forms.wound_chance("PIERCE",beetle) == 20 and Forms.wound_chance("",beetle) == 0,"pierce is flat, nothing is nothing")
	check(Forms.fracture_percent({}) == 25 and Forms.fracture_percent({"boss":true}) == 12,"a boss limps half")

func parts() -> void:
	for form in ["SLASH","IMPACT","PIERCE",""]:
		var counts := {"cut":0,"broken":0,"pierced":0}
		for roll in range(100): counts[Forms.pick_part(form,roll)] += 1
		match form:
			"SLASH": check(counts.cut == 50 and counts.broken == 25 and counts.pierced == 25,"slash drops cut 50/25/25")
			"IMPACT": check(counts.broken == 50 and counts.pierced == 25 and counts.cut == 25,"impact drops broken 50/25/25")
			"PIERCE": check(counts.pierced == 50 and counts.cut == 25 and counts.broken == 25,"pierce drops pierced 50/25/25")
			"": check(counts.cut == 34 and counts.broken == 33 and counts.pierced == 33,"no form is even")

func words() -> void:
	check(Forms.form_name("SLASH") == "베기" and Forms.form_name("IMPACT") == "타격" and Forms.form_name("PIERCE") == "찌르기","form names")
	check(Forms.body_line({"enemy":true,"species_id":"rock_beetle"}) == "공격 타격 · 피부 질김 · 뼈 단단함","body line")
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/damage_forms.gd`
Expected: `forms.gd`가 없어 파싱 오류(`ERROR`)로 실패.

- [ ] **Step 3: `expedition/combat/forms.gd` 작성**

```gdscript
extends RefCounted
## Damage forms (2026-09-26 damage forms spec §4): slash, impact and pierce.
## A blow's form scales it by the target's skin or bone step, may leave a
## wound, and the killing blow's form picks which body part a stone comes from.
## While a blow resolves its form sits in `s.blow_form` (`begin`/`end`), so
## every damage path below it reads the same form.
const SLASH := "SLASH"
const IMPACT := "IMPACT"
const PIERCE := "PIERCE"
const FORMS := [SLASH, IMPACT, PIERCE]
## Body parts in form order: cut by a slash, broken by impact, pierced.
const PARTS := ["cut","broken","pierced"]
const NAMES := {SLASH:"베기", IMPACT:"타격", PIERCE:"찌르기"}
const SKIN_NAMES := {-1:"무름", 0:"보통", 1:"질김"}
const BONE_NAMES := {-1:"약함", 0:"보통", 1:"단단함"}
const STEP_PERCENT := 25
const WOUND_BASE := 20
const WOUND_STEP := 10
const FRACTURE_PERCENT := 25
const SPELL_FORMS := {"bolt":PIERCE, "line":PIERCE, "burst":IMPACT, "cone":IMPACT, "wall":IMPACT}
const DOT_FORMS := {"bleed":SLASH, "poison":PIERCE, "burn":IMPACT}
## Tests pin the wound roll here: -1 rolls for real, anything else is the roll.
static var force := -1
static var combat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/combat.json"))
static var monsters: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/floor_monsters.json"))

static func species_rows() -> Array:
	return monsters.get("species",[])

static func species_row(species_id: String) -> Dictionary:
	if species_id.is_empty(): return {}
	for row in species_rows():
		if str(row.species_id) == species_id: return row
	return {}

## A form that is one of the three, or IMPACT for anything else.
static func known(form: String) -> String:
	return form if form in FORMS else IMPACT

## The form of `actor`'s basic attack: a summon's row, a monster's species,
## a member's weapon (bare hands slam).
static func of_actor(actor: Dictionary) -> String:
	if bool(actor.get("summoned",false)):
		return known(str(combat.get("summons",{}).get(str(actor.get("summon_kind","")),{}).get("form","")))
	if bool(actor.get("enemy",false)):
		return known(str(species_row(str(actor.get("species_id",""))).get("form","")))
	var weapon: String = str(actor.get("gear",{}).get("weapon",{}).get("type",""))
	return known(str(combat.get("weapons",{}).get(weapon,{}).get("form","")))

## A part's own form, else its species', else impact.
static func of_part(def: Dictionary) -> String:
	if str(def.get("form","")) in FORMS: return str(def.form)
	return known(str(species_row(str(def.get("species",""))).get("form","")))

## A spell's form counts only for which part drops: no scaling, no wound.
static func of_spell(spell: Dictionary) -> String:
	return str(SPELL_FORMS.get(str(spell.get("shape","")),""))

static func of_dot(status: String) -> String:
	return str(DOT_FORMS.get(status,""))

## Skin and bone steps: -1, 0 or 1. Only a monster with a species row has any.
static func skin(actor: Dictionary) -> int:
	if not bool(actor.get("enemy",false)): return 0
	return clampi(int(species_row(str(actor.get("species_id",""))).get("skin",0)),-1,1)

static func bone(actor: Dictionary) -> int:
	if not bool(actor.get("enemy",false)): return 0
	return clampi(int(species_row(str(actor.get("species_id",""))).get("bone",0)),-1,1)

## The step a form answers to: skin for a slash, bone for impact, none for pierce.
static func step(form: String, target: Dictionary) -> int:
	match form:
		SLASH: return skin(target)
		IMPACT: return bone(target)
	return 0

## A quarter less against the tough step, a quarter more against the weak one.
static func scale(raw: int, form: String, target: Dictionary) -> int:
	if raw <= 0 or form not in FORMS: return raw
	return maxi(1,raw*(100-STEP_PERCENT*step(form,target))/100)

## Hangs `form` on the blow now resolving; returns what was there before.
static func begin(s, form: String) -> String:
	var previous: String = str(s.blow_form)
	s.blow_form = form
	return previous

static func end(s, previous: String) -> void:
	s.blow_form = previous

## The form written on whoever a hit lands on: none for secondary damage,
## the blow's form while one resolves, else the damage's own form word.
static func kill_form(s, form: String, secondary: Array) -> String:
	if form in secondary: return ""
	if str(s.blow_form) in FORMS: return str(s.blow_form)
	return form if form in FORMS else ""

static func wound_chance(form: String, target: Dictionary) -> int:
	if form not in FORMS: return 0
	return WOUND_BASE-WOUND_STEP*step(form,target)

## How much slower a fractured actor acts, in percent; a boss half as much.
static func fracture_percent(actor: Dictionary) -> int:
	return FRACTURE_PERCENT/2 if bool(actor.get("boss",false)) else FRACTURE_PERCENT

## Which of the three parts a roll of 0..99 gives: the killing form's own part
## half the time, the next two a quarter each; no form spreads it evenly.
static func pick_part(form: String, roll: int) -> String:
	var own := FORMS.find(form)
	if own < 0: return PARTS[0] if roll < 34 else PARTS[1] if roll < 67 else PARTS[2]
	if roll < 50: return PARTS[own]
	if roll < 75: return PARTS[(own+1)%3]
	return PARTS[(own+2)%3]

static func form_name(form: String) -> String:
	return str(NAMES.get(form,""))

## "공격 베기 · 피부 질김 · 뼈 단단함" for the enemy info card.
static func body_line(actor: Dictionary) -> String:
	return "공격 %s · 피부 %s · 뼈 %s" % [form_name(of_actor(actor)),SKIN_NAMES[skin(actor)],BONE_NAMES[bone(actor)]]
```

- [ ] **Step 4: `data/content/combat.json` 수정**

`weapons`의 각 행에 `"form"`을 추가하고, 철퇴의 `"trait": "pierce"`를 `"trait": ""`로 바꾼다. 결과(다른 필드는 그대로 두고 `form`만 더하고 `mace.trait`만 바꾼다):

| id | form | trait |
| --- | --- | --- |
| sword | SLASH | balanced |
| axe | SLASH | cleave |
| mace | IMPACT | `""` |
| spear | PIERCE | reach |
| bow | PIERCE | ranged |
| dagger | PIERCE | stab |
| staff | IMPACT | focus |

`summons`의 각 행에 `"form"` 추가: `mirror` SLASH, `hound` PIERCE, `imp` SLASH, `rat` PIERCE, `wolf` PIERCE.

파이썬으로 하면 들여쓰기·키 순서가 바뀔 수 있다. 파일의 기존 서식을 유지하도록 각 행에 직접 `"form": "..."` 텍스트를 넣는다(예: `"trait": "balanced"` 뒤에 `, "form": "SLASH"`). 수정 뒤 `python3 -c "import json;json.load(open('data/content/combat.json'))"`로 JSON이 유효한지 확인한다.

- [ ] **Step 5: `data/content/floor_monsters.json` 수정**

`species[]`의 30행마다 `"form"`, `"skin"`, `"bone"`을 추가한다(기존 필드 그대로, 행 끝 `"role": ...` 뒤에 덧붙인다). 값:

| species_id | form | skin | bone |
| --- | --- | --- | --- |
| dcss_rat | PIERCE | -1 | -1 |
| dcss_frilled_lizard | PIERCE | 0 | 0 |
| kobold | PIERCE | 0 | 0 |
| goblin | PIERCE | -1 | 0 |
| goblin_archer | PIERCE | -1 | 0 |
| goblin_shield | IMPACT | 0 | 0 |
| dcss_hobgoblin | IMPACT | 0 | 1 |
| goblin_hexer | IMPACT | -1 | -1 |
| dcss_orc | SLASH | 1 | 0 |
| orc_thrower | SLASH | 1 | 0 |
| cave_spider | PIERCE | -1 | -1 |
| rock_beetle | IMPACT | 1 | 1 |
| ore_golem | IMPACT | 1 | 1 |
| kobold_firecaller | IMPACT | 0 | -1 |
| storm_bat | PIERCE | -1 | -1 |
| dcss_river_rat | PIERCE | -1 | -1 |
| giant_leech | PIERCE | -1 | 1 |
| swamp_toad | IMPACT | -1 | 0 |
| temple_serpent | PIERCE | 1 | 0 |
| water_spirit | IMPACT | -1 | 1 |
| dcss_gnoll | PIERCE | 0 | 0 |
| frost_imp | SLASH | 0 | 0 |
| gnoll_summoner | IMPACT | 0 | 0 |
| skeleton_soldier | SLASH | -1 | -1 |
| skeleton_archer | PIERCE | -1 | -1 |
| ghoul | SLASH | 0 | 0 |
| vampire_bat | PIERCE | -1 | -1 |
| wraith_knight | SLASH | 1 | 0 |
| wraith | SLASH | -1 | 1 |
| gravekeeper | IMPACT | 0 | 0 |

(뼈가 없는 거머리·물의 정령·원혼은 "부러지지 않음"이라 `bone: 1`로 둔다.)
수정 뒤 JSON 유효성 확인: `python3 -c "import json;d=json.load(open('data/content/floor_monsters.json'));assert all(all(k in r for k in ('form','skin','bone')) for r in d['species'])"`

- [ ] **Step 6: 테스트 통과 확인**

Run: `godot --headless --path . --script res://tests/damage_forms.gd`
Expected: `Damage forms: N checks, 0 failures`, 종료 코드 0.

- [ ] **Step 7: 기존 데이터 소비자 확인**

Run: `for t in encounter_builder floor_generator model_b_combat start_kit combat_basics; do godot --headless --path . --script res://tests/$t.gd 2>&1 | grep -E "failures|ERROR" | head -3; done`
Expected: 모두 `0 failures`, `ERROR` 없음. (`start_kit`/`model_b_combat`은 `trait`를 `ranged`/`focus`로만 검사하므로 철퇴 변경의 영향이 없어야 한다.)

- [ ] **Step 8: Commit**

```bash
git add expedition/combat/forms.gd data/content/combat.json data/content/floor_monsters.json tests/damage_forms.gd
git commit -m "Add damage forms: weapon, species and summon forms with skin and bone steps"
```

---

### Task 2: 피해 경로에 형태 걸기, 처치 형태 기록, 미리보기

**Files:**
- Modify: `expedition/run/session.gd` (상수·변수 선언부, `attack_preview` 약 469~495행, `after_damage` 약 830행~)
- Modify: `expedition/combat/combat_rules.gd` (`attack`)
- Modify: `expedition/items/abilities.gd` (`strike_victim`, 약 316행)
- Modify: `expedition/spells/spells.gd` (`cast`, 약 169행)
- Modify: `expedition/combat/statuses.gd` (`tick`)
- Test: `tests/damage_forms.gd` (함수 추가)

**Interfaces:**
- Consumes: Task 1의 `Forms.of_actor`, `of_part`, `of_spell`, `of_dot`, `scale`, `begin`, `end`, `kill_form`, `IMPACT`
- Produces:
  - `Session.blow_form: String` (기본 `""`)
  - 맞은 인물의 `actor.last_form: String`(처치한 한 방이면 그 형태가 남는다)
  - `Session.attack_preview(...)` 결과에 `"form": String` 키 추가, 피해 범위에 형태 보정 반영

- [ ] **Step 1: 실패하는 테스트 추가** — `tests/damage_forms.gd`

파일 맨 위 상수에 추가:

```gdscript
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Rules = preload("res://expedition/combat/combat_rules.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Spells = preload("res://expedition/spells/spells.gd")
const Statuses = preload("res://expedition/combat/statuses.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")
```

`run()`을 다음으로 바꾼다:

```gdscript
func run() -> void:
	lookups(); body_steps(); scaling(); parts(); words()
	attacks(); kill_forms(); no_leak(); preview()
	print("Damage forms: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
```

파일 끝에 추가:

```gdscript
## Hero at c with `weapon`, a foe of `species` at c+(1,0), nothing else awake.
func duel(weapon: String, species: String) -> Dictionary:
	StoneEffects.force = 99; Forms.force = 99  # no crits, no wounds
	var s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true
	var c: Vector2i = Fixture.arena(s,8)
	var hero: Dictionary = s.party[0]
	hero.gear.weapon = {"type":weapon,"enchant":0}
	s.party[1].pos = c+Vector2i(-4,0)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 400; foe.max_hp = 400; foe.pos = c+Vector2i(1,0); foe.part_id = ""; foe.species_id = species
	foe.res = {}; foe.statuses = {}; foe.sh = 0; foe.ev = 0; foe.ac = 0
	s.floor_state.observe(s)
	return {"s":s,"c":c,"hero":hero,"foe":foe}

## Mean damage of `tries` swings (dodge can miss: misses are skipped).
func swing(d: Dictionary, tries: int = 40) -> float:
	var s = d.s; var total := 0; var landed := 0
	for i in range(tries):
		d.foe.hp = 400
		s.Reactions.begin_action(s)
		var out: Dictionary = Rules.attack(s,d.hero,d.foe)
		if out.hit: total += int(out.damage); landed += 1
	return float(total)/maxf(1.0,float(landed))

func attacks() -> void:
	var soft := swing(duel("sword","skeleton_soldier"))
	var tough := swing(duel("sword","rock_beetle"))
	check(soft > tough*1.4,"a sword bites a skeleton harder than a beetle (%.1f vs %.1f)" % [soft,tough])
	var brittle := swing(duel("mace","skeleton_soldier"))
	var hard := swing(duel("mace","rock_beetle"))
	check(brittle > hard*1.4,"a mace breaks a skeleton harder than a beetle (%.1f vs %.1f)" % [brittle,hard])
	var a := swing(duel("spear","skeleton_soldier")); var b := swing(duel("spear","rock_beetle"))
	check(absf(a-b) < 1.5,"a spear does not care (%.1f vs %.1f)" % [a,b])
	# Impact halves armour: a mace against AC 10 loses less than a sword does.
	var armoured := duel("mace","")
	armoured.foe.ac = 10
	var mace_ac := swing(armoured)
	var sword_ac_d := duel("sword",""); sword_ac_d.foe.ac = 10
	var sword_ac := swing(sword_ac_d)
	var mace_bare_d := duel("mace",""); var mace_bare := swing(mace_bare_d)
	var sword_bare_d := duel("sword",""); var sword_bare := swing(sword_bare_d)
	check(mace_bare-mace_ac < sword_bare-sword_ac,"impact loses less to armour (%.1f vs %.1f)" % [mace_bare-mace_ac,sword_bare-sword_ac])

func kill_forms() -> void:
	# A weapon kill writes the weapon's form.
	var d := duel("spear","dcss_rat")
	d.foe.hp = 1
	d.s.Reactions.begin_action(d.s)
	var out: Dictionary = Rules.attack(d.s,d.hero,d.foe)
	check(out.hit and d.foe.hp <= 0 and d.foe.last_form == "PIERCE","a spear kill is a pierce kill")
	# A blow after death changes nothing.
	d.s.damage(d.foe,5,int(d.hero.id),"SLASH")
	check(d.foe.last_form == "PIERCE","a corpse keeps its killing form")
	# A part writes its own species' form.
	var p := duel("sword","dcss_rat")
	p.foe.hp = 1
	Abilities.strike_victim(p.s,p.hero,p.foe,5,"IMPACT",Abilities.definition("KOBOLD_SLING"))
	check(p.foe.last_form == "PIERCE","a sling kill is a pierce kill")
	# Secondary damage writes none, even inside a blow.
	var r := duel("sword","dcss_rat")
	var was: String = Forms.begin(r.s,"SLASH")
	r.s.damage(r.foe,3,int(r.hero.id),"COUNTER")
	Forms.end(r.s,was)
	check(r.foe.last_form == "","a counter is no form")
	# Damage over time writes its status's form.
	var t := duel("sword","dcss_rat")
	t.foe.hp = 2; t.foe.statuses = {"bleed":t.s.time+300}
	for i in range(3): Statuses.tick(t.s)
	check(t.foe.hp <= 0 and t.foe.last_form == "SLASH","a bleed kill is a slash kill")
	# A spell writes its shape's form.
	var m := duel("staff","dcss_rat")
	m.foe.hp = 1
	var was_spell: String = Forms.begin(m.s,Forms.of_spell({"shape":"bolt"}))
	Spells.hurt(m.s,m.hero,m.foe,10,"fire")
	Forms.end(m.s,was_spell)
	check(m.foe.last_form == "PIERCE","a bolt kill is a pierce kill")
	# A covered hit writes on whoever took it.
	var g := duel("sword","dcss_rat")
	var ally: Dictionary = g.s.party[1]
	ally.pos = g.c+Vector2i(0,1)
	g.hero["protected_by"] = int(ally.id); ally["guarded"] = true
	var was_cover: String = Forms.begin(g.s,"IMPACT")
	g.s.damage(g.hero,3,int(g.foe.id),"physical")
	Forms.end(g.s,was_cover)
	var taker: Dictionary = ally if int(ally.hp) < int(ally.max_hp) else g.hero
	check(str(taker.get("last_form","")) == "IMPACT","the one who took the hit carries its form")

func no_leak() -> void:
	var d := duel("sword","dcss_rat")
	d.s.Reactions.begin_action(d.s)
	Rules.attack(d.s,d.hero,d.foe)
	check(d.s.blow_form == "","an attack leaves no form behind")
	d.foe.hp = 1
	Rules.attack(d.s,d.hero,d.foe)
	check(d.s.blow_form == "","a killing attack leaves no form behind")
	var p := duel("sword","dcss_rat")
	Abilities.strike_victim(p.s,p.hero,p.foe,5,"IMPACT",Abilities.definition("KOBOLD_SLING"))
	check(p.s.blow_form == "","a part leaves no form behind")
	var t := duel("sword","dcss_rat")
	t.foe.statuses = {"poison":t.s.time+300}
	Statuses.tick(t.s)
	check(t.s.blow_form == "","a tick leaves no form behind")

func preview() -> void:
	var d := duel("sword","rock_beetle")
	var tough: Dictionary = d.s.attack_preview(d.foe.pos)
	var e := duel("sword","skeleton_soldier")
	var soft: Dictionary = e.s.attack_preview(e.foe.pos)
	check(tough.form == "SLASH" and soft.form == "SLASH","the preview names the form")
	check(int(soft.damage_max) > int(tough.damage_max),"the preview scales by skin")
```

(`Spells.hurt`는 주문 한 대의 피해 함수로 이미 있다. `Spells.cast` 전체를 부르면 MP·실패율이 끼므로, 이 테스트는 `cast`가 할 일인 `begin`/`end`를 직접 흉내 낸다. `cast` 자체의 `begin`/`end`는 Step 7에서 넣는다.)

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/damage_forms.gd`
Expected: `blow_form`이 없어 오류, 또는 `last_form` 관련 검사 실패.

- [ ] **Step 3: `session.gd` — 상수·변수**

상수 목록(다른 `preload`들 옆, 예: 34행 `const Reactions = ...` 아래)에 추가:

```gdscript
const Forms = preload("res://expedition/combat/forms.gd")
```

`var roll_serial := 0`(약 106행) 아래에 추가:

```gdscript
## The damage form of the blow now resolving (`Forms.begin`/`end`); empty between blows.
var blow_form := ""
```

- [ ] **Step 4: `session.gd` — `after_damage`에서 `last_form` 기록**

`after_damage` 안의 `target.hp -= lost; Body.sync(target)` 줄 바로 앞에 한 줄을 넣는다:

```gdscript
	target.last_form = Forms.kill_form(self,form,Reactions.SECONDARY)
	target.hp -= lost; Body.sync(target)
```

(함수 첫 줄 `if target.hp <= 0: return 0` 덕분에 이미 쓰러진 대상은 여기까지 오지 않는다.)

- [ ] **Step 5: `session.gd` — `attack_preview`**

`attack_preview`의 다음 세 줄:

```gdscript
	var ac: int = int(defense.ac)/2 if offense.trait == "pierce" else int(defense.ac)
	var dodge: int = clampi(int(defense.ev)*2+int(defense.get("dodge",0)),5,45)
	var block: int = int(defense.sh)
	return {"actor":actor.id,"target":victim.id,"cell":target,"name":victim.name,
		"chance":maxi(0,(100-dodge)*(100-block)/100),"block":block,"damage":maxi(1,int(offense.damage)-ac),
		"damage_min":maxi(1,int(offense.damage)-ac),"damage_max":int(offense.damage),"time":action_cost(actor,"ATTACK",target)}
```

를 다음으로 바꾼다:

```gdscript
	var form: String = Forms.of_actor(actor)
	var raw: int = Forms.scale(int(offense.damage),form,victim)
	var ac: int = int(defense.ac)/2 if form == Forms.IMPACT else int(defense.ac)
	var dodge: int = clampi(int(defense.ev)*2+int(defense.get("dodge",0)),5,45)
	var block: int = int(defense.sh)
	return {"actor":actor.id,"target":victim.id,"cell":target,"name":victim.name,"form":form,
		"chance":maxi(0,(100-dodge)*(100-block)/100),"block":block,"damage":maxi(1,raw-ac),
		"damage_min":maxi(1,raw-ac),"damage_max":raw,"time":action_cost(actor,"ATTACK",target)}
```

같은 함수 위쪽의 옛 유물 경로(`return {"actor":old_actor.id, ... "chance":100 ...}`)는 건드리지 않는다.

- [ ] **Step 6: `combat_rules.gd` — `attack`**

파일 위 `preload` 목록에 추가:

```gdscript
const Forms = preload("res://expedition/combat/forms.gd")
```

`attack`의 끝부분, 현재:

```gdscript
	var raw := int(offense.damage)
	if offense.trait == "stab" and (target.get("statuses", {}).has("confuse") or not bool(target.get("alert", true))): raw *= 2
	var ac := int(defense.ac) / 2 if offense.trait == "pierce" else int(defense.ac)
	var physical: Dictionary = Turns.physical(raw, 950, 0, roll(s, source, target, "absorb", ac + 1))
	out.hit = true
	out.damage = damage(s, source, target, int(physical.damage), "physical")
	if target.hp <= 0: return out
	match str(offense.brand):
		"fire", "ice": out.damage += damage(s, source, target, 4, str(offense.brand),0,Reactions.EXTRA_FORM)
		"venom":
			if int(defense.res.get("poison", 0)) < 100: target.statuses["poison"] = s.time + 300
		"drain": source.hp = mini(int(source.max_hp), int(source.hp) + 3)
	if offense.trait == "cleave":
		for other in s.party + s.npcs + s.enemies:
			if other.id != target.id and other.hp > 0 and s.side_of(other) != s.side_of(source) and s.melee_reach(source.pos, other.pos):
				damage(s, source, other, maxi(1, raw / 2 - int(Stats.stats(s, other).ac)), "physical")
	return out
```

를 다음으로 바꾼다(작업 트리에 이 함수 앞부분을 고친 미커밋 변경이 있을 수 있다. 이 끝부분만 바꾸고 앞부분은 그대로 둔다):

```gdscript
	# The blow's form: a quarter more or less by the target's skin or bone,
	# and impact meets only half the armour.
	var form: String = Forms.of_actor(source)
	var unscaled := int(offense.damage)
	var raw := Forms.scale(unscaled, form, s.protection_recipient(target))
	if offense.trait == "stab" and (target.get("statuses", {}).has("confuse") or not bool(target.get("alert", true))): raw *= 2
	var ac := int(defense.ac) / 2 if form == Forms.IMPACT else int(defense.ac)
	var physical: Dictionary = Turns.physical(raw, 950, 0, roll(s, source, target, "absorb", ac + 1))
	out.hit = true
	var was: String = Forms.begin(s, form)
	out.damage = damage(s, source, target, int(physical.damage), "physical")
	if target.hp > 0:
		match str(offense.brand):
			"fire", "ice": out.damage += damage(s, source, target, 4, str(offense.brand),0,Reactions.EXTRA_FORM)
			"venom":
				if int(defense.res.get("poison", 0)) < 100: target.statuses["poison"] = s.time + 300
			"drain": source.hp = mini(int(source.max_hp), int(source.hp) + 3)
		if offense.trait == "cleave":
			for other in s.party + s.npcs + s.enemies:
				if other.id != target.id and other.hp > 0 and s.side_of(other) != s.side_of(source) and s.melee_reach(source.pos, other.pos):
					var taker: Dictionary = s.protection_recipient(other)
					var cleave_raw := Forms.scale(unscaled/2,form,taker)
					damage(s,source,other,maxi(1,cleave_raw-Forms.armour(int(Stats.stats(s,taker).ac),form)),"physical")
	Forms.end(s, was)
	return out
```

- [ ] **Step 7: `abilities.gd` — `strike_victim`**

파일 위 `preload` 목록에 추가:

```gdscript
const Forms = preload("res://expedition/combat/forms.gd")
```

`strike_victim`의 현재 본문:

```gdscript
	if actor.enemy and victim == s.party[0] and not s.floor_state.visible.has(actor.pos): return 0
	var element: String = str(def.get("element",""))
	var damage_form: String = form if element in ["","bleed"] else str(ELEMENT_FORMS[element])
	if element == "air" and int(s.tile(victim.pos).wet) > 0: amount += SHOCK_BONUS
	var lost: int = int(s.damage(victim,amount,actor.id,damage_form))
```

를 다음으로 바꾼다(아래 줄들은 그대로):

```gdscript
	if actor.enemy and victim == s.party[0] and not s.floor_state.visible.has(actor.pos): return 0
	var element: String = str(def.get("element",""))
	var damage_form: String = form if element in ["","bleed"] else str(ELEMENT_FORMS[element])
	if element == "air" and int(s.tile(victim.pos).wet) > 0: amount += SHOCK_BONUS
	# A part strikes with its own form; only a plain physical part is scaled by the body.
	var part_form: String = Forms.of_part(def)
	if element in ["","bleed"]: amount = Forms.scale(amount,part_form,victim)
	var was: String = Forms.begin(s,part_form)
	var lost: int = int(s.damage(victim,amount,actor.id,damage_form))
	Forms.end(s,was)
```

- [ ] **Step 8: `spells.gd` — `cast`**

파일 위 `preload` 목록에 추가:

```gdscript
const Forms = preload("res://expedition/combat/forms.gd")
```

`cast`의:

```gdscript
	if shape_of(spell).is_empty(): relic_cast(s,caster,id,target,spell)
	else: shaped_cast(s,caster,id,target,spell)
```

를 다음으로 바꾼다:

```gdscript
	# The spell's shape is the form a kill by it counts as (which part drops);
	# spells are never scaled by the body and never wound.
	var was: String = Forms.begin(s,Forms.of_spell(spell))
	if shape_of(spell).is_empty(): relic_cast(s,caster,id,target,spell)
	else: shaped_cast(s,caster,id,target,spell)
	Forms.end(s,was)
```

- [ ] **Step 9: `statuses.gd` — `tick`의 지속 피해**

파일 위 `preload` 목록에 추가:

```gdscript
const Forms = preload("res://expedition/combat/forms.gd")
```

`tick`의:

```gdscript
			if status == "bleed": Rules.damage(s,{},actor,2,"physical")
			# A spell's burn says how hard it bites; the old mastery burn keeps
			# the single point it always did.
			elif status == "burn": Rules.damage(s,{},actor,int(payload.get("burn",1)),"fire")
			elif status == "poison": Rules.damage(s,{},actor,2,"poison")
```

를 다음으로 바꾼다:

```gdscript
			# A tick counts as its status's form, so a bleed kill is a slash kill.
			var was: String = Forms.begin(s,Forms.of_dot(status))
			if status == "bleed": Rules.damage(s,{},actor,2,"physical")
			# A spell's burn says how hard it bites; the old mastery burn keeps
			# the single point it always did.
			elif status == "burn": Rules.damage(s,{},actor,int(payload.get("burn",1)),"fire")
			elif status == "poison": Rules.damage(s,{},actor,2,"poison")
			Forms.end(s,was)
```

- [ ] **Step 10: 남은 `"pierce"` 분기 확인**

Run: `grep -rn '"pierce"' --include=*.gd expedition`
Expected: 결과 없음.

- [ ] **Step 11: 테스트 통과 확인**

Run: `godot --headless --path . --script res://tests/damage_forms.gd`
Expected: `0 failures`.

엄호 검사가 실패하면 `protection_recipient`가 요구하는 조건(보호자 인접, `guarded` 등)을 `session.gd`의 `protection_recipient`에서 읽고 테스트의 준비 코드를 거기에 맞춘다. 검사 의도(실제로 맞은 인물에 `last_form`)는 바꾸지 않는다.

- [ ] **Step 12: 회귀 확인**

Run: `for t in combat_basics model_b_combat crit stone_effects reactions parts model_b_spells spellbooks essence_spells bosses; do echo "== $t"; godot --headless --path . --script res://tests/$t.gd 2>&1 | grep -E "failures|ERROR" | head -3; done`
Expected: 모두 `0 failures`, `ERROR` 없음. 피해 수치를 정확히 비교하던 검사가 몬스터 종족 몸 단계 때문에 깨지면, 그 테스트의 적에 `species_id = ""`(몸 단계 0)을 두거나 기대값을 형태 보정만큼 바꾼다. 검사를 지우지 않는다.

- [ ] **Step 13: Commit**

```bash
git add expedition/run/session.gd expedition/combat/combat_rules.gd expedition/items/abilities.gd expedition/spells/spells.gd expedition/combat/statuses.gd tests/damage_forms.gd
git commit -m "Carry the blow's damage form through attacks, parts, spells and ticks"
```

(`combat_rules.gd`·`session.gd`에 이 계획과 무관한 미커밋 변경이 섞여 있으면 `git add -p`로 이 Task의 변경만 고른다. 판단이 어려우면 멈추고 사람에게 묻는다.)

---

### Task 3: 부상 3종

**Files:**
- Modify: `expedition/combat/forms.gd` (`wound` 추가)
- Modify: `expedition/combat/combat_rules.gd` (`damage`)
- Modify: `expedition/combat/statuses.gd` (`HARMFUL`)
- Modify: `expedition/progression/stone_effects.gd` (`HARMFUL`, `CRIT_FORMS`, `crit_chance`, `outgoing`, `delay`)
- Test: `tests/wounds.gd` (새)

**Interfaces:**
- Consumes: Task 1의 `Forms.wound_chance`, `fracture_percent`, `force`, `FORMS`; Task 2의 `s.blow_form`
- Produces:
  - `static func wound(s, source: Dictionary, target: Dictionary, lost: int) -> String` — 건 상태 이름(`"bleed"`/`"fracture"`/`"exposed"`) 또는 `""`
  - `const WOUNDS := {SLASH:["bleed",300,"출혈!"], IMPACT:["fracture",300,"골절!"], PIERCE:["exposed",200,"급소!"]}`
  - 상태 `fracture`, `exposed`

- [ ] **Step 1: 실패하는 테스트 작성** — `tests/wounds.gd`

```gdscript
extends SceneTree
## Wounds (2026-09-26 damage forms spec §4.3–4.4): a landed primary blow may
## leave a bleed, a fracture or exposed vitals by its form; spells, ticks and
## secondary damage never do.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Forms = preload("res://expedition/combat/forms.gd")
const Rules = preload("res://expedition/combat/combat_rules.gd")
const Statuses = preload("res://expedition/combat/statuses.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")
const Spells = preload("res://expedition/spells/spells.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	by_form(); odds(); not_these(); fracture(); exposed(); harmful()
	Forms.force = -1; StoneEffects.force = -1
	print("Wounds: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func duel(weapon: String, species: String) -> Dictionary:
	StoneEffects.force = 99  # Forms.force is controlled by each test
	var s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true
	var c: Vector2i = Fixture.arena(s,8)
	var hero: Dictionary = s.party[0]
	hero.gear.weapon = {"type":weapon,"enchant":0}
	s.party[1].pos = c+Vector2i(-4,0)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 400; foe.max_hp = 400; foe.pos = c+Vector2i(1,0); foe.part_id = ""; foe.species_id = species
	foe.res = {}; foe.statuses = {}; foe.sh = 0; foe.ev = 0; foe.ac = 0
	s.floor_state.observe(s)
	s.effects.clear()
	return {"s":s,"c":c,"hero":hero,"foe":foe}

## One landed blow of `form` from the hero, as the attack path would carry it.
func blow(d: Dictionary, form: String, amount: int = 5, element: String = "physical") -> void:
	d.s.Reactions.begin_action(d.s)
	var was: String = Forms.begin(d.s,form)
	d.s.damage(d.foe,amount,int(d.hero.id),element)
	Forms.end(d.s,was)

func procs(s) -> Array:
	return s.effects.filter(func(e): return e.get("kind","") == "PROC").map(func(e): return str(e.text))

func by_form() -> void:
	Forms.force = 0
	for row in [["SLASH","bleed","출혈!"],["IMPACT","fracture","골절!"],["PIERCE","exposed","급소!"]]:
		var w := duel("sword","dcss_rat")
		blow(w,row[0])
		check(w.foe.statuses.has(row[1]),"%s leaves %s" % [row[0],row[1]])
		check(row[2] in procs(w.s),"%s raises %s" % [row[0],row[2]])
	var d := duel("sword","dcss_rat")
	blow(d,"SLASH")
	check(int(d.foe.statuses.bleed) == int(d.s.time)+300,"a bleed lasts 300")
	var e := duel("sword","dcss_rat")
	blow(e,"PIERCE")
	check(int(e.foe.statuses.exposed) == int(e.s.time)+200,"exposed lasts 200")

func odds() -> void:
	# The roll must be under the chance: 30 on a skeleton's soft skin, 10 on a beetle.
	Forms.force = 25
	var soft := duel("sword","skeleton_soldier"); blow(soft,"SLASH")
	var tough := duel("sword","rock_beetle"); blow(tough,"SLASH")
	check(soft.foe.statuses.has("bleed") and not tough.foe.statuses.has("bleed"),"a roll of 25 cuts soft skin, not tough")
	Forms.force = 15
	var ordinary := duel("sword","dcss_frilled_lizard"); blow(ordinary,"PIERCE")
	check(ordinary.foe.statuses.has("exposed"),"a roll of 15 pierces anyone")
	Forms.force = 99
	var none := duel("sword","skeleton_soldier"); blow(none,"SLASH")
	check(not none.foe.statuses.has("bleed"),"a roll of 99 wounds nobody")

func not_these() -> void:
	Forms.force = 0
	var spell := duel("staff","dcss_rat")
	spell.s.casting += 1; blow(spell,"PIERCE"); spell.s.casting -= 1
	check(not spell.foe.statuses.has("exposed"),"a spell never wounds")
	var counter := duel("sword","dcss_rat")
	blow(counter,"SLASH",5,"COUNTER")
	check(not counter.foe.statuses.has("bleed"),"a counter never wounds")
	var tick := duel("sword","dcss_rat")
	tick.foe.statuses = {"bleed":tick.s.time+300}
	Statuses.tick(tick.s)
	check(tick.foe.statuses.keys() == ["bleed"],"a bleed tick wounds nothing more")
	var formless := duel("sword","dcss_rat")
	blow(formless,"")
	check(formless.foe.statuses.is_empty(),"a blow with no form wounds nothing")
	var nothing := duel("sword","dcss_rat")
	blow(nothing,"SLASH",0)
	check(nothing.foe.statuses.is_empty(),"no damage, no wound")

func fracture() -> void:
	var d := duel("sword","dcss_rat")
	var before: int = StoneEffects.delay(d.s,d.foe,100)
	d.foe.statuses["fracture"] = d.s.time+300
	check(StoneEffects.delay(d.s,d.foe,100) == before*125/100,"a fracture slows a quarter")
	d.foe["boss"] = true
	check(StoneEffects.delay(d.s,d.foe,100) == before*112/100,"a boss limps half as much")

func exposed() -> void:
	var d := duel("sword","dcss_rat")
	var before: int = StoneEffects.crit_chance(d.s,d.hero,d.foe)
	d.foe.statuses["exposed"] = d.s.time+200
	check(StoneEffects.crit_chance(d.s,d.hero,d.foe) == before+25,"exposed vitals add 25 to a crit")
	# One crit roll spends it, whether or not the crit lands.
	StoneEffects.force = 99
	d.s.Reactions.begin_action(d.s)
	StoneEffects.outgoing(d.s,d.hero,d.foe,10,"physical")
	check(not d.foe.statuses.has("exposed"),"a crit roll spends exposed vitals")
	# A spell does not spend it.
	d.foe.statuses["exposed"] = d.s.time+200
	d.s.casting += 1
	StoneEffects.outgoing(d.s,d.hero,d.foe,10,"fire")
	d.s.casting -= 1
	check(d.foe.statuses.has("exposed"),"a spell leaves exposed vitals")

func harmful() -> void:
	for status in ["fracture","exposed","bleed"]:
		check(status in Statuses.HARMFUL and status in StoneEffects.HARMFUL,"%s is harmful" % status)
	var d := duel("sword","dcss_rat")
	d.foe.statuses["immune"] = d.s.time+300
	Forms.force = 0
	blow(d,"IMPACT")
	check(not d.foe.statuses.has("fracture"),"immunity stops a fracture")
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/wounds.gd`
Expected: 부상이 걸리지 않아 `by_form`부터 실패.

- [ ] **Step 3: `forms.gd`에 `wound` 추가**

`const DOT_FORMS` 아래에:

```gdscript
## The wound each form leaves: status, ticks, notice.
const WOUNDS := {SLASH:["bleed",300,"출혈!"], IMPACT:["fracture",300,"골절!"], PIERCE:["exposed",200,"급소!"]}
```

`fracture_percent` 아래에:

```gdscript
## A landed primary blow's wound: only while a blow's form is set, never from a
## spell or a sourceless tick. Returns the status it hung, or "".
static func wound(s, source: Dictionary, target: Dictionary, lost: int) -> String:
	var form: String = str(s.blow_form)
	if lost <= 0 or source.is_empty() or form not in FORMS or int(s.casting) > 0: return ""
	if target.is_empty() or int(target.get("hp",0)) <= 0: return ""
	var odds := wound_chance(form,target)
	var rolled: int = force if force >= 0 else int(s.CombatRules.roll(s,source,target,"wound",100))
	if rolled >= odds: return ""
	var row: Array = WOUNDS[form]
	s.Statuses.apply(s,target,str(row[0]),int(row[1]),source)
	if not target.get("statuses",{}).has(str(row[0])): return ""
	s.StoneEffects.proc(s,target.pos,str(row[2]),"debuff")
	return str(row[0])
```

- [ ] **Step 4: `combat_rules.gd` — `damage`에서 부상 호출**

`damage` 끝의:

```gdscript
	if hit_form == Reactions.HIT_FORM: StoneEffects.procs(s, source, target, lost)
	return lost
```

를 다음으로 바꾼다:

```gdscript
	if hit_form == Reactions.HIT_FORM: StoneEffects.procs(s, source, target, lost)
	# The blow's form may leave a wound: bleed, fracture or exposed vitals.
	if hit_form == Reactions.HIT_FORM: Forms.wound(s, source, victim, lost)
	return lost
```

(`damage`가 `session.damage`를 거쳐 `COUNTER`·`RETALIATE` 등으로 불리면 `hit_form`이 그 이름이라 여기서 걸러진다.)

- [ ] **Step 5: `HARMFUL` 두 곳 갱신**

`expedition/combat/statuses.gd` 11행과 `expedition/progression/stone_effects.gd` 54행의 `HARMFUL` 배열 끝에 `"fracture","exposed"`를 더한다:

```gdscript
const HARMFUL := ["confuse","slow","freeze","bind","burn","weak","brittle","distort","vulnerable","dominate","bleed","poison","taunted","stun","fracture","exposed"]
```

- [ ] **Step 6: `stone_effects.gd` — 치명타, 골절 지연**

`preload` 목록에 추가:

```gdscript
const Forms = preload("res://expedition/combat/forms.gd")
```

`CRIT_FORMS`를:

```gdscript
const CRIT_FORMS := ["physical","SLASH","IMPACT","PIERCE"]
```

`crit_chance`를:

```gdscript
static func crit_chance(_s, attacker: Dictionary, target: Dictionary) -> int:
	var total := 15 if has(attacker,"SKELETON_VOLLEY") else 0
	var ambush := TagSets.bracket(attacker,"AMBUSH")
	total += int(AMBUSH_CRIT.get(ambush,0))
	if ambush == 6 and not target.is_empty() and fresh(target): total = 100
	# 급소 노출: the next crit roll against it is 25 surer.
	if not target.is_empty() and target.get("statuses",{}).has("exposed"): total += 25
	return mini(100,total)
```

`outgoing`의:

```gdscript
	if not spell and form in CRIT_FORMS and chance(s,attacker,target,"crit",crit_chance(s,attacker,target)):
		amount = amount*crit_percent(attacker)/100
		proc(s,target.pos,"치명타!","crit")
		s.message("%s 치명타" % str(attacker.get("name","")))
	return amount
```

를:

```gdscript
	if not spell and form in CRIT_FORMS:
		var exposed: bool = target.get("statuses",{}).has("exposed")
		if chance(s,attacker,target,"crit",crit_chance(s,attacker,target)):
			amount = amount*crit_percent(attacker)/100
			proc(s,target.pos,"치명타!","crit")
			s.message("%s 치명타" % str(attacker.get("name","")))
		# Exposed vitals are spent on the first crit roll against them.
		if exposed: target.statuses.erase("exposed")
	return amount
```

`delay`를:

```gdscript
static func delay(s, actor: Dictionary, cost: int, kind: String = "ATTACK") -> int:
	var cut := speed(s,actor)
	var result: int = cost if cut <= 0 else cost*(100-cut)/100
	if kind in ["MOVE","SWAP"] or Forms.attack_action(s,kind): result = Forms.fracture_delay(actor,result)
	return result
```

(`Session.action_cost`는 행동 종류를 `delay`에 넘긴다. 몬스터·독립 NPC는 이 경로를 지나지 않으므로 `time/scheduler.gd`에도 별도로 적용한다.)

- [ ] **Step 7: 테스트 통과 확인**

Run: `godot --headless --path . --script res://tests/wounds.gd`
Expected: `Wounds: N checks, 0 failures`.
`godot --headless --path . --script res://tests/damage_forms.gd`도 다시 `0 failures`.

- [ ] **Step 8: 회귀 확인**

Run: `for t in combat_basics model_b_combat crit stone_effects reactions parts enemy_turns bosses companion_tactics solo_floor solo_balance; do echo "== $t"; godot --headless --path . --script res://tests/$t.gd 2>&1 | grep -E "failures|ERROR" | head -3; done`
Expected: 모두 `0 failures`. 무작위 부상이 끼어 결정론 기대값(예: 정확한 HP, 정확한 지연)이 깨지는 검사는 그 테스트 시작부에서 `Forms.force = 99`(부상 없음)를 두고 끝에서 `-1`로 되돌려 고친다. 검사를 지우지 않는다.

- [ ] **Step 9: Commit**

```bash
git add expedition/combat/forms.gd expedition/combat/combat_rules.gd expedition/combat/statuses.gd expedition/progression/stone_effects.gd tests/wounds.gd
git commit -m "Leave wounds by damage form: bleed, fracture and exposed vitals"
```

(Step 8에서 고친 기존 테스트 파일도 함께 `git add`한다.)

---

### Task 4: 부위 판정 기록

**Files:**
- Modify: `expedition/items/gear.gd` (`roll_part`, 약 85행)
- Test: `tests/part_drops.gd` (새)

**Interfaces:**
- Consumes: Task 1의 `Forms.pick_part`, Task 2의 `enemy.last_form`
- Produces: 영혼석이 떨어진 적에 `enemy.part_kind: String`(`"cut"`/`"broken"`/`"pierced"`). 부위 영혼석은 ④에서 이 값으로 고른다. 지금은 기존 영혼석을 그대로 준다.

- [ ] **Step 1: 실패하는 테스트 작성** — `tests/part_drops.gd`

```gdscript
extends SceneTree
## Part drops (2026-09-26 damage forms spec §2): whether a stone drops is the
## old rule; which part it is follows the killing blow's form 50/25/25.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Forms = preload("res://expedition/combat/forms.gd")
const Gear = preload("res://expedition/items/gear.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	recorded(); spread(); unchanged_drop()
	print("Part drops: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

## A dead rat killed by `form`, carrying the rat's stone, ready for roll_part.
func corpse(form: String) -> Dictionary:
	var s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true
	Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	revive(s,foe,form,int(foe.id))
	return {"s":s,"foe":foe}

## The same corpse again, as a fresh kill with another id and nothing seen yet.
func revive(s, foe: Dictionary, form: String, enemy_id: int) -> void:
	foe.id = enemy_id; foe.species_id = "dcss_rat"; foe.variant_element = ""; foe.part_id = "RAT_GNAW"
	foe.hp = 0; foe.last_form = form; foe.erase("part_rolled"); foe.erase("part_kind")
	s.essence_seen.clear()

func recorded() -> void:
	var d := corpse("SLASH")
	Gear.roll_part(d.s,d.foe)
	var roll: int = Hexaco.sample(d.s.seed_value,d.s.depth*10000+int(d.foe.id),"essence_part",100)
	check(str(d.foe.get("part_kind","")) == Forms.pick_part("SLASH",roll),"the dropped part follows the killing form and the roll")
	check(int(d.s.parts_bag.get("RAT_GNAW",0)) == 1,"the old stone still drops")

func spread() -> void:
	# Across many enemy ids a slash kill gives cut about half the time.
	# One session, the same corpse revived under 200 ids: a first kill always drops.
	var d := corpse("SLASH")
	var counts := {"cut":0,"broken":0,"pierced":0}
	for i in range(200):
		revive(d.s,d.foe,"SLASH",1000+i)
		Gear.roll_part(d.s,d.foe)
		counts[str(d.foe.part_kind)] += 1
	check(counts.cut > 80 and counts.cut < 120,"a slash kill drops cut about half the time (%d/200)" % counts.cut)
	check(counts.broken > 30 and counts.pierced > 30,"the other two still drop (%d, %d)" % [counts.broken,counts.pierced])
	var even := {"cut":0,"broken":0,"pierced":0}
	for i in range(200):
		revive(d.s,d.foe,"",2000+i)
		Gear.roll_part(d.s,d.foe)
		even[str(d.foe.part_kind)] += 1
	check(even.values().all(func(n): return n > 45),"no form spreads evenly (%s)" % str(even))

func unchanged_drop() -> void:
	# Second kill of the species: the old one-in-four rule still decides whether.
	var d := corpse("PIERCE")
	d.s.essence_seen["dcss_rat"] = true
	var roll: int = Hexaco.sample(d.s.seed_value,d.s.depth*10000+int(d.foe.id),"essence",100)
	Gear.roll_part(d.s,d.foe)
	var dropped: bool = int(d.s.parts_bag.get("RAT_GNAW",0)) == 1
	check(dropped == (roll < Essences.REPEAT_PERCENT),"whether it drops is the old rule")
	check(d.foe.has("part_kind") == dropped,"a part is picked only when a stone drops")
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/part_drops.gd`
Expected: `part_kind`가 없어 실패.

- [ ] **Step 3: `gear.gd` — `roll_part`**

`preload` 목록에 추가:

```gdscript
const Forms = preload("res://expedition/combat/forms.gd")
```

`roll_part`의 끝부분:

```gdscript
	if Hexaco.sample(s.seed_value,s.depth*10000+enemy.id,"essence",100) >= chance: return
	s.parts_bag[id] = int(s.parts_bag.get(id,0))+1
```

를 다음으로 바꾼다:

```gdscript
	if Hexaco.sample(s.seed_value,s.depth*10000+enemy.id,"essence",100) >= chance: return
	# Which body part: the killing blow's form's own part half the time. Part
	# stones do not exist yet, so the pick is only recorded for now.
	enemy.part_kind = Forms.pick_part(str(enemy.get("last_form","")),Hexaco.sample(s.seed_value,s.depth*10000+enemy.id,"essence_part",100))
	s.parts_bag[id] = int(s.parts_bag.get(id,0))+1
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `godot --headless --path . --script res://tests/part_drops.gd`
Expected: `Part drops: N checks, 0 failures`.

- [ ] **Step 5: 회귀 확인**

Run: `for t in essences npc_essences bestiary parts test_loadout; do echo "== $t"; godot --headless --path . --script res://tests/$t.gd 2>&1 | grep -E "failures|ERROR" | head -3; done`
Expected: 모두 `0 failures`.

- [ ] **Step 6: Commit**

```bash
git add expedition/items/gear.gd tests/part_drops.gd
git commit -m "Record the body part a soul stone drop comes from"
```

---

### Task 5: 화면 문구와 CI

**Files:**
- Modify: `expedition/ui/screens/popups.gd` (`show_enemy_info` 약 79행, `gear_name` 약 330행)
- Modify: `expedition/ui/screens/character_folio.gd` (장비 줄 약 118행)
- Modify: `.github/workflows/deploy-pages.yml` (스위트 목록 38행)
- Test: `tests/damage_forms.gd` (UI 문구 검사는 순수 함수로), 기존 `inspect_ui`, `character_ui`, `ui_smoke`

**Interfaces:**
- Consumes: `Forms.body_line`, `Forms.form_name`, `Forms.of_actor`
- Produces: 적 정보 창의 `EnemyBody` 라벨, 무기 이름 뒤 `" · 베기"` 등

- [ ] **Step 1: 실패하는 테스트 추가** — `tests/damage_forms.gd`의 `words()` 끝에:

```gdscript
	check(Forms.weapon_label("장검","sword") == "장검 · 베기","a weapon's name carries its form")
	check(Forms.weapon_label("알 수 없음","no_such") == "알 수 없음","an unknown weapon keeps its bare name")
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/damage_forms.gd`
Expected: `weapon_label`이 없어 오류.

- [ ] **Step 3: `forms.gd`에 `weapon_label` 추가** (`body_line` 아래)

```gdscript
## "장검 · 베기": a weapon's name with its form, the bare name when it has none.
static func weapon_label(name: String, weapon_id: String) -> String:
	var form: String = str(combat.get("weapons",{}).get(weapon_id,{}).get("form",""))
	return name if form not in FORMS else "%s · %s" % [name,form_name(form)]
```

- [ ] **Step 4: `popups.gd` — 적 정보 창과 장비 이름**

`preload` 목록(파일 위)에 추가:

```gdscript
const Forms = preload("res://expedition/combat/forms.gd")
```

`show_enemy_info`에서 `defence.name = "EnemyDefence"` 줄 바로 아래에:

```gdscript
	var body = ui.label(ui.modal_content,Forms.body_line(enemy),13)
	body.name = "EnemyBody"
```

`gear_name`의 마지막 줄:

```gdscript
	return str(catalog.get(id,{}).get("name",id))
```

을:

```gdscript
	var name: String = str(catalog.get(id,{}).get("name",id))
	return Forms.weapon_label(name,id) if slot == "weapon" else name
```

- [ ] **Step 5: `character_folio.gd` — 장비 줄**

`preload` 목록에 `const Forms = preload("res://expedition/combat/forms.gd")`를 추가하고, 장비 줄의:

```gdscript
		var item_name: String = "—" if item.is_empty() else "방패" if slot == "shield" else str(catalogue.get(item_id,{}).get("name",item_id))
```

바로 아래에:

```gdscript
		if slot == "weapon" and not item.is_empty(): item_name = Forms.weapon_label(item_name,item_id)
```

- [ ] **Step 6: CI 스위트 목록**

`.github/workflows/deploy-pages.yml` 38행 `for suite in ...` 목록의 `combat_basics` 바로 뒤에 `damage_forms wounds part_drops`를 넣는다(공백으로 구분).

- [ ] **Step 7: 테스트 확인**

Run: `for t in damage_forms wounds part_drops inspect_ui character_ui ui_smoke equipped_inventory; do echo "== $t"; godot --headless --path . --script res://tests/$t.gd 2>&1 | grep -E "failures|ERROR" | head -3; done`
Expected: 모두 `0 failures`. 무기 이름 문자열을 정확히 비교하던 UI 검사가 깨지면 기대 문자열에 `" · <형태>"`를 붙여 고친다.

- [ ] **Step 8: 전체 CI 스위트**

Run (CI와 같은 목록 전부):

```bash
fail=0; for suite in $(sed -n 's/.*for suite in \(.*\); do/\1/p' .github/workflows/deploy-pages.yml); do out=$(godot --headless --path . --script "res://tests/${suite}.gd" 2>&1); if echo "$out" | grep -q "SCRIPT ERROR\|ERROR"; then echo "FAIL $suite"; fail=1; fi; done; echo "fail=$fail"
```

Expected: `fail=0`. 실패한 스위트는 그 로그를 읽어 원인을 고친다. 형태·부상 때문에 결정론 수치가 바뀐 경우는 Task 3 Step 8과 같은 방식(`Forms.force = 99`)으로 고친다. 검사 수를 줄이지 않는다.

- [ ] **Step 9: Commit**

```bash
git add expedition/combat/forms.gd expedition/ui/screens/popups.gd expedition/ui/screens/character_folio.gd .github/workflows/deploy-pages.yml tests/damage_forms.gd
git commit -m "Show damage forms and body steps on the enemy card and weapon names"
```

(Step 7·8에서 고친 기존 테스트 파일도 함께 `git add`한다.)

---

## 끝난 뒤 확인

- `grep -rn '"pierce"' --include=*.gd expedition` → 없음
- `grep -rn "blow_form" --include=*.gd expedition` → `session.gd`, `forms.gd`만
- 설계 문서 §4.5의 "공격 미리보기에 형태 보정" → Task 2 Step 5, "적 정보 창 한 줄" → Task 5 Step 4, "무기 설명에 형태" → Task 5 Step 4·5, "발동 알림" → Task 3 Step 3
