class_name BodyState
extends RefCounted

const SCHEMA_VERSION:=2
const MAX_SMALL_VALUE:=2147483647
const MAX_SAFE_JSON_INTEGER:=9007199254740991
const PART_CONDITIONS:=["FUNCTIONAL","DISABLED","SEVERED"]
const LIMB_PART_IDS:=["LEFT_ARM","RIGHT_ARM","LEFT_LEG","RIGHT_LEG"]
const RegistryScript=preload("res://sim/body_template_registry.gd")
const Int64CodecScript=preload("res://sim/int64_codec.gd")

var schema_version:=SCHEMA_VERSION
var entity_id:int=-1
var species_id:=""
var template_id:=""
var body_seed:int=0
var body_scalars:Dictionary={}
var parts:Array[Dictionary]=[]
var wounds:Array[Dictionary]=[]
var current_blood:int=0
var shock:int=0
var consciousness:int=1000
var revision:int=0


static func create(p_entity_id:int,p_species_id:String,p_body_seed:int):
	if p_entity_id<=0 or p_species_id.is_empty() or p_body_seed<0:return null
	var template:=RegistryScript.template_for_species(p_species_id)
	if template.is_empty() or not RegistryScript.template_error(template).is_empty():return null
	var value=load("res://sim/body_state.gd").new()
	value.entity_id=p_entity_id;value.species_id=p_species_id
	value.template_id=str(template.template_id);value.body_seed=p_body_seed
	for scalar_id in RegistryScript.SCALAR_IDS:
		var baseline:=RegistryScript.scalar_baseline(template,scalar_id)
		var variation:=int(template.variation[scalar_id])
		value.body_scalars[scalar_id]=baseline+_variation(p_body_seed,scalar_id,variation)
	for part in template.parts:
		var layers:Array=[]
		for layer_id in RegistryScript.LAYER_IDS:
			layers.append({"layer_id":layer_id,"integrity":1000})
		value.parts.append({"part_id":str(part.part_id),"condition":"FUNCTIONAL",
			"condition_source_event_id":-1,"layers":layers,
			"vital_tags":part.vital_tags.duplicate()})
	value.current_blood=int(value.body_scalars.blood_capacity)
	return value if value.validation_error().is_empty() else null


static func world_body_seed(world_seed:int,p_entity_id:int,p_species_id:String)->int:
	# Body variation is identity-derived. Entity creation must not consume the
	# world's command RNG or make later combat rolls depend on roster creation.
	var digest:PackedByteArray=("body-world-v1|world=%d|entity=%d|species=%s"%[
		world_seed,p_entity_id,p_species_id]).sha256_buffer()
	return ((int(digest[0])&0x7f)<<24)|(int(digest[1])<<16) \
		|(int(digest[2])<<8)|int(digest[3])


func validation_error()->String:
	if schema_version!=SCHEMA_VERSION:return "unsupported_body_state_schema"
	if entity_id<=0:return "invalid_body_entity_id"
	if body_seed<0:return "invalid_body_seed"
	if species_id.is_empty() or template_id.is_empty():return "invalid_body_identity"
	var template:=RegistryScript.template_definition(template_id)
	if template.is_empty() or (str(template.species_id)!=species_id \
			and template_id!="generic_humanoid"):
		return "invalid_body_template_identity"
	if not RegistryScript.scalars_within_template(body_scalars,template):
		return "invalid_body_scalars"
	if parts.size()!=RegistryScript.PART_IDS.size():return "invalid_body_part_rows"
	for index in range(parts.size()):
		var part:Dictionary=parts[index]
		var part_keys:Array=part.keys();part_keys.sort()
		if part_keys!=["condition","condition_source_event_id","layers","part_id","vital_tags"] \
				or str(part.get("part_id",""))!=RegistryScript.PART_IDS[index] \
				or not part.get("condition") is String \
				or str(part.condition) not in PART_CONDITIONS \
				or not part.get("condition_source_event_id") is int \
				or not part.get("layers") is Array \
				or part.layers.size()!=RegistryScript.LAYER_IDS.size() \
				or part.get("vital_tags")!=template.parts[index].vital_tags:
			return "invalid_body_part_rows"
		var condition:=str(part.condition)
		var source_event_id:=int(part.condition_source_event_id)
		if (condition=="FUNCTIONAL" and source_event_id!=-1) \
				or (condition!="FUNCTIONAL" and source_event_id<=0) \
				or (str(part.part_id) not in LIMB_PART_IDS and condition!="FUNCTIONAL"):
			return "invalid_body_part_condition"
		for layer_index in range(part.layers.size()):
			var layer:Variant=part.layers[layer_index]
			if not layer is Dictionary:return "invalid_body_layer_rows"
			var layer_keys:Array=layer.keys();layer_keys.sort()
			if layer_keys!=["integrity","layer_id"] \
					or str(layer.get("layer_id",""))!=RegistryScript.LAYER_IDS[layer_index] \
					or not layer.get("integrity") is int \
					or int(layer.integrity)<0 or int(layer.integrity)>1000:
				return "invalid_body_layer_rows"
			if condition=="SEVERED" and int(layer.integrity)!=0:
				return "invalid_severed_body_part"
	var previous_wound_id:=0
	var seen_wounds:Dictionary={}
	for wound in wounds:
		if not wound is Dictionary:return "invalid_body_wound_rows"
		var wound_keys:Array=wound.keys();wound_keys.sort()
		if wound_keys!=["bleeding","depth","form","layer_id","part_id","severity",
				"source_event_id","wound_id"] \
				or not wound.get("wound_id") is int \
				or not wound.get("source_event_id") is int:
			return "invalid_body_wound_rows"
		var wound_id:=int(wound.wound_id)
		if wound_id<=previous_wound_id or seen_wounds.has(wound_id):
			return "invalid_body_wound_rows"
		previous_wound_id=wound_id;seen_wounds[wound_id]=true
		if str(wound.get("part_id","")) not in RegistryScript.PART_IDS \
				or str(wound.get("layer_id","")) not in RegistryScript.LAYER_IDS \
				or str(wound.get("form","")) not in ["SLASH","PIERCE","IMPACT"] \
				or int(wound.source_event_id)<=0:
			return "invalid_body_wound_rows"
		for key in ["severity","bleeding","depth"]:
			if not wound.get(key) is int or int(wound[key])<0 \
					or int(wound[key])>MAX_SMALL_VALUE:return "invalid_body_wound_rows"
	if current_blood<0 or current_blood>int(body_scalars.blood_capacity) \
			or shock<0 or shock>MAX_SMALL_VALUE or consciousness<0 or consciousness>1000 \
			or revision<0 or revision>MAX_SMALL_VALUE:
		return "invalid_body_state_scalar"
	return ""


func to_dict()->Dictionary:
	var part_rows:Array=[]
	for part in parts:
		var layer_rows:Array=[]
		for layer in part.layers:layer_rows.append(layer.duplicate(true))
		part_rows.append({"part_id":str(part.part_id),"condition":str(part.condition),
			"condition_source_event_id":str(part.condition_source_event_id),"layers":layer_rows,
			"vital_tags":part.vital_tags.duplicate()})
	var wound_rows:Array=[]
	for wound in wounds:
		wound_rows.append({"wound_id":str(wound.wound_id),"part_id":str(wound.part_id),
			"layer_id":str(wound.layer_id),"form":str(wound.form),
			"severity":int(wound.severity),"bleeding":int(wound.bleeding),
			"depth":int(wound.depth),"source_event_id":str(wound.source_event_id)})
	return {"schema_version":schema_version,"entity_id":str(entity_id),
		"species_id":species_id,"template_id":template_id,"body_seed":str(body_seed),
		"body_scalars":body_scalars.duplicate(true),"parts":part_rows,"wounds":wound_rows,
		"current_blood":current_blood,"shock":shock,"consciousness":consciousness,
		"revision":revision}.duplicate(true)


static func validation_error_for(row:Variant)->String:
	if not row is Dictionary:return "invalid_body_state_shape"
	var keys:Array=row.keys();keys.sort()
	if keys!=["body_scalars","body_seed","consciousness","current_blood","entity_id",
			"parts","revision","schema_version","shock","species_id","template_id","wounds"]:
		return "invalid_body_state_keys"
	if not _wire_integer(row.schema_version) or int(row.schema_version)!=SCHEMA_VERSION:
		return "unsupported_body_state_schema"
	if not Int64CodecScript.is_canonical(row.entity_id) \
			or Int64CodecScript.parse(row.entity_id,"body entity")<=0:
		return "invalid_body_entity_id"
	if not Int64CodecScript.is_canonical(row.body_seed) \
			or Int64CodecScript.parse(row.body_seed,"body seed")<0:
		return "invalid_body_seed"
	if not row.species_id is String or not row.template_id is String \
			or not row.body_scalars is Dictionary or not row.parts is Array \
			or not row.wounds is Array:
		return "invalid_body_state_shape"
	var scalar_keys:Array=row.body_scalars.keys();scalar_keys.sort()
	var expected_scalar_keys:Array=RegistryScript.SCALAR_IDS.duplicate();expected_scalar_keys.sort()
	if scalar_keys!=expected_scalar_keys:return "invalid_body_scalars"
	for scalar_id in RegistryScript.SCALAR_IDS:
		if not _wire_integer(row.body_scalars.get(scalar_id)):return "invalid_body_scalars"
	for key in ["current_blood","shock","consciousness","revision"]:
		if not _wire_integer(row.get(key)):return "invalid_body_state_scalar"
	if row.parts.size()!=RegistryScript.PART_IDS.size():return "invalid_body_part_rows"
	for index in range(row.parts.size()):
		var part:Variant=row.parts[index]
		if not part is Dictionary:return "invalid_body_part_rows"
		var part_keys:Array=part.keys();part_keys.sort()
		if part_keys!=["condition","condition_source_event_id","layers","part_id","vital_tags"] \
				or str(part.get("part_id",""))!=RegistryScript.PART_IDS[index] \
				or not part.get("condition") is String \
				or not Int64CodecScript.is_canonical(part.get("condition_source_event_id")) \
				or not part.get("layers") is Array \
				or not part.get("vital_tags") is Array:
			return "invalid_body_part_rows"
		if part.layers.size()!=RegistryScript.LAYER_IDS.size():return "invalid_body_layer_rows"
		for layer_index in range(part.layers.size()):
			var layer:Variant=part.layers[layer_index]
			if not layer is Dictionary:return "invalid_body_layer_rows"
			var layer_keys:Array=layer.keys();layer_keys.sort()
			if layer_keys!=["integrity","layer_id"] \
					or str(layer.get("layer_id",""))!=RegistryScript.LAYER_IDS[layer_index] \
					or not _wire_integer(layer.get("integrity")):return "invalid_body_layer_rows"
	var previous_wound_id:=0
	for wound in row.wounds:
		if not wound is Dictionary:return "invalid_body_wound_rows"
		var wound_keys:Array=wound.keys();wound_keys.sort()
		if wound_keys!=["bleeding","depth","form","layer_id","part_id","severity",
				"source_event_id","wound_id"] \
				or not Int64CodecScript.is_canonical(wound.get("wound_id")) \
				or not Int64CodecScript.is_canonical(wound.get("source_event_id")):
			return "invalid_body_wound_rows"
		var wound_id:=Int64CodecScript.parse(wound.wound_id,"wound")
		if wound_id<=previous_wound_id:return "invalid_body_wound_rows"
		previous_wound_id=wound_id
		for key in ["severity","bleeding","depth"]:
			if not _wire_integer(wound.get(key)):return "invalid_body_wound_rows"
	var value=_from_dict_unchecked(row)
	return value.validation_error()


static func from_dict(row:Variant):
	return _from_dict_unchecked(row) if validation_error_for(row).is_empty() else null


static func _from_dict_unchecked(row:Dictionary):
	var value=load("res://sim/body_state.gd").new()
	value.schema_version=int(row.schema_version)
	value.entity_id=Int64CodecScript.parse(row.entity_id,"body entity")
	value.species_id=str(row.species_id);value.template_id=str(row.template_id)
	value.body_seed=Int64CodecScript.parse(row.body_seed,"body seed")
	value.body_scalars={}
	for scalar_id in RegistryScript.SCALAR_IDS:
		value.body_scalars[scalar_id]=int(row.body_scalars[scalar_id])
	value.parts.clear()
	for part in row.parts:
		var layers:Array=[]
		for layer in part.layers:
			layers.append({"layer_id":str(layer.layer_id),"integrity":int(layer.integrity)})
		value.parts.append({"part_id":str(part.part_id),"condition":str(part.condition),
			"condition_source_event_id":Int64CodecScript.parse(
				part.condition_source_event_id,"part condition source event"),"layers":layers,
			"vital_tags":part.vital_tags.duplicate()})
	value.wounds.clear()
	for wound in row.wounds:
		value.wounds.append({"wound_id":Int64CodecScript.parse(wound.wound_id,"wound"),
			"part_id":str(wound.part_id),"layer_id":str(wound.layer_id),
			"form":str(wound.form),"severity":int(wound.severity),
			"bleeding":int(wound.bleeding),"depth":int(wound.depth),
			"source_event_id":Int64CodecScript.parse(wound.source_event_id,"source event")})
	value.current_blood=int(row.current_blood);value.shock=int(row.shock)
	value.consciousness=int(row.consciousness);value.revision=int(row.revision)
	return value


func part_condition(part_id:String)->String:
	var index:=RegistryScript.PART_IDS.find(part_id)
	return str(parts[index].condition) if index>=0 and index<parts.size() else ""


func transition_part_condition(part_id:String,next_condition:String,
		source_event_id:int)->String:
	var error:=part_condition_transition_error(part_id,next_condition,source_event_id)
	if not error.is_empty():return error
	var index:=RegistryScript.PART_IDS.find(part_id)
	parts[index].condition=next_condition
	parts[index].condition_source_event_id=source_event_id
	if next_condition=="SEVERED":
		for layer in parts[index].layers:layer.integrity=0
	revision+=1
	return ""


func part_condition_transition_error(part_id:String,next_condition:String,
		source_event_id:int)->String:
	if not validation_error().is_empty():return "invalid_body_state"
	if part_id not in LIMB_PART_IDS:return "part_not_severable"
	if next_condition not in ["DISABLED","SEVERED"]:return "invalid_part_condition_target"
	if source_event_id<=0:return "invalid_part_condition_source_event"
	if revision>=MAX_SMALL_VALUE:return "body_revision_overflow"
	var current:=part_condition(part_id)
	if current==next_condition:return "part_condition_unchanged"
	if current=="SEVERED" or current=="DISABLED" and next_condition!="SEVERED":
		return "part_condition_regression"
	return ""


static func _wire_integer(value:Variant)->bool:
	return (value is int or value is float and value==floor(value)) \
		and value>=-MAX_SAFE_JSON_INTEGER and value<=MAX_SAFE_JSON_INTEGER


static func _variation(seed:int,scalar_id:String,maximum:int)->int:
	if maximum<=0:return 0
	var digest:PackedByteArray=("body-b0|seed=%d|scalar=%s"%[seed,scalar_id]).sha256_buffer()
	var value:=((int(digest[0])&0x7f)<<24)|(int(digest[1])<<16)|(int(digest[2])<<8)|int(digest[3])
	return value%(maximum*2+1)-maximum
