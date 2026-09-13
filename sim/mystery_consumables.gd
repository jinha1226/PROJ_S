extends RefCounted
const Specs=preload("res://sim/consumable_catalog.gd")
const IDS=Specs.DROP_IDS
const Catalog=preload("res://sim/item_catalog_registry.gd")
const Items=preload("res://sim/item_registry.gd")
static func has(id:String)->bool:return Specs.SPECS.has(id)
static func known(world,id:String)->bool:
	if not has(id):return true
	var cache:Dictionary=world.get_meta("identified_consumables",{"cursor":0,"ids":{}})
	if int(cache.cursor)>world.events.size() or (int(cache.cursor)>0 and cache.get("tail")!=world.events[int(cache.cursor)-1]):cache={"cursor":0,"ids":{}}
	for index in range(int(cache.cursor),world.events.size()):
		var event=world.events[index]
		if event.type=="item.identified":cache.ids[str(event.data.definition_id)]=true
	cache.cursor=world.events.size();cache.tail=world.events.back() if not world.events.is_empty() else null
	world.set_meta("identified_consumables",cache)
	return cache.ids.has(id)
static func appearance(world,id:String)->int:
	var family:String="POTION" if id.begins_with("POTION") else "SCROLL"
	var run_seed:String=str(world.seed)
	if world is Object:
		if not world.has_meta("mystery_run_seed"):
			var event=preload("res://sim/personal_talent_rules.gd").seed_event(world)
			world.set_meta("mystery_run_seed",str(event.data.seed) if event!=null else run_seed)
		run_seed=str(world.get_meta("mystery_run_seed"))
	var pool:Array=[]
	for key in Specs.SPECS:
		if str(key).begins_with(family):pool.append(key)
	pool.sort_custom(func(a,b):return ("mystery-v2/%s/%s"%[run_seed,a]).sha256_text()<("mystery-v2/%s/%s"%[run_seed,b]).sha256_text())
	return pool.find(id)
static func label(world,id:String)->String:
	if not has(id) or known(world,id):
		var item=Items.definition(id);return str(item.label) if item!=null else id
	var index:=appearance(world,id)
	return ("봉인병 %s" if id.begins_with("POTION") else "문양 두루마리 %s")%str(index+1)+" · 미감정"
static func decorate(world,row:Dictionary)->Dictionary:
	var id:String=str(row.get("definition_id",""))
	if not has(id):return row
	row.label=label(world,id);row.identified=known(world,id)
	row.visual_icon_key=("MYSTERY_POTION_" if id.begins_with("POTION") else "MYSTERY_SCROLL_")+str(appearance(world,id))
	row.usable=true
	row.appearance_mark=str(appearance(world,id)+1)
	if not row.identified:
		row.use_kind="UNIDENTIFIED";row.heal_amount=0;row.energy_amount=0
		row.compact_stat_text="미감정";row.purpose="사용하면 정체를 알 수 있습니다."
	else:
		var d:=Catalog.definition(id)
		row.energy_amount=int(d.effect_power) if d.effect_kind=="ENERGY" else 0
		row.compact_stat_text=Specs.definition(id).text
		row.purpose=Specs.definition(id).text
	return row
static func event_error(world,event)->String:
	if event.type not in ["item.identified","item.energy_restored"]:return ""
	var source=world.event_by_id(event.cause_id)
	if event.type=="item.identified" and source!=null and source.type=="consumable.activated":
		return "" if Specs.definition(str(source.data.definition_id)).get("effect")=="IDENTIFY" and has(str(event.data.get("definition_id",""))) and event.actor_id==source.actor_id and event.world_time==source.world_time else "item_identification_invalid"
	if source==null or source.type!="item.used" or source.actor_id!=event.actor_id or source.target_id!=event.target_id \
			or source.world_time!=event.world_time or source.step_index!=event.step_index or source.position!=event.position \
			or event.data.get("schema_version")!=1 or not has(str(source.data.get("definition_id",""))):return "mystery_item_source_invalid"
	if event.type=="item.identified":
		if event.magnitude!=0 or event.data!={"schema_version":1,"definition_id":str(source.data.definition_id)}:return "item_identification_invalid"
	else:
		var d:=Catalog.definition(str(source.data.definition_id))
		if d.effect_kind!="ENERGY" or event.magnitude<1 or event.magnitude>int(d.effect_power) \
				or event.data.keys().size()!=2 or not event.data.get("energy_after") is int:return "item_energy_invalid"
	return ""
