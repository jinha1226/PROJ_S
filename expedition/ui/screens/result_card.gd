extends RefCounted
## The defeat screen: the run's numbers, who walked with the party, and the way
## back to the kit picker. Moved out of main.gd.

static func build_result_card(ui) -> void:
	var session = ui.session
	var card := VBoxContainer.new(); card.name = "ResultCard"; card.size_flags_vertical = Control.SIZE_EXPAND_FILL; ui.root_layout.add_child(card)
	ui.label(card,"%d층에서 쓰러졌다" % session.depth,24)
	ui.label(card,"점수 %d · 라운드 %d · 처치 %d" % [session.score,session.world_time/100,session.run_stats.kills],16)
	for actor in session.party.slice(1):
		ui.label(card,"%s · %s" % [actor.name,"생존" if actor.hp > 0 else "%d층에서 전사" % session.depth],14)
	ui.label(card,"실수 %d" % int(session.run_stats.mistakes),14)
	companion_history(ui,card)
	# Another run means another kit: the result card hands the picker back.
	var start = ui.button(card,"새 Run",func(): ui.session = null; ui.refresh()); start.name = "NewRun"

## Who walked with the party this run, where they joined and whether they came
## back out (스펙 §1.2).
static func companion_history(ui, list: VBoxContainer) -> void:
	var rows: Array = ui.session.companion_rows()
	if rows.is_empty(): return
	ui.label(list,"동료 이력",15)
	for row in rows:
		ui.label(list,"%s · %d층 합류 · %s" % [row.name,int(row.joined_floor),"생존" if row.alive else "전사"],13)
