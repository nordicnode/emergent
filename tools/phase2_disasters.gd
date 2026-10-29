extends SceneTree

## The plan's three Phase 2 disaster scenarios, each run through the real fixed
## tick with placement as the only script:
##
##   drought  - one pond, no water placed, ten days; water is left to evaporate.
##   feast    - heavy food placement for three days, then none for ten.
##   flood    - water placed onto an established hardened-sand structure.
##
## These are observational runs, not a second simulation. Their overrides are
## starting conditions and scenario parameters, recorded in the output.

const ParamsRef := preload("res://sim/params.gd")
const SimRef := preload("res://sim/sim.gd")
const GridRef := preload("res://sim/grid.gd")
const StoreRef := preload("res://sim/creature_store.gd")

const DAY_SECONDS := 480.0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scenario := _arg(args, "--scenario=", "all")
	var days := float(_arg(args, "--days=", "10"))
	print("=== Phase 2 disaster scenarios (%s) ===" % scenario)
	if scenario == "all" or scenario == "drought":
		_run_drought(days)
	if scenario == "all" or scenario == "feast":
		_run_feast(days)
	if scenario == "all" or scenario == "flood":
		# The flood observation is shorter than the drought and famine: one day
		# is enough for the structure to soften and residents to move, without
		# turning the scenario into a supply test on an artificially tiny map.
		_run_flood(1.0)
	quit(0)


func _base_params() -> SimParams:
	return ParamsRef.load_default()


func _small_world(params, w: int, h: int, chunk: int = 64) -> void:
	params.data["world"]["width"] = w
	params.data["world"]["height"] = h
	params.data["world"]["chunk_size"] = chunk


func _run_drought(days: float) -> void:
	var params := _base_params()
	_small_world(params, 256, 192, 64)
	params.data["world_gen"]["ponds"] = 1
	params.data["world_gen"]["food_patches"] = 8
	params.data["world_gen"]["nearby_food_patches"] = 2
	params.data["spawn"]["founders"] = 14
	# The scenario's dry season: the one pond evaporates at a rate that reaches
	# empty within the ten-day window. It changes only a world parameter, never
	# a creature rule.
	params.data["materials"]["water_evaporate_per_day"] = 0.20
	var sim = SimRef.new(params, 9101)
	sim.generate_world()
	sim.spawn_founders()
	var start_water: int = int(sim.grid.water_cell_count())
	var min_water: int = start_water
	var population: Array = []
	var curve_water: Array = []
	var steps := int(days * DAY_SECONDS / sim.dt)
	var every := maxi(1, int(steps / 10))
	for s in steps:
		sim.step(sim.dt)
		if s % every == 0 or s == steps - 1:
			population.append(sim.alive_count())
			curve_water.append(sim.grid.water_cell_count())
			min_water = mini(min_water, sim.grid.water_cell_count())
	var m: Dictionary = sim.metrics()
	print("")
	print("--- DRYOUT / DROUGHT: one pond, no water placed, %.1f days ---" % days)
	print("water cells %d → %d (min %d); population %s" % [start_water, sim.grid.water_cell_count(), min_water, str(population)])
	print("water over time: %s" % str(curve_water))
	print("alive %d · births %d · deaths %d · dehydrated %d · starved %d · both %d" % [
		int(m["alive"]), int(m["births"]), int(m["deaths"]), int(m["dehydrated"]), int(m["starved"]), int(m["starved_and_dehydrated"]),
	])
	print("mean water %.2f · mean food %.2f · recall %d · food disputes %d · flee %d" % [
		float(m["mean_water"]), float(m["mean_food"]), int(m["recall_actions"]), int(m["food_taken_events"]), int(m["flee_actions"]),
	])
	print("spread %.0f cells · lineages living %d · extinct %d" % [
		_spread(sim), int(m["lineages"]), int(m["lineages_total"]) - int(m["lineages"]),
	])


func _run_feast(days: float) -> void:
	var params := _base_params()
	_small_world(params, 320, 240, 64)
	params.data["world_gen"]["food_patches"] = 3
	params.data["world_gen"]["nearby_food_patches"] = 0
	params.data["spawn"]["founders"] = 14
	# The famine half needs a world that does not quietly refill while the
	# player is not placing food. Regrowth is a scenario setting here, not a
	# creature rule.
	params.data["materials"]["food_regrow_per_day"] = 0.0
	var sim = SimRef.new(params, 9102)
	sim.generate_world()
	sim.spawn_founders()
	var center := _founder_centroid(sim)
	var steps := int(days * DAY_SECONDS / sim.dt)
	var feast_end := int(3.0 * DAY_SECONDS / sim.dt)
	var famine_start := int(3.0 * DAY_SECONDS / sim.dt)
	var last_place := -999999
	var placed := 0
	var storer_ids: Array = []
	var storer_birth: Dictionary = {}
	var nonstorer_ids: Array = []
	var nonstorer_birth: Dictionary = {}
	var population: Array = []
	var sample_every := maxi(1, int(steps / 12))
	var famine_alive := 0
	for s in steps:
		# Feast: a heavy brush of food every half simulated day for three days.
		if s < feast_end and s - last_place >= int(0.5 * DAY_SECONDS / sim.dt):
			last_place = s
			var cx := int(center.x + sim.rng.randf_range(-10.0, 10.0))
			var cy := int(center.y + sim.rng.randf_range(-10.0, 10.0))
			placed += sim.apply_brush(GridRef.FOOD, cx, cy, 1, 4.0)
		if s == famine_start:
			for i in sim.store.count:
				if sim.store.alive[i] == 0:
					continue
				if int(sim.store.piled_food[i]) > 0:
					storer_ids.append(i)
					storer_birth[i] = float(sim.store.birth_time[i])
				else:
					nonstorer_ids.append(i)
					nonstorer_birth[i] = float(sim.store.birth_time[i])
			famine_alive = storer_ids.size() + nonstorer_ids.size()
		sim.step(sim.dt)
		if s % sample_every == 0 or s == steps - 1:
			population.append(sim.alive_count())
	var m: Dictionary = sim.metrics()
	var storers_alive := _survivors(sim, storer_ids, storer_birth)
	var nonstorers_alive := _survivors(sim, nonstorer_ids, nonstorer_birth)
	print("")
	print("--- FEAST THEN FAMINE: heavy food 3 days, none for %.1f days ---" % maxf(days - 3.0, 0.0))
	print("placed %d food cells · population %s" % [placed, str(population)])
	print("at famine start %d alive: %d storers, %d non-storers" % [famine_alive, storer_ids.size(), nonstorer_ids.size()])
	print("survived famine: storers %d/%d (%.0f%%), non-storers %d/%d (%.0f%%)" % [
		storers_alive, storer_ids.size(), 100.0 * float(storers_alive) / float(maxi(storer_ids.size(), 1)),
		nonstorers_alive, nonstorer_ids.size(), 100.0 * float(nonstorers_alive) / float(maxi(nonstorer_ids.size(), 1)),
	])
	print("alive %d · births %d · deaths %d · old age %d · starvation %d · stores: %d food loads piled, %d caches used" % [
		int(m["alive"]), int(m["births"]), int(m["deaths"]), int(m["aged"]), int(m["starved"]),
		int(m["loads_piled_food"]), int(m["storing_events"]),
	])
	print("pickup/pile actions %d/%d · shares %d · food disputes %d" % [
		int(m["pickup_actions"]), int(m["pile_actions"]), int(m["share_events"]), int(m["food_taken_events"]),
	])


func _run_flood(days: float) -> void:
	var params := _base_params()
	_small_world(params, 64, 64, 16)
	params.data["world_gen"]["ponds"] = 0
	params.data["world_gen"]["dunes"] = 0
	params.data["world_gen"]["food_patches"] = 0
	params.data["world_gen"]["nearby_food_patches"] = 0
	params.data["materials"]["food_regrow_per_day"] = 0.0
	var sim = SimRef.new(params, 9103)
	sim.generate_world()
	# An established structure: five by five hard sand, compacted and dry.
	for y in range(28, 33):
		for x in range(28, 33):
			sim.grid.set_cell(x, y, GridRef.SAND, 1.0)
			var i: int = int(sim.grid.index(x, y))
			sim.grid.hardness[i] = 0.90
			sim.grid.cohesion[i] = 0.90
			sim.grid.compaction[i] = 0.80
			sim.grid.wet_history[i] = 0.70
			sim.grid.wetness[i] = 0.0
	# Residents resting on the structure, with a meal and a spring nearby so
	# leaving is a choice rather than the only option.
	var ids: Array = []
	for k in 4:
		var id: int = sim.store.spawn(30.4 + 0.3 * float(k), 30.4, 0.5, 1.0, 1.0, 0.12)
		sim.store.stage[id] = StoreRef.ADULT
		sim.store.age_days[id] = 0.5
		sim.store.body_scale[id] = 1.0
		sim.store.energy_level[id] = 0.12
		sim.store.comfort_level[id] = 0.30
		sim.store.safety_level[id] = 1.0
		ids.append(id)
	# Food and water sit outside the flood brush, so the residents have a real
	# choice between staying and leaving rather than dying of thirst beside a
	# structure the scenario has just soaked.
	for fy in range(29, 32):
		for fx in range(37, 40):
			sim.grid.set_cell(fx, fy, GridRef.FOOD, 1.0)
	# A hard pan under the spring keeps a little water on the map long enough
	# to be found; the scenario is about the structure, not a leaking pond bed.
	for wy in range(37, 42):
		for wx in range(34, 42):
			sim.grid.set_cell(wx, wy, GridRef.SAND, 1.0)
			var wi: int = sim.grid.index(wx, wy)
			sim.grid.hardness[wi] = 0.90
			sim.grid.cohesion[wi] = 0.90
	for wy in range(34, 38):
		for wx in range(35, 41):
			sim.grid.set_cell(wx, wy, GridRef.WATER, 1.0)
	sim.memory.ensure(sim.store.count)
	sim.opinion.ensure(sim.store.count)
	sim.neighbors.rebuild(sim.store)
	for _s in int(0.25 * DAY_SECONDS / sim.dt):
		sim.step(sim.dt)
	var hard_before := _average_hardness(sim, 28, 28, 5, 5)
	var resting_before := _resting_on(sim, 28, 28, 5, 5)
	var start_x := 0.0
	var start_y := 0.0
	for id in ids:
		start_x += sim.store.px[id]
		start_y += sim.store.py[id]
	start_x /= float(ids.size())
	start_y /= float(ids.size())
	# The player's flood: a heavy water brush on the established structure.
	sim.apply_brush(GridRef.WATER, 30, 30, 3, 4.0)
	for _s in int(days * DAY_SECONDS / sim.dt):
		sim.step(sim.dt)
	var hard_after := _average_hardness(sim, 28, 28, 5, 5)
	var resting_after := _resting_on(sim, 28, 28, 5, 5)
	var moved := 0.0
	var alive := 0
	for id in ids:
		if sim.store.alive[id] == 0:
			continue
		alive += 1
		var dx: float = float(sim.store.px[id]) - start_x
		var dy: float = float(sim.store.py[id]) - start_y
		moved += sqrt(dx * dx + dy * dy)
	moved /= float(maxi(alive, 1))
	print("")
	print("--- FLOOD THE SHELTER: water on an established 5x5 hard structure, %.1f days ---" % days)
	print("hardness %.2f → %.2f · resting on it %d → %d · residents alive %d/%d · mean move %.1f cells" % [
		hard_before, hard_after, resting_before, resting_after, alive, ids.size(), moved,
	])
	var m: Dictionary = sim.metrics()
	print("shelter events %d · hardening events %d · water cells %d" % [
		int(sim.story.shelter_events), int(sim.story.hardening_events), sim.grid.water_cell_count(),
	])
	print("deaths %d (starved %d, dehydrated %d, both %d, old age %d) · mean water %.2f, food %.2f, energy %.2f" % [
		int(m["deaths"]), int(m["starved"]), int(m["dehydrated"]), int(m["starved_and_dehydrated"]), int(m["aged"]),
		float(m["mean_water"]), float(m["mean_food"]), float(m["mean_energy"]),
	])


func _survivors(sim, ids: Array, births: Dictionary) -> int:
	var n := 0
	for id in ids:
		var i := int(id)
		if i < 0 or i >= sim.store.count or sim.store.alive[i] == 0:
			continue
		if absf(float(sim.store.birth_time[i]) - float(births.get(i, -1.0))) <= 0.0001:
			n += 1
	return n


func _average_hardness(sim, x0: int, y0: int, w: int, h: int) -> float:
	var total := 0.0
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			total += float(sim.grid.hardness[sim.grid.index(x, y)])
	return total / float(w * h)


func _resting_on(sim, x0: int, y0: int, w: int, h: int) -> int:
	var n := 0
	for i in sim.store.count:
		if sim.store.alive[i] == 0 or int(sim.store.verb[i]) != StoreRef.Verb.REST:
			continue
		var cx := int(floor(sim.store.px[i]))
		var cy := int(floor(sim.store.py[i]))
		if cx >= x0 and cx < x0 + w and cy >= y0 and cy < y0 + h:
			n += 1
	return n


func _spread(sim) -> float:
	var n := 0
	var sx := 0.0
	var sy := 0.0
	for i in sim.store.count:
		if sim.store.alive[i] == 0:
			continue
		n += 1
		sx += sim.store.px[i]
		sy += sim.store.py[i]
	if n == 0:
		return 0.0
	var cx := sx / float(n)
	var cy := sy / float(n)
	var best := 0.0
	for i in sim.store.count:
		if sim.store.alive[i] == 0:
			continue
		var dx: float = float(sim.store.px[i]) - cx
		var dy: float = float(sim.store.py[i]) - cy
		best = maxf(best, sqrt(dx * dx + dy * dy))
	return best


func _founder_centroid(sim) -> Vector2:
	var n := 0
	var sx := 0.0
	var sy := 0.0
	for i in sim.store.count:
		if sim.store.alive[i] == 0:
			continue
		n += 1
		sx += sim.store.px[i]
		sy += sim.store.py[i]
	if n == 0:
		return Vector2(float(sim.grid.width) * 0.5, float(sim.grid.height) * 0.5)
	return Vector2(sx / float(n), sy / float(n))


func _arg(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for arg in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback
