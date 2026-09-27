extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Drop = preload("res://expedition/progression/stone_drop.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Mobile = preload("res://expedition/progression/attack_wait.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func setup_session():
	var s = Session.new(731,false,true,true,3); s.depart(); s.manual_mode = true
	Fixture.arena(s,8); s.npcs.clear()
	for actor in s.party: actor.level = 6; actor.equipped_abilities = []; actor.essences = {}
	return s
func stone_for(effect: String) -> String:
	for id in Mobile.catalog():
		if Mobile.effect_id(str(id)) == effect: return str(id)
	push_error("missing test effect "+effect); return ""
func auto_actor(effects: Array) -> Dictionary:
	return {"hp":100,"level":6,"combat_profile":Mobile.PROFILE,"equipped_abilities":effects.map(func(id): return stone_for(str(id))),"essences":{},"gear":{"weapon":{"type":"bow"}}}
func run() -> void:
	var s = setup_session()
	s.grant_part("FIRE_CALLER/cut",true)
	check(s.pending_stone_drops.is_empty(),"non-interactive simulations never await loot choices")
	s.interactive_stone_drops = true
	s.grant_part("FIRE_CALLER/cut",true); s.grant_part("FIRE_CALLER/broken",true)
	check(s.pending_stone_drops.size() == 2,"burst loot is queued FIFO")
	var token: int = s.pending_stone_drops[0].token
	var bag: Dictionary = s.parts_bag.duplicate(true)
	var tick: int = s.time
	check(not s.submit("WAIT",s.party[0].pos) and not s.auto_step(),"pending decision blocks new manual and auto actions")
	check(s.time == tick,"waiting for a card does not advance time")
	check(not s.resolve_stone_drop(token+1,0).is_empty() and s.parts_bag == bag,"stale and out-of-order tokens cannot consume loot")
	check(not s.resolve_stone_drop(token,99).is_empty(),"unknown member rejected")
	s.party[1].hp = 0
	check(s.resolve_stone_drop(token,1) == "쓰러짐" and s.parts_bag == bag,"downed members cannot absorb")
	s.party[1].hp = s.party[1].max_hp
	s.phase = "BATTLE"
	check(s.absorb_essence(0,"FIRE_CALLER/cut") == "영혼석 선택 중","inventory cannot consume reserved drops")
	check(s.resolve_stone_drop(token,1).is_empty(),"companion can take the exact new drop even during combat")
	check(Essences.absorbed(s.party[1],"FIRE_CALLER/cut") and not Essences.absorbed(s.party[0],"FIRE_CALLER/cut"),"permanent absorption belongs to the selected companion")
	check(int(s.parts_bag["FIRE_CALLER/cut"]) == int(bag["FIRE_CALLER/cut"])-1 and s.pending_stone_drops.size() == 1,"one decision consumes exactly one stone")
	check(not s.resolve_stone_drop(token,1).is_empty(),"double taps cannot repeat absorption")
	token = s.pending_stone_drops[0].token
	check(s.resolve_stone_drop(token,-1).is_empty() and int(s.parts_bag["FIRE_CALLER/broken"]) == 1,"keep closes the card without consuming loot")
	check(s.absorb_essence(0,"FIRE_CALLER/broken") == "전투 중","ordinary inventory absorption still requires safety")
	s.grant_part("FIRE_CALLER/cut",true); token = s.pending_stone_drops[0].token
	check(s.resolve_stone_drop(token,1) == "이미 흡수함","duplicate absorption is refused")
	check(s.resolve_stone_drop(token,-2).is_empty() and s.parts_bag["FIRE_CALLER/cut"] == 1,"leave discards only the current copy")
	s.party[0].level = 1; s.party[0].equipped_abilities = ["RAT_GNAW/cut"]
	check(Drop.unavailable(s.party[0],"FIRE_CALLER/broken") == "빈 슬롯 없음","only unlocked permanent slots may be used")
	s.grant_part("FIRE_CALLER/broken",true); token = s.pending_stone_drops[0].token
	s.phase = "DEFEAT"
	check(s.resolve_stone_drop(token,2) == "원정 종료" and s.resolve_stone_drop(token,-1).is_empty(),"result loot may be kept but cannot revive a finished run")
	# Real monster death queues exactly once; an independent NPC hunt does not.
	s = setup_session(); s.interactive_stone_drops = true
	var foe: Dictionary = s.enemies[0]; foe.hp = 0; foe.part_id = "RAT_GNAW"; foe.species_id = "dcss_rat"; foe.erase("part_rolled")
	s.roll_part(foe); s.roll_part(foe)
	check(s.pending_stone_drops.size() == 1,"actual first-kill drop produces one card")
	foe.erase("part_rolled"); s.roll_part(foe,[])
	check(s.pending_stone_drops.size() == 1,"unparticipated NPC kills do not produce party cards")
	# Pure fit previews do not alter actor state or invent absent seeds.
	var actor := auto_actor([]); var copy: Dictionary = actor.duplicate(true)
	check(Drop.fit(actor,stone_for("fire_chain")).kind == "missing","unseeded fire chain is marked as needing preparation")
	check(actor == copy,"fit is a read-only preview")
	actor = auto_actor(["fire_hit"])
	check(Drop.fit(actor,stone_for("fire_chain")).kind == "linked","existing burn producer supports an incoming chain")
	actor = auto_actor(["fire_chain"])
	check(Drop.fit(actor,stone_for("fire_hit")).kind == "linked","incoming producer enables a previously unseeded chain")
	actor = auto_actor(["fire_hit"]); actor.sealed = {stone_for("fire_hit"):true}
	check(Drop.fit(actor,stone_for("fire_chain")).kind == "missing","sealed producers do not count")
	actor = auto_actor(["ice_chain"])
	check(Drop.fit(actor,stone_for("ice_shatter")).kind == "missing","conditional producers need their own seed")
	actor = auto_actor(["ice_hit","ice_chain"])
	check(Drop.fit(actor,stone_for("ice_shatter")).kind == "linked","multi-step slow freeze shatter chain is recognized")
	actor = auto_actor(["water_hit"])
	check(Drop.fit(actor,stone_for("water_air")).kind == "linked","wet alone now supports the water lightning chain")
	actor = auto_actor(["water_hit","air_hit"])
	check(Drop.fit(actor,stone_for("water_air")).kind == "linked","extra lightning does not introduce another prerequisite")
	actor = auto_actor(["fire_poison"])
	check(Drop.fit(actor,stone_for("poison_hit")).kind == "linked" and Drop.fit(actor,stone_for("fire_hit")).kind == "neutral","poison explosion needs only its poison seed")
	actor = auto_actor([])
	check(Drop.fit(actor,stone_for("summon_focus")).kind == "missing","pet support requires a summon source")
	actor = auto_actor(["summon_wait"])
	check(Drop.fit(actor,stone_for("summon_focus")).kind == "linked","summon skill supports pet focus")
	actor = auto_actor(["bless_hit"])
	check(Drop.fit(actor,stone_for("bless_chain")).kind == "linked","self blessing prerequisite is recognized")
	check(Drop.fit(actor,stone_for("bless_hit")).kind == "duplicate","identical effect is flagged without disabling stat rewards")
	actor = auto_actor(["vital_hit"]); actor.gear.weapon.type = "sword"
	check(Drop.fit(actor,stone_for("focus_chain")).kind == "linked","weak-point chain works without a weapon-type requirement")
	actor = {"hp":100,"level":6,"equipped_abilities":["FIRE_CALLER/cut"]}
	check(Drop.fit(actor,"FIRE_CALLER/broken").kind == "linked","legacy preview uses actual set thresholds")
	s = setup_session(); s.interactive_stone_drops = true
	s.grant_part("RAT_GNAW/cut",true)
	tick = s.time
	check(s.Scheduler.advance(s,100) and s.time == tick+100,"a committed interval finishes despite loot queued during it")
	check(s.party.slice(1).all(func(member): return member.ready_at > tick),"pending loot does not cancel companions' due turns")
	print("Stone drop: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
