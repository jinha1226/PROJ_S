extends SceneTree
const Effects=preload("res://sim/abilities/active_effect_model.gd")
const Registry=preload("res://sim/abilities/active_skill_registry.gd")

func _init()->void:
	var failures:Array[String]=[]
	var caster:={"id":1,"team":"PARTY","position":Vector2i(2,2),"hp":100,"max_hp":100,"energy":12,"skills":["STRIKE","FIREBOLT","MEND","BARRIER","SHOVE"]}
	var enemy:={"id":2,"team":"ENEMY","position":Vector2i(3,2),"hp":60,"max_hp":60,"energy":0,"resistances":{"FIRE":25}}
	var ally:={"id":3,"team":"PARTY","position":Vector2i(2,3),"hp":50,"max_hp":100,"energy":12,"recoverable":15,"barrier":0}
	var bounds:=Rect2i(0,0,18,18);var actors:Array=[caster,enemy,ally]
	var before:=actors.duplicate(true)
	if Registry.error()!="":failures.append("registry")
	var fire:=Effects.assess("FIREBOLT",caster,enemy,actors,{},bounds)
	if not fire.accepted or fire.damage!=24 or fire.cost!=3:failures.append("fire resistance/cost")
	var mend:=Effects.assess("MEND",caster,ally,actors,{},bounds)
	if not mend.accepted or mend.healing!=15:failures.append("bounded heal")
	var shield:=Effects.assess("BARRIER",caster,ally,actors,{},bounds)
	if not shield.accepted or shield.barrier!=28:failures.append("barrier")
	var shove:=Effects.assess("SHOVE",caster,enemy,actors,{},bounds)
	if not shove.accepted or shove.destination!=Vector2i(4,2):failures.append("shove")
	if actors!=before:failures.append("assessment mutated inputs")
	caster.energy=2
	if Effects.assess("FIREBOLT",caster,enemy,actors,{},bounds).accepted:failures.append("insufficient resource")
	caster.energy=12
	if Effects.assess("STRIKE",caster,ally,actors,{},bounds).accepted:failures.append("friendly target")
	if Effects.assess("SHOVE",caster,enemy,actors,{Vector2i(4,2):true},bounds).accepted:failures.append("blocked shove")
	ally.barrier=28
	if Effects.assess("BARRIER",caster,ally,actors,{},bounds).accepted:failures.append("barrier stacking")
	if Effects.clear_line(Vector2i(2,2),Vector2i(3,3),{Vector2i(3,2):true}):failures.append("corner LOS")
	for failure in failures:printerr(failure)
	print("Active effect rules: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
