extends SceneTree

const Items=preload("res://playtest/pixel24_item_assets.gd")
const Buildings=preload("res://playtest/pixel24_building_assets.gd")
const InventorySlot=preload("res://playtest/item_inventory_slot.gd")
const SettlementView=preload("res://playtest/base_settlement_view.gd")
const Grid=preload("res://playtest/party_grid_view.gd")

var failures:Array[String]=[]


func _init()->void:call_deferred("run")


func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)


func run()->void:
	_check_assets()
	_check_consumers_keep_state()
	_check_ground_fov_and_priority()
	if failures.is_empty():print("PASS pixel24 item/building acceptance")
	else:printerr("FAIL pixel24 item/building acceptance: %d"%failures.size())
	quit(0 if failures.is_empty() else 1)


func _check_assets()->void:
	for id in ["POTION_HEALING","FOOD_RATION","SCROLL_UNSPECIFIED",
			"ACCESSORY_BRASS_CHARM","MATERIAL_UNSPECIFIED","MAGIC_STONE",
			"TIMBER","STONE","HERBS","DROPPED_ITEM","LOOT_SACK","TOWN_GOLD"]:
		check(_is_binary(Items.texture_for_id(id),Vector2i(24,24)),
			"%s resolves binary-alpha 24px"%id)
	for type_id in ["STORAGE","LODGE","CLINIC","MARKET","ARMORY","GATE"]:
		for level in [1,2,3]:
			check(_is_binary(Buildings.texture(type_id,level),Buildings.expected_size(type_id)),
				"%s level %d matches footprint sprite size"%[type_id,level])
	check(Buildings.texture("UNKNOWN",1)==null,"unknown building keeps procedural fallback")
	check(Items.texture_for_id("RESERVED_KEY")==null,"reserved art does not invent an item ID")


func _check_consumers_keep_state()->void:
	var slot=InventorySlot.new()
	slot.configure({"definition_id":"POTION_HEALING","category":"CONSUMABLE",
		"quantity":4,"empty":false},2)
	var spec:Dictionary=slot.slot_draw_spec()
	check(spec.uses_texture and spec.quantity==4 and spec.slot_index==2,
		"inventory sprite preserves quantity and slot semantics")
	slot.configure({"empty":true,"quantity":0},3)
	check(not bool(slot.slot_draw_spec().uses_texture),"empty inventory slot stays code-drawn")
	slot.free()
	var settlement=SettlementView.new();settlement.size=Vector2(384,320);root.add_child(settlement)
	settlement.present({"settlement":{"width":16,"height":16,"buildings":[{
		"instance_id":"LODGE","type_id":"LODGE","tile_origin":[2,3],
		"footprint":[3,2],"level":2}] }},"LODGE")
	check(settlement.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,
		"settlement building sprites use nearest filtering")
	var lodge_rect:Rect2=settlement.building_rect("LODGE")
	check(lodge_rect.size==Vector2(60,40) \
		and bool(settlement.building_visual_state("LODGE").selected),
		"building sprite preserves footprint and selected building state")
	settlement.queue_free()


func _check_ground_fov_and_priority()->void:
	var grid=Grid.new();grid.size=Vector2(360,360)
	grid.set_observation({"width":15,"height":15,"cells":[
		{"position":[7,7],"terrain_id":"floor","visibility_state":"VISIBLE",
			"ground_items":[{"presentation_kind":"POTION","definition_id":"POTION_HEALING"},
				{"presentation_kind":"MATERIAL","definition_id":"MATERIAL_UNSPECIFIED"}],"actors":[]},
		{"position":[8,7],"terrain_id":"floor","visibility_state":"MEMORY",
			"ground_items":[{"presentation_kind":"POTION","definition_id":"POTION_HEALING"}],"actors":[]},
	]})
	var visible:=grid.ground_item_draw_spec(Vector2i(7,7))
	var memory:=grid.ground_item_draw_spec(Vector2i(8,7))
	check(visible.visible and visible.draw_image \
		and str(visible.texture.resource_path).ends_with("potion_healing.png"),
		"ground sprite follows the existing first-visible item priority")
	check(not memory.visible and not grid._cells["8:7"].has("ground_items") \
		and str(grid._cells["8:7"].get("ground_item_icon_id","")).is_empty(),
		"memory cell leaks neither item collection nor icon key")
	grid.free()


func _is_binary(texture:Texture2D,size:Vector2i)->bool:
	if texture==null or texture.get_size()!=Vector2(size):return false
	var image:=texture.get_image()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var alpha:=image.get_pixel(x,y).a
			if alpha!=0.0 and alpha!=1.0:return false
	return true
