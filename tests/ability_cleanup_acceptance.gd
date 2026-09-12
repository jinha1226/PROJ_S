extends SceneTree
const Member=preload("res://sim/party_member_state.gd")
const Binding=preload("res://sim/abilities/ability_binding_rules.gd")
const Registry=preload("res://sim/abilities/active_skill_registry.gd")
const Service=preload("res://sim/abilities/party_active_skill_service.gd")
func _init()->void:
	var hero=Member.new(1,0,"PROTAGONIST","DEPLOYED")
	var ally=Member.new(2,1,"COMPANION","GROUPED")
	assert(hero.active_skill_ids().is_empty(),"no prototype hero kit")
	assert(ally.active_skill_ids().is_empty(),"no prototype companion kit")
	for id in Registry.GROUND_SKILLS:
		assert(not Binding.has(id) and id not in Service.ENABLED_SKILLS,"test skill blocked")
	hero.bound_ability_ids.assign(["FIREBOLT"])
	assert(hero.active_skill_ids()==["FIREBOLT"],"earned ability remains usable")
	print("ABILITY CLEANUP: PASS")
	quit()
