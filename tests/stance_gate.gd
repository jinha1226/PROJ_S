extends SceneTree
## Manual tool: runs gate G7 (태세 생존) and writes docs/balance/stance-gates.md.
## Not part of the CI suite. Usage:
##   godot --headless --path . --script res://tests/stance_gate.gd -- [--quick]
const Runner = preload("res://expedition/sim/encounter_runner.gd")
const Arena = preload("res://expedition/sim/encounter_arena.gd")
const Stances = preload("res://expedition/ai/stances.gd")
const Floor = preload("res://expedition/level/continuous_floor.gd")
## 게이트 G7 (스펙 §4): 혼합 파티는 전 아레나에서, 단일 태세는 6아레나 중 4개 이상에서.
const MIXED_FLOOR := 0.85
const SINGLE_FLOOR := 0.60
const SINGLE_ARENAS := 4
static var experiments: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/balance_experiments.json"))

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var started := Time.get_ticks_msec()
	var ex: Dictionary = experiments.experiments.stance_gate
	var seeds: Array = range(int(ex.seed_set.start),int(ex.seed_set.start)+int(ex.seed_set.count))
	var quick: bool = "--quick" in OS.get_cmdline_user_args()
	var explain: bool = "--explain" in OS.get_cmdline_user_args()
	if quick: seeds = seeds.slice(0,8)
	var table: Array = []
	for size in ex.party_sizes:
		for build_id in ex.builds:
			for arena_id in ex.arenas:
				var config := matrix_config(ex,arena_id,size,build_id)
				var stats: Dictionary = Runner.run_many(config,seeds)
				stats.erase("runs")
				table.append({"party":size,"build":build_id,"arena":arena_id,"tier":config.arena.tier,"stats":stats})
				print("p%d %s %s: win %.2f [%.2f,%.2f] dmg %.1f rounds %.1f role %s" % [size,build_id,arena_id,
					stats.win_rate,stats.win_ci[0],stats.win_ci[1],stats.damage.mean,stats.rounds.mean,role_line(stats.role_rounds)])
	if explain:
		for line in explain_lines(table): print(line)
	var verdicts := decide(table,ex)
	write_report(table,verdicts,ex,seeds,Time.get_ticks_msec()-started,quick,explain)
	print("G7: %s (혼합 %d/%d 아레나 통과)" % ["통과" if verdicts.pass_all else "**미달**",verdicts.mixed_pass,ex.arenas.size()])
	quit(0)

func matrix_config(ex: Dictionary, arena_id: String, size: int, build_id: String) -> Dictionary:
	var spec: Dictionary = Arena.DEFAULT_SPEC.duplicate(true)
	spec.tier = ex.arenas[arena_id].tier
	spec.members = ex.arenas[arena_id].members.map(func(pair): return {"species_id":pair[0],"role":pair[1]})
	return {"arena":spec,"party_size":size,"build":build_id,"policy":ex.policies[0],
		"rules":ex.rules[ex.rules.keys()[0]],"supplies":ex.supplies,"max_rounds":60}

## `in_role/total` per stance, as a ratio; "—" when the stance held no seat.
func role_ratio(role_rounds: Dictionary, stance: String) -> String:
	var row: Dictionary = role_rounds.get(stance,{})
	if row.is_empty() or int(row.total) == 0: return "—"
	return "%.2f (%d/%d)" % [float(row.in_role)/float(row.total),int(row.in_role),int(row.total)]

func role_line(role_rounds: Dictionary) -> String:
	var parts: Array = []
	for stance in Stances.IDS:
		if role_rounds.has(stance): parts.append("%s %s" % [Stances.SHORT[stance],role_ratio(role_rounds,stance)])
	return " ".join(parts)

func row(table: Array, build: String, arena: String) -> Dictionary:
	for r in table:
		if r.build == build and r.arena == arena: return r
	return {}

## 판정은 사전 고정: 혼합은 전 아레나 ≥ MIXED_FLOOR, 단일 태세는 ≥ SINGLE_ARENAS 아레나에서 ≥ SINGLE_FLOOR.
func decide(table: Array, ex: Dictionary) -> Dictionary:
	var mixed: String = str(ex.mixed_build)
	var out := {"mixed_build":mixed,"mixed_pass":0,"mixed_fail_arenas":[],"per_build":{},"pass_all":true}
	for arena_id in ex.arenas:
		var r: Dictionary = row(table,mixed,arena_id)
		if float(r.stats.win_rate) >= MIXED_FLOOR: out.mixed_pass += 1
		else: out.mixed_fail_arenas.append(arena_id)
	if out.mixed_pass < ex.arenas.size(): out.pass_all = false
	for build_id in ex.builds:
		if build_id == mixed: continue
		var passed: Array = []
		for arena_id in ex.arenas:
			if float(row(table,build_id,arena_id).stats.win_rate) >= SINGLE_FLOOR: passed.append(arena_id)
		out.per_build[build_id] = {"pass_arenas":passed,"ok":passed.size() >= SINGLE_ARENAS}
		if passed.size() < SINGLE_ARENAS: out.pass_all = false
	return out


## `--explain` (설계 §6): 아레나 × 태세별로 효용이 고른 행동의 **최상위 고려
## 사항** 빈도. 판정에는 쓰이지 않는다 — 태세가 서로 다른 이유로 움직인다는
## 정량 증거를 보기 위한 표다.
func explain_lines(table: Array) -> Array:
	var lines: Array = []
	lines.append("## 설명 빈도 (`--explain`)")
	lines.append("")
	lines.append("각 칸은 그 태세가 효용 풀에서 고른 행동의 최상위 고려 사항을 빈도순으로 셋까지 적는다.")
	lines.append("모수 `n`은 `battle_stats.members[].explains`(멤버당 마지막 20라운드)를 시드 묶음 전체로 합산한 행동 수다.")
	lines.append("불길 회피·머뭇거림·후퇴선처럼 효용 풀이 아닌 단계가 답한 행동은 `explain`이 비어 있어 세지 않는다.")
	lines.append("")
	lines.append("| 빌드 | 아레나 | %s |" % " | ".join(Stances.IDS.map(func(id): return Stances.NAMES[id])))
	lines.append("| --- | --- |%s" % " --- |".repeat(Stances.IDS.size()))
	for r in table:
		var cells: Array = Stances.IDS.map(func(id): return Runner.explain_cell(r.stats.get("explain_top",{}),id))
		lines.append("| `%s` | `%s` | %s |" % [r.build,r.arena," | ".join(cells)])
	lines.append("")
	return lines

func commit_hash() -> String:
	var root: String = ProjectSettings.globalize_path("res://")
	var output: Array = []
	if OS.execute("git",["-C",root,"rev-parse","--short","HEAD"],output,true) != 0 or output.is_empty(): return "unknown"
	var text: String = str(output[0]).strip_edges()
	if text.is_empty(): return "unknown"
	var status: Array = []
	if OS.execute("git",["-C",root,"status","--porcelain"],status,true) == 0 and not status.is_empty() and not str(status[0]).strip_edges().is_empty():
		text += "-dirty"
	return text

func spec_line(ex: Dictionary) -> String:
	var spec: Dictionary = Arena.DEFAULT_SPEC
	return "size %d · room %s · door %s · pillars %s · party_entry %s · sight 5 · supplies %s" % [spec.size,str(spec.room),str(spec.door),str(spec.pillars),str(spec.party_entry),str(ex.supplies.map(func(v): return int(v)))]

func write_report(table: Array, verdicts: Dictionary, ex: Dictionary, seeds: Array, elapsed: int, quick: bool, explain: bool = false) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/balance"))
	var today := Time.get_date_string_from_system()
	var lines: Array = []
	lines.append("# 태세 게이트 G7 결과")
	lines.append("")
	lines.append("생성: `tests/stance_gate.gd`(수동 도구) · 커밋 `%s` · 날짜 %s%s" % [commit_hash(),today," · **--quick 실행(축약 시드)**" if quick else ""])
	lines.append("근거: [밸런스 방법론](../balance-method.ko.md) §5 · 설계: [태세 설계](../superpowers/specs/2026-09-23-stances-design.md) §4")
	lines.append("")
	lines.append("- 시드 묶음: `%s` %d개 (%d~%d)" % [ex.seed_set.id,seeds.size(),int(seeds[0]),int(seeds[seeds.size()-1])])
	lines.append("- 인원: %s · 봇 정책: `%s`(영웅도 동료와 같은 규칙 목록을 읽고 `Tactics.choose`가 고른 행동을 누른다)" % [str(ex.party_sizes),ex.policies[0]])
	lines.append("- 규칙: `%s` (`solo_actions %d` / `solo_max_members %d`)" % [ex.rules.keys()[0],int(ex.rules[ex.rules.keys()[0]].solo_actions),int(ex.rules[ex.rules.keys()[0]].solo_max_members)])
	lines.append("- **물자 0**: `supplies %s` — 태세의 값이 회복품에 가려지지 않는다." % str(ex.supplies.map(func(v): return int(v))))
	lines.append("- 아레나 공통 spec: %s" % spec_line(ex))
	lines.append("- 행렬: 빌드 %d × 아레나 %d × 시드 %d = %d전투" % [ex.builds.size(),ex.arenas.size(),seeds.size(),ex.builds.size()*ex.arenas.size()*seeds.size()])
	lines.append("- 실행 시간: %.1f초" % (elapsed/1000.0))
	lines.append("- 솔로 HP 스케일: `SOLO_HP_PERCENT %d` / `SOLO_HP_MIN %d` / `SOLO_HP_MAX %d` (3인 실험이라 적용되지 않는다)" % [Floor.SOLO_HP_PERCENT,Floor.SOLO_HP_MIN,Floor.SOLO_HP_MAX])
	lines.append("")
	lines.append("> 명중 판정이 없으므로 같은 커밋·같은 시드·같은 빌드는 같은 전투를 낸다 — 표의 모든 칸은 재실행으로 재현된다.")
	lines.append("> `역할 유지`는 `battle_stats.members[id].role_rounds`(`Stances.in_role`이 참인 라운드 / 전체 라운드)를 그 태세를 든 자리 전부에 대해 시드 묶음 전체로 합산한 비율이다.")
	lines.append("")
	lines.append("빌드 구성:")
	lines.append("")
	lines.append("| 빌드 | 태세 | 장착 | 규칙 |")
	lines.append("| --- | --- | --- | --- |")
	for build_id in ex.builds:
		var b: Dictionary = Runner.build(build_id)
		var stance: String = ", ".join(b.stances) if b.has("stances") else str(b.get("stance","CHARGER"))
		var equipped: String = ", ".join(b.get("equipped",[]))
		if b.has("equipped_by_member"): equipped = " / ".join(b.equipped_by_member.map(func(e): return ",".join(e)))
		var rules: Array = b.get("rules",[]).map(func(r): return "%s→%s(%s)" % [r[0],r[1],r[2]])
		lines.append("| `%s` | %s | %s | %s |" % [build_id,stance,equipped,", ".join(rules)])
	lines.append("")
	lines.append("아레나 구성:")
	lines.append("")
	lines.append("| 아레나 | 티어 | 구성 |")
	lines.append("| --- | --- | --- |")
	for arena_id in ex.arenas:
		var names: Array = ex.arenas[arena_id].members.map(func(pair): return "%s/%s" % [pair[0],pair[1]])
		lines.append("| `%s` | %s | %s |" % [arena_id,ex.arenas[arena_id].tier,", ".join(names)])
	lines.append("")
	lines.append("## 표 1 — 빌드 × 아레나")
	lines.append("")
	lines.append("| 빌드 | 아레나 | 티어 | 승률 [95% CI] | 평균 피해(개인별) | 평균 라운드 | 역할 유지 |")
	lines.append("| --- | --- | --- | --- | --- | --- | --- |")
	for r in table:
		var st: Dictionary = r.stats
		lines.append("| `%s` | `%s` | %s | %.2f [%.2f, %.2f] | %.1f | %.1f | %s |" % [r.build,r.arena,r.tier,
			st.win_rate,st.win_ci[0],st.win_ci[1],st.damage.mean,st.rounds.mean,role_line(st.role_rounds)])
	lines.append("")
	lines.append("## 표 2 — 태세별 역할 유지 비율")
	lines.append("")
	lines.append("| 빌드 | 아레나 | %s |" % " | ".join(Stances.IDS.map(func(id): return Stances.NAMES[id])))
	lines.append("| --- | --- | %s" % " --- |".repeat(Stances.IDS.size()))
	for r in table:
		var cells: Array = Stances.IDS.map(func(id): return role_ratio(r.stats.role_rounds,id))
		lines.append("| `%s` | `%s` | %s |" % [r.build,r.arena," | ".join(cells)])
	lines.append("")
	lines.append("## 게이트 G7 판정 (스펙 §4, 사전 고정)")
	lines.append("")
	lines.append("- **혼합 파티**(`%s`, 돌·거·호): 아레나 %d개 **전부**에서 승률 ≥ %.2f." % [verdicts.mixed_build,ex.arenas.size(),MIXED_FLOOR])
	lines.append("- **단일 태세 파티**: 각 빌드가 아레나 %d개 중 %d개 이상에서 승률 ≥ %.2f (어느 태세도 사장 아님)." % [ex.arenas.size(),SINGLE_ARENAS,SINGLE_FLOOR])
	lines.append("")
	lines.append("| 빌드 | 기준 | 충족 아레나 | 판정 |")
	lines.append("| --- | --- | --- | --- |")
	lines.append("| `%s` | 전 아레나 ≥ %.2f | %d/%d%s | %s |" % [verdicts.mixed_build,MIXED_FLOOR,verdicts.mixed_pass,ex.arenas.size(),
		"" if verdicts.mixed_fail_arenas.is_empty() else " (미달: %s)" % ", ".join(verdicts.mixed_fail_arenas.map(func(a): return "`%s`" % a)),
		"통과" if verdicts.mixed_pass == ex.arenas.size() else "**미달**"])
	for build_id in verdicts.per_build:
		var pb: Dictionary = verdicts.per_build[build_id]
		lines.append("| `%s` | %d/%d 아레나 ≥ %.2f | %d/%d (%s) | %s |" % [build_id,SINGLE_ARENAS,ex.arenas.size(),SINGLE_FLOOR,
			pb.pass_arenas.size(),ex.arenas.size(),", ".join(pb.pass_arenas.map(func(a): return "`%s`" % a)) if not pb.pass_arenas.is_empty() else "—",
			"통과" if pb.ok else "**미달**"])
	lines.append("")
	lines.append("**G7 종합: %s**" % ("통과" if verdicts.pass_all else "미달"))
	lines.append("")
	if explain: lines += explain_lines(table)
	lines.append("솔로 기준(`tests/solo_balance.gd` ≥ 3/8)은 이 도구가 아니라 CI 스위트가 잰다 — 아래 \"솔로 기준\" 절에 결과를 손으로 적는다.")
	lines.append("")
	var md := FileAccess.open("res://docs/balance/stance-gates.md",FileAccess.WRITE)
	md.store_string("\n".join(lines)+"\n")
	md.close()
	var payload := {"generated":today,"commit":commit_hash(),"quick":quick,"elapsed_ms":elapsed,
		"seed_set":{"id":ex.seed_set.id,"start":int(seeds[0]),"count":seeds.size()},"table":table,"verdicts":verdicts}
	var js := FileAccess.open("res://docs/balance/stance-gates.json",FileAccess.WRITE)
	js.store_string(JSON.stringify(payload,"  ")+"\n")
	js.close()
	print("wrote docs/balance/stance-gates.md and .json (%.1fs)" % (elapsed/1000.0))
