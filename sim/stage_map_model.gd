extends RefCounted
const Rooms=preload("res://sim/room_transition_rules.gd")
const Stage=preload("res://sim/stage_counterplay.gd")
const RoundRules=preload("res://sim/round_combat_rules.gd")
static func build(w)->Dictionary:
	if not Rooms.enabled(w):return {}
	var s:Dictionary=w.party_encounter.nine_room_floor;var floor_row:Dictionary=Rooms.current_floor(w)
	var current:int=int(s.active_room_id);var f:int=int(s.floor_index)
	var in_combat:bool=RoundRules.active(w) and not Stage.cleared(w)
	var edges:Array=[];var adjacent:Dictionary={}
	for p in floor_row.portals:
		if p.portal_id not in s.discovered_portals:continue
		edges.append([int(p.a),int(p.b)])
		if int(p.a)==current:adjacent[int(p.b)]=true
		if int(p.b)==current:adjacent[int(p.a)]=true
	var nodes:Array=[]
	for id in range(9):
		var visited:bool="%d:%d"%[f,id] in s.visited
		if not visited and not adjacent.has(id):continue
		var room:Dictionary=floor_row.rooms[id]
		var enemies:int=0
		for enemy_id in w.party_encounter.enemy_ids:
			if w.is_unresolved_enemy(enemy_id) and Rooms.membership(w.entities[enemy_id].position)==Vector2i(f,id):enemies+=1
		var cleared:bool=(enemies==0) if id!=current else Stage.cleared(w) or str(room.role)!="COMBAT"
		nodes.append({"id":id,"name":str(room.get("template_name","")) if visited else "미탐색","role":str(room.role),"biome":str(room.get("biome","dungeon")),"visited":visited,"cleared":cleared,"reachable":adjacent.has(id) and not in_combat and s.pending_exit.is_empty(),"current":id==current})
	return {"floor_index":f,"current":current,"in_combat":in_combat,"nodes":nodes,"edges":edges}
