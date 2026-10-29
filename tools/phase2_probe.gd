extends SceneTree

## Temporary Phase 2 diagnostic. Prints population and phase timings so the soak
## budget is measured instead of guessed:
##   godot --headless --path . --script res://tools/phase2_probe.gd -- --days=1 --seed=101

const ParamsRef := preload("res://sim/params.gd")
const SimRef := preload("res://sim/sim.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var days := float(_arg(args, "--days=", "1.0"))
	var seed_value := int(_arg(args, "--seed=", "101"))
	var params = ParamsRef.load_default()
	var sim = SimRef.new(params, seed_value)
	sim.generate_world()
	sim.spawn_founders()
	var steps := int(round(days * sim.day_seconds / sim.dt))
	var sample := maxi(1, int(round(0.25 * sim.day_seconds / sim.dt)))
	var mat := 0.0
	var needs := 0.0
	var decide := 0.0
	var execute := 0.0
	var step := 0.0
	var t0 := Time.get_ticks_usec()
	for s in steps:
		sim.step(sim.dt)
		mat += sim.tick.last_material_ms
		needs += sim.tick.last_needs_ms
		decide += sim.tick.last_decide_ms
		execute += sim.tick.last_execute_ms
		step += sim.tick.last_step_ms
		if (s + 1) % sample == 0 or s == steps - 1:
			var n := float(s + 1)
			print("day %.2f pop %d | step %.2f ms = mat %.2f + needs %.2f + decide %.2f + exec %.2f | food cells %d" % [
				sim.day(), sim.alive_count(), step / n, mat / n, needs / n, decide / n, execute / n,
				sim.grid.food_cell_count(),
			])
	var wall := float(Time.get_ticks_usec() - t0) / 1000000.0
	print("wall %.1f s for %.2f simulated days, %d steps, %.2f ms/step" % [wall, sim.day(), steps, step / float(maxi(steps, 1))])
	print("births %d deaths %d food cells %d water cells %d" % [int(sim.metrics()["births"]), int(sim.metrics()["deaths"]), sim.grid.food_cell_count(), sim.grid.water_cell_count()])
	quit(0)


func _arg(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for arg in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback
