extends RefCounted
const Session = preload("res://expedition/run/session.gd")
const Floor = preload("res://tests/floor_fixture.gd")
const Essences = preload("res://expedition/progression/essences.gd")

static func reset(s = null) -> Dictionary:
	if s == null:
		s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true; Floor.arena(s,8)
	s.phase = "BATTLE"; s.time = 0; s.boundary = 100; s.casting = 0; s.blow_form = ""
	s.party = [s.make_actor(0,"주인공",false),s.make_actor(1,"동료",false)]
	for actor in s.party:
		actor.level = 10; actor.equipped_abilities = []; actor.essences = {}; actor.rules = []; actor.statuses = {}; actor.cooldowns = {}
		actor.max_hp = 100; actor.hp = 100; actor.max_mp = 60; actor.mp = 0; actor.ready_at = 0
		actor.gear = {"weapon":{"type":"sword"},"offhand":{},"armour":{},"ring1":{},"ring2":{}}
		actor.stance = "CHARGER"; actor.knobs = {"posture":0,"retreat_hp":0,"cohesion":0}; actor.conflicted = false
	s.party[0].pos = Vector2i(3,3); s.party[1].pos = Vector2i(3,4)
	var foe: Dictionary = s.make_actor(100,"적",true)
	foe.pos = Vector2i(4,3); foe.hp = 500; foe.max_hp = 500; foe.species_id = ""; foe.part_id = ""; foe.ac = 0; foe.sh = 0; foe.ev = 0; foe.res = {}; foe.role = "MELEE"; foe.alert = true; foe.ready_at = 200
	s.enemies = [foe]; s.npcs = []; s.intents = []; s.effects = []; s.effect_delays = []; s.gear_bag = []; s.parts_bag = {}; s.essence_seen = {}; s.finish_yielded = {}; s.part_wishes = {}; s.aim_parts = true; s.unrands_seen = {}
	s.mistake_override = {0:false,1:false}
	s.lookahead_enabled = true; s.party_command = "FOLLOW"; s.command_target = -1
	s.floor_state.visible.clear()
	for y in range(1,7):
		for x in range(1,8):
			s.floor_state.visible[Vector2i(x,y)] = true
			var tile: Dictionary = s.tile(Vector2i(x,y)); tile.terrain = "stone"; tile.fire = 0; tile.wet = 0
	s.reset_battle_stats(); s.Reactions.begin_action(s)
	return {"s":s,"hero":s.party[0],"ally":s.party[1],"foe":foe}

static func slot(actor: Dictionary, effects: Array) -> void:
	actor.equipped_abilities = []; actor.essences = {}; actor.rules = []
	for effect in effects:
		for id in Essences.catalog():
			if str(Essences.row(id).get("effect","")) == str(effect):
				actor.equipped_abilities.append(id); actor.essences[id] = 1; break
