class_name SimParams
extends RefCounted

## The parameter register, loaded from data/parameters.json at startup.
## Tuning never requires recompiling, and soak runs can sweep values.

const DEFAULT_PATH := "res://data/parameters.json"

var data: Dictionary = {}


static func load_default(path: String = DEFAULT_PATH) -> SimParams:
	var p := SimParams.new()
	p._load(path)
	return p


func _load(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_error("Parameter register missing: %s" % path)
		return
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Parameter register is empty: %s" % path)
		return
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		data = parsed
	else:
		push_error("Parameter register is not valid JSON: %s" % path)


func f(section: String, key: String, fallback: float) -> float:
	var s: Variant = data.get(section, {})
	if s is Dictionary:
		var v: Variant = (s as Dictionary).get(key, null)
		if v is float or v is int:
			return float(v)
	return fallback


func i(section: String, key: String, fallback: int) -> int:
	return int(f(section, key, float(fallback)))
