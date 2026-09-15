# 동시 제공 이능 전환 + 1층 부위 이능 7종 — 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 결속 슬롯 하나가 패시브+액티브를 동시에 제공하도록 계약을 바꾸고(옛 저장은 모드 규칙으로 계속 재생), 1층 6종 몬스터의 부위에서 드롭되는 신규 이능 7종과 이능 FEAR(적 도주) 연결을 추가한다.

**Architecture:** 동시 제공 여부는 `PartyEncounterState.legacy_ability_modes`(schema v26) 한 플래그로 결정하고, 런타임·검증기·세션은 이 플래그로 분기한다. 신규 이능은 `monster_ability_definitions.gd`의 정의 + `monster_ability_runtime.gd`의 assess/commit/reactions 확장으로 구현하며, 상태·반응은 기존 `ability.status`/`ability.impact`/`ability.reaction` 이벤트 계약을 재사용한다. 콘텐츠는 `monster_abilities.json`·`items.json`·`species_drop_tables.json` 3개 JSON에 추가한다.

**Tech Stack:** Godot 4.6 GDScript. 테스트는 `SceneTree` 스크립트를 `godot --headless --path . --script res://tests/<file>.gd`로 실행. 모든 명령은 `/mnt/d/STARTU/living-world-legacy-integration`(worktree, 브랜치 `feat/legacy-shell-new-core`)에서 실행. **`godot --headless`는 한 번에 하나만 실행한다**(동시 실행 시 클래스 캐시가 깨져 가짜 파싱 오류가 난다).

**Spec:** `docs/superpowers/specs/2026-09-15-dual-effect-abilities-floor1-design.md`

## Global Constraints

- 결속 한도 `min(레벨, 6)`, canonical 이능 중복 금지, 제거 정책 `LOCKED_UNTIL_POLICY_DEFINED`는 바꾸지 않는다.
- 기존 16종 이능의 수치는 바꾸지 않는다.
- 액티브(`ability.cast`) 피해는 어떤 적중 패시브도 발동시키지 않는다(현재 동작 유지).
- 모든 상태의 `until`은 발생 시각 +300 이하. 상태 magnitude ≥ 0. `ability.impact` magnitude 1..1000.
- 액티브 거절(`assess` 미승인) 시 MP·HP·아이템·상태를 소모하지 않는다.
- 미리보기·UI 조회 함수(`effect_preview`, `ability_binding_rows`, `markers`)는 이벤트·RNG·시간을 바꾸지 않는다.
- 코드 스타일: 주변 코드와 같이 탭 들여쓰기, 한 줄에 여러 문장을 `;`로 잇는 밀도, 한국어 사용자 메시지.
- 커밋 메시지 끝에 `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>` 를 붙인다. 푸시하지 않는다.
- 다른 세션의 미커밋 파일(`assets/**/*.import` 등)은 커밋에 포함하지 않는다. 항상 파일을 명시해 `git add`한다.

---

## 파일 구조

| 파일 | 역할 | 작업 |
|---|---|---|
| `sim/party_encounter_state.gd` | `legacy_ability_modes` 필드, schema v26 | Task 2 |
| `playtest/party_playtest_session.gd` | v25→v26 이전, 재생 시 플래그 전달, `set_ability_mode` 거부, 행 DTO | Task 2, 3 |
| `sim/abilities/monster_ability_runtime.gd` | `passive()` 분기, `accuracy_bonus`, FEAR, 신규 effect·패시브, `event_error` | Task 3, 4, 6 |
| `sim/abilities/monster_passive_service.gd` | historical 검사 분기 | Task 3 |
| `sim/world_state.gd:2040-2100` | 모드 이벤트 검사 분기 | Task 3 |
| `sim/abilities/ability_binding_rules.gd` | `dual_effect`, 신규 preview 문구 | Task 3, 5 |
| `playtest/ability_loadout_mockup.gd` | 모드 버튼 제거 | Task 3 |
| `sim/systems/party_encounter_coordinator.gd:1943` | 이능 FEAR → `fear_retreat` | Task 4 |
| `sim/abilities/monster_ability_definitions.gd` | 7종 정의 | Task 5 |
| `data/content/monster_abilities.json`, `items.json`, `species_drop_tables.json` | 콘텐츠 | Task 5 |
| `tests/monster_dual_effect_acceptance.gd` (신규, `monster_dual_mode_acceptance.gd` 대체) | 동시 제공 계약 | Task 3 |
| `tests/ability_legacy_mode_save_acceptance.gd` (신규) | v25 저장 이전 | Task 2 |
| `tests/floor1_part_abilities_acceptance.gd` (신규) | 7종 + FEAR + 드롭 | Task 4, 6 |
| `tests/monster_all_abilities_acceptance.gd`, `monster_ability_drops_acceptance.gd` | 갱신 | Task 3, 5 |
| `docs/ABILITY_DUAL_EFFECT_RESULTS.ko.md`, `docs/MONSTER_ABILITY_CONTENT_CATALOG.ko.md` | 결과·카탈로그 | Task 7 |

---

### Task 1: 기준선 측정

**Files:**
- Create: `docs/ABILITY_DUAL_EFFECT_RESULTS.ko.md` (기준선 절만)

- [ ] **Step 1: 관련 테스트를 순차 실행하고 결과를 기록**

```bash
cd /mnt/d/STARTU/living-world-legacy-integration
for t in monster_dual_mode_acceptance monster_all_abilities_acceptance run_ability_binding_tests portrait_skills_acceptance ability_binding_gameplay_acceptance starting_ability_drop_acceptance monster_ability_drops_acceptance fireball_environment_acceptance awareness_contact_regression ability_cleanup_acceptance; do
  echo "=== $t"; timeout 600 godot --headless --path . --script res://tests/$t.gd 2>&1 | tail -3
done
```

Expected: 각 suite의 마지막 출력(`PASS` 또는 실패 목록)을 확인한다. 실패하는 suite가 있으면 "기존 실패"로 기록한다.

- [ ] **Step 2: 결과 문서에 기준선 절 작성**

```markdown
# 동시 제공 이능 전환 + 1층 부위 이능 결과

- 작업일: 2026-09-15
- spec: docs/superpowers/specs/2026-09-15-dual-effect-abilities-floor1-design.md
- 기준 commit: <git rev-parse --short HEAD 출력>

## 기준선 (변경 전)

| suite | 결과 |
|---|---|
| monster_dual_mode_acceptance | <실제 출력> |
| ... | ... |
```

- [ ] **Step 3: Commit**

```bash
git add docs/ABILITY_DUAL_EFFECT_RESULTS.ko.md
git commit -m "docs: record ability suite baseline before dual-effect transition

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `legacy_ability_modes` 플래그와 schema v26

**Files:**
- Modify: `sim/party_encounter_state.gd:4,43,95,162,170,313,340,356`
- Modify: `playtest/party_playtest_session.gd:8345-8350,8561-8562`
- Test: `tests/ability_legacy_mode_save_acceptance.gd`

**Interfaces:**
- Produces: `PartyEncounterState.legacy_ability_modes: bool` (신규 세션 `false`), `PartyEncounterState.DUAL_EFFECT_SCHEMA_VERSION := 26`, `SCHEMA_VERSION := 26`.

- [ ] **Step 1: 실패하는 테스트 작성**

```gdscript
# tests/ability_legacy_mode_save_acceptance.gd
extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
var failures:Array[String]=[]
func _init():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.town_life_command({"action":"START"}).accepted,"town")
	check(not s.sim.world.party_encounter.legacy_ability_modes,"new sessions use dual-effect bindings")
	var decoded:Dictionary=JSON.parse_string(s.save_session_json())
	var party:Dictionary=decoded.snapshot.party_encounter
	check(int(party.schema_version)==26 and party.legacy_ability_modes==false,"fresh save writes schema 26 with legacy_ability_modes=false")
	var fresh=Session.new();var loaded:Dictionary=fresh.load_session_json(JSON.stringify(decoded))
	check(loaded.accepted,"schema 26 save loads "+str(loaded.get("reason","")))
	if loaded.accepted:check(fresh.sim.snapshot()==s.sim.snapshot(),"schema 26 snapshot equality")
	# v25 저장 흉내: 키를 지우고 버전을 내린다.
	party.erase("legacy_ability_modes");party.schema_version=25
	var old=Session.new();var old_loaded:Dictionary=old.load_session_json(JSON.stringify(decoded))
	check(old_loaded.accepted,"schema 25 save loads "+str(old_loaded.get("reason","")))
	if old_loaded.accepted:
		check(old.sim.world.party_encounter.legacy_ability_modes,"schema 25 save keeps mode rules")
		var resaved:Dictionary=JSON.parse_string(old.save_session_json())
		check(resaved.snapshot.party_encounter.legacy_ability_modes==true,"migrated flag persists on re-save")
	print("ABILITY LEGACY MODE SAVE ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/ability_legacy_mode_save_acceptance.gd 2>&1 | tail -5`
Expected: `FAIL fresh save writes schema 26 ...` 등 실패 (필드가 없어 `legacy_ability_modes` 접근 시 스크립트 오류가 날 수도 있음 — 어느 쪽이든 실패).

- [ ] **Step 3: party state에 필드·버전 추가**

`sim/party_encounter_state.gd`:

```gdscript
# 4행
const SCHEMA_VERSION := 26
# 43행 ABILITY_BINDING_SCHEMA_VERSION 아래에 추가
# v26: one binding grants passive and active together. Saves made under the
# mode-selection rule keep it through legacy_ability_modes.
const DUAL_EFFECT_SCHEMA_VERSION := 26
# 95행 legacy_contact_rule 아래에 추가
var legacy_ability_modes := false
```

`to_dict` (162행 `legacy_contact_rule` 기록 다음):

```gdscript
	if schema_version >= DUAL_EFFECT_SCHEMA_VERSION:
		wire["legacy_ability_modes"] = legacy_ability_modes
```

`from_dict` (170행 `legacy_contact_rule` 파싱 다음):

```gdscript
	state.legacy_ability_modes = bool(row.get("legacy_ability_modes",
		int(row.get("schema_version", 1)) < DUAL_EFFECT_SCHEMA_VERSION))
```

키 검증 (313행 `v25_keys` 다음):

```gdscript
	var v26_keys:Array=v25_keys.duplicate();v26_keys.append("legacy_ability_modes");v26_keys.sort()
```

340행의 조건 사슬 마지막에 추가:

```gdscript
		or (parsed_schema_version == ABILITY_BINDING_SCHEMA_VERSION and keys != v25_keys) \
		or (parsed_schema_version == DUAL_EFFECT_SCHEMA_VERSION and keys != v26_keys):
```

지원 버전 목록(`CONTACT_RULE_SCHEMA_VERSION,ABILITY_BINDING_SCHEMA_VERSION]`)에 `DUAL_EFFECT_SCHEMA_VERSION` 추가. 356행 다음에:

```gdscript
	if parsed_schema_version >= DUAL_EFFECT_SCHEMA_VERSION \
			and not row.get("legacy_ability_modes") is bool:
		return "invalid_legacy_ability_modes"
```

- [ ] **Step 4: 세션 로드 이전과 재생 전달**

`playtest/party_playtest_session.gd` 8350행(`raw_party["schema_version"]=PartyStateScript.ABILITY_BINDING_SCHEMA_VERSION`) 다음에:

```gdscript
	# v25 -> v26: a binding now grants passive and active together. A save made
	# under mode selection keeps that rule so its journal replays unchanged.
	if raw_party is Dictionary \
			and int(raw_party.get("schema_version",0))==PartyStateScript.ABILITY_BINDING_SCHEMA_VERSION:
		raw_party["legacy_ability_modes"]=true
		raw_party["schema_version"]=PartyStateScript.DUAL_EFFECT_SCHEMA_VERSION
```

8562행(`legacy_contact_rule` 전달) 다음에:

```gdscript
	replay.sim.world.party_encounter.legacy_ability_modes= \
		restored.world.party_encounter.legacy_ability_modes
```

- [ ] **Step 5: 통과 확인**

Run: `godot --headless --path . --script res://tests/ability_legacy_mode_save_acceptance.gd 2>&1 | tail -3`
Expected: `ABILITY LEGACY MODE SAVE PASS`

Run: `godot --headless --path . --script res://tests/awareness_contact_regression.gd 2>&1 | tail -3`
Expected: 기준선과 같음. 이 테스트가 `schema_version==24`를 기대해 실패하면 89행의 기대를 `26`으로, 91행의 `party_wire["schema_version"]=23;party_wire.erase("legacy_contact_rule")`를 `party_wire["schema_version"]=23;party_wire.erase("legacy_contact_rule");party_wire.erase("legacy_ability_modes")`로 갱신한다.

- [ ] **Step 6: Commit**

```bash
git add sim/party_encounter_state.gd playtest/party_playtest_session.gd tests/ability_legacy_mode_save_acceptance.gd tests/awareness_contact_regression.gd
git commit -m "feat: persist legacy_ability_modes flag with party schema v26

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: 동시 제공 런타임·검증·UI 전환

**Files:**
- Modify: `sim/abilities/monster_ability_runtime.gd:11-13,251-262`
- Modify: `sim/abilities/monster_passive_service.gd:43-52`
- Modify: `sim/world_state.gd:2049-2096`
- Modify: `playtest/party_playtest_session.gd:2709,2827-2833`
- Modify: `sim/abilities/ability_binding_rules.gd:13-14,60-65`
- Modify: `playtest/ability_loadout_mockup.gd:100-118`
- Modify: `tests/monster_all_abilities_acceptance.gd:14-27`
- Create: `tests/monster_dual_effect_acceptance.gd`; Delete: `tests/monster_dual_mode_acceptance.gd`(+`.uid`)

**Interfaces:**
- Produces: `AbilityBindingRules.dual_effect(id)->bool` (기존 `dual_mode` 개명), preview 키 `dual_effect`. 세션 `set_ability_mode`는 v2에서 `{"accepted":false,"reason":"ability_mode_retired"}`.

- [ ] **Step 1: 실패하는 테스트 작성**

```gdscript
# tests/monster_dual_effect_acceptance.gd
extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Action=preload("res://sim/party_action_command.gd")
const AbilityPanel=preload("res://playtest/ability_loadout_mockup.gd")
var failures:Array[String]=[]
func _init():run.call_deferred()
func check(value:bool,label:String):
	if not value:failures.append(label);printerr("FAIL ",label)
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.town_life_command({"action":"START"}).accepted,"town")
	check(s.guild_tutorial_command({"action":"ACCEPT","quest_id":"GUILD_TUTORIAL_BIND"}).accepted,"quest")
	check(s.guild_tutorial_command({"action":"SUPPORT","quest_id":"GUILD_TUTORIAL_BIND"}).accepted,"essence")
	var hero:int=s.sim.world.party_control_actor_id()
	var rows:Array=s.ability_binding_item_rows(hero)
	check(not rows.is_empty(),"real inventory essence")
	if rows.is_empty():quit(1);return
	check(s.bind_ability_item(hero,str(rows[0].instance_id)).accepted,"bind")
	var member=s.sim.world.party_encounter.member(hero)
	check(member.bound_ability_ids==["FIREBOLT"],"one slot used")
	check("FIREBOLT" in member.active_skill_ids(),"active available after bind")
	check(member.passive_ability_ids.is_empty(),"no passive list in dual-effect mode")
	check(s.set_ability_mode(hero,"FIREBOLT","PASSIVE").reason=="ability_mode_retired","mode selection retired")
	var binding_rows:Array=s.ability_binding_rows(hero)
	check(not binding_rows[0].has("mode") and binding_rows[0].get("dual_effect",false),"binding row describes both effects")
	var panel=AbilityPanel.new();root.add_child(panel)
	panel.configure(hero,binding_rows,s.ability_binding_item_rows(hero))
	check(panel.find_child("AbilityModeACTIVE",true,false)==null and panel.find_child("AbilityModePASSIVE",true,false)==null,"no mode buttons")
	panel.queue_free();await process_frame
	check(s.depart_town().accepted,"depart")
	var triggered:=false
	for turn in range(100):
		var command=null;var best:Dictionary={}
		for enemy_id in s.sim.world.party_encounter.enemy_ids:
			if not s.sim.world.is_autonomous_target(enemy_id):continue
			if s.FieldTurns.assess(s.sim,Action.melee(hero,enemy_id)).accepted:
				command=Action.melee(hero,enemy_id);break
			for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var path:Dictionary=s.sim.pathfinder.find_path(hero,s.sim.world.entities[enemy_id].position+direction)
				if path.get("found",false) and path.path.size()>1 and (best.is_empty() or path.path.size()<best.path.size()):best=path
		if command==null and not best.is_empty():command=Action.move_to(hero,best.path[1])
		if command==null:break
		var before:int=s.sim.world.events.size()
		var result:Dictionary=s.commit_field_action(command)
		if not result.accepted:print("field stopped ",result);break
		for event in s.sim.world.events.slice(before):
			if event.type=="ability.passive_triggered":triggered=true
		if triggered:break
	check(triggered,"passive fires while the active stays bound")
	check("FIREBOLT" in member.active_skill_ids(),"active still available in combat")
	var audit:String=s.sim.world.world_state_error();check(audit.is_empty(),"full state audit "+audit)
	var restored=Session.new();var loaded:Dictionary=restored.load_session_json(s.save_session_json())
	check(loaded.accepted,"replay "+str(loaded.get("reason","")))
	if loaded.accepted:check(restored.sim.snapshot()==s.sim.snapshot(),"replay equality")
	print("MONSTER DUAL EFFECT ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/monster_dual_effect_acceptance.gd 2>&1 | tail -5`
Expected: `FAIL mode selection retired`, `FAIL binding row describes both effects`, `FAIL no mode buttons`, `FAIL passive fires while the active stays bound` (v1에서는 결속 직후 ACTIVE 모드라 패시브가 안 뜸).

- [ ] **Step 3: 런타임 `passive()`와 `accuracy_bonus` 분기**

`sim/abilities/monster_ability_runtime.gd` 11-13행 교체:

```gdscript
static func passive(world,id:int,ability:String)->bool:
	var member=world.party_encounter.member(id) if world.party_encounter!=null else null
	if member==null:return false
	if world.party_encounter.legacy_ability_modes:return ability in member.passive_ability_ids
	return ability in member.bound_ability_ids
```

`accuracy_bonus` (251-262행) 의 `if before>0:` 블록 교체:

```gdscript
	if before>0:
		enabled=false
		for e in world.events:
			if e.id>=before:break
			if e.actor_id!=actor or e.data.get("ability_id")!="THROWING_INSTINCT":continue
			if world.party_encounter.legacy_ability_modes:
				if e.type=="party.ability_mode_changed":enabled=e.data.mode=="PASSIVE"
			elif e.type=="party.ability_bound":enabled=true
```

- [ ] **Step 4: 패시브 서비스 historical 검사 분기**

`sim/abilities/monster_passive_service.gd` 43-52행: `if not bound or not passive:return "monster_passive_not_equipped"` 를

```gdscript
		if not bound or (world.party_encounter.legacy_ability_modes and not passive):return "monster_passive_not_equipped"
```

로 교체.

- [ ] **Step 5: world_state 검증 분기**

`sim/world_state.gd` 2049행 `if event.type=="party.ability_mode_changed":` 블록 첫 줄에 추가:

```gdscript
		if event.type=="party.ability_mode_changed":
			if not party_encounter.legacy_ability_modes:return "ability_mode_event_retired"
```

2063행 `if (id in passive[event.actor_id])!=(event.type=="ability.pulse"):return "monster_ability_wrong_mode"` 를

```gdscript
			if party_encounter.legacy_ability_modes and (id in passive[event.actor_id])!=(event.type=="ability.pulse"):return "monster_ability_wrong_mode"
```

로 교체. 2096행은 그대로 둔다(v2에서는 양쪽 다 빈 배열).

- [ ] **Step 6: 세션 — 모드 변경 거부, 행 DTO**

`playtest/party_playtest_session.gd` `set_ability_mode` (2827행) 두 번째 줄 다음에:

```gdscript
	if not sim.world.party_encounter.legacy_ability_modes:return _rejection_dto("ability_mode_retired")
```

`ability_binding_rows` 2709행 `preview["mode"]=...` 를

```gdscript
			if sim.world.party_encounter.legacy_ability_modes:preview["mode"]="PASSIVE" if ability_id in member.passive_ability_ids else "ACTIVE"
```

로 교체. `_rejection_dto`가 사용하는 `reason_message` 표에 `"ability_mode_retired":"이능은 결속만으로 패시브와 액티브를 함께 제공합니다."` 를 추가한다(표 위치: `grep -n '"ability_mode_unsafe_phase\|invalid_ability_mode"' playtest/party_playtest_session.gd`로 찾아 그 옆에).

- [ ] **Step 7: `dual_mode` → `dual_effect`**

`sim/abilities/ability_binding_rules.gd`:

```gdscript
static func dual_effect(id:String)->bool:
	return preload("res://sim/abilities/monster_ability_definitions.gd").has(canonical_id(id))
```

`effect_preview`의 `"dual_mode":dual_mode(canonical)` → `"dual_effect":dual_effect(canonical)`, `elif dual_mode(canonical):` → `elif dual_effect(canonical):`. 저장소 전체에서 `dual_mode(` 호출을 바꾼다:

```bash
grep -rn "dual_mode" --include=*.gd sim playtest tests game
```

세션 `set_ability_mode`의 `AbilityBindingRulesScript.dual_mode(ability_id)`, world_state 2058행 `AbilityBindingRulesScript.dual_mode(id)`, mockup 100행 `row.get("dual_mode",false)` 를 각각 `dual_effect`로.

- [ ] **Step 8: 목업 UI에서 모드 버튼 제거**

`playtest/ability_loadout_mockup.gd` 100-118행을 다음으로 교체:

```gdscript
	var planned:bool=bool(row.get("planned",false))
	var dual:bool=bool(row.get("dual_effect",false))
	_mode("패시브 · 결속 시 항상 적용" if dual else "패시브 · 미구현",str(row.get("passive","패시브 효과 미구현")),dual)
	var effect:=str(row.get("active",""))
	if effect.is_empty():effect="기본 위력 %d · 기력 %d · 사거리 %d"%[int(row.get("power",0)),int(row.get("cost",0)),int(row.get("range",0))]
	_mode("액티브 · 미구현" if planned else "액티브 · 결속 시 사용 가능",effect,not planned)
```

`mode_action` 변수(23행)는 남겨도 되지만 참조가 없어지므로 삭제한다. `_mode(title,effect,active)`의 세 번째 인자는 강조 여부로 계속 사용한다.

- [ ] **Step 9: 기존 전체 이능 테스트에서 모드 주입 제거**

`tests/monster_all_abilities_acceptance.gd` 14-27행 `equip` 함수의 `if passive:` 블록을 삭제하고 시그니처를 `func equip(s,row,_passive:bool)`로 둔다(호출부 변경 최소화). 결과: 결속만으로 패시브·액티브 모두 검사된다. 실행해 기존 검사가 통과하는지 본다; 패시브 검사가 "ACTIVE 모드에서는 안 뜸"을 기대하는 검사가 있으면 그 검사(라벨에 `mode`/`active mode` 포함)를 삭제한다.

- [ ] **Step 10: 옛 모드 테스트 삭제, 통과 확인**

```bash
git rm tests/monster_dual_mode_acceptance.gd tests/monster_dual_mode_acceptance.gd.uid
for t in monster_dual_effect_acceptance monster_all_abilities_acceptance run_ability_binding_tests portrait_skills_acceptance ability_binding_gameplay_acceptance ability_legacy_mode_save_acceptance; do echo "=== $t"; timeout 600 godot --headless --path . --script res://tests/$t.gd 2>&1 | tail -3; done
```

Expected: `MONSTER DUAL EFFECT PASS`, 나머지는 기준선 이상. `portrait_skills`/`ability_binding_gameplay`가 `mode` 키나 `dual_mode`를 기대하면 `dual_effect`로 고친다.

- [ ] **Step 11: Commit**

```bash
git add sim/abilities/monster_ability_runtime.gd sim/abilities/monster_passive_service.gd sim/world_state.gd playtest/party_playtest_session.gd sim/abilities/ability_binding_rules.gd playtest/ability_loadout_mockup.gd tests/monster_all_abilities_acceptance.gd tests/monster_dual_effect_acceptance.gd tests/portrait_skills_acceptance.gd tests/ability_binding_gameplay_acceptance.gd
git commit -m "feat: grant passive and active together from one ability binding

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: 이능 FEAR 상태와 적 도주 연결

**Files:**
- Modify: `sim/abilities/monster_ability_runtime.gd` (`event_error` 상태 목록, `markers`, `poison` 시그니처)
- Modify: `sim/systems/party_encounter_coordinator.gd:1943`
- Test: `tests/floor1_part_abilities_acceptance.gd` (신규, 이 태스크에서는 FEAR 절만)

**Interfaces:**
- Produces: `monster_ability_runtime.status(world,id,"FEAR")`가 이능 FEAR를 반환; `poison(world,actor,target,stacks,cause,id:String="VENOM_FANG")`; `fear_cells(world,origin,radius)->Array[int]` (반경 내 시야 통과 자율 적 ID 목록).

- [ ] **Step 1: 실패하는 테스트 작성**

```gdscript
# tests/floor1_part_abilities_acceptance.gd
extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Runtime=preload("res://sim/abilities/monster_ability_runtime.gd")
const Action=preload("res://sim/party_action_command.gd")
const Inventory=preload("res://sim/inventory_state.gd")
const Item=preload("res://sim/item_instance.gd")
var failures:Array[String]=[]
func _init():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func bind(s,ability:String,item:String)->void:
	var w=s.sim.world;var hero:int=w.party_control_actor_id()
	var inv=w.inventory_of(hero);var items:Array=inv.backpack.duplicate()
	items.append(Item.new("PART_"+ability,item,1))
	w.item_state.inventory_rows[hero]=Inventory.new(items,inv.equipped)
	var result:Dictionary=s.bind_ability_item(hero,"PART_"+ability)
	check(result.accepted,"bind "+ability+" "+str(result.get("reason")))
func nearest(s)->int:
	var w=s.sim.world;var hero:int=w.party_control_actor_id();var best:=-1;var dist:=999
	for id in w.party_encounter.enemy_ids:
		if not w.is_autonomous_target(id):continue
		var d:int=Runtime.distance(w.entities[hero].position,w.entities[id].position)
		if d<dist:best=id;dist=d
	return best
func approach(s)->bool:
	var w=s.sim.world;var hero:int=w.party_control_actor_id();var best:Dictionary={}
	for enemy in w.party_encounter.enemy_ids:
		if not w.is_autonomous_target(enemy):continue
		for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if not preload("res://sim/party_perception_registry.gd").field_visible(w,w.entities[enemy].position+delta,w.entities[enemy].position):continue
			var p:Dictionary=s.sim.pathfinder.find_path(hero,w.entities[enemy].position+delta)
			if p.get("found",false) and p.path.size()>1 and (best.is_empty() or p.path.size()<best.path.size()):best=p
	if best.is_empty():return false
	for cell in best.path.slice(1):
		var terrain:String=w.tile_at(cell).terrain
		if s.sim.movement.commit_preflighted_move(hero,cell,terrain,preload("res://sim/terrain_registry.gd").definition(terrain).move_time_cost)==null:return false
	w.party_encounter.group_anchor=w.entities[hero].position
	return s.FieldTurns.assess(s.sim,Action.melee(hero,nearest(s))).accepted
func fresh():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.town_life_command({"action":"START"}).accepted,"town")
	return s
func run():
	test_fear_retreat()
	print("FLOOR1 PART ABILITIES ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
func test_fear_retreat():
	var s=fresh();bind(s,"WAR_ROAR","PART_ORC_THROAT")
	check(s.depart_town().accepted,"depart");check(approach(s),"adjacent fixture")
	var w=s.sim.world;var hero:int=w.party_control_actor_id();var enemy:int=nearest(s)
	var before:int=w.entities[enemy].position.distance_to(w.entities[hero].position)
	var result:Dictionary=s.use_active_skill(hero,"WAR_ROAR",hero)
	check(result.accepted,"roar accepted "+str(result.get("reason","")))
	check(Runtime.status(w,enemy,"FEAR")!=null,"enemy feared by roar")
	var forecast:Dictionary=s.sim.party_coordinator.forecast_enemy_action(enemy)
	check(forecast.reason=="fear_retreat","feared enemy retreats instead of attacking: "+str(forecast.reason))
	check(w.world_state_error().is_empty(),"audit "+w.world_state_error())
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/floor1_part_abilities_acceptance.gd 2>&1 | tail -5`
Expected: `FAIL bind WAR_ROAR ...` (정의·아이템이 아직 없음). 이 태스크에서는 FEAR 배관만 만들고, 테스트 통과는 Task 6에서 확인한다.

- [ ] **Step 3: 런타임에 FEAR·범위 헬퍼·poison ID 추가**

`sim/abilities/monster_ability_runtime.gd`:

`poison` 교체:

```gdscript
static func poison(world,actor:int,target:int,stacks:int,cause:int,id:String="VENOM_FANG")->bool:
	var old=status(world,target,"POISON")
	return add_status(world,actor,target,id,"POISON",mini(3,stacks+(old.magnitude if old!=null else 0)),300,cause)
```

`area` 아래에 추가:

```gdscript
static func enemies_within(world,origin:Vector2i,radius:int)->Array:
	var result:Array=[]
	for target in world.party_encounter.enemy_ids:
		if world.is_autonomous_target(target) and distance(origin,world.entities[target].position)<=radius \
				and preload("res://sim/enemy_perception_registry.gd").has_line_of_sight(world,origin,world.entities[target].position):result.append(target)
	return result

static func fear(world,actor:int,id:String,radius:int,duration:int,cause:int)->int:
	var count:=0
	for target in enemies_within(world,world.entities[actor].position,radius):
		if not add_status(world,actor,target,id,"FEAR",1,duration,cause):return -1
		count+=1
	return count
```

`tick()`의 독 피해 `impact(sim,s.actor_id,s.target_id,"VENOM_FANG",...)` → `impact(sim,s.actor_id,s.target_id,str(s.data.ability_id),...)`.

`event_error` `ability.status` 상태 목록에 `"FEAR","FRILL","GAZE"` 추가. `allowed` 표에 `"RODENT_INCISORS":["POISON"],"HEAVY_ARM":["SLOW"],"FRILL_DISPLAY":["FRILL","FEAR"],"WAR_ROAR":["FEAR"],"NIGHT_EYE":["GAZE"]` 추가. `ability.status`/`ability.impact` 공통 source 허용 목록(`source.type not in [...]`)에 `"entity.died"` 추가. `consumable.pulse` 분기의 `expected` 계산은 `source.data.effect=="POISON"`일 때 `id in ["VENOM_FANG","RODENT_INCISORS"]`를 허용하도록:

```gdscript
			var poison_ids:Array=["VENOM_FANG","RODENT_INCISORS"]
			var ok_id:bool=(id in poison_ids) if source.data.effect=="POISON" else id=="REGENERATIVE_TISSUE"
			return "" if ok_id and e.data.kind==kind and ... else "consumable_impact_invalid"
```

(기존 `id==expected` 자리를 `ok_id`로 바꾼다. `expected` 변수는 삭제.)

`markers()`의 마커 상태 목록 `["FROST_ZONE","POISON","HIDE","SHELL","STONE","VEIL"]`에 `"FEAR","FRILL"` 추가.

- [ ] **Step 4: 적 예측에 이능 FEAR 연결**

`sim/systems/party_encounter_coordinator.gd` 1943행:

```gdscript
	if preload("res://sim/consumable_effects.gd").status(world,enemy_id,"FEAR")!=null \
			or preload("res://sim/abilities/monster_ability_runtime.gd").status(world,enemy_id,"FEAR")!=null:
```

- [ ] **Step 5: 회귀 확인**

Run: `godot --headless --path . --script res://tests/monster_all_abilities_acceptance.gd 2>&1 | tail -3`
Expected: 기준선과 같음(독·시그니처 변경이 기존 동작을 바꾸지 않음).

- [ ] **Step 6: Commit**

```bash
git add sim/abilities/monster_ability_runtime.gd sim/systems/party_encounter_coordinator.gd tests/floor1_part_abilities_acceptance.gd
git commit -m "feat: let ability FEAR status drive enemy retreat

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: 콘텐츠 — 정의·부위 아이템·드롭·미리보기

**Files:**
- Modify: `sim/abilities/monster_ability_definitions.gd`
- Modify: `data/content/monster_abilities.json`, `data/content/items.json`, `data/content/species_drop_tables.json`
- Modify: `sim/abilities/ability_binding_rules.gd:60-65`
- Modify: `tests/monster_ability_drops_acceptance.gd`

**Interfaces:**
- Produces: 이능 ID 7종과 effect 키 `BITE`, `RETREAT_LEAP`, `FRILL`, `SMASH`, `BLOOD_STRIKE`, `ROAR`, `GAZE`; 아이템 ID `PART_RAT_INCISORS`, `PART_RAT_HINDLEG`, `PART_LIZARD_FRILL`, `PART_HOBGOBLIN_ARM`, `PART_ORC_HEART`, `PART_ORC_THROAT`, `PART_GOBLIN_EYE`.

- [ ] **Step 1: 드롭 테스트를 23종으로 갱신(실패 확인)**

`tests/monster_ability_drops_acceptance.gd`: `assert(Catalog.DATA.definitions.size()==16)` → `==23`, 출력 문구 `(23 mappings)`. 실행:

Run: `godot --headless --path . --script res://tests/monster_ability_drops_acceptance.gd 2>&1 | tail -3`
Expected: assertion 실패.

- [ ] **Step 2: 정의 추가**

`sim/abilities/monster_ability_definitions.gd` `SKILLS` 마지막에:

```gdscript
	"RODENT_INCISORS":{"name":"물어뜯기","cost":2,"range":1,"target":"ENEMY","effect":"BITE","power":14,"element":"PHYSICAL","axis":"MELEE","passive":"같은 적에게 150시간 안에 다시 근접 적중 시 추가 피해 3"},
	"FLIGHT_INSTINCT":{"name":"후퇴 도약","cost":2,"range":1,"target":"SELF","effect":"RETREAT_LEAP","power":0,"element":"NONE","axis":"DEFENSE","passive":"인접한 적이 없으면 둔화 이동 지연 무시"},
	"FRILL_DISPLAY":{"name":"과시","cost":3,"range":1,"target":"SELF","effect":"FRILL","power":4,"element":"NONE","axis":"DEFENSE","passive":"HP 절반 이하일 때 방어 +2"},
	"HEAVY_ARM":{"name":"강타 밀치기","cost":3,"range":1,"target":"ENEMY","effect":"SMASH","power":16,"element":"PHYSICAL","axis":"MELEE","passive":"근접 적중 시 대상 이동 50시간 지연 · 200시간"},
	"BERSERKER_BLOOD":{"name":"피의 일격","cost":2,"range":1,"target":"ENEMY","effect":"BLOOD_STRIKE","power":26,"element":"PHYSICAL","axis":"MELEE","passive":"HP 절반 이하일 때 근접 적중 추가 피해 4"},
	"WAR_ROAR":{"name":"포효","cost":3,"range":1,"target":"SELF","effect":"ROAR","power":0,"element":"NONE","axis":"MAGIC","passive":"적을 처치하면 3칸 안 적에게 공포 100시간"},
	"NIGHT_EYE":{"name":"어둠 응시","cost":2,"range":1,"target":"SELF","effect":"GAZE","power":6,"element":"NONE","axis":"MAGIC","passive":"어두운 곳에서 3칸 안 생명체 위치 감지"},
```

- [ ] **Step 3: JSON 콘텐츠 추가**

`data/content/monster_abilities.json` `definitions` 끝에 7행 (`essence_id`는 부위 아이템 ID; 기존 필드명 유지):

```json
    {"species_id": "dcss_rat", "ability_id": "RODENT_INCISORS", "label": "설치류 앞니", "essence_id": "PART_RAT_INCISORS", "passive": "같은 적 연속 근접 적중 시 추가 피해", "active": "물어뜯기 · 피해와 독 1중첩", "effect_status": "IMPLEMENTED_DUAL_EFFECT"},
    {"species_id": "dcss_rat", "ability_id": "FLIGHT_INSTINCT", "label": "도주 본능", "essence_id": "PART_RAT_HINDLEG", "passive": "인접 적이 없으면 둔화 무시", "active": "적에게서 멀어지는 후퇴 도약", "effect_status": "IMPLEMENTED_DUAL_EFFECT"},
    {"species_id": "dcss_frilled_lizard", "ability_id": "FRILL_DISPLAY", "label": "위협 과시", "essence_id": "PART_LIZARD_FRILL", "passive": "HP 절반 이하 방어 증가", "active": "인접 적 공포 + 자신 방어 강화", "effect_status": "IMPLEMENTED_DUAL_EFFECT"},
    {"species_id": "dcss_hobgoblin", "ability_id": "HEAVY_ARM", "label": "육중한 팔", "essence_id": "PART_HOBGOBLIN_ARM", "passive": "근접 적중 시 대상 둔화", "active": "강타 후 1칸 밀치기", "effect_status": "IMPLEMENTED_DUAL_EFFECT"},
    {"species_id": "dcss_orc", "ability_id": "BERSERKER_BLOOD", "label": "광전사의 피", "essence_id": "PART_ORC_HEART", "passive": "HP 절반 이하 근접 추가 피해", "active": "HP를 소모하는 강한 일격", "effect_status": "IMPLEMENTED_DUAL_EFFECT"},
    {"species_id": "dcss_orc", "ability_id": "WAR_ROAR", "label": "포효", "essence_id": "PART_ORC_THROAT", "passive": "처치 시 주변 적 공포", "active": "3칸 안 적 공포", "effect_status": "IMPLEMENTED_DUAL_EFFECT"},
    {"species_id": "goblin", "ability_id": "NIGHT_EYE", "label": "야간 안구", "essence_id": "PART_GOBLIN_EYE", "passive": "어둠 속 근거리 생명체 감지", "active": "바라보는 방향 원거리 탐지", "effect_status": "IMPLEMENTED_DUAL_EFFECT"}
```

기존 16행의 `"effect_status": "IMPLEMENTED_DUAL_MODE"`도 `"IMPLEMENTED_DUAL_EFFECT"`로 일괄 치환(`sed -i 's/IMPLEMENTED_DUAL_MODE/IMPLEMENTED_DUAL_EFFECT/' data/content/monster_abilities.json`). 이 문자열을 검사하는 코드가 있는지 `grep -rn "DUAL_MODE" --include=*.gd --include=*.md sim playtest tests docs`로 확인하고 코드가 있으면 같이 바꾼다.

`data/content/items.json` `definitions`에 7개 (기존 `ESSENCE_PREDATOR_NERVE` 행과 같은 형식):

```json
{"definition_id": "PART_RAT_INCISORS", "label": "쥐 앞니", "category": "MATERIAL", "stack_limit": 1, "equip_slots": [], "weapon_id": "", "requirements": {"STR": 0, "DEX": 0, "INT": 0}, "bonuses": {"armor_flat": 0, "parry_milli": 0, "dodge_milli": 0, "stealth": 0}, "use_kind": "NONE", "placeholder": false}
```

같은 형식으로 `PART_RAT_HINDLEG` "쥐 뒷발", `PART_LIZARD_FRILL` "도마뱀 목도리", `PART_HOBGOBLIN_ARM` "홉고블린 곤봉팔", `PART_ORC_HEART` "오크 심장", `PART_ORC_THROAT` "오크 성대", `PART_GOBLIN_EYE` "고블린 눈".

`data/content/species_drop_tables.json` — `dcss_rat`, `dcss_frilled_lizard`, `dcss_hobgoblin`, `dcss_orc`의 빈 `rolls`에, 그리고 `goblin`의 `rolls`에 추가:

```json
{"roll_id": "PART_RAT_INCISORS", "definition_id": "PART_RAT_INCISORS", "chance_per_1000": 200, "min_quantity": 1, "max_quantity": 1},
{"roll_id": "PART_RAT_HINDLEG", "definition_id": "PART_RAT_HINDLEG", "chance_per_1000": 200, "min_quantity": 1, "max_quantity": 1}
```

(도마뱀 `PART_LIZARD_FRILL`, 홉고블린 `PART_HOBGOBLIN_ARM`, 오크 `PART_ORC_HEART`+`PART_ORC_THROAT`, 고블린 `PART_GOBLIN_EYE` 동일 형식. `roll_id`는 테이블 전체에서 유일해야 한다.) 드롭 registry의 `content_version`/`ruleset_id`는 바꾸지 않는다(`species_drop_registry.registry_error`가 검사하는 항목을 `grep -n "ruleset_id\|content_version" sim/species_drop_registry.gd`로 확인하고, 문자열 고정 검사가 있다면 그 규칙에 따른다).

- [ ] **Step 4: 미리보기 문구**

`sim/abilities/ability_binding_rules.gd` `effect_preview`의 `if row.effect in ["DAMAGE","EXECUTE","LEAP","ACID","SIPHON","DISCHARGE"]` 목록에 `"BITE","SMASH","BLOOD_STRIKE"` 추가. 설명 사전에 추가:

```gdscript
"BITE":" · 독 1중첩(최대 3), 300시간","RETREAT_LEAP":" · 가장 가까운 적에서 멀어지는 2칸 내 빈칸으로 도약","FRILL":" · 인접 적 공포 200시간, 자신 방어 +4 200시간","SMASH":" · 1칸 밀치기, 정박·암석 골격은 밀리지 않음","BLOOD_STRIKE":" · HP 5 소모","ROAR":" · 3칸 안 적 공포 200시간","GAZE":" · 바라보는 방향 6칸 생명체 탐지, 300시간"
```

- [ ] **Step 5: 통과 확인**

Run: `godot --headless --path . --script res://tests/monster_ability_drops_acceptance.gd 2>&1 | tail -3`
Expected: `MONSTER ABILITY DROPS: PASS (23 mappings)`

Run: `godot --headless --path . --script res://tests/run_ability_binding_tests.gd 2>&1 | tail -3` — 기준선과 같음.

- [ ] **Step 6: Commit**

```bash
git add sim/abilities/monster_ability_definitions.gd sim/abilities/ability_binding_rules.gd data/content/monster_abilities.json data/content/items.json data/content/species_drop_tables.json tests/monster_ability_drops_acceptance.gd
git commit -m "content: add seven floor-1 body-part abilities and drops

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: 신규 effect 7종 런타임

**Files:**
- Modify: `sim/abilities/monster_ability_runtime.gd` (`projection`, `assess`, `commit`, `move_delay`, `armor`, `reactions`, `markers`, `event_error`)
- Modify: `tests/floor1_part_abilities_acceptance.gd` (절 추가)
- Modify: `tests/monster_all_abilities_acceptance.gd` (신규 7종 포함되는지 확인)

**Interfaces:**
- Consumes: Task 4의 `fear()`, `enemies_within()`, `poison(...,id)`; Task 5의 정의.
- Produces: 없음(런타임 내부).

- [ ] **Step 1: 테스트 절 추가**

`tests/floor1_part_abilities_acceptance.gd` `run()`을 다음으로 교체하고 함수들을 추가:

```gdscript
func run():
	test_fear_retreat()
	test_bite_and_incisors()
	test_blood_strike()
	test_smash()
	test_frill_and_retreat_leap()
	test_night_eye()
	test_replay()
	print("FLOOR1 PART ABILITIES ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
func melee(s,hero:int,enemy:int)->int:
	var before:int=s.sim.world.events.size()
	check(s.commit_field_action(Action.melee(hero,enemy)).accepted,"melee")
	return before
func impacts(w,since:int,ability:String)->Array:
	return w.events.slice(since).filter(func(e):return e.type=="ability.impact" and e.data.ability_id==ability)
func test_bite_and_incisors():
	var s=fresh();bind(s,"RODENT_INCISORS","PART_RAT_INCISORS")
	check(s.depart_town().accepted,"depart");check(approach(s),"adjacent fixture")
	var w=s.sim.world;var hero:int=w.party_control_actor_id();var enemy:int=nearest(s)
	var first:int=melee(s,hero,enemy)
	check(impacts(w,first,"RODENT_INCISORS").is_empty(),"first hit has no follow-up bonus")
	if w.is_autonomous_target(enemy):
		var second:int=melee(s,hero,enemy)
		var hit:bool=w.events.slice(second).any(func(e):return e.type=="combat.physical_damage" and e.magnitude>0)
		if hit and w.is_autonomous_target(enemy):check(not impacts(w,second,"RODENT_INCISORS").is_empty(),"second hit within 150 adds incisor damage")
	var mp:int=w.party_encounter.member(hero).energy
	var result:Dictionary=s.use_active_skill(hero,"RODENT_INCISORS",enemy)
	if w.is_autonomous_target(enemy):
		check(result.accepted,"bite accepted "+str(result.get("reason","")))
		if result.accepted:
			check(w.party_encounter.member(hero).energy==mp-2,"bite costs 2 MP")
			check(Runtime.status(w,enemy,"POISON")!=null or not w.is_autonomous_target(enemy),"bite poisons")
	check(w.world_state_error().is_empty(),"audit "+w.world_state_error())
func test_blood_strike():
	var s=fresh();bind(s,"BERSERKER_BLOOD","PART_ORC_HEART")
	check(s.depart_town().accepted,"depart");check(approach(s),"adjacent fixture")
	var w=s.sim.world;var hero:int=w.party_control_actor_id();var enemy:int=nearest(s)
	var hp:int=w.entities[hero].health;var mp:int=w.party_encounter.member(hero).energy
	var result:Dictionary=s.use_active_skill(hero,"BERSERKER_BLOOD",enemy)
	check(result.accepted,"blood strike accepted "+str(result.get("reason","")))
	check(w.entities[hero].health<hp,"blood strike costs HP")
	check(w.party_encounter.member(hero).energy==mp-2,"blood strike costs 2 MP")
	# 거절 시 무소비: HP를 5 이하로 만들 수 없으므로 MP 부족으로 거절을 만든다.
	w.party_encounter.member(hero).energy=1
	var hp2:int=w.entities[hero].health;var events:int=w.events.size()
	var rejected:Dictionary=s.use_active_skill(hero,"BERSERKER_BLOOD",enemy)
	check(not rejected.accepted and w.entities[hero].health==hp2 and w.events.size()==events,"rejected strike spends nothing")
	check(w.world_state_error().is_empty(),"audit "+w.world_state_error())
func test_smash():
	var s=fresh();bind(s,"HEAVY_ARM","PART_HOBGOBLIN_ARM")
	check(s.depart_town().accepted,"depart");check(approach(s),"adjacent fixture")
	var w=s.sim.world;var hero:int=w.party_control_actor_id();var enemy:int=nearest(s)
	var origin:Vector2i=w.entities[enemy].position
	var result:Dictionary=s.use_active_skill(hero,"HEAVY_ARM",enemy)
	check(result.accepted,"smash accepted "+str(result.get("reason","")))
	if result.accepted and w.is_autonomous_target(enemy):
		var moved:bool=w.entities[enemy].position!=origin
		var landing:Vector2i=origin+Vector2i(signi(origin.x-w.entities[hero].position.x),signi(origin.y-w.entities[hero].position.y))
		var free:bool=w.in_bounds(landing) and preload("res://sim/terrain_registry.gd").definition(str(w.tile_at(landing).terrain)).get("passable",false) and w.occupying_entities_at(landing).is_empty()
		check(moved==free or moved,"smash pushes when landing is free (moved=%s free=%s)"%[moved,free])
	var hit:bool=w.events.any(func(e):return e.type=="ability.status" and e.data.status=="SLOW" and e.data.ability_id=="HEAVY_ARM")
	if w.is_autonomous_target(enemy):
		melee(s,hero,enemy)
		hit=w.events.any(func(e):return e.type=="ability.status" and e.data.status=="SLOW" and e.data.ability_id=="HEAVY_ARM")
		check(hit or not w.events.any(func(e):return e.type=="combat.physical_damage" and e.magnitude>0 and e.target_id==enemy),"melee hit slows target")
	check(w.world_state_error().is_empty(),"audit "+w.world_state_error())
func test_frill_and_retreat_leap():
	var s=fresh();bind(s,"FRILL_DISPLAY","PART_LIZARD_FRILL");bind(s,"FLIGHT_INSTINCT","PART_RAT_HINDLEG")
	check(s.depart_town().accepted,"depart");check(approach(s),"adjacent fixture")
	var w=s.sim.world;var hero:int=w.party_control_actor_id();var enemy:int=nearest(s)
	var armor_before:int=Runtime.armor(w,hero)
	var result:Dictionary=s.use_active_skill(hero,"FRILL_DISPLAY",hero)
	check(result.accepted,"frill accepted "+str(result.get("reason","")))
	check(Runtime.armor(w,hero)==armor_before+4,"frill adds +4 armor")
	check(Runtime.status(w,enemy,"FEAR")!=null,"adjacent enemy feared by frill")
	var before:Vector2i=w.entities[hero].position;var dist:int=Runtime.distance(before,w.entities[enemy].position)
	var leap:Dictionary=s.use_active_skill(hero,"FLIGHT_INSTINCT",hero)
	check(leap.accepted,"retreat leap accepted "+str(leap.get("reason","")))
	if leap.accepted:check(Runtime.distance(w.entities[hero].position,w.entities[enemy].position)>dist,"retreat leap increases distance")
	# 도주 본능 패시브: 인접 적이 없으면 SLOW 지연 무시
	check(Runtime.add_status(w,hero,hero,"FROST_SILK","SLOW",100,300,-1),"inject slow")
	var adjacent:bool=Runtime.distance(w.entities[hero].position,w.entities[enemy].position)<=1
	check(Runtime.move_delay(w,hero)==(100 if adjacent else 0),"flight instinct ignores slow when no enemy adjacent")
	# 방어 패시브: HP 절반 이하
	w.entities[hero].health=w.entities[hero].max_health/2
	check(Runtime.armor(w,hero)>=armor_before+4+2,"frill passive +2 under half HP")
func test_night_eye():
	var s=fresh();bind(s,"NIGHT_EYE","PART_GOBLIN_EYE")
	check(s.depart_town().accepted,"depart")
	var w=s.sim.world;var hero:int=w.party_control_actor_id()
	var result:Dictionary=s.use_active_skill(hero,"NIGHT_EYE",hero)
	check(result.accepted or result.reason=="active_skill_combat_required","gaze usable or combat-gated: "+str(result.get("reason","")))
	if result.accepted:
		check(Runtime.status(w,hero,"GAZE")!=null,"gaze status")
		check(Runtime.markers(w).any(func(m):return m.kind=="LIFE") or Runtime.enemies_within(w,w.entities[hero].position,6).is_empty(),"gaze markers show life ahead")
func test_replay():
	var s=fresh();bind(s,"WAR_ROAR","PART_ORC_THROAT");bind(s,"HEAVY_ARM","PART_HOBGOBLIN_ARM")
	check(s.depart_town().accepted,"depart");check(approach(s),"adjacent fixture")
	var w=s.sim.world;var hero:int=w.party_control_actor_id();var enemy:int=nearest(s)
	s.use_active_skill(hero,"HEAVY_ARM",enemy);s.use_active_skill(hero,"WAR_ROAR",hero)
	var restored=Session.new();var loaded:Dictionary=restored.load_session_json(s.save_session_json())
	check(loaded.accepted,"replay "+str(loaded.get("reason","")))
	if loaded.accepted:check(restored.sim.snapshot()==s.sim.snapshot(),"replay equality")
```

주의: `test_night_eye`는 마을 출발 직후 전투 밖일 수 있어 `active_skill_combat_required` 거절을 허용한다. 전투 중 검사가 필요하면 `approach(s)` 후 사용한다.

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/floor1_part_abilities_acceptance.gd 2>&1 | tail -8`
Expected: `roar accepted` 등 다수 실패 (`commit`의 `match`에 effect가 없어 `ok=true`로 아무 일도 안 하거나, assess가 거절).

- [ ] **Step 3: projection에 직전 근접 적중 추적**

`projection()`의 초기 사전에 `"last_hits":{}` 추가하고 루프에:

```gdscript
		elif e.type=="combat.physical_damage" and e.magnitude>0:
			var attack=world.event_by_id(e.cause_id)
			if attack!=null and attack.type=="action.melee_attack":p.last_hits["%d:%d"%[attack.actor_id,e.target_id]]=e
```

- [ ] **Step 4: assess 확장**

`assess()`에서 `if d.effect=="ACID" and ...` 줄 다음에:

```gdscript
	if d.effect=="BLOOD_STRIKE" and world.entities[actor].health<=5:no.message="HP가 6 이상 필요합니다.";return no
	if d.effect=="ROAR" and enemies_within(world,origin,3).is_empty():no.message="범위 안에 적이 없습니다.";return no
```

`var landing:=position` 다음, `if d.effect=="LEAP":` 블록 뒤에:

```gdscript
	if d.effect=="RETREAT_LEAP":
		var threat:=-1;var threat_distance:=999
		for enemy in world.party_encounter.enemy_ids:
			if not alive(world,enemy):continue
			var dd:int=distance(origin,world.entities[enemy].position)
			if dd<threat_distance or (dd==threat_distance and enemy<threat):threat=enemy;threat_distance=dd
		if threat<0:no.message="도망칠 적이 없습니다.";return no
		landing=Vector2i(-1,-1);var gain:=0
		for y in range(origin.y-2,origin.y+3):
			for x in range(origin.x-2,origin.x+3):
				var cell:=Vector2i(x,y)
				if cell==origin or not world.in_bounds(cell) or not Terrain.definition(str(world.tile_at(cell).terrain)).get("passable",false):continue
				if not world.occupying_entities_at(cell).is_empty():continue
				if not preload("res://sim/combat_kernel.gd").sees(origin,cell,world.combat_sight_blocked):continue
				var g:int=distance(cell,world.entities[threat].position)-threat_distance
				if g>gain:gain=g;landing=cell
		if landing==Vector2i(-1,-1):no.message="도약할 빈칸이 없습니다.";return no
```

(y→x 순 순회이므로 동률은 y, x 오름차순으로 먼저 찾은 칸이 유지된다 — `g>gain` 엄격 비교.)

- [ ] **Step 5: commit 확장**

`commit()`의 `match str(d.effect):`에 분기 추가:

```gdscript
		"BITE":
			var dealt:=impact(sim,actor,target,id,power,"physical",e.id)
			ok=dealt>=0 and (not alive(w,target) or poison(w,actor,target,1,e.id,id))
		"BLOOD_STRIKE":
			ok=impact(sim,actor,actor,id,5,"physical",e.id)>=0 and impact(sim,actor,target,id,power,"physical",e.id)>=0
		"SMASH":
			var dealt:=impact(sim,actor,target,id,power,"physical",e.id)
			ok=dealt>=0
			if ok and alive(w,target) and not passive(w,target,"STONE_SKELETON") and not anchored(w,target):
				var from:Vector2i=w.entities[actor].position;var at:Vector2i=w.entities[target].position
				var landing:Vector2i=at+Vector2i(signi(at.x-from.x),signi(at.y-from.y))
				if w.in_bounds(landing) and Terrain.definition(str(w.tile_at(landing).terrain)).get("passable",false) \
						and w.occupying_entities_at(landing).is_empty() and preload("res://sim/combat_kernel.gd").sees(at,landing,w.combat_sight_blocked):
					ok=sim.movement.commit_preflighted_move(target,landing,str(w.tile_at(landing).terrain),1,e.id)!=null
		"RETREAT_LEAP":
			ok=sim.movement.commit_preflighted_move(actor,a.destination,str(w.tile_at(a.destination).terrain),1,e.id)!=null
		"FRILL":
			ok=add_status(w,actor,actor,id,"FRILL",power,200,e.id) and fear(w,actor,id,1,200,e.id)>=0
		"ROAR":ok=fear(w,actor,id,3,200,e.id)>0
		"GAZE":ok=add_status(w,actor,actor,id,"GAZE",6,300,e.id)
```

`SMASH`의 적 이동이 `enemy_busy_rows`를 바꾸지 않는지 `commit_preflighted_move` 본문을 확인한다(바꾼다면 그대로 둔다 — 밀린 적이 잠시 늦어지는 것은 허용).

- [ ] **Step 6: 패시브 — armor, move_delay, reactions, markers**

`armor()`에 추가:

```gdscript
	if passive(world,id,"FRILL_DISPLAY") and world.entities.has(id) and world.entities[id].health*2<=world.entities[id].max_health:value+=2
	for key in ["HIDE","SHELL","STONE","FRILL"]:   # 기존 ["HIDE","SHELL","STONE"] 루프를 이 목록으로 교체
```

`move_delay()` 첫 줄 뒤에:

```gdscript
	if passive(world,id,"FLIGHT_INSTINCT") and world.entities.has(id) and enemies_within(world,world.entities[id].position,1).is_empty():return 0
```

(`enemies_within`은 시야 통과를 요구하므로 인접 칸은 사실상 항상 통과. 주의: `move_delay`는 적에게도 호출되므로 `passive()`가 파티원이 아니면 false를 돌려 안전.)

`reactions()` 루프 안, `if hit.type=="action.move":` 블록 앞에 처치 반응:

```gdscript
		if hit.type=="entity.died" and hit.target_id in w.party_encounter.enemy_ids and hit.instigator_id>0 and passive(w,hit.instigator_id,"WAR_ROAR") and alive(w,hit.instigator_id):
			var reaction=w.emit_event("ability.reaction",hit.instigator_id,hit.instigator_id,w.entities[hit.instigator_id].position,0,-1,{"schema_version":1,"ability_id":"WAR_ROAR","trigger_id":hit.id})
			if reaction==null or fear(w,hit.instigator_id,"WAR_ROAR",3,100,reaction.id)<0:return false
			continue
```

적중 패시브 루프 `for id in ["PREDATOR_NERVE","THROWING_INSTINCT","HUNTER_LEAP"]:`를 `["PREDATOR_NERVE","THROWING_INSTINCT","HUNTER_LEAP","RODENT_INCISORS","BERSERKER_BLOOD"]`로 바꾸고 `amount` 계산에 추가:

```gdscript
				if id=="RODENT_INCISORS" and melee:
					var last=projection(w).last_hits.get("%d:%d"%[actor,target])
					if last!=null and last.id<hit.id and last.world_time+150>=w.world_time:amount=3
				if id=="BERSERKER_BLOOD" and melee and w.entities[actor].health*2<=w.entities[actor].max_health:amount=4
```

주의: `projection(w)`는 이 hit까지 포함해 갱신되므로 `last_hits`에는 현재 hit가 들어 있다. 위 코드는 `last.id<hit.id` 조건으로 현재 hit를 제외하지 못한다 — 따라서 projection에 저장할 때 **현재 키의 이전 값**을 `prev_hits`로 함께 보관한다: 루프에서 `p.prev_hits[key]=p.last_hits.get(key);p.last_hits[key]=e`로 저장하고, 여기서는 `projection(w).prev_hits.get(...)`를 읽는다. 초기 사전에 `"prev_hits":{}`도 추가.

`FROST_SILK` 줄 다음에:

```gdscript
			if passive(w,actor,"HEAVY_ARM") and melee and not add_status(w,actor,target,"HEAVY_ARM","SLOW",50,200,hit.id):return false
```

`markers()`: `var radius:=3 if passive(...ECHO_SENSE) or passive(...DEEP_EYE) else 0` 다음에:

```gdscript
	if radius==0 and passive(world,actor,"NIGHT_EYE"):
		var vision=preload("res://sim/vision_rules.gd");var lighting:Dictionary=vision.lighting_for_world(world);lighting.ambient_level=0
		if vision.illumination(world,origin,lighting)<300:radius=3
	var gaze=status(world,actor,"GAZE")
	if gaze!=null:radius=6
```

방향 필터 `if deep!=null and echo==null and ...dot<0:continue` 를 `if (deep!=null or gaze!=null) and echo==null and ...` 로 바꾼다. 위험 타일 절(`if passive(world,actor,"DEEP_EYE") or deep!=null:`)은 그대로 둔다(GAZE는 생명체만).

- [ ] **Step 7: event_error 갱신**

`ability.impact`의 `kind`는 그대로. `ability.reaction` 검사:

```gdscript
			var trigger=world.event_by_id(e.data.trigger_id)
			if trigger==null or trigger.id>=e.id or trigger.step_index!=e.step_index or trigger.world_time!=e.world_time:return "monster_reaction_invalid"
			if id=="WAR_ROAR":
				if trigger.type!="entity.died" or trigger.instigator_id!=e.actor_id:return "monster_reaction_invalid"
			elif trigger.type!="combat.physical_damage" or trigger.target_id!=e.actor_id or id not in ["CAUSTIC_BLOOD","CHARGE_ORGAN"]:return "monster_reaction_invalid"
```

`ability.status` magnitude 검사: `FEAR`는 magnitude 1, `FRILL`은 `power`(4), `GAZE`는 6 — 별도 검사는 추가하지 않는다(기존 HIDE 등도 검사하지 않음).

- [ ] **Step 8: 통과 확인**

Run: `godot --headless --path . --script res://tests/floor1_part_abilities_acceptance.gd 2>&1 | tail -8`
Expected: `FLOOR1 PART ABILITIES PASS`. 실패 시 실패 라벨을 읽고 원인을 고친다. 흔한 원인: (a) `event_error`의 source 허용 목록 누락 → `monster_effect_source_invalid`; (b) 상태 `until` 300 초과; (c) `approach` fixture가 특정 이능에서 적을 처치해 후속 검사가 무의미 — `is_autonomous_target` 가드로 이미 완화.

Run: `godot --headless --path . --script res://tests/monster_all_abilities_acceptance.gd 2>&1 | tail -3`
Expected: 기준선 이상. 이 테스트가 `Catalog.DATA.definitions`를 순회한다면 신규 7종도 결속·사용을 검사하게 되므로 그 결과를 확인한다.

- [ ] **Step 9: Commit**

```bash
git add sim/abilities/monster_ability_runtime.gd tests/floor1_part_abilities_acceptance.gd tests/monster_all_abilities_acceptance.gd
git commit -m "feat: implement seven floor-1 body-part abilities

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: 전체 검증, 문서, 마무리

**Files:**
- Modify: `docs/ABILITY_DUAL_EFFECT_RESULTS.ko.md`, `docs/MONSTER_ABILITY_CONTENT_CATALOG.ko.md`
- Modify: `docs/superpowers/specs/2026-09-15-dual-effect-abilities-floor1-design.md` §3.6 (포효 패시브 발동 범위 명시)

- [ ] **Step 1: 관련 suite 전체 순차 실행**

```bash
for t in monster_dual_effect_acceptance ability_legacy_mode_save_acceptance floor1_part_abilities_acceptance monster_all_abilities_acceptance run_ability_binding_tests portrait_skills_acceptance ability_binding_gameplay_acceptance starting_ability_drop_acceptance monster_ability_drops_acceptance fireball_environment_acceptance awareness_contact_regression ability_cleanup_acceptance; do echo "=== $t"; timeout 600 godot --headless --path . --script res://tests/$t.gd 2>&1 | tail -3; done
```

Expected: Task 1 기준선 대비 신규 실패 0. 신규 3개 suite PASS.

- [ ] **Step 2: 결과 문서 완성**

`docs/ABILITY_DUAL_EFFECT_RESULTS.ko.md`에 절 추가: `## 변경 요약`(계약 v2, 플래그, 7종, FEAR), `## 검증 결과`(suite별 실제 출력), `## 제한`(포효 패시브는 `reactions()`가 보는 사망만 — 독 틱 사망은 발동하지 않음; 액티브 피해는 적중 패시브를 발동하지 않음; 동료 AI 자동 사용·소환은 단계 2·3; 드롭 확률 200/1000은 임시값).

- [ ] **Step 3: 카탈로그 문서와 spec 갱신**

`docs/MONSTER_ABILITY_CONTENT_CATALOG.ko.md`에 신규 7종 표(ID, 라벨, 종·부위, 획득물, 패시브, 액티브, 공유 원리) 추가. spec §3.6 패시브 문장을 "`reactions()`가 처리하는 사망 이벤트(직접 공격·같은 반응 패스 내 파생 피해)만 발동. 주기 틱 사망은 제외."로 수정.

- [ ] **Step 4: Commit**

```bash
git add docs/ABILITY_DUAL_EFFECT_RESULTS.ko.md docs/MONSTER_ABILITY_CONTENT_CATALOG.ko.md docs/superpowers/specs/2026-09-15-dual-effect-abilities-floor1-design.md
git commit -m "docs: record dual-effect ability transition and floor-1 part ability results

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```
