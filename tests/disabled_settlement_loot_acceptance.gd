extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Salvage=preload("res://sim/base_monster_supply_rules.gd")
const Art=preload("res://playtest/pixel24_item_assets.gd")
var failures:Array[String]=[]
func _init():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	var session=Session.new(44,1,Session.DUO_SCENARIO_ID,"human",true)
	session.start_procedural_run_with_species("human",15,13)
	var sim=session.sim;var world=sim.world
	var target=null
	for id in world.party_encounter.enemy_ids:
		if world.entities[id].species_id=="goblin":target=world.entities[id];break
	check(target!=null,"procedural floor has goblin fixture")
	if target==null:quit(1);return
	check(session._base_cache_rows().is_empty(),"disabled settlement has no static caches")
	var processed_step:int=world.step_index+1
	world.begin_step(processed_step)
	var source=world.emit_event("environment.electric_arc",-1,-1,target.position,10000,-1,{"distance":0,"from_position":[-1,-1]})
	sim.damage.apply_damage(target,10000,"electric",int(source.id),target.position,processed_step)
	world.finish_step()
	var old_salvage=Salvage.caches(world,session._map_layout)
	check(old_salvage.any(func(row):return row.resource_id=="TIMBER" and row.position==[target.position.x,target.position.y]),"canonical goblin death reproduces legacy timber")
	var old_texture=Art.texture_for_id("TIMBER")
	check(old_texture is AtlasTexture and old_texture.region==Rect2(288,408,16,24),"legacy timber uses crate atlas image")
	check(session._base_cache_rows().is_empty(),"disabled settlement hides death salvage too")
	var dropped:Array=[]
	for row in world.item_state.ground_items.rows:
		if row.position==target.position:dropped.append(row.item.definition_id)
	check("WEAPON_SHORT_SWORD" in dropped,"normal carried weapon still drops")
	check("TIMBER" not in dropped,"timber is legacy cache, not item loot")
	print("DEATH AUDIT legacy salvage=",old_salvage," actual items=",dropped)
	print("DISABLED SETTLEMENT LOOT: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
