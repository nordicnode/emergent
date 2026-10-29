extends SceneTree

## Temporary Phase 2 cost probe:
##   godot --headless --path . --script res://tools/perception_probe.gd

const ParamsRef := preload("res://sim/params.gd")
const SimRef := preload("res://sim/sim.gd")
const BrainRef := preload("res://sim/brain.gd")
const GridRef := preload("res://sim/grid.gd")
const StoreRef := preload("res://sim/creature_store.gd")


func _initialize() -> void:
	var params = ParamsRef.load_default()
	var sim = SimRef.new(params, 101)
	sim.generate_world()
	sim.spawn_founders()
	var id := 0
	var t0 := Time.get_ticks_usec()
	for k in 2000:
		BrainRef._find_perceived(sim.grid, sim.store.px[id], sim.store.py[id], GridRef.FOOD, 18.0)
	var scan_ms := float(Time.get_ticks_usec() - t0) / 2000000.0
	t0 = Time.get_ticks_usec()
	for k in 2000:
		BrainRef._find_perceived(sim.grid, sim.store.px[id], sim.store.py[id], GridRef.WATER, 18.0)
	var water_ms := float(Time.get_ticks_usec() - t0) / 2000000.0
	t0 = Time.get_ticks_usec()
	for k in 1000:
		BrainRef.decide(sim.store, id, sim.grid, params, sim.rng, 18.0, false, -1, 0.0, sim.memory, sim.day(), sim.opinion, sim.neighbors, true, true, true)
	var decide_ms := float(Time.get_ticks_usec() - t0) / 1000000.0
	print("perceived food %.3f ms, water %.3f ms, decide %.3f ms (1 creature)" % [scan_ms, water_ms, decide_ms])
	quit(0)
