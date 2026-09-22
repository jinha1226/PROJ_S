extends SceneTree
## Scripted solo run: shortest path to the relic and back, fighting whatever is
## seen, healing between fights. Guards the first-playtest tuning; a real
## player has guard/push/terrain and should do better than this bot.
const Session = preload("res://expedition/session.gd")
const Objective = preload("res://expedition/expedition_objective.gd")
const SEEDS := 8
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func route(s, target: Vector2i) -> Array:
	var goals: Array = [target]
	for d in s.DIRECTIONS:
		if s.is_free(target+d) and s.melee_reach(target+d,target): goals.append(target+d)
	var r: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,s.party[0].pos,goals,func(a,b): return s.can_step(a,b),func(_p): return 100)
	return r.path if r.found else []

## Shopping list in priority order; buys while funds last, then departs.
const SHOPPING := ["supply:0","supply:5","supply:5","supply:1","supply:1","food","food","food","food","food","food","food","food","torch","supply:0","supply:5","torch"]
func provision(s) -> void:
	for id in SHOPPING:
		if s.bank >= s.price(id): s.buy(id)

func play(s) -> Dictionary:
	provision(s)
	s.depart()
	var hero: Dictionary = s.party[0]
	var actions := 0; var heals := 0; var stuck := 0
	var calming_before: int = s.supplies[1]
	var goal := "relic"
	while s.phase == "BATTLE" and actions < 1500:
		var target: Vector2i = s.objective.pos if goal == "relic" else s.entry_position()
		if not s.combat_enemies().is_empty():
			if hero.hp < 14 and s.supplies[0] > 0 and s.use_supply(0): heals += 1; actions += 1; continue
			if hero.hp < 10 and s.supplies[5] > 0 and s.use_supply(5): heals += 1; actions += 1; continue
			if s.auto_attack(): actions += 1; continue
			s.act("WAIT",hero.pos); actions += 1; continue
		if hero.stress >= 125 and s.supplies[1] > 0 and s.use_supply(1): actions += 1; continue
		if s.light < 35 and s.torches > 0 and s.use_torch(): continue
		if hero.hp <= hero.max_hp-20 and s.supplies[0] > 0 and s.use_supply(0): heals += 1; actions += 1; continue
		if hero.hp <= hero.max_hp-10 and s.supplies[5] > 0 and s.use_supply(5): heals += 1; actions += 1; continue
		if goal == "relic" and Objective.error(s).is_empty():
			s.pickup_relic(); actions += 1; goal = "home"; continue
		if goal == "home" and s.return_error().is_empty():
			s.return_home(); break
		var path := route(s,target)
		if path.size() < 2:
			stuck += 1
			if stuck > 5: break
			s.act("WAIT",hero.pos); actions += 1; continue
		if not s.act("MOVE",path[1]): s.act("WAIT",hero.pos)
		actions += 1
	return {"reason":s.result.get("reason","STUCK"),"actions":actions,"heals":heals,"hp":hero.hp,"food":s.result.get("remaining_food",s.food),"light":s.result.get("remaining_light",s.light),"bank":s.bank,"stress":hero.stress,"calming":calming_before-int(s.result.get("remaining_stock",{}).get("supply:1",s.supplies[1]))}

func run() -> void:
	var wins := 0
	for seed_value in range(SEEDS):
		var row := play(Session.new(seed_value,true,false,true))
		print("seed %d: %s · 행동 %d · 회복 %d · 체력 %d · 식량 %d · 밝기 %d · 자금 %d · 스트레스 %d" % [seed_value,row.reason,row.actions,row.heals,row.hp,row.food,row.light,row.bank,row.stress])
		if row.reason == "SUCCESS": wins += 1
		check(row.reason != "STUCK","bot never gets stuck (seed %d)" % seed_value)
		check(row.actions >= 120 and row.actions <= 300,"round trip within the target action band (seed %d: %d)" % [seed_value,row.actions])
		check(row.food > 0 and row.light > 0,"supplies last a round trip (seed %d)" % seed_value)
	check(wins >= 6,"scripted solo run completes on most seeds (%d/%d)" % [wins,SEEDS])
	var campaign = Session.new(0,true,false,true)
	for expedition in range(4):
		if expedition > 0:
			campaign.refit()
			if expedition >= 2:
				var funds: int = campaign.bank
				check(campaign.rest_town() and campaign.bank == funds-20,"earned funds pay for repeat-run recovery")
		var row := play(campaign)
		print("repeat %d: %s" % [expedition+1,row])
		check(row.reason == "SUCCESS","same hero completes repeat expedition %d" % (expedition+1))
		check(row.hp >= 10,"repeat expedition keeps a health margin (%d)" % (expedition+1))
		check(row.actions <= 400 and row.food > 0 and row.light > 0,"repeat expedition stays within supply and action budgets")
	print("Solo balance: %d failures; %d/%d wins" % [failures,wins,SEEDS]); quit(1 if failures else 0)
