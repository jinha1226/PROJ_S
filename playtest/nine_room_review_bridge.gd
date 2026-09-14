extends Node
## Read-only instrumentation, enabled exclusively by capture_preview for local
## browser acceptance. It exposes the same public room/round data as the UI.
var ui
var elapsed:=0.0
func _process(delta:float)->void:
	elapsed+=delta
	if elapsed<0.2 or ui==null or ui.session==null or ui.grid==null:return
	elapsed=0.0
	var s=ui.session
	if not s.room_enabled():return
	var room:Dictionary=s.room_status();var cells:Array=[]
	var origin:=Vector2i(room.bounds[0],room.bounds[1])
	for y in range(8):
		for x in range(8):
			var p:=origin+Vector2i(x,y);var pixel:Vector2=ui.grid.global_position+ui.grid.world_to_pixel_center(p)
			cells.append({"world":[p.x,p.y],"pixel":[pixel.x,pixel.y],"visible":ui.grid.is_world_cell_visible(p)})
	var dto:Dictionary={"room":room,"round":s.round_status(),"time":s.sim.world.world_time,"hero":[s.sim.world.entities[s.sim.world.party_encounter.protagonist_id].position.x,s.sim.world.entities[s.sim.world.party_encounter.protagonist_id].position.y],"cells":cells,"grid_origin":[ui.grid.view_origin.x,ui.grid.view_origin.y],"grid_count":ui.grid.visible_cell_count,"grid_rect":[ui.grid.global_position.x,ui.grid.global_position.y,ui.grid.size.x,ui.grid.size.y],"memory":OS.get_static_memory_usage(),"journal":s.command_journal.size(),"input_locked":ui.grid._camera_input_blocked(),"buttons":{},"viewport":[ui.size.x,ui.size.y],"message":ui.event_label.text,"map_open":ui.map_overlay.visible,"detail_open":ui.member_detail_modal.visible}
	for key in ["product_rest_button","product_attack_button","product_auto_button","product_wait_guard_button","product_bag_button"]:
		var button=ui.get(key)
		if button!=null and button.is_visible_in_tree():
			var r:Rect2=button.get_global_rect();dto.buttons[key]={"text":button.text,"rect":[r.position.x,r.position.y,r.size.x,r.size.y]}
	JavaScriptBridge.eval("window.__nineRoomUI="+JSON.stringify(dto)+";",true)
