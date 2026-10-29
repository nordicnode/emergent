extends Node2D

## Wires the simulation, the views and the interface together.
## The player does exactly three things here: place sand, place water, place
## food. The only other inputs are observation: pause, speed, zoom, inspect.

const ParamsRef := preload("res://sim/params.gd")
const SimRef := preload("res://sim/sim.gd")
const GridRef := preload("res://sim/grid.gd")

@onready var terrain = $Terrain
@onready var creatures = $Creatures
@onready var cursor = $Cursor
@onready var camera: Camera2D = $Camera
@onready var hud = $HUD

var params = null
var sim = null

var selected_id := -1
var brush_material := GridRef.SAND
var brush_radius := 3
var brush_amount := 3.0
var hover_cell := Vector2i.ZERO

var _zoom := 2.0
var _lmb_down := false
var _rmb_down := false
var _rmb_dragged := false
var _rmb_press_screen := Vector2.ZERO
var _hud_timer := 0.0
var _profiling := false
var _prof_frames := 0
var _prof := {"sim": 0.0, "terrain": 0.0, "creatures": 0.0, "cursor": 0.0, "hud": 0.0, "total": 0.0, "delta": 0.0}


func _ready() -> void:
	_profiling = "--profile" in OS.get_cmdline_user_args()
	params = ParamsRef.load_default()
	sim = SimRef.new(params, _cmdline_seed(params.i("spawn", "seed", 12345)))
	sim.generate_world()
	sim.spawn_founders()

	terrain.setup(sim.grid, sim.story)
	creatures.setup(sim.grid, sim.store)
	cursor.setup(sim)
	hud.setup(sim)

	_zoom = params.f("render", "initial_zoom", 2.0)
	camera.zoom = Vector2(_zoom, _zoom)
	camera.position = _founder_centroid()
	hud.update_text(brush_material, brush_radius, brush_amount, hover_cell)
	print("World ready: %d creatures, seed %d" % [sim.alive_count(), sim.seed_used])


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	sim.inspect_id = selected_id
	if not sim.paused:
		sim.advance(delta)
	if _lmb_down:
		_paint(delta)

	_update_hover()
	var t1 := Time.get_ticks_usec()
	terrain.refresh()
	var t2 := Time.get_ticks_usec()
	creatures.sync(sim.time)
	var t3 := Time.get_ticks_usec()
	cursor.update_cursor(hover_cell, brush_radius, brush_material, _brush_visible(), selected_id)
	var t4 := Time.get_ticks_usec()

	_hud_timer += delta
	if _hud_timer >= 0.1:
		_hud_timer = 0.0
		hud.update_text(brush_material, brush_radius, brush_amount, hover_cell)
	var t5 := Time.get_ticks_usec()

	if _profiling:
		_prof["sim"] += float(t1 - t0) / 1000.0
		_prof["terrain"] += float(t2 - t1) / 1000.0
		_prof["creatures"] += float(t3 - t2) / 1000.0
		_prof["cursor"] += float(t4 - t3) / 1000.0
		_prof["hud"] += float(t5 - t4) / 1000.0
		_prof["total"] += float(t5 - t0) / 1000.0
		_prof["delta"] += delta * 1000.0
		_prof_frames += 1
		if _prof_frames % 60 == 0:
			var n := float(_prof_frames)
			print("PROFILE frames %d  frame %.1f ms | sim %.1f terrain %.1f creatures %.1f cursor %.1f hud %.1f" % [
				_prof_frames, float(_prof["delta"]) / n, float(_prof["sim"]) / n, float(_prof["terrain"]) / n,
				float(_prof["creatures"]) / n, float(_prof["cursor"]) / n, float(_prof["hud"]) / n,
			])
			_prof_frames = 0
			for key in _prof.keys():
				_prof[key] = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			_on_key(key)


func _on_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				if event.shift_pressed:
					brush_amount = clampf(brush_amount + 0.5, 0.2, 8.0)
					_refresh_hud()
				else:
					_set_zoom(_zoom * params.f("render", "zoom_step", 1.12))
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				if event.shift_pressed:
					brush_amount = clampf(brush_amount - 0.5, 0.2, 8.0)
					_refresh_hud()
				else:
					_set_zoom(_zoom / params.f("render", "zoom_step", 1.12))
		MOUSE_BUTTON_LEFT:
			_lmb_down = event.pressed
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_rmb_down = true
				_rmb_dragged = false
				_rmb_press_screen = event.position
			else:
				if _rmb_down and not _rmb_dragged:
					_select_at_mouse()
				_rmb_down = false
		_:
			pass


func _on_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _rmb_down:
		return
	if event.position.distance_to(_rmb_press_screen) > 3.0:
		_rmb_dragged = true
	if _rmb_dragged:
		camera.position -= event.relative / _zoom


func _on_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_1:
			_set_material(GridRef.SAND, 3.0)
		KEY_2:
			_set_material(GridRef.WATER, 1.2)
		KEY_3:
			_set_material(GridRef.FOOD, 1.0)
		KEY_Q:
			brush_radius = maxi(1, brush_radius - 1)
			_refresh_hud()
		KEY_E:
			brush_radius = mini(16, brush_radius + 1)
			_refresh_hud()
		KEY_Z:
			brush_amount = maxf(0.2, brush_amount - 0.5)
			_refresh_hud()
		KEY_X:
			brush_amount = minf(8.0, brush_amount + 0.5)
			_refresh_hud()
		KEY_SPACE:
			sim.paused = not sim.paused
			_refresh_hud()
		KEY_BRACKETLEFT:
			sim.speed = maxf(0.25, sim.speed * 0.5)
			_refresh_hud()
		KEY_BRACKETRIGHT:
			sim.speed = minf(16.0, sim.speed * 2.0)
			_refresh_hud()
		KEY_ESCAPE:
			selected_id = -1
			sim.last_inspection = []
			hud.set_selected(-1)
		KEY_H:
			hud.toggle_history()
		KEY_F1:
			hud.toggle()
		_:
			pass


func _set_material(material: int, amount: float) -> void:
	brush_material = material
	brush_amount = amount
	_refresh_hud()


func _set_zoom(value: float) -> void:
	_zoom = clampf(value, params.f("render", "zoom_min", 0.4), params.f("render", "zoom_max", 4.0))
	camera.zoom = Vector2(_zoom, _zoom)


func _paint(delta: float) -> void:
	var cell := _mouse_cell()
	sim.apply_brush(brush_material, cell.x, cell.y, brush_radius, brush_amount * delta)


func _update_hover() -> void:
	hover_cell = _mouse_cell()


func _mouse_cell() -> Vector2i:
	var world := get_global_mouse_position()
	return Vector2i(
		int(floor(world.x / float(sim.grid.cell_px))),
		int(floor(world.y / float(sim.grid.cell_px)))
	)


func _brush_visible() -> bool:
	var mouse := get_viewport().get_mouse_position()
	return get_viewport().get_visible_rect().has_point(mouse)


func _select_at_mouse() -> void:
	var world := get_global_mouse_position()
	var px := float(sim.grid.cell_px)
	var best := -1
	var best_distance := 1.3 * px
	for i in sim.store.count:
		if sim.store.alive[i] == 0:
			continue
		var dx: float = float(sim.store.px[i]) * px - world.x
		var dy: float = float(sim.store.py[i]) * px - world.y
		var d: float = sqrt(dx * dx + dy * dy)
		if d < best_distance:
			best_distance = d
			best = i
	selected_id = best
	sim.inspect_id = best
	sim.last_inspection = []
	hud.set_selected(best)
	_refresh_hud()


func _refresh_hud() -> void:
	if hud != null:
		hud.update_text(brush_material, brush_radius, brush_amount, hover_cell)


func _founder_centroid() -> Vector2:
	var total := Vector2.ZERO
	var n := 0
	for i in sim.store.count:
		if sim.store.alive[i] == 0:
			continue
		total += Vector2(sim.store.px[i], sim.store.py[i])
		n += 1
	if n == 0:
		return Vector2(float(sim.grid.width) * 0.5, float(sim.grid.height) * 0.5)
	var cell := total / float(n)
	return cell * float(sim.grid.cell_px)


func _cmdline_seed(fallback: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			return int(arg.split("=")[1])
	return fallback
