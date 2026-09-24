extends SceneTree
## Layout guard: scripts live in domain folders, and modules never preload the session.
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

const FOLDERS := ["run","time","combat","spells","actors","ai","items","progression","level","ui","art","sim","legacy"]

func scripts(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null: return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var path := dir.path_join(name)
		if d.current_is_dir(): out.append_array(scripts(path))
		elif name.ends_with(".gd"): out.append(path)
		name = d.get_next()
	return out

func run() -> void:
	var flat: Array = scripts("res://expedition").filter(func(p): return p.get_base_dir() == "res://expedition")
	check(flat.is_empty(),"no flat scripts under expedition/: %s" % [flat])
	for p in scripts("res://expedition"):
		var folder: String = p.trim_prefix("res://expedition/").split("/")[0]
		check(folder in FOLDERS,"%s is in an unknown folder" % p)
		if folder in ["run","items","combat","spells","time"] and not p.ends_with("/session.gd"):
			var src := FileAccess.get_file_as_string(p)
			check(not src.contains("res://expedition/run/session.gd"),"%s must not preload the session (cycle)" % p)
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://expedition/ui/main.tscn","main scene lives in ui/")
	print("Layout guard: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
