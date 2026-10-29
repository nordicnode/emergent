extends Node2D

## World-space cursor: the placement brush preview and the selected creature's
## ring. Drawn in the world so it lives under the terrain's zoom, not on a HUD.

const GridRef := preload("res://sim/grid.gd")

var _sim = null
var _cell := Vector2i.ZERO
var _radius := 3
var _material := GridRef.SAND
var _show_brush := false
var _selected := -1


func setup(sim) -> void:
	_sim = sim
	queue_redraw()


func update_cursor(cell: Vector2i, radius: int, material: int, show_brush: bool, selected: int) -> void:
	var flashing := false
	if _sim != null:
		flashing = not _sim.detectors.highlights.is_empty()
	if not flashing and selected < 0 and cell == _cell and radius == _radius and material == _material and show_brush == _show_brush and selected == _selected:
		return
	# A selected creature keeps moving, so its ring and aim line must be redrawn
	# every frame; an active first-time highlight pulses and expires on its own.
	_cell = cell
	_radius = radius
	_material = material
	_show_brush = show_brush
	_selected = selected
	queue_redraw()


func _draw() -> void:
	if _sim == null:
		return
	var px: float = float(_sim.grid.cell_px)

	if _show_brush:
		var center := Vector2((float(_cell.x) + 0.5) * px, (float(_cell.y) + 0.5) * px)
		var r := (float(_radius) + 0.5) * px
		var color := Color(0.9, 0.85, 0.6, 0.85)
		match _material:
			GridRef.SAND:
				color = Color(0.88, 0.79, 0.52, 0.85)
			GridRef.WATER:
				color = Color(0.40, 0.66, 0.95, 0.85)
			GridRef.FOOD:
				color = Color(0.52, 0.86, 0.42, 0.85)
			_:
				pass
		draw_arc(center, r, 0.0, TAU, 48, color, 2.0, true)
		draw_arc(center, r * 0.5, 0.0, TAU, 32, Color(color.r, color.g, color.b, 0.30), 1.0, true)

	# First-time patterns flash where they happened. These are highlights, not
	# narration: the log carries the sentence and the camera stays under the
	# player's control, so the world points at the event without taking over.
	for entry in _sim.detectors.active_highlights(_sim.time):
		if int(entry["x"]) < 0:
			continue
		var center := Vector2((float(entry["x"]) + 0.5) * px, (float(entry["y"]) + 0.5) * px)
		var age := maxf(_sim.time - float(entry["start"]), 0.0)
		var pulse := fmod(age, 1.15) / 1.15
		var color := _highlight_color(String(entry["kind"]))
		var ring := px * (2.2 + 1.7 * pulse)
		draw_arc(center, ring, 0.0, TAU, 36, Color(color.r, color.g, color.b, 0.85 * (1.0 - pulse)), 2.0, true)
		draw_arc(center, px * 1.2, 0.0, TAU, 20, Color(color.r, color.g, color.b, 0.60), 1.0, true)
		var font := ThemeDB.fallback_font
		if font != null:
			draw_string(font, center + Vector2(px * 2.4, -px * 1.2), String(entry["kind"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(color.r, color.g, color.b, 0.90))

	if _selected >= 0 and _selected < _sim.store.count and _sim.store.alive[_selected] == 1:
		var p := Vector2(_sim.store.px[_selected] * px, _sim.store.py[_selected] * px)
		draw_arc(p, px * 1.7, 0.0, TAU, 32, Color(1.0, 0.92, 0.45, 0.95), 2.0, true)
		# The aim line shows the decision the brain actually made.
		var aim := Vector2(_sim.store.aim_x[_selected] * px, _sim.store.aim_y[_selected] * px)
		draw_line(p, aim, Color(1.0, 0.92, 0.45, 0.22), 1.0, true)


func _highlight_color(kind: String) -> Color:
	match kind:
		"hardening":
			return Color(0.88, 0.78, 0.48)
		"shelter":
			return Color(0.98, 0.86, 0.40)
		"stockpile":
			return Color(0.48, 0.88, 0.42)
		"rivalry":
			return Color(0.92, 0.38, 0.32)
		_:
			return Color(0.72, 0.86, 0.98)
