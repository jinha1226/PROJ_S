extends RefCounted
const Stage=preload("res://sim/stage_counterplay.gd")
const Rules=preload("res://sim/round_combat_rules.gd")
const Plans=preload("res://sim/round_plan_service.gd")
const Action=preload("res://sim/party_action_command.gd")

static func apply(host,observation:Dictionary)->void:
	host.grid.deployment_cells.clear()
	var s=host.session;var w=s.sim.world
	if not s.round_active() or s.round_status().phase!="DEPLOYMENT":return
	var plans:Dictionary=w.party_encounter.round_combat.plans
	observation["deployment_positions"]={}
	# Detached observation only; authoritative positions move on confirmation.
	for cell in observation.get("cells",[]):
		for actor in cell.get("actors",[]):
			var id:=str(actor.get("entity_id",-1))
			if plans.has(id) and int(id) in w.party_encounter.active_party_member_ids:
				observation.deployment_positions[int(id)]=plans[id].destination.duplicate()
	var id:int=host.selected_member_id
	if not plans.has(str(id)):id=w.party_control_actor_id()
	var entry:Array=Stage.current(w).entry
	var origin:=Vector2i(entry[0],entry[1])
	var radius:=mini(2,int(Stage.CONFIG.deployment_radius))
	for y in range(origin.y-radius,origin.y+radius+1):
		for x in range(origin.x-radius,origin.x+radius+1):
			var target:=Vector2i(x,y)
			if not Stage.Rooms.current(w,target):continue
			var route:Dictionary=s.sim.party_coordinator.pathfinder.find_path(id,target)
			if not route.get("found",false):continue
			var path:Array=[];var cost:=0
			for p in route.path.slice(1):path.append([p.x,p.y]);cost+=Rules.terrain_cost(w,p)
			var plan:=Plans.pack(w,Action.hold(id),"USER",path)
			if Stage.deployment_error(w,plan).is_empty() and cost<=12 and path.size()<=12:host.grid.deployment_cells.append(target)
