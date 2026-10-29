extends SceneTree

## Temporary diagnostic for the move-to distance check.

const ParamsRef := preload("res://sim/params.gd")
const SimRef := preload("res://sim/sim.gd")
const GridRef := preload("res://sim/grid.gd")
const GenomeRef := preload("res://sim/genome.gd")
const StoreRef := preload("res://sim/creature_store.gd")


func _initialize() -> void:
	var params = ParamsRef.load_default()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cb="):
			params.data["brain"]["commitment_bonus"] = float(arg.substr(5))
			print("commitment bonus ", params.data["brain"]["commitment_bonus"])
	var sim = SimRef.new(params, 152)
	for y in range(6, 30):
		for x in range(6, 30):
			sim.grid.set_cell(x, y, GridRef.SAND, 1.0)
	var id: int = sim.store.spawn(10.5, 10.5, 0.5, 0.3, 0.9, 0.9)
	sim.memory.ensure(sim.store.count)
	sim.grid.set_cell(11, 10, GridRef.FOOD, 1.0)
	for s in 40:
		sim.step(sim.dt)
	sim.grid.consume(11, 10, 99.0)
	sim.store.px[id] = 20.5
	sim.store.py[id] = 20.5
	var target: int = sim.grid.index(16, 14)
	sim.memory.remember_place(id, target, GridRef.FOOD, 1.0, sim.day())
	sim.store.food_level[id] = 0.25
	sim.store.commitment[id] = 0.0
	sim.store.verb[id] = StoreRef.Verb.WANDER
	sim.inspect_id = id
	print("id %d age %.3f stage %d scale %.2f speedfactor %.3f dt %.4f" % [
		id, sim.store.age_days[id], int(sim.store.stage[id]), sim.store.body_scale[id],
		GenomeRef.speed_factor(sim.store, id), sim.dt,
	])
	print("target cell %d amount %.3f material %d" % [target, sim.grid.amount[target], int(sim.grid.material[target])])
	var changes_before: int = sim.verb_changes
	for s in 45:
		sim.step(sim.dt)
	var dx: float = sim.store.px[id] - 16.5
	var dy: float = sim.store.py[id] - 14.5
	print("distance 7.21 -> %.2f cells; verb changes in 45 ticks %d; move_to picks %d" % [
		sqrt(dx * dx + dy * dy), sim.verb_changes - changes_before,
		int(sim.action_counts[StoreRef.Verb.MOVE_TO]),
	])
	quit(0)
