extends SceneTree
const Rules=preload("res://sim/guild_tutorial_rules.gd")
const Index=preload("res://sim/guild_tutorial_index.gd")
const Event=preload("res://sim/sim_event.gd")
const HUD=preload("res://playtest/guild_tutorial_hud.gd")
var errors:Array[String]=[]
var events:Array=[]
func _init():call_deferred("run")
func add(type:String,data:Dictionary={},actor:int=7,target:int=-1):
	events.append(Event.new(events.size()+1,0,0,type,actor,target,Vector2i(1,1),1,-1,actor,data))
func check(ok:bool,label:String):
	if not ok:errors.append(label);printerr("FAIL ",label)
func run():
	var index=Index.new()
	for id in Rules.QUEST_IDS:add(Rules.EVENT_ACCEPTED,{"quest_id":id,"campaign_id":Rules.CAMPAIGN_ID})
	var before:Dictionary=index.observe(events,7,[99],Rules.definitions())
	add("party.ability_bound",{},8,8)
	check(not index.observe(events,7,[99],Rules.definitions()).quests[5].completed,"NPC binding excluded")
	add("party.ability_bound",{},7,7)
	add("weapon.recrafted",{},7,7)
	add("town.expedition_departed",{"floor_index":1,"expedition_index":1})
	add("action.skill",{"skill_id":"FIREBOLT"})
	add("guild.tutorial_limb_treated",{"part_ids":["LEFT_ARM"]},7,7)
	check(not index.observe(events,7,[99],Rules.definitions()).quests[9].completed,"treatment before injury excluded")
	add("guild.tutorial_limb_injured",{"part_id":"LEFT_ARM","condition":"DISABLED"},7,7)
	check(index.observe(events,7,[99],Rules.definitions()).quests[8].completed,"limb injury completes")
	add("health.restored",{"kind":"POTION"},7,7)
	check(not index.observe(events,7,[99],Rules.definitions()).quests[9].completed,"HP potion is not limb treatment")
	add("corpse.loot_materialized",{"generated_items":[{"instance_id":"DROP_001"}]},99,99)
	add("item.picked_up",{"instance_id":"DROP_001"})
	add("dungeon.floor_entered",{"floor_index":2,"expedition_index":1})
	add("dungeon.expedition_returned",{"expedition_index":1})
	add("guild.tutorial_limb_treated",{"part_ids":["LEFT_ARM"]},7,7)
	var dto:Dictionary=index.observe(events,7,[99],Rules.definitions())
	for i in [3,4,5,6,7,8,9]:check(dto.quests[i].completed,"completion %s"%Rules.QUEST_IDS[i])
	check(dto==Rules.state(events,7,[99]),"incremental and cold projection match")
	var consumed:int=index.count
	for i in range(100):index.observe(events,7,[99],Rules.definitions())
	check(index.count==consumed,"idle reads consume no events")
	events.pop_back()
	events.pop_back()
	check(not index.observe(events,7,[99],Rules.definitions()).quests[4].completed,"rollback rebuilds completion")
	var panel=Control.new();root.add_child(panel)
	var hud=HUD.new();panel.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hud.offset_top=-48;hud.offset_bottom=-4;hud.offset_left=4;hud.offset_right=-4
	hud.present(before,1,true);hud.present(dto,1,true)
	var notifications:int=hud.completion_notices
	for i in range(5):hud.present(dto,1,true)
	check(notifications>0 and hud.completion_notices==notifications,"completion notice fires only once")
	for width in [360,390,450]:
		panel.size=Vector2(width,500)
		await process_frame;await process_frame
		check(hud.size.x<=width and hud.size.y>=44,"HUD fits touch width %d"%width)
		hud._menu();hud._select(1)
		check(hud.selected_id==hud.rows[1].quest_id,"quest selection")
		hud._select(100);check(hud.folded,"fold HUD")
		hud._select(100);check(not hud.folded,"unfold HUD")
	hud.present(dto,2,true)
	check(hud.completion_notices==notifications,"loading completed quests does not replay notices")
	panel.queue_free();await process_frame
	print("GUILD V2: ",errors);quit(0 if errors.is_empty() else 1)
