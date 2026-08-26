class_name SkillProgress
extends RefCounted

var skill_id: StringName = &""
var level: int = 1
var xp: int = 0
var total_cycles: int = 0


func _init(
	p_skill_id: StringName = &"",
	p_level: int = 1,
	p_xp: int = 0,
	p_total_cycles: int = 0
) -> void:
	skill_id = p_skill_id
	level = p_level
	xp = p_xp
	total_cycles = p_total_cycles


func to_dict() -> Dictionary:
	return {
		"skill_id": str(skill_id),
		"level": level,
		"xp": xp,
		"total_cycles": total_cycles,
	}


static func from_dict(data: Dictionary) -> SkillProgress:
	return SkillProgress.new(
		StringName(str(data.get("skill_id", ""))),
		int(data.get("level", 1)),
		int(data.get("xp", 0)),
		int(data.get("total_cycles", 0))
	)


func clone_state() -> SkillProgress:
	return SkillProgress.from_dict(to_dict())


func validate(_content_registry: Variant = null) -> PackedStringArray:
	var errors := PackedStringArray()
	if skill_id == &"":
		errors.append("SkillProgress.skill_id is empty")
	if level < 1 or level > 5:
		errors.append("SkillProgress.level must be between 1 and 5")
	if xp < 0:
		errors.append("SkillProgress.xp must not be negative")
	if level == 5 and xp != 0:
		errors.append("SkillProgress.xp must be 0 at level 5")
	if total_cycles < 0:
		errors.append("SkillProgress.total_cycles must not be negative")
	return errors
