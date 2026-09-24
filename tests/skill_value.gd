extends SceneTree
## Manual tool: runs the skill-value matrix and writes docs/balance/skill-value.{md,json}.
## Not part of the CI suite. Usage:
##   godot --headless --path . --script res://tests/skill_value.gd -- [--quick]
const Runner = preload("res://expedition/sim/encounter_runner.gd")
const Arena = preload("res://expedition/sim/encounter_arena.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Floor = preload("res://expedition/level/continuous_floor.gd")
const Stances = preload("res://expedition/ai/stances.gd")
const DOMINANT_PP := 0.20
const DOMINANT_ARENAS := 4
const USE_FLOOR := 0.2
## G4 (설계 §5.2): 적이 자기 시그니처 파츠를 쓰는 전투당 평균의 하한.
const ENEMY_USE_FLOOR := 0.5
static var experiments: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/balance_experiments.json"))

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var started := Time.get_ticks_msec()
	var ex: Dictionary = experiments.experiments.skill_value
	var seeds: Array = range(int(ex.seed_set.start),int(ex.seed_set.start)+int(ex.seed_set.count))
	var quick: bool = "--quick" in OS.get_cmdline_user_args()
	var explain: bool = "--explain" in OS.get_cmdline_user_args()
	if quick: seeds = seeds.slice(0,10)
	var rule_id: String = ex.rules.keys()[0]
	var table: Array = []
	for size in ex.party_sizes:
		for build_id in ex.builds:
			for arena_id in ex.arenas:
				var config := matrix_config(ex,arena_id,size,build_id)
				var stats: Dictionary = Runner.run_many(config,seeds)
				stats.erase("runs")
				var skill: String = equipped_skill(build_id)
				table.append({"rule":rule_id,"party":size,"build":build_id,"arena":arena_id,"tier":config.arena.tier,
					"skill":skill,"skill_mean":float(stats.skill_uses_mean.get(skill,0.0)),"stats":stats})
				print("p%d %s %s: win %.2f [%.2f,%.2f] dmg %.1f rounds %.1f %s %.2f guard %.2f distinct %d" % [size,build_id,arena_id,
					stats.win_rate,stats.win_ci[0],stats.win_ci[1],stats.damage.mean,stats.rounds.mean,skill,
					float(stats.skill_uses_mean.get(skill,0.0)),stats.guards.mean,stats.distinct_outcomes])
	var verdicts: Dictionary = decide(table,ex)
	var diagnoses: Dictionary = {}
	# Every build with a zero cell gets the probe, not only the ones the §5-4
	# floor flags: a skill nobody pressed in some arena needs the same line.
	var to_diagnose: Dictionary = {}
	for build_id in verdicts.unused: to_diagnose[build_id] = []
	for r in table:
		if r.skill_mean != 0.0: continue
		if not to_diagnose.has(r.build): to_diagnose[r.build] = []
		to_diagnose[r.build].append({"party":r.party,"arena":r.arena})
	for build_id in to_diagnose:
		# The probe replays exactly the cells that read zero; a build flagged only
		# by the usage floor falls back to its solo arenas.
		var cells: Array = to_diagnose[build_id]
		if cells.is_empty(): cells = ex.arenas.keys().map(func(id): return {"party":1,"arena":id})
		diagnoses[build_id] = diagnose(ex,build_id,cells,seeds.slice(0,3))
		print("diagnose %s: %s" % [build_id,diagnoses[build_id].line])
	var absent: Array = absent_rows(ex,seeds)
	if explain:
		for line in explain_lines(table): print(line)
	write_report(table,verdicts,diagnoses,absent,ex,seeds,Time.get_ticks_msec()-started,quick,explain)
	quit(0)

func matrix_config(ex: Dictionary, arena_id: String, size: int, build_id: String) -> Dictionary:
	var spec: Dictionary = Arena.DEFAULT_SPEC.duplicate(true)
	spec.tier = ex.arenas[arena_id].tier
	spec.members = ex.arenas[arena_id].members.map(func(pair): return {"species_id":pair[0],"role":pair[1]})
	return {"arena":spec,"party_size":size,"build":build_id,"policy":ex.policies[0],
		"rules":ex.rules[ex.rules.keys()[0]],"supplies":ex.supplies,"max_rounds":60}

## The build's first equipped entry is the one its rule list leads with; the
## report reads that skill's usage, not the GUARD fallback in the second slot.
func equipped_skill(build_id: String) -> String:
	var row: Dictionary = Runner.build(build_id)
	var equipped: Array = row.get("equipped",[])
	return str(equipped[0]) if not equipped.is_empty() else ""

func row(table: Array, party: int, build: String, arena: String) -> Dictionary:
	for r in table:
		if r.party == party and r.build == build and r.arena == arena: return r
	return {}

func build_mean_use(table: Array, build: String) -> float:
	var total := 0.0; var n := 0
	for r in table:
		if r.build != build: continue
		total += float(r.skill_mean); n += 1
	return total/maxi(1,n)

## §5-4, fixed before the run: dominance is read at party size 1 only, the two
## dead-skill tests over every cell of the matrix.
func decide(table: Array, ex: Dictionary) -> Dictionary:
	var base: String = ex.baseline_build
	var out := {"dominant":[],"unused":[],"weak":[],"per_build":{}}
	for build_id in ex.builds:
		var dominant_arenas := 0
		var all_worse := true
		var deltas: Array = []
		for size in ex.party_sizes:
			for arena_id in ex.arenas:
				var mine: Dictionary = row(table,size,build_id,arena_id)
				var ref: Dictionary = row(table,size,base,arena_id)
				var dw: float = mine.stats.win_rate-ref.stats.win_rate
				var dd: float = mine.stats.damage.mean-ref.stats.damage.mean
				deltas.append({"party":size,"arena":arena_id,"win":dw,"damage":dd})
				if size == 1 and dw >= DOMINANT_PP: dominant_arenas += 1
				if dw > 0.0 or dd < 0.0: all_worse = false
		var use: float = build_mean_use(table,build_id)
		var mean_delta := 0.0
		for d in deltas: mean_delta += d.win
		mean_delta /= maxi(1,deltas.size())
		out.per_build[build_id] = {"skill":equipped_skill(build_id),"use_mean":use,"mean_win_delta":mean_delta,
			"dominant_arenas":dominant_arenas,"deltas":deltas}
		if build_id == base: continue
		if dominant_arenas >= DOMINANT_ARENAS: out.dominant.append(build_id)
		if use < USE_FLOOR: out.unused.append(build_id)
		elif all_worse: out.weak.append(build_id)
	return out

## Why a skill was never pressed: replay a few seeds with a per-round probe and
## count the rounds in which `Abilities.legal` would have accepted it.
func diagnose(ex: Dictionary, build_id: String, cells: Array, seeds: Array) -> Dictionary:
	var skill: String = equipped_skill(build_id)
	if not Abilities.DEFINITIONS.has(skill):
		return {"skill":skill,"cells":cells.size(),"legal_rounds":0,"rounds":0,"line":"`%s`는 능력이 아니라 기본 전술(`Abilities.DEFINITIONS` 밖)이라 `legal` 진단 대상이 아니다 — 규칙 조건 `CHARGING`이 맞은 라운드가 없었다는 뜻이다." % skill}
	var legal_rounds := 0; var total_rounds := 0
	for cell in cells:
		var config := matrix_config(ex,str(cell.arena),int(cell.party),build_id)
		for seed in seeds:
			var rounds: Dictionary = {}
			config.probe = func(s, round_number: int) -> void:
				if rounds.get(round_number,false): return
				var hero: Dictionary = s.party[s.selected]
				var ok := false
				if str(Abilities.DEFINITIONS[skill].target) == "SELF":
					ok = Abilities.legal(s,hero,skill,hero.pos)
				else:
					for e in s.combat_enemies():
						if e.hp > 0 and Abilities.legal(s,hero,skill,e.pos):
							ok = true
							break
				rounds[round_number] = ok
			Runner.run_one(config,seed)
			for key in rounds:
				total_rounds += 1
				if rounds[key]: legal_rounds += 1
	var line: String = "합법 라운드 %d/%d — 규칙이 고르지 않음" % [legal_rounds,total_rounds]
	if legal_rounds == 0: line = "합법인 라운드 없음(0/%d) — 사거리/조건 확인" % total_rounds
	return {"skill":skill,"cells":cells.size(),"legal_rounds":legal_rounds,"rounds":total_rounds,"line":line}

## Gate G4 covers all eight parts, but two species (목도리 도마뱀·강쥐) hold no
## seat in the six matrix arenas. Each gets a one-species arena on the same seed
## set so no part in the catalog goes unmeasured.
func absent_rows(ex: Dictionary, seeds: Array) -> Array:
	var seated: Dictionary = {}
	for arena_id in ex.arenas:
		for pair in ex.arenas[arena_id].members: seated[str(pair[0])] = true
	var out: Array = []
	for part_id in Abilities.droppable():
		var species: String = str(Abilities.DEFINITIONS[part_id].species)
		if seated.has(species): continue
		var spec: Dictionary = Arena.DEFAULT_SPEC.duplicate(true)
		spec.tier = "early"
		spec.members = [{"species_id":species,"role":"MELEE"}]
		# Averaged over the same build x party grid as 표 3: `melee_1` alone would
		# read near zero, because its PUSH-on-CHARGING rule cancels the telegraph
		# of a lone monster almost every round.
		var cells: Array = []
		for size in ex.party_sizes:
			for build_id in ex.builds:
				cells.append(float(Runner.run_many({"arena":spec,"party_size":size,"build":build_id,
					"policy":ex.policies[0],"rules":ex.rules[ex.rules.keys()[0]],"supplies":ex.supplies,
					"max_rounds":60},seeds).enemy_skill_uses_mean.get(part_id,0.0)))
		var mean := 0.0
		for v in cells: mean += v
		mean /= maxi(1,cells.size())
		out.append({"part":part_id,"species":species,"mean":mean,"lowest":float(cells.min()),"cells":cells.size()})
		print("absent %s %s: mean %.2f lowest %.2f over %d cells" % [species,part_id,mean,float(cells.min()),cells.size()])
	return out

## The signature parts of the species that stand in `arena_id`, in roster order.
func arena_parts(ex: Dictionary, arena_id: String) -> Array:
	var out: Array = []
	for pair in ex.arenas[arena_id].members:
		var part_id: String = Abilities.species_part(str(pair[0]))
		if not part_id.is_empty() and not part_id in out: out.append(part_id)
	return out

func interrupt_mean(table: Array) -> float:
	var total := 0.0
	for r in table: total += float(r.stats.interrupts_mean)
	return total/maxi(1,table.size())

func commit_hash() -> String:
	var root: String = ProjectSettings.globalize_path("res://")
	var output: Array = []
	var code := OS.execute("git",["-C",root,"rev-parse","--short","HEAD"],output,true)
	if code != 0 or output.is_empty(): return "unknown"
	var text: String = str(output[0]).strip_edges()
	if text.is_empty(): return "unknown"
	# A dirty tree means the report cannot be traced back to the commit alone.
	var status: Array = []
	if OS.execute("git",["-C",root,"status","--porcelain"],status,true) == 0 and not status.is_empty() and not str(status[0]).strip_edges().is_empty():
		text += "-dirty"
	return text

func spec_line(ex: Dictionary) -> String:
	var spec: Dictionary = Arena.DEFAULT_SPEC
	return "size %d · room %s · door %s · pillars %s · party_entry %s · sight 5 · supplies %s" % [spec.size,str(spec.room),str(spec.door),str(spec.pillars),str(spec.party_entry),str(ex.supplies.map(func(v): return int(v)))]

## `--explain` (설계 §6): 빌드 × 아레나에서 효용이 고른 행동의 최상위 고려
## 사항 빈도. 판정에는 쓰이지 않는다.
func explain_lines(table: Array) -> Array:
	var lines: Array = []
	lines.append("## 설명 빈도 (`--explain`)")
	lines.append("")
	lines.append("각 칸은 그 태세가 효용 풀에서 고른 행동의 최상위 고려 사항을 빈도순으로 셋까지 적는다(`n`은 행동 수).")
	lines.append("")
	lines.append("| 빌드 | 인원 | 아레나 | %s |" % " | ".join(Stances.IDS.map(func(id): return Stances.NAMES[id])))
	lines.append("| --- | --- | --- |%s" % " --- |".repeat(Stances.IDS.size()))
	for r in table:
		var cells: Array = Stances.IDS.map(func(id): return Runner.explain_cell(r.stats.get("explain_top",{}),id))
		lines.append("| `%s` | %d | `%s` | %s |" % [r.build,r.party,r.arena," | ".join(cells)])
	lines.append("")
	return lines

func write_report(table: Array, verdicts: Dictionary, diagnoses: Dictionary, absent: Array, ex: Dictionary, seeds: Array, elapsed: int, quick: bool, explain: bool = false) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/balance"))
	var today := Time.get_date_string_from_system()
	var base: String = ex.baseline_build
	var lines: Array = []
	lines.append("# 스킬 가치 실험 결과")
	lines.append("")
	lines.append("생성: `tests/skill_value.gd`(수동 도구) · 커밋 `%s` · 날짜 %s%s" % [commit_hash(),today," · **--quick 실행(축약 시드)**" if quick else ""])
	lines.append("근거: [밸런스 방법론](../balance-method.ko.md) §5 · 설계: [스킬 원형 설계](../superpowers/specs/2026-09-22-skill-archetypes-design.md) §5")
	lines.append("")
	lines.append("**몬스터 파츠 도입 후 첫 측정.** 적도 자기 시그니처 파츠를 예고하고 쓰는 환경에서 전 빌드를 다시 잰 결과다 — 이전 보고서의 수치와 직접 비교하지 않는다. 게이트 판정은 [파츠 밸런스 게이트](parts-gates.md)에 있다.")
	lines.append("")
	lines.append("- 시드 묶음: `%s` %d개 (%d~%d)" % [ex.seed_set.id,seeds.size(),int(seeds[0]),int(seeds[seeds.size()-1])])
	lines.append("- 규칙: `%s` (`solo_actions %d` / `solo_max_members %d`) 하나만 쓴다 — 이번 실험의 축은 빌드다." % [ex.rules.keys()[0],int(ex.rules[ex.rules.keys()[0]].solo_actions),int(ex.rules[ex.rules.keys()[0]].solo_max_members)])
	lines.append("- 봇 정책: `%s` — 영웅이 동료와 같은 규칙 목록(`expedition/ai/tactic_rules.gd`)을 읽고 `Tactics.choose`가 고른 행동을 그대로 누른다." % ex.policies[0])
	lines.append("- **물자 0**: `supplies %s`. 회복품이 없으므로 스킬의 값이 물약에 가려지지 않는다." % str(ex.supplies.map(func(v): return int(v))))
	lines.append("- 솔로 HP 스케일: `SOLO_HP_PERCENT %d` / `SOLO_HP_MIN %d` / `SOLO_HP_MAX %d` (파티 인원 1일 때만 적용, 실험 조건의 일부)" % [Floor.SOLO_HP_PERCENT,Floor.SOLO_HP_MIN,Floor.SOLO_HP_MAX])
	lines.append("- 아레나 공통 spec: %s" % spec_line(ex))
	lines.append("- 행렬: 빌드 %d × 인원 %d × 아레나 %d × 시드 %d = %d전투" % [ex.builds.size(),ex.party_sizes.size(),ex.arenas.size(),seeds.size(),ex.builds.size()*ex.party_sizes.size()*ex.arenas.size()*seeds.size()])
	lines.append("- 실행 시간: %.1f초" % (elapsed/1000.0))
	lines.append("")
	lines.append("> 전투의 명중 판정은 없다. 같은 커밋·같은 시드·같은 빌드는 같은 전투를 낸다 — 표의 모든 칸은 재실행으로 그대로 재현된다. 시드는 적 배치와 부상 부위 선택에만 영향을 준다.")
	lines.append("> `사용 평균`은 그 빌드의 첫 장착 스킬을 한 전투에서 누른 횟수의 평균이다(누르지 않은 전투는 0으로 센다).")
	lines.append("> `distinct`는 시드 묶음에서 나온 서로 다른 `(결과, 라운드, 피해)` 조합의 수다.")
	lines.append("")
	lines.append("이 파이프라인이 찾아낸 사전 수정: HEAVY_STRIKE(사거리 1)가 대각선 인접 적에게 불법이던 문제 — `Abilities.legal`이 사거리 1 스킬에 맨해튼 거리 대신 `melee_reach`를 쓰도록 고쳤다(Task 2). 기본 공격이 닿는 칸에 강타가 닿지 않는 상태에서는 사용 평균이 스킬의 값이 아니라 기하의 사고를 재던 셈이다.")
	lines.append("")
	lines.append("빌드 구성:")
	lines.append("")
	lines.append("| 빌드 | 장착 | 규칙 |")
	lines.append("| --- | --- | --- |")
	for build_id in ex.builds:
		var b: Dictionary = Runner.build(build_id)
		var rules: Array = b.get("rules",[]).map(func(r): return "%s→%s(%s)" % [r[0],r[1],r[2]])
		lines.append("| `%s` | %s | %s |" % [build_id,", ".join(b.get("equipped",[])),", ".join(rules)])
	lines.append("")
	lines.append("아레나 구성:")
	lines.append("")
	lines.append("| 아레나 | 티어 | 구성 |")
	lines.append("| --- | --- | --- |")
	for arena_id in ex.arenas:
		var names: Array = ex.arenas[arena_id].members.map(func(pair): return "%s/%s" % [pair[0],pair[1]])
		lines.append("| `%s` | %s | %s |" % [arena_id,ex.arenas[arena_id].tier,", ".join(names)])
	lines.append("")
	lines.append("## 표 1 — 빌드 × 인원 × 아레나")
	lines.append("")
	lines.append("| 빌드 | 인원 | 아레나 | 티어 | 승률 [95% CI] | 평균 피해(개인별) | 평균 라운드 | 장착 스킬 | 사용 평균 | 방어 사용 평균 | distinct |")
	lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	for r in table:
		var st: Dictionary = r.stats
		lines.append("| `%s` | %d | `%s` | %s | %.2f [%.2f, %.2f] | %.1f | %.1f | %s | %.2f | %.2f | %d |" % [r.build,r.party,r.arena,r.tier,
			st.win_rate,st.win_ci[0],st.win_ci[1],st.damage.mean,st.rounds.mean,r.skill,r.skill_mean,st.guards.mean,st.distinct_outcomes])
	lines.append("")
	lines.append("## 표 2 — 기준선 `%s` 대비 Δ" % base)
	lines.append("")
	lines.append("같은 인원·같은 아레나의 기준선 칸과 비교한다. Δ승률은 퍼센트포인트, Δ피해는 개인별 평균 피해의 절대 변화량이다(피해는 낮을수록 좋다).")
	lines.append("")
	lines.append("| 빌드 | 인원 | 아레나 | Δ승률(pp) | Δ피해 |")
	lines.append("| --- | --- | --- | --- | --- |")
	for build_id in ex.builds:
		if build_id == base: continue
		for d in verdicts.per_build[build_id].deltas:
			lines.append("| `%s` | %d | `%s` | %+.1f | %+.1f |" % [build_id,d.party,d.arena,d.win*100.0,d.damage])
	lines.append("")
	lines.append("빌드별 요약(전 칸 기준, 우세/열세는 Δ승률의 부호):")
	lines.append("")
	lines.append("| 빌드 | 장착 스킬 | 사용 평균 | Δ승률 평균(pp) | 우세 칸 | 열세 칸 | 1인 Δ승률 ≥ +20pp 아레나 |")
	lines.append("| --- | --- | --- | --- | --- | --- | --- |")
	for build_id in ex.builds:
		if build_id == base: continue
		var pb: Dictionary = verdicts.per_build[build_id]
		var up := 0; var down := 0
		for d in pb.deltas:
			if d.win > 0.0: up += 1
			elif d.win < 0.0: down += 1
		lines.append("| `%s` | %s | %.2f | %+.1f | %d/%d | %d/%d | %d/%d |" % [build_id,pb.skill,pb.use_mean,pb.mean_win_delta*100.0,
			up,pb.deltas.size(),down,pb.deltas.size(),pb.dominant_arenas,ex.arenas.size()])
	lines.append("")
	lines.append("## 표 3 — 적 시그니처 파츠 사용 (아레나 × 파츠)")
	lines.append("")
	lines.append("한 전투에서 그 종족이 자기 시그니처 파츠를 실제로 해결한 횟수의 평균이다(`run_many.enemy_skill_uses_mean`). 각 칸은 그 아레나의 모든 빌드·인원 조합(%d칸)을 평균한 값이고, `최소`는 그 조합들 중 가장 낮은 칸이다. 게이트 G4의 기준은 전투당 평균 ≥ %.1f회다." % [ex.builds.size()*ex.party_sizes.size(),ENEMY_USE_FLOOR])
	lines.append("")
	lines.append("| 아레나 | 종족 | 파츠 | 전투당 평균 | 최소 칸 | 판정 |")
	lines.append("| --- | --- | --- | --- | --- | --- |")
	for arena_id in ex.arenas:
		for part_id in arena_parts(ex,arena_id):
			var values: Array = table.filter(func(r): return r.arena == arena_id).map(func(r): return float(r.stats.enemy_skill_uses_mean.get(part_id,0.0)))
			var mean := 0.0
			for v in values: mean += v
			mean /= maxi(1,values.size())
			var lowest: float = values.min() if not values.is_empty() else 0.0
			lines.append("| `%s` | %s | `%s` | %.2f | %.2f | %s |" % [arena_id,Abilities.DEFINITIONS[part_id].species,part_id,mean,lowest,"통과" if mean >= ENEMY_USE_FLOOR else "**미달**"])
	lines.append("")
	lines.append("준비가 끊긴 횟수(밀치기·피격)는 `interrupts_mean`으로 같은 행렬에서 잰다 — 전 칸 평균 %.2f회/전투." % interrupt_mean(table))
	lines.append("")
	if not absent.is_empty():
		lines.append("행렬의 6아레나에 자리가 없는 종족은 같은 시드 묶음으로 1종족 아레나를 따로 돌려 잰다 — G4가 파츠 8종을 빠짐없이 덮게 하기 위해서다(표 3과 같은 빌드 %d × 인원 %d 격자, `rules` 정책, 물자 0)." % [ex.builds.size(),ex.party_sizes.size()])
		lines.append("")
		lines.append("| 종족 | 파츠 | 전투당 평균 | 최소 칸 | 판정 |")
		lines.append("| --- | --- | --- | --- | --- |")
		for r in absent:
			lines.append("| %s | `%s` | %.2f | %.2f | %s |" % [r.species,r.part,r.mean,r.lowest,"통과" if r.mean >= ENEMY_USE_FLOOR else "**미달**"])
		lines.append("")
	lines.append("## 후보 판정 (설계 §5-4, 사전 고정)")
	lines.append("")
	lines.append("- **지배 후보**: 1인에서 아레나 %d개 중 %d개 이상에서 Δ승률 ≥ +%.0fpp." % [ex.arenas.size(),DOMINANT_ARENAS,DOMINANT_PP*100.0])
	lines.append("- **사장 후보(봇이 못 씀)**: 장착 스킬 사용 평균 < %.1f회/전투." % USE_FLOOR)
	lines.append("- **사장 후보(약함)**: 모든 칸에서 Δ승률 ≤ 0 이고 Δ피해 ≥ 0.")
	lines.append("")
	lines.append("| 판정 | 빌드 |")
	lines.append("| --- | --- |")
	lines.append("| 지배 후보 | %s |" % (", ".join(verdicts.dominant.map(func(b): return "`%s`" % b)) if not verdicts.dominant.is_empty() else "—"))
	lines.append("| 사장 후보(봇이 못 씀) | %s |" % (", ".join(verdicts.unused.map(func(b): return "`%s`" % b)) if not verdicts.unused.is_empty() else "—"))
	lines.append("| 사장 후보(약함) | %s |" % (", ".join(verdicts.weak.map(func(b): return "`%s`" % b)) if not verdicts.weak.is_empty() else "—"))
	lines.append("")
	lines.append("**후보는 확정이 아니다.** 이 판정은 검사한 조건(이 6아레나·2인원·물자 0·`rules` 정책) 안에서의 후보 탐지이며, 모든 상황에서의 우위나 열위를 증명하지 않는다. 수치 조정은 이 도구가 하지 않는다 — 사람이 보고서를 읽고 별도 커밋으로 결정한다(방법론 §5).")
	lines.append("")
	lines.append("## 발견 사항 — 사용되지 않은 스킬")
	lines.append("")
	var zero: Array = table.filter(func(r): return r.skill_mean == 0.0)
	var zero_builds: Dictionary = {}
	for r in zero: zero_builds[r.build] = true
	if zero_builds.is_empty():
		lines.append("사용 평균이 0인 칸은 없다 — 모든 빌드가 장착 스킬을 적어도 한 번은 눌렀다.")
	else:
		lines.append("사용 평균이 0인 칸이 있는 빌드: %s. 각 빌드를 사용 평균 0인 바로 그 칸의 config로·시드 3개씩 다시 돌리며, 매 라운드 `Abilities.legal(영웅, 스킬, 보이는 적 각각 또는 자신)`을 검사해 합법이었던 라운드 수를 셌다." % ", ".join(zero_builds.keys().map(func(b): return "`%s`" % b)))
		lines.append("")
		lines.append("| 빌드 | 스킬 | 사용 평균 0인 칸 | 진단 |")
		lines.append("| --- | --- | --- | --- |")
		for build_id in zero_builds:
			var zero_cells: Array = zero.filter(func(r): return r.build == build_id)
			var cells: Array = zero_cells.map(func(r): return "%d인/`%s`" % [r.party,r.arena])
			if zero_cells.size() == table.filter(func(r): return r.build == build_id).size(): cells = ["전 칸"]
			var line: String = str(diagnoses[build_id].line) if diagnoses.has(build_id) else "진단 없음"
			lines.append("| `%s` | %s | %s | %s |" % [build_id,equipped_skill(build_id),", ".join(cells),line])
	lines.append("")
	if not diagnoses.is_empty():
		lines.append("`합법 라운드 N/M`이 0이 아니면 스킬은 쓸 수 있었는데 규칙이 그 라운드를 고르지 않았다는 뜻이고(규칙 조건 쪽 문제), 0이면 `legal`이 한 번도 참이 되지 않았다는 뜻이다(사거리·대상·쿨다운 쪽 문제).")
		lines.append("")
	if explain: lines += explain_lines(table)
	lines.append("## 추적 계획")
	lines.append("")
	lines.append("1. 사장 후보의 원인을 규칙 조건과 사거리로 분리해 재실험(진단 줄이 가리키는 쪽만 바꾼다)")
	lines.append("2. 지배 후보는 비용 축(쿨다운·자원)을 하나만 바꿔 다시 측정")
	lines.append("3. 물자 축(0 vs 2)을 더해 스킬과 소모품의 대체 관계 측정")
	lines.append("4. 3인에서 동료도 같은 빌드를 드는 조건 추가(현재는 파티 전원이 같은 빌드다)")
	lines.append("")
	var md := FileAccess.open("res://docs/balance/skill-value.md",FileAccess.WRITE)
	md.store_string("\n".join(lines)+"\n")
	md.close()
	var payload := {"generated":today,"commit":commit_hash(),"quick":quick,"elapsed_ms":elapsed,
		"seed_set":{"id":ex.seed_set.id,"start":int(seeds[0]),"count":seeds.size()},
		"baseline_build":base,"table":table,"verdicts":verdicts,"diagnoses":diagnoses,"absent_species":absent}
	var js := FileAccess.open("res://docs/balance/skill-value.json",FileAccess.WRITE)
	js.store_string(JSON.stringify(payload,"  ")+"\n")
	js.close()
	print("wrote docs/balance/skill-value.md and .json (%.1fs, 지배 %d · 사장 %d)" % [elapsed/1000.0,verdicts.dominant.size(),verdicts.unused.size()+verdicts.weak.size()])
