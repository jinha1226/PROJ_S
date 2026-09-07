extends SceneTree

const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
var failures:Array[String]=[]

func _init()->void:call_deferred("_run")

func _run()->void:
	for dimensions in [Vector2i(360,640),Vector2i(450,800)]:
		root.size=dimensions
		var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
		var sandbox=Sandbox.new()
		sandbox.size=Vector2(dimensions)
		sandbox.initialize_for_headless_test(session)
		root.add_child(sandbox)
		await process_frame
		var source:Dictionary=session.party_cards()[0]
		for count in range(1,5):
			var rows:Array=[]
			for index in range(count):
				var row:Dictionary=source.duplicate(true)
				row.entity_id=index+1
				row.display_name="동료%d"%(index+1)
				rows.append(row)
			var spec:Dictionary=sandbox.render_party_cards_for_headless_test(rows)
			await process_frame
			await process_frame
			if spec.party_height!=72 or sandbox.cards.get_child_count()!=count:failures.append("count/height")
			for card in sandbox.cards.get_children():
				if card.party_count!=count:failures.append("presentation mode")
				if card.size.x<44 or card.size.y<44:failures.append("touch size")
				if not sandbox.get_global_rect().encloses(card.get_global_rect()):failures.append("outside viewport")
				if sandbox.grid.get_global_rect().intersects(card.get_global_rect()):failures.append("map overlap")
			rows[0].health=1
			sandbox._update_stable_party_cards(rows)
			if sandbox.cards.get_child(0).actor.health!=1:failures.append("stale HP")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/illustrated-ui-%d.png"%dimensions.x)
		sandbox.queue_free()
		await process_frame
	for failure in failures:printerr(failure)
	print("Compact party strip: 8 layouts, %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
