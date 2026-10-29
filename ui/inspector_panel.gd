extends PanelContainer

## Read-only causal evidence for the selected creature. The panel exists because
## the event chain is the point of the inspector: a list of opinion numbers
## without the events behind them is a scoreboard, not an explanation.
##
## It reads one story accessor and formats it. It never reads the log ring or
## reaches into sim state, and it never changes what the creature does.

const MUTED := "#8f9a88"
const BODY := "#e6e9dd"
const ACCENT := "#d8c58a"
const MemoryRef := preload("res://sim/memory.gd")
const GenomeRef := preload("res://sim/genome.gd")
const GridRef := preload("res://sim/grid.gd")

var _title: Label
var _body: RichTextLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(424.0, 0.0)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -442.0
	offset_right = -18.0
	offset_top = 18.0
	offset_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.055, 0.048, 0.94)
	style.border_color = Color(0.82, 0.86, 0.76, 0.14)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	_title = Label.new()
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_font_size_override("font_size", 16)
	_title.add_theme_color_override("font_color", Color(0.92, 0.94, 0.87))
	box.add_child(_title)

	_body = RichTextLabel.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("normal_font_size", 14)
	_body.add_theme_font_size_override("bold_font_size", 14)
	_body.add_theme_color_override("default_color", Color(0.90, 0.92, 0.86))
	_body.add_theme_constant_override("line_separation", 3)
	box.add_child(_body)


## `id` is the selected creature. Hidden when nothing is selected; the empty
## state teaches what will fill the panel, rather than showing a blank box.
func refresh(sim, id: int) -> void:
	if sim == null or id < 0 or id >= sim.store.count or sim.store.alive[id] == 0:
		visible = false
		return
	visible = true
	_title.text = "Creature %d" % id
	_body.text = _format(sim, id, sim.story.inspector_evidence(sim, id))


func _format(sim, id: int, evidence: Dictionary) -> String:
	var lines: Array = []
	# The individual's own life, in the order a player asks: what is it, where
	# did it come from, what does it remember, and who does it know?
	lines.append("[color=%s]Life[/color]" % MUTED)
	lines.append("%s · %.2f days · health %d%% · generation %d · founder line %d" % [
		String(sim.store.stage_name(int(sim.store.stage[id]))),
		float(sim.store.age_days[id]),
		int(round(float(sim.store.health[id]) * 100.0)),
		int(sim.store.generation[id]), int(sim.store.founder[id]),
	])
	lines.append("  born day %.2f · parents %d/%d · offspring %d" % [
		float(sim.store.birth_time[id]) / maxf(float(sim.day_seconds), 0.001),
		int(sim.store.mother[id]), int(sim.store.father[id]), int(sim.store.offspring[id]),
	])
	lines.append("  genes: %s" % GenomeRef.words(sim.store, id))

	# The same scores the brain chose from. The panel is self-contained: a player
	# reading only the inspector can still see the need, curve, memory, opinion
	# or distance component behind the current action.
	var scores: Array = sim.last_inspection.duplicate()
	scores.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	lines.append("")
	lines.append("[color=%s]Why this action[/color]" % MUTED)
	if scores.is_empty():
		lines.append("  waiting for the next decision")
	else:
		for k in mini(3, scores.size()):
			var candidate: Dictionary = scores[k]
			var parts_text := ""
			var parts: Dictionary = candidate.get("parts", {})
			for key in parts.keys():
				if not parts_text.is_empty():
					parts_text += ", "
				parts_text += "%s %.2f" % [key, float(parts[key])]
			lines.append("  %-9s %.2f  (%s)" % [String(candidate["label"]), float(candidate["score"]), parts_text])

	var places: int = int(sim.memory.place_count(id))
	if places > 0:
		lines.append("")
		lines.append("[color=%s]Remembered places[/color]" % MUTED)
		for k in mini(places, 3):
			var place: Dictionary = sim.memory.place_at(id, k)
			var cell := int(place.get("cell", -1))
			lines.append("  %d,%d %s · value %.2f · day %.2f" % [
				sim.grid.cell_x(cell), sim.grid.cell_y(cell),
				String(GridRef.MATERIAL_NAMES[int(place.get("material", 0))]),
				float(place.get("value", 0.0)), float(place.get("day", 0.0)),
			])

	var episodes: int = int(sim.memory.episode_count(id))
	if episodes > 0:
		lines.append("")
		lines.append("[color=%s]Last memories[/color]" % MUTED)
		for k in mini(episodes, 5):
			var ep: Dictionary = sim.memory.episode_at(id, episodes - 1 - k)
			lines.append("  day %.2f · %s (%s) · %s %.2f→%.2f · stress %.2f" % [
				float(ep.get("day", 0.0)),
				String(sim.store.verb_name(int(ep.get("verb", 0)))),
				String(MemoryRef.CONTEXT_NAMES[clampi(int(ep.get("context", 0)), 0, MemoryRef.CONTEXT_NAMES.size() - 1)]),
				"gain" if float(ep.get("after", 0.0)) >= float(ep.get("before", 0.0)) else "cost",
				float(ep.get("before", 0.0)), float(ep.get("after", 0.0)),
				float(ep.get("stress", 0.0)),
			])

	var opinions: Array = evidence.get("opinions", [])
	for op in opinions:
		lines.append("[color=%s]Strongest opinion[/color]" % MUTED)
		var kin := " · kin" if bool(op["kin"]) else ""
		lines.append("[b]%s[/b] · creature %d · %+.2f · %d events%s" % [
			String(op["label"]), int(op["other"]), float(op["valence"]), int(op["events"]), kin
		])
		var chain: Array = op.get("chain", [])
		if chain.is_empty():
			lines.append("[color=%s]No retained events.[/color]" % MUTED)
		else:
			for event in chain:
				lines.append("  %s · day %.2f · %+.2f" % [
					String(event["reason"]), float(event["day"]), float(event["delta"])
				])
		var acted: Dictionary = op.get("acted", {})
		if not acted.is_empty():
			lines.append("[color=%s]acted[/color]  fled creature %d · day %.2f" % [
				ACCENT, int(op["other"]), float(acted["day"])
			])

	var shelters: Array = evidence.get("shelters", [])
	if not shelters.is_empty():
		lines.append("")
		lines.append("[color=%s]Shelter[/color]" % MUTED)
		for shelter in shelters:
			lines.append("[b]%d,%d[/b]  piled by %d · day %.2f" % [
				int(shelter["x"]), int(shelter["y"]), int(shelter["builder"]), float(shelter["pile_day"])
			])
			lines.append("  hard day %.2f · rested by %d · day %.2f" % [
				float(shelter["hard_day"]), int(shelter["rester"]), float(shelter["rest_day"])
			])

	var caches: Array = evidence.get("caches", [])
	if not caches.is_empty():
		lines.append("")
		lines.append("[color=%s]Cache[/color]" % MUTED)
		for cache in caches:
			lines.append("[b]%d,%d[/b]  piled by %d · day %.2f" % [
				int(cache["x"]), int(cache["y"]), int(cache["builder"]), float(cache["pile_day"])
			])
			lines.append("  eaten by %d after %.1f h · hunger %d%%→%d%%" % [
				int(cache["eater"]), float(cache["hours"]),
				int(round((1.0 - float(cache["hunger_before"])) * 100.0)),
				int(round((1.0 - float(cache["hunger_after"])) * 100.0)),
			])

	if lines.is_empty():
		lines.append("[color=%s]No causal evidence yet.[/color]" % MUTED)
		lines.append("[color=%s]The first changed opinion, used shelter or eaten cache will appear here.[/color]" % MUTED)
	return "\n".join(lines)
