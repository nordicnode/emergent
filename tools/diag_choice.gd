extends SceneTree

## Temporary Phase 2 diagnostic: what does a starving creature choose?
##   godot --headless --path . --script res://tools/diag_choice.gd -- --seed=202 --days=1

const ParamsRef := preload("res://sim/params.gd")
const SimRef := preload("res://sim/sim.gd")
const BrainRef := preload("res://sim/brain.gd")
const GridRef := preload("res://sim/grid.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := int(_arg(args, "--seed=", "202"))
	var days := float(_arg(args, "--days=", "1"))
	var params = ParamsRef.load_default()
	var sim = SimRef.new(params, seed_value)
	sim.generate_world()
	sim.spawn_founders()
	var steps := int(round(days * sim.day_seconds / sim.dt))
	var watched := -1
	var next_sample: float = 0.35 * sim.day_seconds
	var asked := 0
	for s in steps:
		sim.step(sim.dt)
		if watched < 0 or int(sim.store.alive[watched]) == 0:
			watched = _hungriest(sim)
			sim.inspect_id = watched
			if watched < 0:
				print("no creature alive at day %.2f" % sim.day())
				break
		if sim.time >= next_sample:
			next_sample += 0.15 * sim.day_seconds
			_report(sim, watched, params)
			asked += 1
			if asked >= 7:
				break
	quit(0)


func _hungriest(sim) -> int:
	var best := -1
	var low := 2.0
	for i in sim.store.count:
		if int(sim.store.alive[i]) == 0:
			continue
		if float(sim.store.food_level[i]) < low:
			low = float(sim.store.food_level[i])
			best = i
	return best


func _report(sim, id: int, params) -> void:
	var x := float(sim.store.px[id])
	var y := float(sim.store.py[id])
	var food := float(sim.store.food_level[id])
	var water := float(sim.store.water_level[id])
	var energy := float(sim.store.energy_level[id])
	var hunger_u: float = pow(clampf(1.0 - food, 0.0, 1.0), params.f("needs", "hunger_curve_exp", 2.2))
	var thirst_u: float = pow(clampf(1.0 - water, 0.0, 1.0), params.f("needs", "thirst_curve_exp", 2.6))
	var energy_u: float = pow(clampf(1.0 - energy, 0.0, 1.0), params.f("needs", "energy_curve_exp", 1.8))
	var rest_score: float = params.f("brain", "rest_weight", 0.9) * maxf(energy_u, 0.0) * (1.0 - 0.8 * maxf(hunger_u, thirst_u))
	var perceived: Dictionary = BrainRef._find_perceived(sim.grid, x, y, GridRef.FOOD, params.f("perception", "sensory_radius_cells", 18.0))
	var adjacent := 0
	var cx := int(floor(x))
	var cy := int(floor(y))
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var i: int = sim.grid.index(cx + ox, cy + oy)
			if int(sim.grid.material[i]) == GridRef.FOOD and float(sim.grid.amount[i]) > sim.grid.food_min_amount:
				adjacent += 1
	print("day %.2f #%d %s | food %.2f water %.2f energy %.2f | u hunger %.2f thirst %.2f energy %.2f | adj food %d perceived dist %.1f value %.2f | rest %.2f" % [
		sim.day(), id, sim.store.verb_name(int(sim.store.verb[id])), food, water, energy,
		hunger_u, thirst_u, energy_u, adjacent, float(perceived["dist"]), float(perceived["value"]), rest_score,
	])
	var scores: Array = sim.last_inspection.duplicate()
	scores.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	for k in mini(4, scores.size()):
		var c: Dictionary = scores[k]
		var parts := ""
		for key in (c.get("parts", {}) as Dictionary).keys():
			parts += "%s=%.2f " % [key, float(c["parts"][key])]
		print("   %-12s %.2f  %s" % [String(c["label"]), float(c["score"]), parts])


func _arg(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for arg in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback
