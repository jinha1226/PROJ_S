extends SceneTree
## Rasterises every SVG under a folder to PNG with Godot's own SVG renderer,
## the one the game uses, so a preview matches what ships.
##   godot --headless --path . --script res://tools/art/rasterize_svgs.gd -- <res://folder> <scale>
## PNGs land in <folder>/png/<same sub-path>.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var root: String = args[0] if args.size() > 0 else "res://assets/soulstone-icons-v1"
	var scale: float = float(args[1]) if args.size() > 1 else 1.0
	var count := walk(root, root, scale)
	print("rasterised %d svg files" % count)
	quit(0 if count > 0 else 1)

func walk(root: String, dir_path: String, scale: float) -> int:
	var count := 0
	var dir := DirAccess.open(dir_path)
	if dir == null: return 0
	for sub in dir.get_directories():
		if sub == "png": continue
		count += walk(root, dir_path.path_join(sub), scale)
	for file in dir.get_files():
		if not file.ends_with(".svg"): continue
		var image := Image.new()
		if image.load_svg_from_string(FileAccess.get_file_as_string(dir_path.path_join(file)), scale) != OK:
			push_error("could not read " + file); continue
		var out: String = root.path_join("png").path_join(dir_path.trim_prefix(root)).path_join(file.get_basename()+".png")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
		image.save_png(out)
		count += 1
	return count
