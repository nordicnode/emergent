extends SceneTree

## Temporary Phase 2 diagnostic. Answers one question: when creatures starve,
## is the failure supply, spoilage, distance, or exhaustion?
##   godot --headless --path . --script res://tools/diag_access.gd -- --seed=202 --days=2

const ParamsRef := preload("res://sim/params.gd")
const SimRef := preload("res://sim/sim.gd")
const GridRef := preload("res://sim/grid.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := int(_arg(args, "--seed=", "202"))
	var days := float(_arg(args, "--days=", "2"))
	var params = ParamsRef.load_default()
	var sim = SimRef.new(params, seed_value)
	sim.generate_world()
	sim.spawn_founders()
	var steps := int(round(days * sim.day_seconds / sim.dt))
	var every := maxi(1, int(round(0.5 * sim.day_seconds / sim.dt)))
	var sense := params.f("perception", "sensory_radius_cells", 18.0)
	for s in steps:
		sim.step(sim.dt)
		if (s + 1) % every == 0 or s == steps - 1:
			_report(sim, sense)
	quit(0)


func _report(sim, sense: float) -> void:
	var i_amt := 0.0
	var i_nut := 0.0
	var good: Array[int] = []
	for i in sim.grid.food_cell_snapshot():
		if int(sim.grid.material[i]) != GridRef.FOOD:
			continue
		var amt := float(sim.grid.amount[i])
		i_amt += amt
		i_nut += amt * float(sim.grid.nutrition[i])
		if float(sim.grid.nutrition[i]) >= 0.3 and amt > 0.02:
			good.append(i)
	var hungry := 0
	var hungry_near := 0
	var dists: Array[float] = []
	var xs: Array[float] = []
	var ys: Array[float] = []
	var sum_energy := 0.0
	var examples: Array[String] = []
	for c in sim.store.count:
		if int(sim.store.alive[c]) == 0:
			continue
		xs.append(float(sim.store.px[c]))
		ys.append(float(sim.store.py[c]))
		sum_energy += float(sim.store.energy_level[c])
		if float(sim.store.food_level[c]) >= 0.4:
			continue
		hungry += 1
		var best := 1e9
		for i in good:
			var d := Vector2(sim.store.px[c] - float(i % sim.grid.width), sim.store.py[c] - float(i / sim.grid.width)).length()
			if d < best:
				best = d
		dists.append(best)
		if best <= sense:
			hungry_near += 1
		if examples.size() < 4:
			examples.append("#%d food %.2f energy %.2f water %.2f health %.2f verb %d dist %.0f" % [
				c, sim.store.food_level[c], sim.store.energy_level[c], sim.store.water_level[c],
				sim.store.health[c], int(sim.store.verb[c]), best,
			])
	dists.sort()
	var mean_d := 0.0
	for d in dists:
		mean_d += d
	if not dists.is_empty():
		mean_d /= float(dists.size())
	var spread := 0.0
	if xs.size() > 1:
		var mx := 0.0
		var my := 0.0
		for k in xs.size():
			mx += xs[k]
			my += ys[k]
		mx /= float(xs.size())
		my /= float(ys.size())
		for k in xs.size():
			spread += (xs[k] - mx) * (xs[k] - mx) + (ys[k] - my) * (ys[k] - my)
		spread = sqrt(spread / float(xs.size()))
	var alive: int = sim.alive_count()
	print("day %.1f pop %d | food mass %.1f nutrition %.2f cells %d | hungry %d near %d median %.0f mean %.0f | mean energy %.2f | spread %.0f | water %d" % [
		sim.day(), alive, i_amt, (i_nut / i_amt) if i_amt > 0.0 else 0.0, good.size(),
		hungry, hungry_near, dists[dists.size() / 2] if not dists.is_empty() else -1.0, mean_d,
		(sum_energy / float(alive)) if alive > 0 else 0.0, spread, sim.grid.water_cell_count(),
	])
	for line in examples:
		print("   ", line)


func _arg(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for arg in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback
