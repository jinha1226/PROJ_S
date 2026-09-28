extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Mobile = preload("res://expedition/progression/attack_wait.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Forms = preload("res://expedition/combat/forms.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func field(stones: Array = [], size: int = 1) -> Dictionary:
	var s = Session.new(731,false,size > 1,true,size); s.depart(); s.manual_mode = true
	var centre := Fixture.arena(s,10)
	s.MobileEffects.enable(s,Mobile.PROFILE)
	var hero: Dictionary = s.party[0]
	hero.level = 10; hero.hp = 100; hero.max_hp = 100; hero.mp = 0; hero.max_mp = 0; hero.stress = 0
	hero.equipped_abilities = ["","","","","",""]; hero.essences = {}
	for id in stones: s.Essences.bind(hero,str(id))
	var foe: Dictionary = s.make_actor(900,"검사 적",true)
	foe.pos = centre+Vector2i.RIGHT; foe.hp = 200; foe.max_hp = 200; foe.ev = 0; foe.sh = 0; foe.ac = 0; foe.alert = true
	foe.ready_at = 10000; foe.awake = true
	s.enemies.append(foe); s.phase = "BATTLE"; s.floor_state.observe(s)
	s.Reactions.begin_action(s); s.effects.clear()
	return {"s":s,"hero":hero,"foe":foe,"centre":centre}
func stone(effect: String) -> String:
	for id in Session.Essences.catalog():
		if Mobile.effect_id(str(id)) == effect: return str(id)
	for id in Session.Essences.catalog():
		for element in Session.Essences.ELEMENTS:
			if Mobile.effect_id(str(id)+"@"+str(element)) == effect: return str(id)+"@"+str(element)
	return ""
func with_effects(ids: Array, size: int = 1) -> Dictionary:
	return field(ids.map(func(id): return stone(str(id))),size)
func wait(d: Dictionary, intentional: bool = true) -> bool:
	return d.s.act_as(d.hero,"WAIT",d.hero.pos,false,intentional)
func hit(d: Dictionary) -> Dictionary:
	d.s.Reactions.begin_action(d.s)
	return d.s.CombatRules.attack(d.s,d.hero,d.foe)
func near(d: Dictionary, id: int, offset: Vector2i) -> Dictionary:
	var actor: Dictionary = d.s.make_actor(id,"주변 적",true)
	actor.pos = d.centre+offset; actor.hp = 200; actor.max_hp = 200; actor.ev = 0; actor.ac = 0; actor.sh = 0
	actor.alert = true; actor.ready_at = 10000; d.s.enemies.append(actor)
	d.s.floor_state.observe(d.s)
	return actor
func run() -> void:
	Forms.force = 99; Session.StoneEffects.force = 99
	check(Mobile.validate().is_empty(),"whole catalog validates: "+str(Mobile.validate()))
	var reachable := {}
	for id in Session.Essences.catalog():
		reachable[Mobile.effect_id(str(id))] = true
		for element in Session.Essences.ELEMENTS: reachable[Mobile.effect_id(str(id)+"@"+str(element))] = true
	for id in Mobile.data.effects: check(reachable.has(id),"reachable effect "+str(id))
	reward_stats(); mobile_items(); simple_rules(); seeding(); waiting(); manual_execution(); defense(); ice(); electricity(); support(); pets(); physical(); compatibility(); pure_prediction(); advanced_contracts(); operations()
	Forms.force = -1; Session.StoneEffects.force = -1
	print("Attack/wait: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func simple_rules() -> void:
	var d := with_effects(["fury_hit","evasion_hit"])
	d.hero.hp = d.hero.max_hp; hit(d)
	check(d.s.aw_trace.any(func(e): return e.effect == "fury_hit") and d.s.aw_trace.any(func(e): return e.effect == "evasion_hit"),"full-health stationary attacks activate their bonuses")
	d = with_effects(["wind_hit"]); hit(d)
	check(d.foe.pos == d.centre+Vector2i(2,0),"wind hit pushes without a preceding move")
	d = with_effects(["volley_hit"]); hit(d)
	check(d.s.aw_trace.any(func(e): return e.effect == "volley_hit"),"extra strike works with the starting sword")
	d = with_effects(["heal_wait"]); d.hero.hp = 95; wait(d)
	check(d.hero.hp == 100,"wait healing works for a small wound without a percentage threshold")
	d = with_effects(["summon_wait","summon_chain","summon_kill"]); wait(d)
	var pets: Array = d.s.Spells.Summons.summons_of(d.s,d.hero)
	check(pets.size() == 1 and int(pets[0].get("aw_attack_percent",0)) == 20 and int(pets[0].expires_at) == 400,"one wait summons, strengthens and extends a pet without extra pet events")

func mobile_items() -> void:
	var d := field()
	var item := {"type":"power","props":[{"key":"spell","value":3},{"key":"mp","value":4}],"flaw":{"key":"mp","value":-1}}
	d.hero.gear.ring1 = item
	var before_hp: int = d.hero.max_hp
	d.s.StatSheet.refresh_pools(d.s,d.hero)
	check(d.hero.max_hp == before_hp+6,"gear MP bonuses and penalties become usable HP")
	check(d.s.StatSheet.value(d.s,d.hero,"atk") == 8,"power ring and spell property both improve normal attacks")
	var desc: String = d.s.Gear.Equipment.description(item,d.hero)
	check(desc.contains("공격력 +5") and desc.contains("최대 HP +8") and desc.contains("최대 HP -2") and not desc.contains("MP") and not desc.contains("주문력"),"gear preview agrees with effective rewards and penalties")
	check(d.s.Gear.Equipment.numeric(item,"mp") == 3 and d.s.Gear.Equipment.numeric(item,"spell") == 3,"legacy gear still reads original MP and spell properties")
	d.hero.gear.ring1 = {}; d.hero.gear.armour.affix = "GEAR_COMP_MP"
	d.hero.hp = 50; var before_mp: int = d.hero.mp
	d.s.StoneEffects.fire(d.s,"ROUND_START",{"owner":d.hero})
	check(d.hero.hp == 51 and d.hero.mp == before_mp,"MP regeneration gear heals in automatic profile")
	d.hero.gear.armour = {"type":"robe","cost_effect":"COST_ORB"}
	check(d.s.StoneEffects.hp_percent(d.s,d.hero) == -25,"former MP artifact penalty keeps a real HP cost")
	d.hero.gear.armour = {"type":"robe"}
	Mobile.track_encounter(d.s,d.hero)
	var st := Mobile.state(d.hero)
	st.cooldowns = {"summon_wait":int(d.s.time)+600}; st.uses = {"heal_defense":2}
	st.foes = [d.foe.id]; st.encounters = [d.foe.id]
	d.s.bag.recharging = 2
	check(d.s.use_item("recharging"),"recharging scroll releases automatic cooldowns")
	check(st.cooldowns.is_empty() and st.uses.get("heal_defense",0) == 2 and d.hero.mp == before_mp,"recharging preserves encounter use limits and consumes no MP")
	var before_time: int = d.s.time
	check(not d.s.use_item("recharging") and d.s.bag.recharging == 1 and d.s.time == before_time,"no cooldown means no scroll or action is spent")
func reward_stats() -> void:
	var d := field()
	for id in Mobile.catalog():
		var rewards: Dictionary = d.s.Essences.stats(str(id),d.hero)
		check(not rewards.has("mp") and not rewards.has("spell"),"automatic rewards have no unused MP or spell stat: "+str(id))
	check(d.s.Essences.stats("FIRE_CALLER/pierced",d.hero) == {"atk":2,"hp":12},"magic reward supplies usable attack and HP")
	check(d.s.Essences.stats("RAT_GNAW/cut",d.hero) == {"hp":16},"support reward replaces MP with HP")
	check(d.s.Essences.stats("FIRE_CALLER/pierced") == {"spell":4,"mp":8} and d.s.Essences.stats("RAT_GNAW/cut") == {"hp":10,"mp":6},"legacy reward queries are unchanged beside automatic queries")
	check(d.s.Essences.stats("FIRE_CALLER/pierced@ice",d.hero) == {"atk":2,"hp":12,"res_ice":10},"automatic reward preserves variant resistance")
	var before_damage: int = d.s.CombatStats.stats(d.s,d.hero).damage
	d.s.phase = "CAMP"; d.s.parts_bag["FIRE_CALLER/pierced"] = 1
	check(d.s.absorb_essence(0,"FIRE_CALLER/pierced").is_empty(),"normal permanent absorption applies new reward")
	check(d.hero.max_hp == 112 and d.hero.max_mp == 0 and d.s.CombatStats.stats(d.s,d.hero).damage == before_damage+2,"reward changes actual HP and basic damage without MP")
	d.s.StatSheet.refresh_pools(d.s,d.hero)
	check(d.hero.max_hp == 112,"pool refresh never duplicates the new reward")
	Mobile.enable(d.s,"legacy")
	check(d.hero.max_hp == 100 and d.hero.max_mp == 8 and d.s.StatSheet.bonus(d.hero,"spell") == 4,"switching to legacy restores exactly its original reward")
	Mobile.enable(d.s,Mobile.PROFILE)
	check(d.hero.max_hp == 112 and d.hero.max_mp == 0 and d.s.StatSheet.bonus(d.hero,"spell") == 0,"switching back removes the legacy pool bonus")
	var npc: Dictionary = d.s.make_actor(401,"보상 검사 NPC",false); npc.npc = true; npc.level = 6
	var npc_hp: int = npc.max_hp; var npc_mp: int = npc.max_mp
	check(d.s.Essences.bind(npc,"RAT_GNAW/cut").is_empty(),"NPC absorption uses the same profile")
	d.s.StatSheet.refresh_pools(d.s,npc)
	check(npc.max_hp == npc_hp+16 and npc.max_mp == npc_mp,"NPC gains usable support HP and no MP")
func seeding() -> void:
	var d := with_effects(["fire_hit","fire_chain"]); var n := near(d,901,Vector2i(2,0))
	hit(d)
	check(d.foe.statuses.has("burn") and n.hp == 197,"same basic hit seeds burn then bursts nearby foe")
	check(d.s.aw_trace.filter(func(e): return e.effect == "fire_chain").size() == 1,"burst does not restart itself")
	check(d.hero.mp == 0 and d.s.aw_overflows == 0,"no MP or emergency queue exhaustion")
	d = with_effects(["poison_hit","poison_chain"]); n = near(d,901,Vector2i(2,0)); hit(d)
	check(n.statuses.has("poison") and n.hp == 200,"same-hit poison spreads without instant damage")
	var origin: int = int(n.status_sources.poison.id)
	d.s.time = 100; d.s.Reactions.begin_action(d.s); d.s.MobileEffects.status(d.s,d.foe,d.foe,"poison",500)
	d.s.MobileEffects.push(d.s,"HIT",d.hero,{"target":d.foe,"lost":1,"primary":true})
	check(n.status_sources.poison.id == origin,"refresh retains existing DOT owner")
	d = with_effects(["fire_hit","poison_hit"]); hit(d)
	check(d.foe.statuses.has("burn") and d.foe.statuses.has("poison"),"mobile statuses never invoke implicit toxic recipe")
	d.foe.statuses.immune = 1000; d.foe.statuses.erase("burn"); d.foe.statuses.erase("poison"); hit(d)
	check(not d.foe.statuses.has("burn") and not d.foe.statuses.has("poison"),"immune target receives no seeds")
	d = with_effects(["fire_hit"]); d.foe.hp = 1; hit(d)
	check(d.foe.hp == 0 and not d.foe.statuses.has("burn"),"fatal basic damage cannot seed corpse")
func waiting() -> void:
	var d := with_effects(["fire_wait","poison_wait"]); var n := near(d,901,Vector2i(3,2)); var far := near(d,902,Vector2i(5,0))
	var before_actions: int = d.s.action_serial
	wait(d)
	check(d.foe.statuses.has("burn") and n.statuses.has("poison") and not far.statuses.has("poison"),"deliberate wait applies all valid area targets")
	check(d.s.action_serial == before_actions+1,"automatic effects share one action")
	d = with_effects(["fire_wait"]); wait(d,false)
	check(not d.foe.statuses.has("burn"),"forced fallback wait has no offensive proc")
	d = with_effects(["fire_wait"]); d.s.tile(d.centre+Vector2i(2,0)).terrain = "wall"; n = near(d,901,Vector2i(3,0)); wait(d)
	check(not n.statuses.has("burn"),"visible enemy behind wall is not a legal area target")
	var serial: int = d.s.action_serial; var preps: Dictionary = d.hero.aw_state.duplicate(true)
	check(not d.s.act_as(d.hero,"ATTACK",d.centre+Vector2i(9,0),false) and serial == d.s.action_serial and preps == d.hero.aw_state,"rejected action preserves serial and preparation")

func manual_execution() -> void:
	var d := with_effects(["fire_wait"])
	var before_time: int = d.s.time
	check(not d.hero.has("ap") and d.s.submit("WAIT",d.hero.pos) and d.s.time == before_time+100 and not d.hero.has("ap"),"manual wait advances time without an AP field")
	check(d.foe.statuses.has("burn"),"automatic wait effect still fires without AP")
	d.hero.prepared = ["blink"]
	check(not d.s.submit("CAST",d.hero.pos,"blink") and not d.s.submit("PUSH",d.foe.pos),"automatic profile has no manually selected spells or parts")
func defense() -> void:
	var d := with_effects(["defense_defense","defense_threat"])
	wait(d); wait(d); wait(d)
	check(d.hero.aw_state.waits == 1,"one wait grants full lure without stacking")
	check(Mobile.incoming(d.s,d.hero,d.foe,100,"HIT") == 80,"guard refresh never stacks reduction")
	check(Mobile.incoming(d.s,d.hero,d.foe,100,"MOBILE_DOT") == 100,"stance excludes DOT")
	check(Mobile.threat(d.s,d.foe,d.hero) == 9,"known target threat bonus is bounded")
	wait(d,false); check(d.hero.aw_state.waits == 0 and d.hero.aw_state.preps.is_empty(),"forced skip clears stance and threat")
	d = with_effects(["poison_defense"]); wait(d)
	Mobile.struck(d.s,d.hero,d.foe,{"lost":4}); check(d.foe.statuses.has("poison"),"poison skin reacts to a real hostile hit")
	d.foe.statuses.erase("poison"); d.s.Reactions.begin_action(d.s); Mobile.struck(d.s,d.hero,d.foe,{"lost":4})
	check(not d.foe.statuses.has("poison"),"next enemy action does not recharge defensive preparation")
	d = with_effects(["air_defense"]); wait(d); Session.StoneEffects.force = 99
	Mobile.struck(d.s,d.hero,d.foe,{"lost":1})
	check(d.foe.statuses.has("stun"),"electric barrier triggers without a random proc roll")
	d.foe.statuses.erase("stun"); Session.StoneEffects.force = 0; Mobile.struck(d.s,d.hero,d.foe,{"lost":1})
	check(not d.foe.statuses.has("stun"),"electric barrier remains one reaction per preparation")
	wait(d); check(d.hero.aw_state.preps.is_empty(),"strong guaranteed control keeps its cooldown")
	Session.StoneEffects.force = 99
	d = with_effects(["ice_defense"]); wait(d)
	check(d.s.CombatStats.stats(d.s,d.hero).ac >= 4,"ice armor enters real stat calculation")
	Mobile.begin(d.s,d.hero,"ATTACK"); check(Mobile.modifier(d.s,"armour",d.hero) == 0,"normal own action expires defense")
func ice() -> void:
	var d := with_effects(["ice_hit","ice_chain","ice_shatter"]); hit(d)
	check(d.foe.statuses.has("freeze") and not d.s.aw_trace.any(func(e): return e.effect == "ice_shatter"),"new freeze is not shattered in same hit")
	hit(d); check(not d.foe.statuses.has("freeze") and d.s.aw_trace.any(func(e): return e.effect == "ice_shatter"),"next hit shatters existing freeze")
	check(not d.s.Statuses.apply(d.s,d.foe,"stun",100,d.hero),"shared CC guard blocks repeated stun until normal action")
	d.foe.erase("aw_cc_locked"); check(d.s.Statuses.apply(d.s,d.foe,"stun",100,d.hero),"normal-action release permits future control")
func electricity() -> void:
	var d := with_effects(["air_hit","air_chain"]); var a := near(d,901,Vector2i(3,0)); var b := near(d,902,Vector2i(5,0)); var c := near(d,903,Vector2i(6,0))
	hit(d)
	check(a.hp == 197 and b.hp == 197 and c.hp == 200,"lightning visits exactly three distinct targets")
	check(not d.foe.statuses.has("charge"),"chain consumes charge without restarting")
	d = with_effects(["air_hit"]); d.s.reset_battle_stats(); d.foe.statuses.charge = d.s.time+1000
	var facts := {"target":d.foe,"lost":1,"primary":true}
	Mobile.push(d.s,"HIT",d.hero,facts)
	var report: Dictionary = d.s.member_stats(d.hero.id).get("effects",{}).get("aw:air_hit",{})
	check(d.foe.hp == 198 and d.foe.statuses.charge == d.s.time+1000,"existing charge still takes real electric damage without extending status")
	check(int(report.get("procs",0)) == 1 and int(report.get("damage",0)) == 2 and d.s.aw_trace.any(func(e): return e.effect == "air_hit"),"damage-only proc is present in contribution report and trace")
	check(d.s.effects.any(func(e): return e.get("kind","") == "PROC" and str(e.get("text","")) == str(Mobile.data.effects.air_hit.name)),"damage-only proc displays its effect")
	Mobile.push(d.s,"HIT",d.hero,facts)
	check(d.foe.hp == 198 and int(report.procs) == 1,"damage-only proc retains its per-action limit")
	d.s.Reactions.begin_action(d.s); Mobile.push(d.s,"HIT",d.hero,facts)
	check(d.foe.hp == 196 and int(report.procs) == 2,"next action records another damage-only proc")
	d.foe.res.air = 100; d.s.Reactions.begin_action(d.s); d.s.effects.clear()
	Mobile.push(d.s,"HIT",d.hero,facts)
	check(d.foe.hp == 196 and int(report.procs) == 2 and not d.s.effects.any(func(e): return e.get("kind","") == "PROC"),"no status change and no damage produces no fabricated proc")
func support() -> void:
	var d := with_effects(["heal_wait","heal_chain"],2)
	d.hero.hp = 50; d.s.party[1].hp = 10; d.s.party[1].max_hp = 100
	wait(d); check(d.s.party[1].hp == 18,"wait heal chooses actual ally with lowest HP ratio")
	d.s.time += 300; wait(d); check(d.s.party[1].hp == 26,"heal has two encounter uses")
	d.s.time += 300; d.foe.pos = d.centre+Vector2i(20,0); wait(d); d.foe.pos = d.centre+Vector2i.RIGHT; wait(d)
	check(d.s.party[1].hp == 26,"losing sight and reacquiring same foe does not recharge healing")
	d = with_effects(["heal_hit"]); d.hero.hp = 50; d.foe.hp = 1; hit(d)
	check(d.hero.hp == 51,"lifesteal uses actual lost HP of overkill target")
	d = with_effects(["poison_hit","bleed_kill"]); d.foe.hp = 2; d.s.Statuses.apply(d.s,d.foe,"poison",300,d.hero)
	d.s.Statuses.tick(d.s); check(d.foe.hp == 0,"mobile attributed DOT resolves death")
	check(d.s.aw_trace.any(func(e): return e.event == "KILL" ) == false,"unmatched kill stone does not fabricate effects")
func pets() -> void:
	var d := with_effects(["death_wait","bless_summon"]); wait(d)
	var pets: Array = d.s.Spells.Summons.summons_of(d.s,d.hero)
	check(pets.size() == 1 and pets[0].summon_kind == "skeleton","deliberate wait summons real actor")
	check(pets.size() == 1 and pets[0].statuses.has("blessing"),"successful summon chains blessing")
	d.s.time += 300; wait(d); check(d.s.Spells.Summons.summons_of(d.s,d.hero).size() == 1,"shared summon cap respected")
	var count: int = d.s.aw_trace.size(); pets[0].expires_at = d.s.time; d.s.Spells.Summons.expire(d.s)
	check(d.s.aw_trace.size() == count,"natural expiration does not fabricate death burst")
	d = with_effects(["death_hit","death_chain"]); hit(d); d.foe.hp = 1; hit(d)
	check(d.s.Spells.Summons.summons_of(d.s,d.hero).size() == 1,"marked hit summons exactly one skeleton without a kill condition")
func physical() -> void:
	var d := with_effects(["focus_wait"]); d.hero.gear.weapon = {"type":"bow","enchant":0}
	wait(d); wait(d); wait(d); wait(d)
	check(d.hero.aw_state.attack_preps.focus.percent == 20,"one wait fully prepares focus without stacking")
	hit(d); check(d.hero.aw_state.attack_preps.is_empty(),"legal basic attack consumes focus preparation")
	d = with_effects(["crush_hit","crush_chain"]); var blocked: Vector2i = d.foe.pos+Vector2i.RIGHT
	d.s.tile(blocked).terrain = "wall"; hit(d)
	check(not d.s.aw_trace.any(func(e): return e.effect == "crush_chain"),"wall collision alone is no longer a separate activation condition")
	d = with_effects(["vital_hit","crush_chain"]); hit(d)
	check(d.s.aw_trace.any(func(e): return e.effect == "crush_chain"),"weak-point seed activates crush chain in an open room")
	d = with_effects(["rapid_hit","bleed_hit","bleed_chain"]); hit(d)
	check(d.s.aw_trace.filter(func(e): return e.event == "HIT").size() <= 3 and d.s.aw_overflows == 0,"extra attacks cannot recursively restart attack stones")
func compatibility() -> void:
	var d := with_effects(["fire_hit"]); var legacy = Session.new(731); legacy.depart()
	check(legacy.combat_profile == "legacy" and not Mobile.active(legacy.party[0]),"concurrent sessions do not leak profiles")
	check(not d.s.Abilities.usable_by(d.hero,"FIRE_CALLER"),"automatic stone has no duplicate manual action")
	check(d.s.StoneEffects.effects(d.foe) == legacy.StoneEffects.effects(d.foe),"monster effects remain unchanged")
	var stranger: Dictionary = d.s.make_actor(400,"중립 인물",false); stranger.npc = true; stranger.pos = d.centre+Vector2i.UP; stranger.awake = true; d.s.npcs.append(stranger)
	check(not Mobile.allied(d.s,d.hero,stranger) and not Mobile.hostile(d.s,d.hero,stranger),"neutral stranger is neither heal ally nor hostile")
	stranger.hostile = true; check(Mobile.active(stranger),"hostile NPC keeps person profile")
func pure_prediction() -> void:
	var d := with_effects(["fire_wait","heal_wait","air_defense"])
	var hp: int = d.foe.hp; var rolls: int = d.s.roll_serial; var serial: int = d.s.action_serial
	var snapshot: Dictionary = d.hero.duplicate(true)
	for _i in range(8): Mobile.estimate(d.s,d.hero,"WAIT"); Mobile.summary(d.hero)
	check(d.foe.hp == hp and d.s.roll_serial == rolls and d.s.action_serial == serial and d.hero == snapshot,"AI and UI prediction mutate no actor or RNG")
func operations() -> void:
	# Exercise every mapped rule through real events to catch invalid ops/resources.
	for id in Mobile.data.effects:
		var d := with_effects([str(id)])
		d.hero.hp = 40; d.foe.statuses = {"burn":1000,"poison":1000,"bleed":1000,"slow":1000,"weak":1000,"freeze":1000,"confuse":1000,"charge":1000,"death_mark":1000,"wet":1000,"exposed":1000}
		d.hero.statuses.blessing = 1000
		var r: Dictionary = Mobile.data.effects[id]
		var ctx := {"target":d.foe,"lost":5,"ranged":true,"moved":true,"aim":2,"damage_element":"air","previous_target":d.foe.id,"victim_statuses":d.foe.statuses.duplicate(true)}
		Mobile.push(d.s,str(r.event),d.hero,ctx)
		check(d.s.aw_overflows == 0 and d.s.aw_queue.is_empty(),"bounded mapped event "+str(id))

func advanced_contracts() -> void:
	var d := with_effects(["fire_wait"])
	var npc: Dictionary = d.s.make_actor(401,"시야 밖 동료",false)
	npc.level = 10; npc.npc = true; npc.awake = true; npc.pos = d.centre+Vector2i(9,0)
	npc.equipped_abilities = ["","","","","",""]; npc.essences = {}
	d.s.Essences.bind(npc,stone("fire_wait")); d.s.npcs.append(npc)
	var foe := near(d,902,Vector2i(10,0))
	d.s.floor_state.visible.erase(foe.pos)
	check(d.s.act_as(npc,"WAIT",npc.pos,false) and foe.statuses.has("burn"),"NPC wait uses its own perception outside camera")
	d = with_effects(["fire_hit","heal_hit"],2); d.hero.hp = 50
	d.s.party[1].hp = 100; d.s.party[1].max_hp = 100; d.foe.protected_by = int(d.s.party[1].id)
	hit(d)
	check(d.hero.hp == 50 and not d.s.party[1].statuses.has("burn"),"redirected friendly HP loss receives no hostile seed or lifesteal")
	d = with_effects(["fire_wait","defense_threat"])
	d.hero.statuses.stun = 500
	check(wait(d) and not d.foe.statuses.has("burn") and int(d.hero.aw_state.waits) == 0,"stunned hero can spend time without receiving deliberate-wait effects")
	d = with_effects(["focus_wait","fire_hit"])
	wait(d); d.foe.ev = 100
	for serial in range(100):
		var next_roll: int = d.s.Hexaco.sample(d.s.seed_value,d.s.time*37+int(d.hero.id)*997+int(d.foe.id)*17+serial+1,"dodge",100)
		if next_roll < 45: d.s.roll_serial = serial; break
	var result: Dictionary = hit(d)
	check(result.evaded and d.hero.aw_state.attack_preps.is_empty() and not d.foe.statuses.has("burn"),"legal miss consumes preparation without HIT seeds")
	d = with_effects(["fire_hit","fire_chain"]); var neighbour := near(d,901,Vector2i(2,0))
	hit(d); var first: int = neighbour.hp
	var reverse := field([stone("fire_chain"),stone("fire_hit")]); var other := near(reverse,901,Vector2i(2,0)); hit(reverse)
	check(first == int(other.hp),"absorption order cannot alter seeding/link result")
	d = with_effects(["bless_defense"],2); wait(d)
	check(Mobile.incoming(d.s,d.s.party[1],d.foe,100,"HIT") == 80,"gifted ally guard validates its original giver")
	d = with_effects(["defense_defense","defense_threat","heal_chain"]); wait(d)
	d.s.bag.healing = 2
	var before_serial: int = d.s.action_serial; var old_state: Dictionary = d.hero.aw_state.duplicate(true)
	check(not d.s.use_item("healing") and before_serial == d.s.action_serial and d.hero.aw_state == old_state,"rejected consumable preserves preparation and root")
	d.hero.hp = 50
	check(d.s.use_item("healing") and int(d.hero.aw_state.waits) == 0 and not d.hero.aw_state.preps.has("stance"),"committed item expires stance and consecutive waits")
	check(not d.s.aw_trace.any(func(e): return e.event == "HEALED") and not d.hero.aw_state.preps.has("guard"),"potions do not activate an extra healing event")
	d = with_effects(["water_cleanse"]); d.hero.hp = 50; d.hero.statuses.bleed = 300; d.s.bag.healing = 1
	check(d.s.use_item("healing") and not d.hero.statuses.has("bleed") and not d.s.aw_trace.any(func(e): return e.event == "CLEANSED"),"potion cleansing works without another soulstone trigger")
	d = with_effects(["mental_hit"]); hit(d)
	check(Mobile.confusion_penalty(d.foe) == 20 and bool(d.foe.enemy),"mobile confusion impairs aim without changing allegiance")
	# Pick a real deterministic roll that hits normally but misses when confused.
	d.hero.ev = 0; d.hero.sh = 0
	for serial in range(1000):
		var roll: int = d.s.Hexaco.sample(d.s.seed_value,d.s.time*37+int(d.foe.id)*997+int(d.hero.id)*17+serial+1,"dodge",100)
		if roll >= 5 and roll < 25: d.s.roll_serial = serial; break
	var confusion_serial: int = d.s.roll_serial
	check(d.s.CombatRules.attack(d.s,d.foe,d.hero).evaded,"mobile confusion changes a real physical attack outcome")
	d.foe.status_sources.confuse.policy = "legacy"; d.s.roll_serial = confusion_serial
	check(Mobile.confusion_penalty(d.foe) == 0 and d.s.CombatRules.attack(d.s,d.foe,d.hero).hit,"legacy confusion retains its previous aim")
	d = with_effects(["ice_defense"]); wait(d)
	d.hero.sealed = {stone("ice_defense"):true}
	check(Mobile.modifier(d.s,"armour",d.hero) == 0,"sealing originating stone disables preparation immediately")
	d = with_effects(["summon_defense"]); wait(d)
	var pet: Dictionary = d.s.Spells.Summons.summons_of(d.s,d.hero)[0]
	check(d.s.protection_recipient(d.hero).id == pet.id,"adjacent guard pet uses real cover recipient")
	check(d.s.protection_recipient(d.hero,false).id == d.hero.id,"guard pet does not redirect status damage")
	d = with_effects(["summon_wait","summon_focus"]); wait(d)
	pet = d.s.Spells.Summons.summons_of(d.s,d.hero)[0]
	var second := near(d,903,Vector2i(2,1)); second.awake = true
	pet.pos = d.centre+Vector2i(1,1); pet.aw_focus = int(second.id)
	d.s.floor_state.visible.erase(second.pos)
	var hp: int = second.hp; d.s.NpcAI.pet_turn(d.s,pet)
	check(second.hp < hp and int(d.foe.hp) == 200,"pet focus uses its own sight for its next normal attack, without an immediate free hit")
	d = with_effects(["poison_hit","bleed_kill"]); d.hero.hp = 50; d.foe.hp = 2
	d.s.Statuses.apply(d.s,d.foe,"bleed",300,d.hero); d.s.Statuses.apply(d.s,d.foe,"poison",300,d.hero)
	d.s.Statuses.tick(d.s)
	check(not d.s.aw_trace.any(func(e): return e.effect == "bleed_kill") and d.hero.hp == 50,"DOT death no longer activates a hidden kill-healing condition")
	d = with_effects(["water_hit","water_air"]); second = near(d,904,Vector2i(3,0)); hit(d)
	check(second.hp == 197,"wet alone activates its chain without a lightning-source requirement")
	d = with_effects(["death_end","death_wait"]); wait(d)
	pet = d.s.Spells.Summons.summons_of(d.s,d.hero)[0]; pet.hp = 1; pet.pos = d.centre+Vector2i(1,1)
	d.s.CombatRules.damage(d.s,d.foe,pet,5,"physical")
	check(not d.foe.statuses.has("weak"),"pet death no longer activates a hidden soulstone trigger")
	d = with_effects(["death_hit","death_end"]); second = near(d,904,Vector2i(2,0)); hit(d)
	check(second.statuses.has("weak"),"death-marked hit spreads weakness without sacrificing a pet")
