extends SceneTree
## Manual tool: runs the action-economy matrix and writes docs/balance/action-economy.{md,json}.
## Not part of the CI suite. Usage:
##   godot --headless --path . --script res://tests/action_economy.gd -- [--quick]
const Runner = preload("res://expedition/sim/encounter_runner.gd")
const Arena = preload("res://expedition/sim/encounter_arena.gd")
const Session = preload("res://expedition/session.gd")
const Floor = preload("res://expedition/continuous_floor.gd")
static var experiments: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/balance_experiments.json"))

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var started := Time.get_ticks_msec()
	var ex: Dictionary = experiments.experiments.action_economy
	var seeds: Array = range(int(ex.seed_set.start),int(ex.seed_set.start)+int(ex.seed_set.count))
	var quick: bool = "--quick" in OS.get_cmdline_user_args()
	if quick: seeds = seeds.slice(0,20)
	var table: Array = []
	for rule_id in ex.rules:
		for size in ex.party_sizes:
			for build_id in ex.builds:
				for arena_id in ex.arenas:
					var spec: Dictionary = Arena.DEFAULT_SPEC.duplicate(true)
					spec.tier = ex.arenas[arena_id].tier
					spec.members = ex.arenas[arena_id].members.map(func(pair): return {"species_id":pair[0],"role":pair[1]})
					var config := {"arena":spec,"party_size":size,"build":build_id,"policy":ex.policies[0],"rules":ex.rules[rule_id],"supplies":ex.supplies,"max_rounds":60}
					var stats: Dictionary = Runner.run_many(config,seeds)
					stats.erase("runs")
					table.append({"rule":rule_id,"party":size,"build":build_id,"arena":arena_id,"tier":spec.tier,"stats":stats})
					print("%s p%d %s %s: win %.2f [%.2f,%.2f] distinct %d dmg %.1f p95 %.1f rounds %.1f" % [rule_id,size,build_id,arena_id,stats.win_rate,stats.win_ci[0],stats.win_ci[1],stats.distinct_outcomes,stats.damage.mean,stats.damage.p95,stats.rounds.mean])
	var verdicts: Dictionary = decide(table,ex)
	write_report(table,verdicts,ex,seeds,Time.get_ticks_msec()-started,quick)
	quit(0)

func row(table: Array, rule: String, party: int, build: String, arena: String) -> Dictionary:
	for r in table:
		if r.rule == rule and r.party == party and r.build == build and r.arena == arena: return r.stats
	return {}

func decide(table: Array, ex: Dictionary) -> Dictionary:
	var deep: Array = ex.arenas.keys().filter(func(id): return ex.arenas[id].tier == "deep")
	var out: Dictionary = {}
	for rule_id in ex.rules:
		var a: bool = deep.all(func(id): return row(table,rule_id,1,"melee_1",id).win_rate >= 0.70)
		var b: bool = deep.all(func(id): return row(table,rule_id,2,"melee_1",id).damage.mean < row(table,rule_id,1,"melee_1",id).damage.mean)
		var c: bool = deep.all(func(id): return row(table,rule_id,3,"melee_1",id).win_rate >= 0.90)
		out[rule_id] = {"a":a,"b":b,"c":c,"pass":a and b and c}
	var order := ["current","B","A"]
	out["candidate"] = ""
	for rule_id in order:
		if out.has(rule_id) and out[rule_id]["pass"]:
			out["candidate"] = rule_id
			break
	return out

func commit_hash() -> String:
	var output: Array = []
	var code := OS.execute("git",["-C",ProjectSettings.globalize_path("res://"),"rev-parse","--short","HEAD"],output,true)
	if code != 0 or output.is_empty(): return "unknown"
	var text: String = str(output[0]).strip_edges()
	return text if not text.is_empty() else "unknown"

func spec_line(ex: Dictionary) -> String:
	var spec: Dictionary = Arena.DEFAULT_SPEC
	return "size %d · room %s · door %s · pillars %s · party_entry %s · light %d · supplies %s" % [spec.size,str(spec.room),str(spec.door),str(spec.pillars),str(spec.party_entry),spec.light,str(ex.supplies.map(func(v): return int(v)))]

func write_report(table: Array, verdicts: Dictionary, ex: Dictionary, seeds: Array, elapsed: int, quick: bool) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/balance"))
	var today := Time.get_date_string_from_system()
	var lines: Array = []
	lines.append("# 행동 경제 실험 결과")
	lines.append("")
	lines.append("생성: `tests/action_economy.gd`(수동 도구) · 커밋 `%s` · 날짜 %s%s" % [commit_hash(),today," · **--quick 실행(축약 시드)**" if quick else ""])
	lines.append("근거: [밸런스 방법론](../balance-method.ko.md) §8-1 · 설계: [조우 시뮬레이터 설계](../superpowers/specs/2026-09-22-encounter-sim-design.md) §5.2·§6")
	lines.append("")
	lines.append("- 시드 묶음: `%s` %d개 (%d~%d)" % [ex.seed_set.id,seeds.size(),int(seeds[0]),int(seeds[seeds.size()-1])])
	lines.append("- 솔로 HP 스케일: `SOLO_HP_PERCENT %d` / `SOLO_HP_MIN %d` / `SOLO_HP_MAX %d` (파티 인원 1일 때만 적용, 실험 조건의 일부)" % [Floor.SOLO_HP_PERCENT,Floor.SOLO_HP_MIN,Floor.SOLO_HP_MAX])
	lines.append("- 봇 정책: `%s` (`expedition/sim/bot_policy.gd`: 접근 → 회복·방어 → 자동 공격)" % ex.policies[0])
	lines.append("- 아레나 공통 spec: %s" % spec_line(ex))
	lines.append("- 행렬: 규칙 %d × 인원 %d × 빌드 %d × 아레나 %d × 시드 %d = %d전투" % [ex.rules.size(),ex.party_sizes.size(),ex.builds.size(),ex.arenas.size(),seeds.size(),ex.rules.size()*ex.party_sizes.size()*ex.builds.size()*ex.arenas.size()*seeds.size()])
	lines.append("- 실행 시간: %.1f초" % (elapsed/1000.0))
	lines.append("")
	lines.append("> 전투 자체는 결정론적(명중 판정 없음)이며, 시드는 적 배치만 바꾼다. 신뢰구간은 배치 분산에 대한 것이다.")
	lines.append("> `distinct`는 시드 묶음에서 나온 서로 다른 `(결과, 라운드, 피해)` 조합의 수다 — 1이면 그 칸의 구간은 배치 분산이 없다는 뜻이다.")
	lines.append("")
	lines.append("아레나 구성:")
	lines.append("")
	lines.append("| 아레나 | 티어 | 구성 |")
	lines.append("| --- | --- | --- |")
	for arena_id in ex.arenas:
		var names: Array = ex.arenas[arena_id].members.map(func(pair): return "%s/%s" % [pair[0],pair[1]])
		lines.append("| `%s` | %s | %s |" % [arena_id,ex.arenas[arena_id].tier,", ".join(names)])
	lines.append("")
	lines.append("규칙:")
	lines.append("")
	lines.append("| 규칙 | `solo_actions` | `solo_max_members` |")
	lines.append("| --- | --- | --- |")
	for rule_id in ex.rules:
		lines.append("| %s | %d | %d |" % [rule_id,int(ex.rules[rule_id].solo_actions),int(ex.rules[rule_id].solo_max_members)])
	lines.append("")
	lines.append("## 표 1 — 규칙 × 인원 × 빌드 × 아레나")
	lines.append("")
	lines.append("| 규칙 | 인원 | 빌드 | 아레나 | 티어 | 승률 [95% CI] | distinct | 평균 피해(개인별) | p95 피해 | 평균 라운드 | 첫 사망 라운드 중앙값 | 회복 사용 평균 |")
	lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	for r in table:
		var st: Dictionary = r.stats
		var death: String = "—" if st.first_death.median == 0.0 else "%.0f" % st.first_death.median
		lines.append("| %s | %d | %s | `%s` | %s | %.2f [%.2f, %.2f] | %d | %.1f | %.1f | %.1f | %s | %.2f |" % [r.rule,r.party,r.build,r.arena,r.tier,st.win_rate,st.win_ci[0],st.win_ci[1],st.distinct_outcomes,st.damage.mean,st.damage.p95,st.rounds.mean,death,st.heals.mean])
	lines.append("")
	lines.append("## 표 2 — 결정 규칙 판정 (설계 §6, 사전 고정)")
	lines.append("")
	lines.append("판정은 `tactical` 정책·`melee_1` 빌드·심부 아레나 2개(`deep_mixed`, `deep_caster`)에서만 본다.")
	lines.append("")
	lines.append("| 규칙 | (a) 솔로 심부 승률 ≥ 70% | (b) 2인 개인별 평균 피해 < 솔로 | (c) 3인 심부 승률 ≥ 90% | 통과 |")
	lines.append("| --- | --- | --- | --- | --- |")
	for rule_id in ex.rules:
		var v: Dictionary = verdicts[rule_id]
		lines.append("| %s | %s | %s | %s | %s |" % [rule_id,"통과" if v.a else "실패","통과" if v.b else "실패","통과" if v.c else "실패","**통과**" if v["pass"] else "실패"])
	lines.append("")
	lines.append("## 판정")
	lines.append("")
	var deep: Array = ex.arenas.keys().filter(func(id): return ex.arenas[id].tier == "deep")
	if verdicts["candidate"] != "":
		lines.append("**채택 후보: %s.** 세 조건을 모두 만족하는 규칙 중 현행과의 변경 폭이 작은 순(현행 > B > A)으로 고른 결과다." % verdicts["candidate"])
	else:
		lines.append("**보류.** 세 조건을 모두 만족하는 규칙이 없다. 설계 §6에 따라 사망 원인을 아래에 기록하고 실험안을 다시 정의한다.")
	lines.append("")
	lines.append("심부 아레나에서 솔로(`melee_1`)가 무너지는 지점:")
	lines.append("")
	lines.append("| 규칙 | 아레나 | 승률 | 첫 사망 라운드 중앙값 | p95 피해 | 첫 행동 이전 피해 평균 | 평균 라운드 |")
	lines.append("| --- | --- | --- | --- | --- | --- | --- |")
	for rule_id in ex.rules:
		for arena_id in deep:
			var st: Dictionary = row(table,rule_id,1,"melee_1",arena_id)
			var death: String = "—" if st.first_death.median == 0.0 else "%.0f" % st.first_death.median
			lines.append("| %s | `%s` | %.2f | %s | %.1f | %.1f | %.1f |" % [rule_id,arena_id,st.win_rate,death,st.damage.p95,st.before_first.mean,st.rounds.mean])
	lines.append("")
	lines.append("이 도구는 **후보를 계산해 출력할 뿐 채택을 확정하지 않는다.** 채택 확정은 사람이 이 보고서를 읽고 별도 커밋으로 한다(설계 §6·§8).")
	lines.append("")
	var md := FileAccess.open("res://docs/balance/action-economy.md",FileAccess.WRITE)
	md.store_string("\n".join(lines))
	md.close()
	var payload := {"generated":today,"commit":commit_hash(),"quick":quick,"elapsed_ms":elapsed,
		"seed_set":{"id":ex.seed_set.id,"start":int(seeds[0]),"count":seeds.size()},"table":table,"verdicts":verdicts}
	var js := FileAccess.open("res://docs/balance/action-economy.json",FileAccess.WRITE)
	js.store_string(JSON.stringify(payload,"  ")+"\n")
	js.close()
	print("wrote docs/balance/action-economy.md and .json (%.1fs, candidate: %s)" % [elapsed/1000.0,verdicts["candidate"] if verdicts["candidate"] != "" else "보류"])
