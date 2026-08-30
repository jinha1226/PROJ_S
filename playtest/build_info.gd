class_name BuildInfo
extends RefCounted

# GitHub Pages CI replaces only this validated literal immediately before export.
# Local runs and all pre-export tests intentionally retain the safe fallback.
const BUILD_ID := "LOCAL"


static func display_text() -> String:
	return "BUILD %s" % BUILD_ID
