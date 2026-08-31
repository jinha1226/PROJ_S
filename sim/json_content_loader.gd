class_name JsonContentLoader
extends RefCounted

const CONTENT_SCHEMA_VERSION := 1


static func load_document(resource_path:String) -> Dictionary:
	if not FileAccess.file_exists(resource_path): return {}
	var file:=FileAccess.open(resource_path,FileAccess.READ)
	if file==null:return {}
	var parser:=JSON.new()
	if parser.parse(file.get_as_text())!=OK or not parser.data is Dictionary:
		return {}
	return _normalize_json_numbers(parser.data)


static func document_error(document:Variant,content_type:String,
		expected_keys:Array) -> String:
	if not document is Dictionary or document.is_empty():return "content_document_unreadable"
	var keys:Array=document.keys();keys.sort()
	var expected:Array=expected_keys.duplicate();expected.sort()
	if keys!=expected:return "content_document_keys_invalid"
	if not document.get("content_schema_version") is int \
			or int(document.content_schema_version)!=CONTENT_SCHEMA_VERSION:
		return "content_schema_unsupported"
	if not document.get("content_version") is String \
			or str(document.content_version).is_empty():return "content_version_invalid"
	if not document.get("content_type") is String \
			or str(document.content_type)!=content_type:return "content_type_mismatch"
	return ""


static func rows_error(rows:Variant,id_key:String,maximum_rows:int=4096) -> String:
	if not rows is Array or rows.size()>maximum_rows:return "content_rows_invalid"
	var seen:Dictionary={}
	for row in rows:
		if not row is Dictionary or not row.get(id_key) is String \
				or str(row[id_key]).is_empty():return "content_row_identity_invalid"
		var identity:=str(row[id_key])
		if seen.has(identity):return "content_row_identity_duplicate"
		seen[identity]=true
	return ""


static func index_rows(rows:Variant,id_key:String) -> Dictionary:
	if not rows_error(rows,id_key).is_empty():return {}
	var result:Dictionary={}
	for row in rows:result[str(row[id_key])]=row.duplicate(true)
	return result


static func ordered_ids(rows:Variant,id_key:String) -> Array[String]:
	var result:Array[String]=[]
	if not rows_error(rows,id_key).is_empty():return result
	for row in rows:result.append(str(row[id_key]))
	return result


static func _normalize_json_numbers(value:Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			return int(value) if value==floor(value) else value
		TYPE_ARRAY:
			var result:Array=[]
			for child in value:result.append(_normalize_json_numbers(child))
			return result
		TYPE_DICTIONARY:
			var result:Dictionary={}
			for key in value:result[key]=_normalize_json_numbers(value[key])
			return result
		_:
			return value
