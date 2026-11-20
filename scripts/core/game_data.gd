class_name GameData
extends RefCounted
## The web game's constants (data/web/*.json, exported by tools/export_data_browser.py). Read-only: never change a
## returned value; duplicate it first.

static var _index := {}
static var _files := {}


## A constant by its web name, e.g. GameData.c("BUILD_DEFS").
static func c(name: String):
	if _index.is_empty():
		var idx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/index.json"))
		_index = idx.constants
	var path: String = _index.get(name, "")
	if path == "":
		push_error("GameData: no constant " + name)
		return null
	if not _files.has(path):
		_files[path] = JSON.parse_string(FileAccess.get_file_as_string("res://" + path))
	return _files[path][name]
