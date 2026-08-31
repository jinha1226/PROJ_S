extends "res://tests/test_case.gd"

const Grid=preload("res://playtest/party_grid_view.gd")
const Style=preload("res://playtest/ascii_visual_style.gd")


func test_awareness_and_species_ascii_grammar()->bool:
	var expected:={"UNAWARE":"","SUSPICIOUS":"?","ALERT":"!","HUNTING":"»",
		"SEARCHING":"~","RETURNING":"<"}
	for state in expected:
		var spec:Dictionary=Style.awareness_spec(state)
		check_eq(spec.glyph,expected[state],"%s awareness glyph"%state)
		check_eq(bool(spec.visible),state!="UNAWARE","%s marker visibility"%state)
	check_eq(Style.awareness_spec("unknown").state,"UNAWARE","unknown state is safely unaware")
	var goblin:=Style.actor_spec({"faction_id":"enemy","species_id":"goblin"})
	var kobold:=Style.actor_spec({"faction_id":"enemy","species_id":"kobold"})
	check_eq([goblin.glyph,kobold.glyph],["g","K"],"standard roguelike species glyphs")
	check(Color(str(goblin.color_hex)).g>Color(str(goblin.color_hex)).r*1.2,
		"goblin owns green ink")
	var kobold_color:=Color(str(kobold.color_hex))
	check(kobold_color.r>kobold_color.b and kobold_color.g>kobold_color.b,
		"kobold owns ochre green-brown ink")
	return finish()


func test_visible_enemy_marks_list_grouping_and_transition_pulse_are_fov_safe()->bool:
	var grid=Grid.new();grid.size=Vector2(360,360)
	var actors:=[_enemy(1,Vector2i(24,24),"goblin","UNAWARE"),
		_enemy(2,Vector2i(25,24),"goblin","SUSPICIOUS"),
		_enemy(3,Vector2i(24,25),"goblin","ALERT"),
		_enemy(4,Vector2i(25,25),"goblin","ALERT"),
		_enemy(5,Vector2i(40,40),"kobold","HUNTING")]
	var observation:=_observation(actors,[{"position":[23,24],"terrain_id":"floor",
		"visibility_state":"MEMORY","actors":[_enemy(6,Vector2i(23,24),"kobold","HUNTING")]}])
	grid.set_observation(observation);grid.set_hero_centered_view(Vector2i(24,24),15)
	var mapping:=grid.mapping_signature();var hit:=grid.actor_hit_rect(2)
	check(not bool(grid.monster_awareness_marker_draw_spec(1).visible),"unaware has no mark")
	var marks:=grid.monster_awareness_marker_draw_specs()
	check_eq(marks.map(func(row):return row.entity_id),[2,3,4],
		"only visible in-viewport aware enemies emit marks")
	for mark in marks:
		check(Rect2(mark.cell_rect).encloses(Rect2(mark.text_rect)),
			"%s mark remains inside its own upper-right cell"%mark.state)
	var list:=grid.monster_list_draw_spec()
	check(list.visible and list.mouse_filter=="IGNORE" and list.row_count==3,
		"compact list includes unaware plus two aware groups without input surface")
	var alert_rows:Array=list.rows.filter(func(row):return row.state=="ALERT")
	check_eq([alert_rows.size(),alert_rows[0].count,alert_rows[0].text],
		[1,2,"g 고블린 ! ×2"],"same species and state aggregate deterministically")
	var changed:=observation.duplicate(true)
	for cell in changed.cells:
		for actor in cell.actors:
			if int(actor.entity_id)==2:actor.awareness_state="ALERT"
	grid.set_observation(changed)
	var pulse:Dictionary=grid._awareness_pulses[2]
	var active:=grid.monster_awareness_marker_draw_spec(2,int(pulse.started_at_ms)+1)
	var expired:=grid.monster_awareness_marker_draw_spec(2,int(pulse.started_at_ms)+221)
	check(active.pulse_active and not expired.pulse_active \
		and int(active.pulse_duration_ms)>=180 and int(active.pulse_duration_ms)<=250,
		"state transition owns a bounded presentation-only pulse")
	check_eq([grid.mapping_signature(),grid.actor_hit_rect(2)],[mapping,hit],
		"mark, list, and pulse preserve mapping and hit authority")
	grid.free();return finish()


func test_awareness_ui_fits_360_450_at_zoom_11_15_19_and_caps_five_rows()->bool:
	var states:=["SUSPICIOUS","ALERT","HUNTING","SEARCHING","RETURNING","UNAWARE"]
	var actors:Array=[]
	for index in range(states.size()):
		actors.append(_enemy(20+index,Vector2i(22+index%3,22+int(index/3)),
			"goblin" if index%2==0 else "kobold",states[index]))
	var observation:=_observation(actors)
	for viewport in [360,450]:
		for zoom in [11,15,19]:
			var grid=Grid.new();grid.size=Vector2(viewport,viewport)
			grid.set_observation(observation);grid.set_hero_centered_view(Vector2i(24,24),zoom)
			var list:=grid.monster_list_draw_spec()
			check(list.visible and int(list.row_count)<=5 and grid.grid_rect().encloses(Rect2(list.bounds)),
				"%dpx zoom%d list caps five rows and stays clipped to grid"%[viewport,zoom])
			for mark in grid.monster_awareness_marker_draw_specs():
				check(Rect2(mark.cell_rect).encloses(Rect2(mark.text_rect)),
					"%dpx zoom%d mark never enters an adjacent glyph cell"%[viewport,zoom])
			grid.free()
	return finish()


func _enemy(entity_id:int,position:Vector2i,species:String,state:String)->Dictionary:
	return {"entity_id":entity_id,"faction_id":"enemy","is_enemy":true,
		"species_id":species,"awareness_state":state,"position":[position.x,position.y]}

func _observation(actors:Array,extra_cells:Array=[])->Dictionary:
	var by_position:Dictionary={}
	for actor in actors:
		var p:=Vector2i(int(actor.position[0]),int(actor.position[1]))
		by_position["%d:%d"%[p.x,p.y]]={"position":[p.x,p.y],"terrain_id":"floor",
			"visibility_state":"VISIBLE","actors":[]}
		by_position["%d:%d"%[p.x,p.y]].actors.append(actor)
	var cells:Array=[]
	for value in by_position.values():cells.append(value)
	for row in extra_cells:cells.append(row)
	return {"width":48,"height":48,"cells":cells}
