extends PanelContainer

## Read-only world history: lineages, completed places and first-time patterns.
## The panel is the Phase 2 lineage, history and place view in one readable
## surface. It reads recorded state only; it never reaches into a creature to
## change behaviour, and every row names the day it came from.

const MUTED := "#8f9a88"
const BODY := "#e6e9dd"
const ACCENT := "#d8c58a"

var _title: Label
var _body: RichTextLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(436.0, 372.0)
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 18.0
	offset_right = 454.0
	offset_top = -390.0
	offset_bottom = -18.0
	grow_vertical = Control.GROW_DIRECTION_BEGIN

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.055, 0.048, 0.94)
	style.border_color = Color(0.82, 0.86, 0.76, 0.14)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 7)
	margin.add_child(box)

	_title = Label.new()
	_title.text = "World history — H to close"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_font_size_override("font_size", 15)
	_title.add_theme_color_override("font_color", Color(0.92, 0.94, 0.87))
	box.add_child(_title)

	_body = RichTextLabel.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.bbcode_enabled = true
	_body.fit_content = false
	_body.scroll_active = true
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("normal_font_size", 13)
	_body.add_theme_font_size_override("bold_font_size", 13)
	_body.add_theme_color_override("default_color", Color(0.90, 0.92, 0.86))
	_body.add_theme_constant_override("line_separation", 2)
	box.add_child(_body)


func refresh(sim) -> void:
	if sim == null:
		return
	_body.text = _format(sim)


func _format(sim) -> String:
	var lines: Array = []

	var rows: Array = sim.history.lineage_rows(sim, 6)
	lines.append("[color=%s]Lineages[/color]" % MUTED)
	if rows.is_empty():
		lines.append("[color=%s]No births recorded yet.[/color]" % MUTED)
	else:
		for row in rows:
			var label := "line %d" % int(row["line"])
			if int(row["alive"]) == 0:
				lines.append("[b]%s[/b]  extinct day %.2f · %d born · %d died" % [
					label, float(row["extinct_day"]), int(row["born"]), int(row["died"])
				])
				continue
			lines.append("[b]%s[/b]  %d alive · %d born · %d died · gen %d" % [
				label, int(row["alive"]), int(row["born"]), int(row["died"]), int(row["max_generation"])
			])
			lines.append("  spread %.0f cells · drift %.2f · oldest %.2f d" % [
				float(row["spread"]), float(row["drift"]), float(row["oldest"])
			])
			var series: Array = row.get("series", [])
			if series.size() >= 2:
				lines.append("  population: %s" % _series_text(series))

	var places: Array = sim.story.place_history(sim, 6)
	lines.append("")
	lines.append("[color=%s]Places[/color]" % MUTED)
	if places.is_empty():
		lines.append("[color=%s]No completed shelter or cache yet.[/color]" % MUTED)
	else:
		for place in places:
			var kind := String(place["kind"])
			if kind == "contest":
				lines.append("[b]%d,%d[/b]  contested place · day %.2f · last loser %d" % [
					int(place["x"]), int(place["y"]), float(place["day"]), int(place["user"]),
				])
				lines.append("  %s" % String(place["detail"]))
				continue
			var kind_name := "shelter" if kind == "shelter" else "cache"
			lines.append("[b]%d,%d[/b]  %s · day %.2f · builder %d · user %d" % [
				int(place["x"]), int(place["y"]), kind_name, float(place["day"]),
				int(place["builder"]), int(place["user"]),
			])
			lines.append("  %s" % String(place["detail"]))
			if int(place.get("contests", 0)) > 0:
				lines.append("  contests: %d disputes, %d injuries (last day %.2f)" % [
					int(place["contests"]), int(place.get("injuries", 0)), float(place.get("contest_day", 0.0)),
				])

	var firsts: Array = sim.detectors.firsts
	lines.append("")
	lines.append("[color=%s]Firsts[/color]" % MUTED)
	if firsts.is_empty():
		lines.append("[color=%s]The first hard ground, shelter, stockpile or rivalry will appear here.[/color]" % MUTED)
	else:
		for entry in firsts:
			lines.append("[color=%s]day %.2f[/color]  %s" % [ACCENT, float(entry["day"]), String(entry["text"])])

	lines.append("")
	lines.append("[color=%s]Recent deaths[/color]" % MUTED)
	var deaths: Array = []
	for k in range(sim.log.entries.size() - 1, -1, -1):
		var entry: Dictionary = sim.log.entries[k]
		if String(entry["kind"]) == "death":
			deaths.append(entry)
			if deaths.size() >= 3:
				break
	if deaths.is_empty():
		lines.append("[color=%s]No deaths recorded yet.[/color]" % MUTED)
	else:
		for entry in deaths:
			lines.append("[color=%s]day %.2f[/color]  %s" % [ACCENT, float(entry["time"]) / maxf(float(sim.day_seconds), 0.001), String(entry["text"])])

	return "\n".join(lines)


## The last twelve samples, in plain numbers. A line of counts is slower to
## scan than a drawn curve but cannot be misread when the font has no block
## glyphs, and it is the same series the soak exports.
func _series_text(series: Array) -> String:
	var parts: Array = []
	var start := maxi(0, series.size() - 12)
	for k in range(start, series.size()):
		parts.append(str(int(series[k])))
	return " ".join(parts)
