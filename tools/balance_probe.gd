extends SceneTree

## Temporary Phase 2 balance probe:
##   godot --headless --path . --script res://tools/balance_probe.gd -- --seed=202 --days=5

const ParamsRef := preload("res://sim/params.gd")
const SimRef := preload("res://sim/sim.gd")
const GridRef := preload("res://sim/grid.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := int(_arg(args, "--seed=", "202"))
	var days := float(_arg(args, "--days=", "5"))
	var params = ParamsRef.load_default()
	var nearby := int(_arg(args, "--nearby=", "0"))
	var patches := int(_arg(args, "--patches=", "0"))
	var ponds := int(_arg(args, "--ponds=", "0"))
	if nearby > 0:
		params.data["world_gen"]["nearby_food_patches"] = nearby
	if patches > 0:
		params.data["world_gen"]["food_patches"] = patches
	if ponds > 0:
		params.data["world_gen"]["ponds"] = ponds
	var energy_decay := float(_arg(args, "--energy-decay=", "0"))
	var energy_move := float(_arg(args, "--energy-move=", "0"))
	var rest_recovery := float(_arg(args, "--rest-recovery=", "0"))
	if energy_decay > 0.0:
		params.data["needs"]["energy_decay_per_day"] = energy_decay
	if energy_move > 0.0:
		params.data["needs"]["energy_movement_mult"] = energy_move
	if rest_recovery > 0.0:
		params.data["needs"]["energy_rest_recovery_per_day"] = rest_recovery
	var sim = SimRef.new(params, seed_value)
	sim.generate_world()
	sim.spawn_founders()
	var steps := int(round(days * sim.day_seconds / sim.dt))
	var every := maxi(1, int(round(0.25 * sim.day_seconds / sim.dt)))
	var t0 := Time.get_ticks_usec()
	for s in steps:
		sim.step(sim.dt)
		if (s + 1) % every == 0 or s == steps - 1:
			print("day %.2f pop %d  food %.2f (%d cells)  water %.1f (%d cells)  mean food %.2f water %.2f energy %.2f  births %d deaths %d" % [
				sim.day(), sim.alive_count(), _mass(sim, GridRef.FOOD), sim.grid.food_cell_count(),
				_mass(sim, GridRef.WATER), sim.grid.water_cell_count(),
				float(sim.metrics()["mean_food"]), float(sim.metrics()["mean_water"]), float(sim.metrics()["mean_energy"]),
				int(sim.metrics()["births"]), int(sim.metrics()["deaths"]),
			])
	var wall := float(Time.get_ticks_usec() - t0) / 1000000.0
	print("wall %.1f s, %.2f ms/step, step %s" % [wall, float(sim.metrics()["mean_step_ms"]), str(sim.metrics()["action_mix"])])
	quit(0)


func _mass(sim, mat: int) -> float:
	var total := 0.0
	var cells: PackedInt32Array = sim.grid.food_cell_snapshot() if mat == GridRef.FOOD else sim.grid.water_cell_snapshot()
	for i in cells:
		if int(sim.grid.material[i]) == mat:
			total += float(sim.grid.amount[i])
	return total


func _arg(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for arg in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback
