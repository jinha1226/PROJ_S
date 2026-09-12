extends SceneTree
const Drops=preload("res://sim/species_drop_registry.gd")
const Catalog=preload("res://sim/abilities/monster_ability_catalog.gd")
const Items=preload("res://sim/item_registry.gd")
const Rewards=preload("res://sim/item_reward_rules.gd")
func _init()->void:
	assert(Drops.registry_error().is_empty(),Drops.registry_error())
	assert(Catalog.DATA.definitions.size()==16)
	for row in Catalog.DATA.definitions:
		assert(Items.definition(row.essence_id)!=null)
		assert(Rewards.family_for_item(row.essence_id)=="MONSTER_ABILITY")
		assert(not str(row.passive).is_empty() and not str(row.active).is_empty())
		var hits:=0
		for death in range(1,201):
			var result:=Drops.rolls_for(44,death,row.species_id)
			assert(result==Drops.rolls_for(44,death,row.species_id),"stable roll")
			for roll in result:
				if roll.definition_id==row.essence_id:
					assert(roll.quantity==1);hits+=1
		assert(hits>0 and hits<200,"probabilistic drop "+str(row.species_id))
	print("MONSTER ABILITY DROPS: PASS (16 mappings)")
	quit()
