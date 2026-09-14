extends SceneTree
const Body=preload("res://sim/body_state.gd")
const Injury=preload("res://sim/body_injury_system.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func plan(body,form:String,loss:int,maximum:int)->Dictionary:
	return Injury.assess_hp_loss(body,form,loss,maximum,"fixed".sha256_text(),1,"LEFT_ARM")
func run()->void:
	var body=Body.create(1,"human",42)
	body.body_scalars.skin_toughness=30;body.body_scalars.soft_tissue_cushioning=30;body.body_scalars.bone_fracture_threshold=80
	for form in ["SLASH","PIERCE","IMPACT","FIRE","ELECTRIC"]:
		var zero:=plan(body,form,0,100)
		check(zero.accepted and not zero.mutated,"zero HP loss means no injury "+form)
		var hit:=plan(body,form,10,100)
		check(hit.accepted and hit.layer_damage==plan(body,form,100,1000).layer_damage,"max HP scale invariance "+form)
		var guarded:=plan(body,form,5,100)
		for layer in hit.layer_damage:
			check(guarded.layer_damage[layer]<=hit.layer_damage[layer],"less final damage means less injury "+form+layer)
		check(hit.resolution.bleed==0 and hit.resolution.shock==0,"no extra life/shock damage "+form)
	var cut:=plan(body,"SLASH",10,100)
	check(cut.layer_damage=={"SKIN":153,"SOFT_TISSUE":76,"BONE":13},"documented slash example")
	body.body_scalars.skin_toughness=33
	check(plan(body,"SLASH",10,100).layer_damage.SOFT_TISSUE<cut.layer_damage.SOFT_TISSUE,"skin protects deeper cutting wounds")
	var impact:=plan(body,"IMPACT",10,100)
	body.body_scalars.soft_tissue_cushioning=31
	check(plan(body,"IMPACT",10,100).layer_damage.BONE<impact.layer_damage.BONE,"muscle cushions bone impact")
	impact=plan(body,"IMPACT",10,100);body.body_scalars.bone_fracture_threshold=84
	check(plan(body,"IMPACT",10,100).layer_damage.BONE<impact.layer_damage.BONE,"bone strength reduces fracture accumulation")
	check(plan(body,"FIRE",10,100).layer_damage.BONE==0 and plan(body,"ELECTRIC",10,100).layer_damage.BONE==0,"elements do not fracture bones")
	check(not plan(body,"SLASH",101,100).accepted,"reject loss beyond max HP")
	var applied:=Injury._apply_plan(body,plan(body,"IMPACT",10,100),1)
	check(applied.accepted and body.wounds.size()==1 and body.validation_error().is_empty(),"shared wound ledger accepts HP-derived injury")
	print("HP DERIVED INJURY: ",failures)
	quit(0 if failures.is_empty() else 1)
