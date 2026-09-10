extends ScrollContainer

## Stable short-range drop targets. Never reorder cards while a pointer is held.
const Assets=preload("res://playtest/fixed_front_topdown_assets.gd")
const DarkSkin=preload("res://playtest/dark_pixel_ui_skin.gd")
var row:HBoxContainer
var hovered_id:=-1
var hover_valid:=true

func _init()->void:
	name="BattleEnemyStrip"
	custom_minimum_size.y=48
	horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	row=HBoxContainer.new();row.add_theme_constant_override("separation",4)
	add_child(row)

var _last_signature:Array=[]

func sync(host,status:Dictionary={})->void:
	if status.is_empty():status=host.session.party_status()
	visible=host._enemy_strip_visible(status)
	if not visible:return
	var world=host.session.sim.world
	var ids:Array=[]
	var signature:Array=[]
	for enemy in host.session.enemy_targets(status):
		ids.append(int(enemy.entity_id))
		signature.append([int(enemy.entity_id),int(enemy.health),int(enemy.max_health),bool(enemy.alive)])
	ids.sort()
	var held:bool=host.battle_drag!=null and host.battle_drag.active
	# Rebuilding icons/text for every enemy on every battle event cost ~1.5ms;
	# only the visible roster, its vitals, the hover and the drag state matter.
	signature.append([held,hovered_id,hover_valid])
	if signature==_last_signature:return
	_last_signature=signature
	if not held:
		for child in row.get_children():
			if int(child.get_meta("entity_id")) not in ids:
				row.remove_child(child);child.queue_free()
	for id in ids:
		var button:=row.get_node_or_null("EnemyPortrait%d"%id) as Button
		if button==null:
			if held:continue
			button=Button.new();button.name="EnemyPortrait%d"%id
			button.set_meta("entity_id",id)
			button.custom_minimum_size=Vector2(76,48)
			button.expand_icon=true;button.icon_alignment=HORIZONTAL_ALIGNMENT_LEFT
			button.add_theme_constant_override("icon_max_width",30)
			button.add_theme_font_size_override("font_size",11)
			row.add_child(button)
			button.pressed.connect(func():
				if not host._battle_target_mode.is_empty():host._commit_battle_target(id)
				else:host._focus_battle_enemy(id))
		var entity=world.entities[id]
		button.icon=Assets.actor_layer_spec({"species_id":entity.species_id}).get("body_texture")
		button.text="%s\n%d/%d"%[entity.display_name,entity.health,entity.max_health]
		button.tooltip_text=entity.display_name
		button.disabled=not world.is_unresolved_enemy(id)
		DarkSkin.apply_action_button(button,(DarkSkin.BRASS if hover_valid else Color("#f36363")) \
			if id==hovered_id else Color("#ad6262"))

func target_at(position:Vector2)->int:
	if not is_visible_in_tree() or not get_global_rect().has_point(position):return -1
	for button in row.get_children():
		if not button.disabled and button.get_global_rect().has_point(position):
			return int(button.get_meta("entity_id"))
	return -1

func set_hover(id:int,valid:bool=true)->void:
	if row==null:return
	hovered_id=id;hover_valid=valid
	for button in row.get_children():
		DarkSkin.apply_action_button(button,(DarkSkin.BRASS if valid else Color("#f36363")) \
			if int(button.get_meta("entity_id"))==id else Color("#ad6262"))
