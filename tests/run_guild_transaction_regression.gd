extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Action=preload("res://sim/party_action_command.gd")
const Items=preload("res://sim/world_item_operations.gd")
class RewardFixture:
	extends "res://playtest/party_playtest_session.gd"
	func guild_tutorial_progress()->Dictionary:
		var dto:Dictionary=super.guild_tutorial_progress()
		for row in dto.quests:
			if row.quest_id=="GUILD_TUTORIAL_RETURN" and row.accepted:
				row.completed=true;row.can_claim=not row.claimed;row.status="COMPLETED"
		return dto
var errors:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:errors.append(label);printerr("FAIL ",label)
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.town_life_command({"action":"START"}).accepted,"town starts")
	check(s.guild_tutorial_command({"action":"ACCEPT","quest_id":"GUILD_TUTORIAL_MOVE"}).accepted,"accept move")
	check(s.depart_town().accepted,"depart")
	var hero:int=s.sim.world.party_control_actor_id();var entry:Vector2i=s.sim.world.entities[hero].position
	var positions:Array[Vector2i]=[entry]
	for step in range(3):
		var moved:=false
		for delta in [Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-1),Vector2i(-1,-1),Vector2i.RIGHT,Vector2i.LEFT,Vector2i.UP,Vector2i.DOWN]:
			var action=Action.move_to(hero,s.sim.world.entities[hero].position+delta)
			if not s.sim.party_coordinator._action_error(action).is_empty():continue
			var result:Dictionary=s.commit_field_action(action)
			if result.accepted:positions.append(s.sim.world.entities[hero].position);moved=true;break
		check(moved,"real move %d"%step)
	check(s.guild_tutorial_progress().quests[0].completed,"real movement completes")
	positions.pop_back();positions.reverse()
	for position in positions:check(s.commit_field_action(Action.move_to(hero,position)).accepted,"retrace entrance")
	var returned:Dictionary=s.base_return();check(returned.accepted,"real return: "+str(returned.get("reason","")))
	var full=Session.new();check(full.load_session_json(s.save_session_json()).accepted,"full bag fixture loads")
	fill_bag(full,0)
	var full_snapshot:Dictionary=full.sim.snapshot();var full_journal:Array=full.command_journal.duplicate(true)
	var denied:Dictionary=full.guild_tutorial_command({"action":"CLAIM","quest_id":"GUILD_TUTORIAL_MOVE"})
	check(not denied.accepted,"full bag refuses claim")
	check(full.sim.snapshot()==full_snapshot and full.command_journal==full_journal,"full bag preserves reward and inventory")
	var claim:Dictionary=s.guild_tutorial_command({"action":"CLAIM","quest_id":"GUILD_TUTORIAL_MOVE"})
	check(claim.accepted,"claim item reward: "+str(claim.get("reason","")))
	var snapshot:Dictionary=s.sim.snapshot();var journal:Array=s.command_journal.duplicate(true)
	check(not s.guild_tutorial_command({"action":"CLAIM","quest_id":"GUILD_TUTORIAL_MOVE"}).accepted,"duplicate claim rejected")
	check(s.sim.snapshot()==snapshot and s.command_journal==journal,"duplicate is atomic")
	var restored=Session.new();var loaded:Dictionary=restored.load_session_json(s.save_session_json())
	check(loaded.accepted,"reward journal loads: "+str(loaded.get("reason","")))
	if loaded.accepted:check(restored.sim.snapshot()==snapshot,"reward replay exact")
	check_support_and_partial_rollback()
	print("GUILD TRANSACTIONS: ",errors);quit(0 if errors.is_empty() else 1)

func fill_bag(s,reserve:int):
	var hero:int=s.sim.world.party_control_actor_id()
	while s.sim.world.inventory_of(hero).used_backpack_slots()<20-reserve:
		var grant:Dictionary=Items.commit_grant(s.sim.world,hero,"FOOD_RATION",1,s.sim.world.entities[hero].position,"TEST_CAPACITY")
		if not grant.accepted:check(false,"fill bag: "+str(grant.reason));break

func check_support_and_partial_rollback():
	var s=RewardFixture.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.town_life_command({"action":"START"}).accepted,"support town")
	check(s.guild_tutorial_command({"action":"ACCEPT","quest_id":"GUILD_TUTORIAL_HEAL"}).accepted,"support quest")
	var hero:int=s.sim.world.party_control_actor_id()
	check(s.depart_town().accepted,"support fixture departure")
	var removed:Dictionary=s.discard_inventory_item("START_POTION_001")
	check(removed.accepted,"remove fixture potions: "+str(removed.get("reason","")))
	var returned:Dictionary=s.base_return()
	check(returned.accepted,"support fixture return: "+str(returned.get("reason","")))
	var support:Dictionary=s.guild_tutorial_command({"action":"SUPPORT","quest_id":"GUILD_TUTORIAL_HEAL"})
	check(support.accepted,"support succeeds: "+str(support.get("reason","")))
	var before:Dictionary=s.sim.snapshot()
	check(not s.guild_tutorial_command({"action":"SUPPORT","quest_id":"GUILD_TUTORIAL_HEAL"}).accepted,"second support rejected")
	check(s.sim.snapshot()==before,"duplicate support atomic")
	var restored=Session.new();var loaded:Dictionary=restored.load_session_json(s.save_session_json())
	check(loaded.accepted,"support replay: "+str(loaded.get("reason","")))
	if loaded.accepted:check(restored.sim.snapshot()==before,"support exact")
	# Projection fixture only: isolate rollback after first bundle item succeeds.
	check(s.guild_tutorial_command({"action":"ACCEPT","quest_id":"GUILD_TUTORIAL_RETURN"}).accepted,"bundle fixture acceptance")
	fill_bag(s,1);before=s.sim.snapshot();var journal:Array=s.command_journal.duplicate(true)
	var reward:Dictionary=s.guild_tutorial_command({"action":"CLAIM","quest_id":"GUILD_TUTORIAL_RETURN"})
	check(not reward.accepted,"second bundle grant refuses full bag")
	check(s.sim.snapshot()==before and s.command_journal==journal,"partial bundle entirely rolled back")
