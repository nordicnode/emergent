extends SceneTree

## Phase 3 staggering probe: same-seed A/B for decision cadence.
##
##   godot --headless --path . --script res://tools/stagger_probe.gd -- --days=3 --seed=101 --every=3
##
## The register keeps decision_every_ticks = 1 (unstaggered). This tool
## overrides it in memory only, so a staggered run never changes the
## shipped register, and the comparison is the same seed either way.

const ParamsRef := preload("res://sim/params.gd")
const SimRef := preload("res://sim/sim.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var days := float(_arg(args, "--days=", "3.0"))
	var seed_value := int(_arg(args, "--seed=", "101"))
	var every := int(_arg(args, "--every=", "3"))
	var params = ParamsRef.load_default()
	var brain: Dictionary = params.data.get("brain", {})
	brain["decision_every_ticks"] = every
	params.data["brain"] = brain
	var sim = SimRef.new(params, seed_value)
	sim.generate_world()
	sim.spawn_founders()
	var steps := int(round(days * sim.day_seconds / sim.dt))
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
	var wall := float(Time.get_ticks_usec() - t0) / 1000000.0
	var m: Dictionary = sim.metrics()
	print("stagger_probe: seed %d days %.2f every %d | alive %d births %d deaths %d diversity %.3f" % [
		seed_value, days, every, int(m["alive"]), int(m["births"]), int(m["deaths"]), float(m["genetic_diversity"]),
	])
	print("stagger_probe: decisions %d over %d steps = %.2f per tick (unstaggered would be ~1 per alive creature per tick)" % [
		int(sim.decisions_made), steps, float(sim.decisions_made) / float(maxi(steps, 1)),
	])
	print("stagger_probe: step %.2f ms = mat %.2f + needs %.2f + decide %.2f + exec %.2f | wall %.1f s" % [
		step / float(maxi(steps, 1)), mat / float(maxi(steps, 1)), needs / float(maxi(steps, 1)),
		decide / float(maxi(steps, 1)), execute / float(maxi(steps, 1)), wall,
	])
	quit(0)


func _arg(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for arg in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback
