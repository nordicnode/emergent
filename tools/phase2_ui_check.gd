extends SceneTree

## Temporary smoke check for the Phase 2 panels. It builds a real sim, advances
## it briefly, then instantiates the reader-only panels and refreshes them.

const ParamsRef := preload("res://sim/params.gd")
const SimRef := preload("res://sim/sim.gd")
const HistoryPanelRef := preload("res://ui/history_panel.gd")
const InspectorPanelRef := preload("res://ui/inspector_panel.gd")


func _initialize() -> void:
	print("building sim")
	var sim = SimRef.new(ParamsRef.load_default(), 4242)
	sim.generate_world()
	sim.spawn_founders()
	for _s in 180:
		sim.step(sim.dt)
	print("sim ready")
	var history = HistoryPanelRef.new()
	history._ready()
	history.refresh(sim)
	print("history text lines: %d" % history._body.text.split("\n").size())
	var inspector = InspectorPanelRef.new()
	inspector._ready()
	inspector.refresh(sim, 0)
	print("inspector text lines: %d" % inspector._body.text.split("\n").size())
	print("history first line: %s" % history._body.text.split("\n")[0])
	print("inspector first line: %s" % inspector._body.text.split("\n")[0])
	quit(0)
