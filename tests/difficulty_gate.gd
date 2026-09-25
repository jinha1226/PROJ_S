extends SceneTree
## §5 난이도 게이트 (manual): the hero who cleared floors 1..N−1 fights each
## pack of floor N from full HP. Writes docs/balance/difficulty-gate.{json,md}.
## Not part of the regular suite loop: it builds dozens of floors.
const Gate = preload("res://expedition/sim/difficulty_gate.gd")
const DEPTHS := [2,3,4,5]
const KITS := ["sword","fire"]
const SEEDS := [100,101,102]
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var first: Dictionary = Gate.run_floor(Gate.prepare(100,"sword",2))
	check(first == Gate.run_floor(Gate.prepare(100,"sword",2)),"the same seed reproduces the whole floor")
	check(not first.fights.is_empty(),"floor two has packs to fight")
	check(first.fights.all(func(f): return f.result in ["WIN","DEFEAT","TIMEOUT"] and int(f.hp_lost_percent) >= 0 and int(f.hp_lost_percent) <= 100),"every fight is accounted for")
	var base: Dictionary = Gate.baseline(100,"sword",3)
	var half: Dictionary = Gate.baseline(100,"sword",3,50)
	check(int(base.xp) > 0 and int(half.xp) == int(base.xp)/2,"half a clear is half the kill XP")
	var rows: Array = []
	for depth in DEPTHS:
		for kit in KITS:
			for share in [100,50]:
				var losses: Array = []; var camps := 0; var wins := 0; var fights := 0
				for seed in SEEDS:
					var floor_row: Dictionary = Gate.run_floor(Gate.prepare(seed,kit,depth,share))
					losses.append(float(floor_row.mean_loss_percent))
					camps += 1 if floor_row.camp_needed else 0
					wins += int(floor_row.wins); fights += floor_row.fights.size()
				var mean: float = losses.reduce(func(a,b): return a+b,0.0)/maxf(1.0,losses.size())
				rows.append({"depth":depth,"kit":kit,"share":share,"mean_loss_percent":snappedf(mean,0.1),"camp_rate":float(camps)/SEEDS.size(),"win_rate":float(wins)/maxf(1.0,fights)})
	for row in rows:
		if row.share != 100: continue
		# Loss is averaged only over packs reached before defeat. A weaker hero
		# can die early and therefore show a lower mean than one that survived to
		# later, harder packs; the monotonic invariant belongs to the inputs.
		var complete: Dictionary = Gate.baseline(100,str(row.kit),int(row.depth))
		var reduced: Dictionary = Gate.baseline(100,str(row.kit),int(row.depth),50)
		check(int(complete.xp) >= int(reduced.xp) and reduced.essences.keys().all(func(id): return int(complete.essences.get(id,0)) >= int(reduced.essences[id])),"%d층 %s: a full clear supplies at least as much XP and essence" % [row.depth,row.kit])
	write(rows)
	print("Difficulty gate: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func write(rows: Array) -> void:
	var json := FileAccess.open("res://docs/balance/difficulty-gate.json",FileAccess.WRITE)
	json.store_string(JSON.stringify({"seeds":SEEDS,"rows":rows},"  ")); json.close()
	var lines: Array = ["# 난이도 게이트","","`tests/difficulty_gate.gd`가 쓴다. 기준 주인공(1~N−1층을 모두 잡은 레벨과 이능)과 절반만 잡은 주인공이 N층 무리를 하나씩, 매번 HP를 채우고 싸운 결과다. 합격선: 기준 주인공의 전투당 HP 손실 25~40%, 야영 필요, 절반 주인공은 뚜렷하게 더 잃음.","","자동 전술 봇의 진단값이다. 매 전투 HP·MP를 채우고 첫 패배에서 중단하므로 실제 원정 완주율로 읽으면 안 된다.","","| 층 | 킷 | 기준 | 전투당 HP 손실 | 야영 필요 비율 | 승률 | 합격선 |","| --- | --- | --- | --- | --- | --- | --- |"]
	for row in rows:
		var verdict: String = "—" if row.share != 100 else ("통과" if float(row.mean_loss_percent) >= 25.0 and float(row.mean_loss_percent) <= 40.0 and float(row.camp_rate) > 0.0 else "조정 필요")
		lines.append("| %d | %s | %s | %.1f%% | %.0f%% | %.0f%% | %s |" % [int(row.depth),str(row.kit),"다 잡음" if row.share == 100 else "절반",float(row.mean_loss_percent),float(row.camp_rate)*100.0,float(row.win_rate)*100.0,verdict])
	var md := FileAccess.open("res://docs/balance/difficulty-gate.md",FileAccess.WRITE)
	md.store_string("\n".join(lines)+"\n"); md.close()
