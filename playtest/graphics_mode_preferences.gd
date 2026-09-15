class_name GraphicsModePreferences
extends RefCounted

const SECTION:="graphics"
const KEY:="mode"

static func load_mode(path:String,allowed:Array,default_mode:String)->String:
	var config:=ConfigFile.new()
	if config.load(path)!=OK:return default_mode
	var mode:=str(config.get_value(SECTION,KEY,default_mode)).to_upper()
	return mode if mode in allowed else default_mode

static func save_mode(path:String,mode:String,allowed:Array)->bool:
	var normalized:=mode.to_upper()
	if normalized not in allowed:return false
	var config:=ConfigFile.new();config.set_value(SECTION,KEY,normalized)
	return config.save(path)==OK
