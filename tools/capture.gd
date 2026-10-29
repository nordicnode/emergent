extends Node

## Opens the real game scene, optionally fast-forwards the simulation, paints one
## brush stroke through the real input path, lets it render N frames, then writes
## the viewport to a PNG.
##   godot --path . res://tools/capture.tscn -- --frames=240 --zoom=3 --inspect=4 --out=/tmp/phase0.png
##   godot --path . res://tools/capture.tscn -- --frames=240 --paint=water --out=/tmp/paint.png
##   godot --path . res://tools/capture.tscn -- --frames=180 --zoom=3 --center=pond --seconds=240 --out=/tmp/pond.png
##   godot --path . res://tools/capture.tscn -- --story=shelter --inspect=0 --frames=120 --out=/tmp/shelter.png

const GridRef := preload("res://sim/grid.gd")
const SimRef := preload("res://sim/sim.gd")
const StoriesRef := preload("res://sim/tests/phase1_stories.gd")
const HarnessRef := preload("res://sim/tests/story_harness.gd")

var _frames := 0
var _target := 120
var _output := "/tmp/phase0_shot.png"
var _zoom := 0.0
var _inspect := -1
var _paint_material := -1
var _seconds := 0.0
var _center := ""
var _story := ""
var _main: Node = null
var _release_at := -1
var _press_screen := Vector2.ZERO
var _start_at := -1
var _done := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			_target = int(arg.split("=")[1])
		elif arg.begins_with("--out="):
			_output = arg.split("=")[1]
		elif arg.begins_with("--zoom="):
			_zoom = float(arg.split("=")[1])
		elif arg.begins_with("--inspect="):
			_inspect = int(arg.split("=")[1])
		elif arg.begins_with("--paint="):
			match arg.split("=")[1]:
				"sand":
					_paint_material = GridRef.SAND
				"water":
					_paint_material = GridRef.WATER
				"food":
					_paint_material = GridRef.FOOD
		elif arg.begins_with("--seconds="):
			_seconds = float(arg.split("=")[1])
		elif arg.begins_with("--center="):
			_center = arg.split("=")[1]
		elif arg.begins_with("--story="):
			_story = arg.split("=")[1]

	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)

	if _story != "":
		_load_story(_story)

	if _seconds > 0.0:
		var steps := int(_seconds / _main.sim.dt)
		for s in steps:
			_main.sim.step(_main.sim.dt)
		_main.terrain.repaint_all()
		print("fast-forwarded to day %.2f (%.0f s, %d steps)" % [_main.sim.day(), _seconds, steps])

	if _center == "pond":
		if _main.sim.pond_centers.is_empty():
			print("no pond to centre on")
		else:
			var pond: Vector2i = _main.sim.pond_centers[0]
			_main.camera.position = Vector2(pond) * float(_main.sim.grid.cell_px)
	elif _center.contains(","):
		var parts := _center.split(",")
		var cell := Vector2(float(parts[0]), float(parts[1]))
		_main.camera.position = cell * float(_main.sim.grid.cell_px)

	if _zoom > 0.0:
		_main.camera.zoom = Vector2(_zoom, _zoom)
	if _inspect >= 0:
		_main.selected_id = _inspect
		_main.sim.inspect_id = _inspect
		_main.hud.set_selected(_inspect)
	if _paint_material >= 0:
		_start_at = 5


## Loads one of the Phase 1 evidence scenarios into the real main scene. This is
## a capture tool, not a simulation path: it runs the same story setup and real
## ticks the headless suite uses, then rebinds the existing views to that world.
func _load_story(kind: String) -> void:
	var stories = StoriesRef.new()
	stories.set_params(_main.params)
	var params
	var setup: Callable
	var days := 0.0
	var story_seed := 0
	var feed := Callable()
	match kind:
		"shelter":
			params = stories._small_world_params()
			setup = stories._shelter_setup
			days = 2.0
			story_seed = 3101
		"storing":
			params = stories._small_world_params()
			setup = stories._storing_setup
			days = 1.5
			story_seed = 3102
		"rivalry":
			params = stories._rivalry_params()
			setup = stories._rivalry_setup
			days = 0.5
			story_seed = 3103
			feed = stories._rivalry_feed
		_:
			push_error("unknown story '%s' (shelter, storing, rivalry)" % kind)
			return
	var probe = SimRef.new(params, story_seed)
	var steps := int(days * float(probe.day_seconds) / probe.dt)
	var sim = HarnessRef.run(params, setup, steps, "", feed)["sim"]
	_main.sim = sim
	_main.terrain.setup(sim.grid, sim.story)
	_main.creatures.setup(sim.grid, sim.store)
	_main.cursor.setup(sim)
	_main.hud.setup(sim)
	_main.camera.position = _story_centroid(sim)
	print("story '%s' ready at day %.2f with %d alive" % [kind, sim.day(), sim.alive_count()])


func _story_centroid(sim) -> Vector2:
	var total := Vector2.ZERO
	var n := 0
	for i in sim.store.count:
		if sim.store.alive[i] == 0:
			continue
		total += Vector2(sim.store.px[i], sim.store.py[i])
		n += 1
	if n == 0:
		return Vector2(float(sim.grid.width) * 0.5, float(sim.grid.height) * 0.5) * float(sim.grid.cell_px)
	return (total / float(n)) * float(sim.grid.cell_px)


## Drives the real input path: warp the pointer to a world cell, press the left
## button, hold for a few frames, release. Verifies placement end to end.
func _start_paint_stroke() -> void:
	var px: float = float(_main.sim.grid.cell_px)
	var zoom: float = _main.camera.zoom.x
	var camera_cell: Vector2 = _main.camera.position / px
	var target := Vector2(camera_cell.x + 12.0, camera_cell.y)
	var world := target * px
	var screen: Vector2 = (world - _main.camera.position) * zoom + get_viewport().get_visible_rect().size * 0.5
	_press_screen = screen
	_main.brush_material = _paint_material
	get_viewport().warp_mouse(screen)

	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	Input.parse_input_event(motion)

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = screen
	press.global_position = screen
	Input.parse_input_event(press)
	_release_at = _frames + 60
	print("sent brush press: material %d, world cell %s, screen %s" % [_paint_material, str(target), str(screen)])


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _start_at >= 0 and _frames >= _start_at:
		_start_at = -1
		_start_paint_stroke()
	if _release_at >= 0 and _frames >= _release_at:
		_release_at = -1
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		release.position = _press_screen
		release.global_position = _press_screen
		Input.parse_input_event(release)

	if _frames < _target:
		return
	_done = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_output)
	if error == OK:
		print("saved screenshot: %s (%d x %d)" % [_output, image.get_width(), image.get_height()])
	else:
		push_error("could not save screenshot: %s" % error)
	get_tree().quit()
