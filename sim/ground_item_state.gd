class_name GroundItemState
extends RefCounted

const SCHEMA_VERSION:=1
const ItemScript=preload("res://sim/item_instance.gd")

var schema_version:=SCHEMA_VERSION
var rows:Array=[]


func _init(p_rows:Array=[])->void:
	rows.clear()
	for value in p_rows:
		if not value is Dictionary:continue
		var position_value:Variant=value.get("position",[])
		var item_value:Variant=value.get("item")
		if position_value is Array and position_value.size()==2 and item_value!=null:
			var item=ItemScript.from_dict(item_value) if item_value is Dictionary \
				else ItemScript.from_dict(item_value.to_dict())
			rows.append({"position":Vector2i(int(position_value[0]),int(position_value[1])),
				"item":item})
	_sort_rows()


func item(instance_id:String):
	var value=_item_ref(instance_id)
	return ItemScript.from_dict(value.to_dict()) if value!=null else null


func _item_ref(instance_id:String):
	for row in rows:
		if row.item.instance_id==instance_id:return row.item
	return null


func position_of(instance_id:String)->Vector2i:
	for row in rows:
		if row.item.instance_id==instance_id:return row.position
	return Vector2i(-1,-1)


func validation_error(width:int=-1,height:int=-1)->String:
	if schema_version!=SCHEMA_VERSION:return "unsupported_ground_item_schema"
	var ids:Dictionary={};var previous_key:=""
	for row in rows:
		if not row is Dictionary or not row.get("position") is Vector2i \
				or row.get("item")==null:return "invalid_ground_item_row"
		var position:Vector2i=row.position
		if position.x<0 or position.y<0 \
				or (width>=0 and position.x>=width) or (height>=0 and position.y>=height):
			return "ground_item_out_of_bounds"
		var error:String=row.item.validation_error()
		if not error.is_empty():return error
		if ids.has(row.item.instance_id):return "duplicate_ground_item_instance"
		ids[row.item.instance_id]=true
		var key:=_sort_key(position,row.item.instance_id)
		if not previous_key.is_empty() and key<previous_key:return "noncanonical_ground_item_order"
		previous_key=key
	return ""


func to_dict()->Dictionary:
	var result_rows:Array=[]
	for row in rows:
		result_rows.append({"position":[row.position.x,row.position.y],
			"item":row.item.to_dict()})
	return {"schema_version":schema_version,"rows":result_rows}.duplicate(true)


static func from_dict(row:Dictionary):
	if not wire_error(row).is_empty():return null
	return _from_valid_dict(row)


static func _from_valid_dict(row:Dictionary):
	var value=load("res://sim/ground_item_state.gd").new(row.rows)
	value.schema_version=int(row.schema_version)
	return value


static func wire_error(row:Variant,width:int=-1,height:int=-1)->String:
	if not row is Dictionary:return "invalid_ground_item_shape"
	var keys:Array=row.keys();keys.sort()
	if keys!=["rows","schema_version"]:return "invalid_ground_item_keys"
	if not _integer(row.schema_version) or int(row.schema_version)!=SCHEMA_VERSION:
		return "unsupported_ground_item_schema"
	if not row.rows is Array:return "invalid_ground_item_shape"
	var raw_ids:Dictionary={};var previous_key:=""
	for value in row.rows:
		if not value is Dictionary:return "invalid_ground_item_row"
		var row_keys:Array=value.keys();row_keys.sort()
		if row_keys!=["item","position"] or not value.position is Array \
				or value.position.size()!=2 or not _integer(value.position[0]) \
				or not _integer(value.position[1]):return "invalid_ground_item_row"
		var error:=ItemScript.wire_error(value.item)
		if not error.is_empty():return error
		var instance_id:=str(value.item.instance_id)
		if raw_ids.has(instance_id):return "duplicate_ground_item_instance"
		var key:=_sort_key(Vector2i(int(value.position[0]),int(value.position[1])),instance_id)
		if not previous_key.is_empty() and key<previous_key:return "noncanonical_ground_item_order"
		raw_ids[instance_id]=true;previous_key=key
	return _from_valid_dict(row).validation_error(width,height)


func _sort_rows()->void:
	rows.sort_custom(func(a:Dictionary,b:Dictionary):
		return _sort_key(a.position,a.item.instance_id)<_sort_key(b.position,b.item.instance_id))


static func _sort_key(position:Vector2i,instance_id:String)->String:
	return "%010d:%010d:%s"%[position.y,position.x,instance_id]


static func _integer(value:Variant)->bool:
	return value is int or (value is float and value==floor(value))
