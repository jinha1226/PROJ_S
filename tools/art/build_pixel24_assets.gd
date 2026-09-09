extends SceneTree

## Deterministic, manifest-driven extraction for generated pixel24 source sheets.
## This tool performs mechanical crop/nearest-resize/palette/alpha operations.
## It deliberately has no automatic subject detection or background guessing.

const DEFAULT_MANIFEST := "res://tools/art/pixel24_manifest.json"
const REVIEW_BG := Color("10151b")

var _manifest:Dictionary={}
var _built:Array[Dictionary]=[]


func _init()->void:
	var manifest_path:=DEFAULT_MANIFEST
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():manifest_path=str(args[0])
	var error:=_build(manifest_path)
	quit(error)


func _build(manifest_path:String)->int:
	var file:=FileAccess.open(manifest_path,FileAccess.READ)
	if file==null:
		push_error("pixel24: cannot open manifest %s"%manifest_path)
		return 2
	var parsed:Variant=JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("pixel24: manifest root must be an object")
		return 2
	_manifest=parsed
	if int(_manifest.get("schema_version",0))!=1:
		push_error("pixel24: unsupported manifest schema")
		return 2
	var entries:Variant=_manifest.get("entries",[])
	if not entries is Array:
		push_error("pixel24: entries must be an array")
		return 2
	var seen_ids:Dictionary={}
	var seen_outputs:Dictionary={}
	var entry_defaults:Dictionary=_manifest.get("entry_defaults",{}) \
		if _manifest.get("entry_defaults",{}) is Dictionary else {}
	for raw_entry in entries:
		if not raw_entry is Dictionary:
			push_error("pixel24: every entry must be an object")
			return 2
		var entry:Dictionary=entry_defaults.duplicate(true)
		entry.merge(raw_entry,true)
		if not bool(entry.get("active",false)):continue
		var entry_id:=str(entry.get("id",""))
		var output:=str(entry.get("output",""))
		if entry_id.is_empty() or output.is_empty() or seen_ids.has(entry_id) \
				or seen_outputs.has(output):
			push_error("pixel24: IDs and outputs must be unique and non-empty: %s"%entry_id)
			return 2
		seen_ids[entry_id]=true;seen_outputs[output]=true
		var result:=_build_entry(entry)
		if not bool(result.get("ok",false)):return 2
		_built.append(result)
	if _built.is_empty():
		push_error("pixel24: no active entries")
		return 2
	if not _write_reviews():return 2
	print("pixel24: built %d assets and review sheets"%_built.size())
	return 0


func _build_entry(entry:Dictionary)->Dictionary:
	var entry_id:=str(entry.id)
	var source_path:=str(entry.get("source",""))
	var source:=Image.load_from_file(source_path)
	if source==null or source.is_empty():
		push_error("pixel24: %s cannot load %s"%[entry_id,source_path])
		return {"ok":false}
	source.convert(Image.FORMAT_RGBA8)
	var rect_values:Variant=entry.get("source_rect",[])
	if not rect_values is Array or rect_values.size()!=4:
		push_error("pixel24: %s needs source_rect [x,y,w,h]"%entry_id)
		return {"ok":false}
	var rect:=Rect2i(int(rect_values[0]),int(rect_values[1]),
		int(rect_values[2]),int(rect_values[3]))
	if rect.size.x<=0 or rect.size.y<=0 \
			or not Rect2i(Vector2i.ZERO,source.get_size()).encloses(rect):
		push_error("pixel24: %s crop %s outside source %s"%[entry_id,rect,source.get_size()])
		return {"ok":false}
	var image:=source.get_region(rect)
	var output_size:=Vector2i(int(_manifest.get("logical_size",24)),
		int(_manifest.get("logical_size",24)))
	var size_values:Variant=entry.get("output_size",[])
	if size_values is Array and size_values.size()==2:
		output_size=Vector2i(int(size_values[0]),int(size_values[1]))
	if output_size.x<=0 or output_size.y<=0:
		push_error("pixel24: %s has invalid output size"%entry_id)
		return {"ok":false}
	if not _apply_alpha_policy(image,entry):return {"ok":false}
	var source_anchor:=Vector2.ZERO
	var has_source_anchor:=false
	var anchor_values:Variant=entry.get("source_anchor",[])
	if anchor_values is Array and anchor_values.size()==2:
		source_anchor=Vector2(float(anchor_values[0]),float(anchor_values[1]))
		has_source_anchor=true
	if entry.has("tile_source_grid"):
		image=_normalize_tile_atlas(image,output_size,entry)
		if image==null:return {"ok":false}
	var anchor_transform:Variant=entry.get("anchor_transform",{})
	var transformed_by_anchors:bool=anchor_transform is Dictionary \
		and not anchor_transform.is_empty()
	if transformed_by_anchors:
		image=_transform_by_two_anchors(image,anchor_transform,output_size,entry_id)
		if image==null:return {"ok":false}
	if not transformed_by_anchors and bool(entry.get("trim_keyed",false)):
		var used:=_alpha_used_rect(image)
		if not used.has_area():
			push_error("pixel24: %s keyed crop has no subject pixels"%entry_id)
			return {"ok":false}
		if has_source_anchor:source_anchor-=Vector2(used.position)
		image=image.get_region(used)
	var fit_values:Variant=[] if transformed_by_anchors else entry.get("fit_size",[])
	if fit_values is Array and fit_values.size()==2:
		var fit_size:=Vector2i(int(fit_values[0]),int(fit_values[1]))
		if fit_size.x<=0 or fit_size.y<=0 or fit_size.x>output_size.x \
				or fit_size.y>output_size.y:
			push_error("pixel24: %s has invalid fit_size"%entry_id)
			return {"ok":false}
		var pre_resize_size:=Vector2(image.get_size())
		var resized:=_resize_for_fit(image,fit_size,str(entry.get("fit_mode","stretch")))
		var resized_anchor:=Vector2(source_anchor.x*float(resized.get_width())/pre_resize_size.x,
			source_anchor.y*float(resized.get_height())/pre_resize_size.y)
		if bool(entry.get("trim_keyed",false)) and not has_source_anchor:
			var resized_used:=_alpha_used_rect(resized)
			if resized_used.has_area():resized=resized.get_region(resized_used)
		var destination:=Vector2i.ZERO
		if has_source_anchor:
			var target_values:Variant=entry.get("target_anchor",[])
			if not target_values is Array or target_values.size()!=2:
				push_error("pixel24: %s anchored asset needs target_anchor [x,y]"%entry_id)
				return {"ok":false}
			destination=Vector2i(roundi(float(target_values[0])-resized_anchor.x),
				roundi(float(target_values[1])-resized_anchor.y))
		else:
			var destination_values:Variant=entry.get("destination",[])
			if not destination_values is Array or destination_values.size()!=2:
				push_error("pixel24: %s fitted asset needs destination [x,y]"%entry_id)
				return {"ok":false}
			destination=Vector2i(int(destination_values[0]),int(destination_values[1]))
		var fit_align:=str(entry.get("fit_align","top_left"))
		if fit_align=="center":
			destination+=Vector2i((fit_size.x-resized.get_width())/2,
				(fit_size.y-resized.get_height())/2)
		elif fit_align=="bottom_center":
			destination+=Vector2i((fit_size.x-resized.get_width())/2,
				fit_size.y-resized.get_height())
		elif fit_align!="top_left":
			push_error("pixel24: %s has invalid fit_align"%entry_id)
			return {"ok":false}
		if destination.x<0 or destination.y<0 \
				or destination.x+resized.get_width()>output_size.x \
				or destination.y+resized.get_height()>output_size.y:
			push_error("pixel24: %s fitted subject leaves output canvas"%entry_id)
			return {"ok":false}
		var canvas:=Image.create(output_size.x,output_size.y,false,Image.FORMAT_RGBA8)
		canvas.fill(Color.TRANSPARENT)
		canvas.blend_rect(resized,Rect2i(Vector2i.ZERO,resized.get_size()),destination)
		image=canvas
	elif image.get_size()!=output_size:
		image.resize(output_size.x,output_size.y,Image.INTERPOLATE_NEAREST)
	_retain_foreground_pixels(image,entry)
	_clear_protected_rects(image,entry)
	_binary_alpha(image,int(_manifest.get("alpha_threshold",128)))
	var palette_limit:=int(entry.get("palette_limit",0))
	if palette_limit>0:_quantize_rgb(image,palette_limit)
	var tile_limits:Variant=entry.get("tile_palette_limits",[])
	if tile_limits is Array and not tile_limits.is_empty():
		if not _quantize_tiles(image,entry,tile_limits):return {"ok":false}
	var runtime_root:=str(_manifest.get("runtime_root",""))
	var output_path:=runtime_root.path_join(str(entry.output))
	if not _ensure_parent(output_path):return {"ok":false}
	var save_error:=image.save_png(ProjectSettings.globalize_path(output_path))
	if save_error!=OK:
		push_error("pixel24: %s failed to save %s (%d)"%[entry_id,output_path,save_error])
		return {"ok":false}
	return {"ok":true,"id":entry_id,"kind":str(entry.get("kind","")),
		"fit":str(entry.get("fit","")),"output":output_path,"image":image}


func _retain_foreground_pixels(image:Image,entry:Dictionary)->void:
	var points:Variant=entry.get("retain_points",[])
	var color_regions:Variant=entry.get("retain_color_regions",[])
	if (not points is Array or points.is_empty()) \
			and (not color_regions is Array or color_regions.is_empty()):return
	var keep:Dictionary={}
	if points is Array:
		for raw in points:
			if raw is Array and raw.size()==2:keep[Vector2i(int(raw[0]),int(raw[1]))]=true
	if color_regions is Array:
		for raw_region in color_regions:
			if not raw_region is Dictionary:continue
			var rv:Variant=raw_region.get("rect",[]);var colors:Variant=raw_region.get("rgb",[])
			if not rv is Array or rv.size()!=4 or not colors is Array:continue
			var rect:=Rect2i(int(rv[0]),int(rv[1]),int(rv[2]),int(rv[3])) \
				.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
			var keys:Dictionary={}
			for rgb in colors:
				if rgb is Array and rgb.size()==3:
					keys[(int(rgb[0])<<16)|(int(rgb[1])<<8)|int(rgb[2])]=true
			for y in range(rect.position.y,rect.end.y):
				for x in range(rect.position.x,rect.end.x):
					if keys.has(_rgb_key(image.get_pixel(x,y))):keep[Vector2i(x,y)]=true
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if not keep.has(Vector2i(x,y)):image.set_pixel(x,y,Color.TRANSPARENT)


func _transform_by_two_anchors(source:Image,values:Dictionary,output_size:Vector2i,
		entry_id:String)->Image:
	var points:Array=[]
	for key in ["source_from","source_to","target_from","target_to"]:
		var raw:Variant=values.get(key,[])
		if not raw is Array or raw.size()!=2:
			push_error("pixel24: %s anchor_transform needs four [x,y] points"%entry_id)
			return null
		points.append(Vector2(float(raw[0]),float(raw[1])))
	var source_from:Vector2=points[0];var source_to:Vector2=points[1]
	var target_from:Vector2=points[2];var target_to:Vector2=points[3]
	var source_axis:=source_to-source_from;var target_axis:=target_to-target_from
	if source_axis.length()<1.0 or target_axis.length()<1.0:
		push_error("pixel24: %s anchor_transform axes are degenerate"%entry_id)
		return null
	var scale:=target_axis.length()/source_axis.length()
	var angle:=target_axis.angle()-source_axis.angle()
	var cosine:=cos(angle);var sine:=sin(angle)
	var output:=Image.create(output_size.x,output_size.y,false,Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	for target_y in range(output_size.y):
		for target_x in range(output_size.x):
			var delta:=(Vector2(target_x,target_y)-target_from)/scale
			var source_delta:=Vector2(delta.x*cosine+delta.y*sine,
				-delta.x*sine+delta.y*cosine)
			var source_position:=source_from+source_delta
			var source_x:=roundi(source_position.x);var source_y:=roundi(source_position.y)
			if source_x>=0 and source_y>=0 and source_x<source.get_width() \
					and source_y<source.get_height():
				output.set_pixel(target_x,target_y,source.get_pixel(source_x,source_y))
	return output


func _apply_alpha_policy(image:Image,entry:Dictionary)->bool:
	var mode:=str(entry.get("alpha_mode","source"))
	if mode=="source":return true
	if mode not in ["chroma_key","magenta_hue"]:
		push_error("pixel24: %s has unknown alpha_mode %s"%[str(entry.id),mode])
		return false
	var kr:=0;var kg:=0;var kb:=0;var tolerance:=0
	if mode=="chroma_key":
		var key_values:Variant=entry.get("chroma_key",[])
		if not key_values is Array or key_values.size()!=3:
			push_error("pixel24: %s chroma_key needs [r,g,b]"%str(entry.id))
			return false
		kr=int(key_values[0]);kg=int(key_values[1]);kb=int(key_values[2])
		tolerance=int(entry.get("chroma_tolerance",0))
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color:=image.get_pixel(x,y)
			if mode=="chroma_key":
				var distance:=absi(int(round(color.r*255.0))-kr) \
					+absi(int(round(color.g*255.0))-kg) \
					+absi(int(round(color.b*255.0))-kb)
				if distance<=tolerance:color=Color.TRANSPARENT
			elif _is_magenta_key(color,entry):color=Color.TRANSPARENT
			elif _is_rejected_hue(color,entry):color=Color.TRANSPARENT
			image.set_pixel(x,y,color)
	return true


func _is_rejected_hue(color:Color,entry:Dictionary)->bool:
	var range_values:Variant=entry.get("reject_hue_range",[])
	if not range_values is Array or range_values.size()!=2:return false
	return color.h>=float(range_values[0]) and color.h<=float(range_values[1]) \
		and color.s>=float(entry.get("reject_hue_min_saturation",0.4))


func _is_magenta_key(color:Color,entry:Dictionary)->bool:
	var hsv_h:=color.h
	var hue_distance:=minf(absf(hsv_h-5.0/6.0),1.0-absf(hsv_h-5.0/6.0))
	return hue_distance<=float(entry.get("key_hue_tolerance",0.12)) \
		and color.s>=float(entry.get("key_min_saturation",0.72)) \
		and color.v>=float(entry.get("key_min_value",0.0))


func _clear_protected_rects(image:Image,entry:Dictionary)->void:
	var protected:Variant=entry.get("protected_rects",[])
	if not protected is Array:return
	for values in protected:
		if not values is Array or values.size()!=4:continue
		var rect:=Rect2i(int(values[0]),int(values[1]),int(values[2]),int(values[3])) \
			.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
		for y in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x):image.set_pixel(x,y,Color.TRANSPARENT)


func _resize_for_fit(source:Image,fit_size:Vector2i,mode:String)->Image:
	var result:=source.duplicate()
	var target:=fit_size
	if mode=="contain":
		var ratio:=minf(float(fit_size.x)/float(source.get_width()),
			float(fit_size.y)/float(source.get_height()))
		target=Vector2i(maxi(1,int(round(source.get_width()*ratio))),
			maxi(1,int(round(source.get_height()*ratio))))
	elif mode!="stretch":
		push_warning("pixel24: unknown fit_mode %s; using stretch"%mode)
	result.resize(target.x,target.y,Image.INTERPOLATE_NEAREST)
	return result


func _normalize_tile_atlas(source:Image,output_size:Vector2i,entry:Dictionary)->Image:
	var grid_values:Variant=entry.get("tile_source_grid",[])
	var inset_values:Variant=entry.get("tile_source_inset",[0,0,0,0])
	if not grid_values is Array or grid_values.size()!=2 \
			or not inset_values is Array or inset_values.size()!=4:
		push_error("pixel24: %s invalid tile source grid/inset"%str(entry.id));return null
	var columns:=int(grid_values[0]);var rows:=int(grid_values[1])
	if columns<=0 or rows<=0 or output_size.x%columns!=0 or output_size.y%rows!=0:
		push_error("pixel24: %s invalid tile output grid"%str(entry.id));return null
	var target_tile:=Vector2i(output_size.x/columns,output_size.y/rows)
	var atlas:=Image.create(output_size.x,output_size.y,false,Image.FORMAT_RGBA8)
	for row in range(rows):
		for column in range(columns):
			var left:=int(floor(float(column*source.get_width())/float(columns)))
			var right:=int(floor(float((column+1)*source.get_width())/float(columns)))
			var top:=int(floor(float(row*source.get_height())/float(rows)))
			var bottom:=int(floor(float((row+1)*source.get_height())/float(rows)))
			var inner:=Rect2i(left+int(inset_values[0]),top+int(inset_values[1]),
				right-left-int(inset_values[0])-int(inset_values[2]),
				bottom-top-int(inset_values[1])-int(inset_values[3]))
			if inner.size.x<=0 or inner.size.y<=0:
				push_error("pixel24: %s tile inset consumes cell"%str(entry.id));return null
			var tile:=source.get_region(inner)
			tile.resize(target_tile.x,target_tile.y,Image.INTERPOLATE_NEAREST)
			atlas.blit_rect(tile,Rect2i(Vector2i.ZERO,target_tile),
				Vector2i(column*target_tile.x,row*target_tile.y))
	return atlas


func _binary_alpha(image:Image,threshold:int)->void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color:=image.get_pixel(x,y)
			color.a=1.0 if int(round(color.a*255.0))>=threshold else 0.0
			image.set_pixel(x,y,color)


func _alpha_used_rect(image:Image)->Rect2i:
	var min_x:=image.get_width();var min_y:=image.get_height()
	var max_x:=-1;var max_y:=-1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x,y).a<=0.0:continue
			min_x=mini(min_x,x);min_y=mini(min_y,y)
			max_x=maxi(max_x,x);max_y=maxi(max_y,y)
	return Rect2i() if max_x<min_x else Rect2i(min_x,min_y,max_x-min_x+1,max_y-min_y+1)


func _quantize_rgb(image:Image,limit:int)->void:
	var histogram:Dictionary={}
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color:=image.get_pixel(x,y)
			if color.a<0.5:continue
			var key:=_rgb_key(color)
			histogram[key]=int(histogram.get(key,0))+1
	if histogram.size()<=limit:return
	var palette:=_clustered_palette(histogram,limit)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color:=image.get_pixel(x,y)
			if color.a<0.5:continue
			var nearest:=_nearest_rgb_key(_rgb_key(color),palette)
			image.set_pixel(x,y,_color_from_rgb_key(nearest))


func _clustered_palette(histogram:Dictionary,limit:int)->Array[int]:
	var keys:Array=histogram.keys();keys.sort()
	var palette:Array[int]=[]
	var darkest:=int(keys[0]);var lightest:=darkest;var saturated:=darkest
	var darkest_luma:=1000000;var lightest_luma:=-1;var best_chroma:=-1
	for raw_key in keys:
		var key:=int(raw_key);var r:=(key>>16)&255;var g:=(key>>8)&255;var b:=key&255
		var luma:=r*299+g*587+b*114
		var chroma:=maxi(r,maxi(g,b))-mini(r,mini(g,b))
		if luma<darkest_luma:darkest_luma=luma;darkest=key
		if luma>lightest_luma:lightest_luma=luma;lightest=key
		if chroma>best_chroma:best_chroma=chroma;saturated=key
	for seed in [darkest,lightest,saturated]:
		if seed not in palette and palette.size()<limit:palette.append(seed)
	while palette.size()<limit:
		var best_key:=-1;var best_score:=-1.0
		for raw_key in keys:
			var key:=int(raw_key)
			if key in palette:continue
			var distance:=_rgb_distance_to_palette(key,palette)
			var score:=float(distance)*sqrt(float(int(histogram[key])))
			if score>best_score or (is_equal_approx(score,best_score) and key<best_key):
				best_score=score;best_key=key
		if best_key<0:break
		palette.append(best_key)
	# Weighted Lloyd refinement keeps clusters deterministic while retaining the
	# explicit dark, light and saturated seeds that protect readability accents.
	for _iteration in range(6):
		var sums:Array=[]
		for _index in range(palette.size()):sums.append([0,0,0,0])
		for raw_key in keys:
			var key:=int(raw_key);var cluster:=_nearest_palette_index(key,palette)
			var weight:=int(histogram[key]);var sum:Array=sums[cluster]
			sum[0]+=((key>>16)&255)*weight;sum[1]+=((key>>8)&255)*weight
			sum[2]+=(key&255)*weight;sum[3]+=weight;sums[cluster]=sum
		for index in range(palette.size()):
			var sum:Array=sums[index]
			if int(sum[3])<=0:continue
			palette[index]=(int(round(float(sum[0])/float(sum[3])))<<16) \
				|(int(round(float(sum[1])/float(sum[3])))<<8) \
				|int(round(float(sum[2])/float(sum[3])))
	palette.sort()
	return palette


func _rgb_distance_to_palette(key:int,palette:Array[int])->int:
	var nearest_distance:=2147483647
	for candidate in palette:
		nearest_distance=mini(nearest_distance,_rgb_distance(key,candidate))
	return nearest_distance


func _nearest_palette_index(key:int,palette:Array[int])->int:
	var best_index:=0;var best_distance:=2147483647
	for index in range(palette.size()):
		var distance:=_rgb_distance(key,palette[index])
		if distance<best_distance:
			best_distance=distance;best_index=index
	return best_index


func _rgb_distance(a:int,b:int)->int:
	var dr:=((a>>16)&255)-((b>>16)&255)
	var dg:=((a>>8)&255)-((b>>8)&255)
	var db:=(a&255)-(b&255)
	return dr*dr+dg*dg+db*db


func _quantize_tiles(image:Image,entry:Dictionary,limits:Array)->bool:
	var grid_values:Variant=entry.get("tile_grid",[4,4])
	if not grid_values is Array or grid_values.size()!=2:return false
	var columns:=int(grid_values[0]);var rows:=int(grid_values[1])
	if columns<=0 or rows<=0 or image.get_width()%columns!=0 \
			or image.get_height()%rows!=0 or limits.size()!=columns*rows:
		push_error("pixel24: %s tile palette/grid mismatch"%str(entry.id))
		return false
	var tile_size:=Vector2i(image.get_width()/columns,image.get_height()/rows)
	for tile_y in range(rows):
		for tile_x in range(columns):
			var index:=tile_y*columns+tile_x
			var rect:=Rect2i(Vector2i(tile_x*tile_size.x,tile_y*tile_size.y),tile_size)
			var tile:=image.get_region(rect)
			_quantize_rgb(tile,int(limits[index]))
			image.blit_rect(tile,Rect2i(Vector2i.ZERO,tile_size),rect.position)
	return true


func _rgb_key(color:Color)->int:
	return (int(round(color.r*255.0))<<16) | (int(round(color.g*255.0))<<8) \
		| int(round(color.b*255.0))


func _nearest_rgb_key(key:int,palette:Array[int])->int:
	var kr:=(key>>16)&255;var kg:=(key>>8)&255;var kb:=key&255
	var best:=palette[0];var best_distance:=2147483647
	for candidate in palette:
		var dr:=kr-((candidate>>16)&255)
		var dg:=kg-((candidate>>8)&255)
		var db:=kb-(candidate&255)
		var distance:=dr*dr+dg*dg+db*db
		if distance<best_distance or (distance==best_distance and candidate<best):
			best_distance=distance;best=candidate
	return best


func _color_from_rgb_key(key:int)->Color:
	return Color8((key>>16)&255,(key>>8)&255,key&255,255)


func _write_reviews()->bool:
	var logical_size:=int(_manifest.get("logical_size",24))
	var review_cell_size:=int(_manifest.get("review_cell_size",logical_size))
	var scale:=int(_manifest.get("review_scale",6))
	var requested_contact_columns:=int(_manifest.get("review_columns",8))
	var columns:=mini(maxi(1,requested_contact_columns),maxi(1,_built.size()))
	var rows:=ceili(float(_built.size())/float(columns))
	var actual:=Image.create(columns*review_cell_size,rows*review_cell_size,false,Image.FORMAT_RGBA8)
	actual.fill(REVIEW_BG)
	for index in range(_built.size()):
		var source:Image=_built[index].image
		var thumbnail:=source.duplicate()
		if thumbnail.get_width()>review_cell_size or thumbnail.get_height()>review_cell_size:
			thumbnail=_resize_for_fit(thumbnail,Vector2i(review_cell_size,review_cell_size),"contain")
		actual.blend_rect(thumbnail,Rect2i(Vector2i.ZERO,thumbnail.get_size()),
			Vector2i((index%columns)*review_cell_size+(review_cell_size-thumbnail.get_width())/2,
				(index/columns)*review_cell_size+(review_cell_size-thumbnail.get_height())/2))
	var review_root:=str(_manifest.get("review_root",""))
	if not _save_review(actual,review_root.path_join("actual-size-contact.png")):return false
	var enlarged:=actual.duplicate()
	enlarged.resize(actual.get_width()*scale,actual.get_height()*scale,
		Image.INTERPOLATE_NEAREST)
	if not _save_review(enlarged,review_root.path_join("nearest-contact-%dx.png"%scale)):
		return false
	for row in _built:
		if str(row.kind)!="terrain_atlas":continue
		var terrain:Image=row.image.duplicate()
		terrain.resize(terrain.get_width()*scale,terrain.get_height()*scale,
			Image.INTERPOLATE_NEAREST)
		if not _save_review(terrain,review_root.path_join("%s-%dx.png"%[
			str(row.id),scale])):return false
	if not _write_composite_reviews(review_root,logical_size,scale):return false
	return _write_review_index(review_root)


func _write_composite_reviews(review_root:String,logical_size:int,scale:int)->bool:
	var composites:Variant=_manifest.get("composites",[])
	if not composites is Array or composites.is_empty():return true
	var by_id:Dictionary={}
	for row in _built:by_id[str(row.id)]=row.image
	var requested_columns:=int(_manifest.get("review_composite_columns",8))
	var columns:=mini(maxi(1,requested_columns),maxi(1,composites.size()))
	var rows:=ceili(float(composites.size())/float(columns))
	var sheet:=Image.create(columns*logical_size,rows*logical_size,false,Image.FORMAT_RGBA8)
	sheet.fill(REVIEW_BG)
	for index in range(composites.size()):
		var composite:Variant=composites[index]
		if not composite is Dictionary or not composite.get("layers",[]) is Array:
			push_error("pixel24: malformed review composite %d"%index);return false
		var canvas:=Image.create(logical_size,logical_size,false,Image.FORMAT_RGBA8)
		canvas.fill(Color.TRANSPARENT)
		for layer_id in composite.layers:
			if not by_id.has(str(layer_id)):
				push_error("pixel24: composite %s lacks layer %s"%[
					str(composite.get("id",index)),str(layer_id)])
				return false
			var layer:Image=by_id[str(layer_id)]
			if layer.get_size()!=Vector2i(logical_size,logical_size):
				push_error("pixel24: composite layers must be logical-size images")
				return false
			canvas.blend_rect(layer,Rect2i(Vector2i.ZERO,layer.get_size()),Vector2i.ZERO)
		var foreground_id:=str(composite.get("foreground_source",""))
		var foreground_regions:Variant=composite.get("foreground_regions",[])
		if not foreground_id.is_empty() and foreground_regions is Array:
			if not by_id.has(foreground_id):
				push_error("pixel24: composite foreground source %s missing"%foreground_id)
				return false
			var foreground:Image=by_id[foreground_id]
			for raw_region in foreground_regions:
				if not raw_region is Array or raw_region.size()!=4:
					push_error("pixel24: malformed foreground region");return false
				var region:=Rect2i(int(raw_region[0]),int(raw_region[1]),
					int(raw_region[2]),int(raw_region[3]))
				canvas.blend_rect(foreground,region,region.position)
		var foreground_points:Variant=composite.get("foreground_points",[])
		if not foreground_id.is_empty() and foreground_points is Array:
			var foreground:Image=by_id[foreground_id]
			for raw_point in foreground_points:
				if not raw_point is Array or raw_point.size()!=2:continue
				var point:=Vector2i(int(raw_point[0]),int(raw_point[1]))
				if Rect2i(Vector2i.ZERO,foreground.get_size()).has_point(point):
					var pixel:=foreground.get_pixelv(point)
					if pixel.a>0.0:canvas.set_pixelv(point,pixel)
		sheet.blend_rect(canvas,Rect2i(Vector2i.ZERO,canvas.get_size()),
			Vector2i((index%columns)*logical_size,(index/columns)*logical_size))
	if not _save_review(sheet,review_root.path_join("actual-size-composites.png")):
		return false
	var enlarged:=sheet.duplicate()
	enlarged.resize(sheet.get_width()*scale,sheet.get_height()*scale,
		Image.INTERPOLATE_NEAREST)
	return _save_review(enlarged,review_root.path_join("nearest-composites-%dx.png"%scale))


func _write_review_index(review_root:String)->bool:
	var rows:Array=[]
	for row in _built:rows.append({"id":row.id,"kind":row.kind,"fit":row.fit,
		"output":row.output})
	var payload:={"schema_version":1,"contact_order":rows,
		"composite_order":_manifest.get("composites",[])}
	var path:=review_root.path_join("review-index.json")
	if not _ensure_parent(path):return false
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:
		push_error("pixel24: cannot write %s"%path);return false
	file.store_string(JSON.stringify(payload,"  ")+"\n")
	return true


func _save_review(image:Image,path:String)->bool:
	if not _ensure_parent(path):return false
	var error:=image.save_png(ProjectSettings.globalize_path(path))
	if error!=OK:push_error("pixel24: failed to save review %s (%d)"%[path,error])
	return error==OK


func _ensure_parent(path:String)->bool:
	var error:=DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir()))
	if error!=OK:
		push_error("pixel24: cannot create output directory for %s (%d)"%[path,error])
	return error==OK
