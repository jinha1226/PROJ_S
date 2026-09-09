class_name BuildInfo
extends RefCounted

# GitHub Pages CI replaces only this validated literal immediately before export.
# Local runs and all pre-export tests intentionally retain the safe fallback.
const BUILD_ID := "LOCAL"


static func display_text() -> String:
	return "BUILD %s" % build_id()


static func build_id() -> String:
	# A local run shows the checked-out commit so a screenshot says which build
	# it came from. Exports keep the CI-stamped literal.
	if BUILD_ID != "LOCAL":
		return BUILD_ID
	var commit := _local_commit()
	return commit if not commit.is_empty() else BUILD_ID


static func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text.strip_edges()


static func _local_commit() -> String:
	var project := ProjectSettings.globalize_path("res://")
	var git_dir := project.path_join(".git")
	if not DirAccess.dir_exists_absolute(git_dir):
		# A worktree checkout keeps a file pointing at its private git dir.
		var pointer := _read_text(git_dir)
		if not pointer.begins_with("gitdir:"):
			return ""
		git_dir = pointer.trim_prefix("gitdir:").strip_edges()
	var head := _read_text(git_dir.path_join("HEAD"))
	if head.is_empty():
		return ""
	if not head.begins_with("ref:"):
		return head.substr(0, 7)
	var ref := head.trim_prefix("ref:").strip_edges()
	var common_dir := git_dir
	var common_pointer := _read_text(git_dir.path_join("commondir"))
	if not common_pointer.is_empty():
		common_dir = common_pointer if common_pointer.is_absolute_path() \
			else git_dir.path_join(common_pointer).simplify_path()
	for base in [git_dir, common_dir]:
		var direct := _read_text(base.path_join(ref))
		if not direct.is_empty():
			return direct.substr(0, 7)
	for line in _read_text(common_dir.path_join("packed-refs")).split("\n"):
		var parts := line.strip_edges().split(" ")
		if parts.size() == 2 and parts[1] == ref:
			return parts[0].substr(0, 7)
	return ref.get_file()
