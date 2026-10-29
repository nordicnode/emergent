extends SceneTree

## Temporary Phase 2 diagnostic: why does the population decline?
##   godot --headless --path . --script res://tools/diag_demography.gd -- --seed=101 --days=12
##
## One line per simulated day: age structure, births and deaths, and a census of
## why living creatures fail the reproduction gate. The gate terms are the same
## ones sim.gd uses; this tool only reports them.

const ParamsRef := preload("res://sim/params.gd")
const SimRef := preload("res://sim/sim.gd")
const GenomeRef := preload("res://sim/genome.gd")
const StoreRef := preload("res://sim/creature_store.gd")
const GridRef := preload("res://sim/grid.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := int(_arg(args, "--seed=", "101"))
	var days := float(_arg(args, "--days=", "12"))
	var step_days := float(_arg(args, "--sample=", "0.5"))
	var params = ParamsRef.load_default()
	for arg in args:
		if arg.begins_with("--param="):
			var spec := arg.substr("--param=".length())
			var equals := spec.find("=")
			var path := spec.substr(0, equals).split(".")
			if equals > 0 and path.size() == 2:
				var value := spec.substr(equals + 1)
				(params.data as Dictionary)[path[0]][path[1]] = float(value) if value.is_valid_float() else value
	var sim = SimRef.new(params, seed_value)
	sim.generate_world()
	sim.spawn_founders()
	var steps := int(round(days * sim.day_seconds / sim.dt))
	var sample_every := maxi(1, int(round(step_days * sim.day_seconds / sim.dt)))
	var day_every := maxi(1, int(round(sim.day_seconds / sim.dt)))
	var gate_food := params.f("repro", "gate_food", 0.55)
	var gate_water := params.f("repro", "gate_water", 0.55)
	var gate_energy := params.f("repro", "gate_energy", 0.55)
	var gate_health := params.f("repro", "gate_health", 0.70)
	var search := params.f("repro", "search_radius_cells", 20.0)
	var min_distance := params.f("repro", "min_genetic_distance", 0.04)
	var births_mark := 0
	var deaths_mark := 0
	print("=== demography: seed %d, %.1f days ===" % [seed_value, days])
	for s in steps:
		sim.step(sim.dt)
		if (s + 1) % sample_every != 0 and s != steps - 1:
			continue
		var m: Dictionary = sim.metrics()
		var gate := _gate_census(sim, gate_food, gate_water, gate_energy, gate_health, search, min_distance)
		var supply := _food_supply(sim)
		var access := _food_access(sim)
		print("day %5.2f pop %3d (c %2d a %2d o %2d) births %2d deaths %2d | mean health %.2f food %.2f water %.2f energy %.2f | water %4d cells, food %4d cells %.0f mass, %3d edible, nut %.2f tox %.2f | gate ready %2d no-mate %2d | fail: child %2d cool %2d health %2d food %2d water %2d energy %2d | age mean %.2f max %.2f" % [
			sim.day(), int(m["alive"]), int(m["children"]), int(m["adults"]), int(m["old"]),
			int(m["births"]) - births_mark, int(m["deaths"]) - deaths_mark,
			float(m["mean_health"]), float(m["mean_food"]), float(m["mean_water"]), float(m["mean_energy"]),
			sim.grid.water_cell_count(), sim.grid.food_cell_count(), float(supply["mass"]), int(supply["edible"]),
			float(supply["nutrition"]), float(supply["toxicity"]),
			int(gate["ready"]), int(gate["no_mate"]),
			int(gate["child"]), int(gate["cooldown"]), int(gate["health"]), int(gate["food"]),
			int(gate["water"]), int(gate["energy"]), float(gate["mean_age"]), float(gate["max_age"]),
		])
		print("        access: nearest food mean %.1f max %.1f cells | hungry(<0.10) %d full(>0.85) %d | nearest water mean %.1f" % [
			float(access["food_mean"]), float(access["food_max"]), int(access["hungry"]), int(access["full"]),
			float(access["water_mean"]),
		])
		var mix: Dictionary = m["action_mix"]
		var shares: Array = []
		for key in mix:
			shares.append([String(key), float(mix[key])])
		shares.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
		var top := ""
		for k in mini(6, shares.size()):
			top += " %s %.0f%%" % [String(shares[k][0]), float(shares[k][1]) * 100.0]
		print("        mix:%s | flee starts %d, flee decisions %d, disputes %d, shares %d, harms %d" % [
			top, int(m["flee_starts"]), int(m["flee_actions"]), int(m["food_taken_events"]),
			int(m["share_events"]), int(m["harm_events"]),
		])
		births_mark = int(m["births"])
		deaths_mark = int(m["deaths"])
		if (s + 1) % day_every == 0:
			var causes := "starved %d dehydrated %d both %d poison %d old %d harm %d" % [
				int(m["starved"]), int(m["dehydrated"]), int(m["starved_and_dehydrated"]),
				int(m["poisoned"]), int(m["aged"]), int(m["harmed"]),
			]
			print("        causes: %s" % causes)
		if int(m["alive"]) == 0:
			print("extinct at day %.2f" % sim.day())
			break
	quit(0)


## What the food supply actually is: cell count says nothing about how much can
## be eaten, because a grazed cell keeps a living trace and stays counted.
func _food_supply(sim) -> Dictionary:
	var mass := 0.0
	var nutrition := 0.0
	var toxicity := 0.0
	var edible := 0
	var cells := 0
	for i in sim.grid.food_cell_snapshot():
		if int(sim.grid.material[i]) != GridRef.FOOD:
			continue
		cells += 1
		mass += float(sim.grid.amount[i])
		nutrition += float(sim.grid.nutrition[i])
		toxicity += float(sim.grid.toxicity[i])
		if float(sim.grid.amount[i]) >= 0.08:
			edible += 1
	var denom := float(maxi(cells, 1))
	return {"mass": mass, "edible": edible, "nutrition": nutrition / denom, "toxicity": toxicity / denom}


## Distance from each living creature to the nearest food and water cell, by a
## multi-source breadth-first sweep, plus how its own food level is distributed.
## Cell counts and totals cannot tell local depletion from abundance; this can.
func _food_access(sim) -> Dictionary:
	var food := _distance_field(sim, GridRef.FOOD)
	var water := _distance_field(sim, GridRef.WATER)
	var food_sum := 0.0
	var water_sum := 0.0
	var food_max := 0.0
	var alive := 0
	var hungry := 0
	var full := 0
	for i in sim.store.count:
		if int(sim.store.alive[i]) == 0:
			continue
		alive += 1
		var x: int = clampi(int(floor(sim.store.px[i])), 0, sim.grid.width - 1)
		var y: int = clampi(int(floor(sim.store.py[i])), 0, sim.grid.height - 1)
		var d := float(food[y * sim.grid.width + x])
		var w := float(water[y * sim.grid.width + x])
		food_sum += d
		water_sum += w
		food_max = maxf(food_max, d)
		var level := float(sim.store.food_level[i])
		if level < 0.10:
			hungry += 1
		elif level > 0.85:
			full += 1
	return {
		"food_mean": food_sum / float(maxi(alive, 1)),
		"food_max": food_max,
		"water_mean": water_sum / float(maxi(alive, 1)),
		"hungry": hungry,
		"full": full,
	}


func _distance_field(sim, material: int) -> PackedInt32Array:
	var w: int = sim.grid.width
	var h: int = sim.grid.height
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(-1)
	var queue := PackedInt32Array()
	var cells: PackedInt32Array = sim.grid.water_cell_snapshot() if material == GridRef.WATER else sim.grid.food_cell_snapshot()
	for i in cells:
		if int(sim.grid.material[i]) != material:
			continue
		dist[i] = 0
		queue.append(i)
	var head := 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var d: int = dist[i] + 1
		var x: int = i % w
		var y: int = i / w
		for k in 4:
			var nx: int = x + (1 if k == 0 else (-1 if k == 1 else 0))
			var ny: int = y + (1 if k == 2 else (-1 if k == 3 else 0))
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var j: int = ny * w + nx
			if dist[j] >= 0:
				continue
			dist[j] = d
			queue.append(j)
	return dist


## Counts why each living creature is not breeding. The first failing term wins,
## in the gate's own order, so the numbers add up to the living population.
func _gate_census(sim, gate_food: float, gate_water: float, gate_energy: float, gate_health: float, search: float, min_distance: float) -> Dictionary:
	var out := {"child": 0, "cooldown": 0, "health": 0, "food": 0, "water": 0, "energy": 0, "ready": 0, "no_mate": 0}
	var ages := 0.0
	var age_max := 0.0
	var alive := 0
	for i in sim.store.count:
		if int(sim.store.alive[i]) == 0:
			continue
		alive += 1
		ages += float(sim.store.age_days[i])
		age_max = maxf(age_max, float(sim.store.age_days[i]))
		if int(sim.store.stage[i]) == StoreRef.CHILD:
			out["child"] += 1
			continue
		if float(sim.store.cooldown_days[i]) > 0.0:
			out["cooldown"] += 1
			continue
		if float(sim.store.health[i]) < gate_health:
			out["health"] += 1
			continue
		var food_need: float = minf(gate_food, sim.store.body_value(i, GenomeRef.F_HUNGER_SET) * 0.90)
		var water_need: float = minf(gate_water, sim.store.body_value(i, GenomeRef.F_THIRST_SET) * 0.90)
		var rest_need: float = minf(gate_energy, sim.store.body_value(i, GenomeRef.F_REST_SET) * 0.90)
		if float(sim.store.food_level[i]) < food_need:
			out["food"] += 1
			continue
		if float(sim.store.water_level[i]) < water_need:
			out["water"] += 1
			continue
		if float(sim.store.energy_level[i]) < rest_need:
			out["energy"] += 1
			continue
		out["ready"] += 1
		var mate: Array = sim._nearest_mate(i, search, min_distance, gate_food, gate_water, gate_energy, gate_health)
		if int(mate[0]) < 0:
			out["no_mate"] += 1
	out["mean_age"] = ages / float(maxi(alive, 1))
	out["max_age"] = age_max
	return out


func _arg(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for arg in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback
