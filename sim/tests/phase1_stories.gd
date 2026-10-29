extends RefCounted

## The plan's Phase 1 exit criteria as real-tick stories:
##
##   shelter  - a creature's wet sand pile dries hard and it rests there;
##   storing  - a creature returns to a food cache it piled;
##   rivalry  - repeated negative events make a rival the creature acts on.
##
## Each story is paired with a disable-one-system run from story_harness.gd.
## Scenarios place materials and set starting needs; every action and every
## logged outcome is produced by Sim.step.

const SimRef := preload("res://sim/sim.gd")
const ParamsRef := preload("res://sim/params.gd")
const GridRef := preload("res://sim/grid.gd")
const StoreRef := preload("res://sim/creature_store.gd")
const GenomeRef := preload("res://sim/genome.gd")
const HarnessRef := preload("res://sim/tests/story_harness.gd")

var _params = null
var _story_params = null
var _checks := 0
var _failures := 0


func set_params(params) -> void:
	_params = params


func run_all() -> Array:
	print("\n-- phase 1 exit criteria stories --")
	_story_params = _small_world_params()
	_test_shelter()
	_test_storing()
	_test_rivalry()
	print("\nphase 1 stories: %d checks, %d failures" % [_checks, _failures])
	return [_checks, _failures]


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if ok:
		print("  ok    %s" % message)
	else:
		_failures += 1
		print("  FAIL  %s" % message)


func _small_world_params():
	var small = ParamsRef.new()
	small.data = _params.data.duplicate(true)
	# A seeded test world, not a different simulation: the same values in a
	# 64-cell square. It keeps a story's actors within encounter range and makes
	# a hundred real-tick runs cheap enough for the suite.
	small.data["world"]["width"] = 64
	small.data["world"]["height"] = 64
	small.data["world"]["chunk_size"] = 16
	return small


func _steps(days: float, sim) -> int:
	return int(days * float(sim.day_seconds) / sim.dt)


func _flat(sim, x0: int, y0: int, w: int, h: int) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			sim.grid.set_cell(x, y, GridRef.SAND, 1.0)


func _log_text(sim, kind: String, must_contain: String) -> Array:
	var out: Array = []
	for entry in sim.log.entries:
		if String(entry["kind"]) == kind and String(entry["text"]).contains(must_contain):
			out.append(String(entry["text"]))
	return out


## The pair whose remembered events cross the rival label, from the same opinion
## store the brain and the inspector read.
func _rival_pair(sim) -> Array:
	for id in sim.store.count:
		if sim.store.alive[id] == 0:
			continue
		for k in sim.opinion.entry_count(id):
			var record: Dictionary = sim.opinion.entry_at(id, k)
			var other := int(record["other"])
			var value: float = sim.opinion.opinion(sim.store, id, other, sim.day())
			if sim.opinion.label_for(value, int(record["events"])) == "rival":
				return [id, other]
	return []


# --- shelter -------------------------------------------------------------

func _shelter_setup(params):
	var sim = SimRef.new(params, 3101)
	# A sand floor holds the water and food, while the open pocket is where the
	# load lands. With no loose sand in reach, the builder has nothing to pick
	# up after its first load; the pile, not another trip, is what it can do.
	_flat(sim, 16, 16, 28, 28)
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			sim.grid.set_cell(22 + ox, 22 + oy, GridRef.AIR, 0.0)
	sim.grid.set_cell(18, 22, GridRef.WATER, 1.0)
	sim.grid.set_cell(18, 21, GridRef.WATER, 1.0)
	sim.grid.set_cell(18, 23, GridRef.WATER, 1.0)
	for fy in range(20, 24):
		sim.grid.set_cell(19, fy, GridRef.FOOD, 1.0, 1.0)
	var id: int = sim.store.spawn(22.5, 22.5, 0.5, 0.9, 1.0, 0.20)
	# Start with the load in hand: the story is the pile-to-shelter chain, not
	# whether this creature first wins the pick-up score against wandering.
	sim.store.carry_material[id] = GridRef.SAND
	sim.store.carry_amount[id] = 1.2
	sim.store.carry_wetness[id] = 1.0
	sim.store.stage[id] = StoreRef.ADULT
	sim.store.body_scale[id] = 1.0
	sim.store.age_days[id] = 0.5
	sim.store.comfort_level[id] = 0.02
	# A builder phenotype, not a new system: low curiosity keeps it near its
	# work; high conscientiousness weights the same pile verb every creature has.
	sim.store.body[id * GenomeRef.FIELDS + GenomeRef.F_CURIOSITY] = 0.0
	sim.store.body[id * GenomeRef.FIELDS + GenomeRef.F_CONSCIENTIOUSNESS] = 1.0
	# An exhausted neighbour is already asleep on the same open cell while the
	# builder works. A resting creature is what makes the hardened cell a
	# shelter-like place; the builder does not have to be the one who uses it.
	var rester: int = sim.store.spawn(23.5, 22.5, 0.6, 1.0, 1.0, 0.0)
	sim.store.stage[rester] = StoreRef.ADULT
	sim.store.body_scale[rester] = 1.0
	sim.store.age_days[rester] = 0.5
	sim.store.comfort_level[rester] = 1.0
	sim.memory.ensure(sim.store.count)
	sim.opinion.ensure(sim.store.count)
	sim.neighbors.rebuild(sim.store)
	return sim


func _test_shelter() -> void:
	var setup := _shelter_setup
	var sim = SimRef.new(_story_params, 3101)
	var steps := _steps(2.0, sim)
	var base: Dictionary = HarnessRef.run(_story_params, setup, steps)
	var base_sim = base["sim"]
	var hard_lines := _log_text(base_sim, "story", "dried hard")
	var rest_lines := _log_text(base_sim, "story", "rests on hard ground")
	print("  shelter default: %d hard lines, %d rest lines, %d shelter events, %d loads piled sand" % [
		hard_lines.size(), rest_lines.size(), int(base_sim.story.shelter_events), int(base_sim.loads_piled_sand)
	])
	_check(hard_lines.size() >= 1, "shelter story: wet sand actually dries hard in the real tick")
	_check(rest_lines.size() >= 1, "shelter story: a creature rests on the hardened pile")
	_check(int(base_sim.story.shelter_events) >= 1, "shelter story: the causal sequence reaches its resting outcome")
	_check(hard_lines.size() > 0 and rest_lines.size() > 0 and hard_lines[0].contains("Creature"), "shelter story: the log names the builder and the place")
	var shelter_view: Dictionary = base_sim.story.inspector_evidence(base_sim, 0)
	var exposed := false
	for sh in shelter_view.get("shelters", []):
		if int(sh["x"]) >= 16 and int(sh["y"]) >= 16 and int(sh["builder"]) == 0 and int(sh["rester"]) >= 0 and float(sh["hard_day"]) > float(sh["pile_day"]):
			exposed = true
	_check(exposed, "inspector evidence: shelter chain names the place, builder, rester and hardening day")

	var ablated: Dictionary = HarnessRef.run(_story_params, setup, steps, "hardening")
	var off = ablated["sim"]
	print("  shelter hardening off: %d hard lines, %d shelter events, %d loads piled sand" % [
		_log_text(off, "story", "dried hard").size(), int(off.story.shelter_events), int(off.loads_piled_sand)
	])
	_check(_log_text(off, "story", "dried hard").is_empty(), "hardening off: no pile dries hard")
	_check(int(off.story.shelter_events) == 0, "hardening off: the shelter story does not complete")
	_check(int(off.loads_piled_sand) > 0, "hardening off isolates hardening: piling still happens")


# --- storing -------------------------------------------------------------

func _storing_setup(params):
	var sim = SimRef.new(params, 3102)
	_flat(sim, 16, 16, 28, 28)
	# The deposit cell is open ground; no loose sand is close enough to turn the
	# story into a different material.
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			sim.grid.set_cell(22 + ox, 22 + oy, GridRef.AIR, 0.0)
	sim.grid.set_cell(18, 22, GridRef.WATER, 1.0)
	var id: int = sim.store.spawn(22.5, 22.5, 0.5, 0.7, 1.0, 0.5)
	sim.store.carry_material[id] = GridRef.FOOD
	sim.store.carry_amount[id] = 1.2
	sim.store.carry_nutrition[id] = 1.0
	sim.store.stage[id] = StoreRef.ADULT
	sim.store.body_scale[id] = 1.0
	sim.store.age_days[id] = 0.5
	sim.store.comfort_level[id] = 0.02
	sim.store.body[id * GenomeRef.FIELDS + GenomeRef.F_CURIOSITY] = 0.0
	sim.store.body[id * GenomeRef.FIELDS + GenomeRef.F_CONSCIENTIOUSNESS] = 1.0
	sim.memory.ensure(sim.store.count)
	sim.opinion.ensure(sim.store.count)
	sim.neighbors.rebuild(sim.store)
	return sim


func _storing_run(ablate: String = "") -> Dictionary:
	var sim_probe = SimRef.new(_story_params, 3102)
	var steps := _steps(1.5, sim_probe)
	return HarnessRef.run(_story_params, _storing_setup, steps, ablate)


func _test_storing() -> void:
	var base: Dictionary = _storing_run()
	var sim = base["sim"]
	var cache_lines := _log_text(sim, "story", "ate from the food cache")
	print("  storing default: %d cache lines, %d storing events, %d food loads piled, learned pile %.3f" % [
		cache_lines.size(), int(sim.story.storing_events), int(sim.loads_piled_food),
		float(sim.memory.learned(0, StoreRef.Verb.PILE, 0)),
	])
	_check(int(sim.loads_piled_food) >= 1, "storing story: a surplus carrier piles a food cache")
	_check(cache_lines.size() >= 1, "storing story: a creature later eats from that cache (log line present)")
	_check(int(sim.story.storing_events) >= 1, "storing story: the delayed use is counted as an outcome")
	_check(cache_lines.size() > 0 and cache_lines[0].contains("after") and cache_lines[0].contains("hours"), "storing story: the log shows the delay, not just a meal")
	var cache_view: Dictionary = sim.story.inspector_evidence(sim, 0)
	var exposed := false
	for cache in cache_view.get("caches", []):
		if int(cache["builder"]) == 0 and int(cache["eater"]) == 0 and float(cache["hours"]) > 0.0:
			exposed = true
	_check(exposed, "inspector evidence: cache chain names the place, builder, eater and delay")

	var carry_off: Dictionary = _storing_run("carry")
	var no_carry = carry_off["sim"]
	print("  storing carry off: %d cache lines, %d food loads piled" % [
		_log_text(no_carry, "story", "ate from the food cache").size(), int(no_carry.loads_piled_food)
	])
	_check(_log_text(no_carry, "story", "ate from the food cache").is_empty(), "carry off: no cache can be made or used")

	var stress_off: Dictionary = _storing_run("stress")
	var flat = stress_off["sim"]
	var flat_cache := _log_text(flat, "story", "ate from the food cache")
	print("  storing stress off: %d cache lines, %d storing events, %d food loads piled, learned pile %.3f" % [
		flat_cache.size(), int(flat.story.storing_events), int(flat.loads_piled_food),
		float(flat.memory.learned(0, StoreRef.Verb.PILE, 0)),
	])
	_check(int(flat.story.storing_events) <= int(sim.story.storing_events), "stress weighting off: storing is no stronger than the control")
	_check(int(flat.story.storing_events) < int(sim.story.storing_events), "stress weighting off: the cache-use rate falls (%d vs %d)" % [int(flat.story.storing_events), int(sim.story.storing_events)])


# --- rivalry -------------------------------------------------------------

func _rivalry_params():
	var small = ParamsRef.new()
	small.data = _params.data.duplicate(true)
	# An eight-cell seeded world for the rivalry story. The pair still wanders
	# freely; the smaller ground simply lets the same creatures meet again
	# after a meal instead of walking out of each other's lives.
	small.data["world"]["width"] = 8
	small.data["world"]["height"] = 8
	small.data["world"]["chunk_size"] = 8
	return small


func _rivalry_setup(params):
	var sim = SimRef.new(params, 3103)
	_flat(sim, 0, 0, 8, 8)
	# A meagre patch, not a stocked larder: the cell is refilled only to a third
	# of a cell, so it is usually empty and the disputes keep coming instead of
	# stopping after the opening burst.
	sim.grid.set_cell(3, 3, GridRef.FOOD, 0.30, 1.0)
	# A spring a few steps away keeps both alive and nearby between meals; the
	# same disputed cell is what makes their paths cross again.
	for wy in range(3, 6):
		sim.grid.set_cell(5, wy, GridRef.WATER, 1.0)
	# Four hungry creatures at one small patch: the meal is genuinely scarce,
	# so the same pair keeps meeting as competitors instead of settling into
	# comfortable sharing. This is the plan's disputed-meal route to rivalry.
	var ids: Array = [
		sim.store.spawn(3.4, 3.5, 0.5, 0.05, 1.0, 1.0),
		sim.store.spawn(4.2, 3.5, 0.5, 0.05, 1.0, 1.0),
		sim.store.spawn(2.7, 3.2, 0.5, 0.05, 1.0, 1.0),
		sim.store.spawn(4.0, 4.2, 0.5, 0.05, 1.0, 1.0),
	]
	for k in ids.size():
		var id: int = ids[k]
		sim.store.body[id * GenomeRef.FIELDS + GenomeRef.F_CURIOSITY] = 0.0
		# None is aggressive enough to turn a lost bite into an injury: this
		# story is the pure dispute route, and harm has its own checks.
		sim.store.body[id * GenomeRef.FIELDS + GenomeRef.F_AGGRESSION] = 0.0
		sim.store.body[id * GenomeRef.FIELDS + GenomeRef.F_SIZE] = 1.0 - 0.04 * k
		sim.store.body[id * GenomeRef.FIELDS + GenomeRef.F_BOLDNESS] = 0.8
		sim.store.health[id] = 0.55
		sim.store.safety_level[id] = 1.0
	sim.memory.ensure(sim.store.count)
	sim.opinion.ensure(sim.store.count)
	sim.neighbors.rebuild(sim.store)
	return sim


func _rivalry_feed(sim) -> void:
	if sim.grid.amount_at(3, 3) < 0.02:
		sim.grid.set_cell(3, 3, GridRef.FOOD, 0.30, 1.0)
	# The scenario's spring, not a simulation rule: a pond in a small test
	# world must not dry into the sand before the second day.
	for wy in range(3, 6):
		if sim.grid.amount_at(5, wy) < 0.20:
			sim.grid.set_cell(5, wy, GridRef.WATER, 1.0)


func _rivalry_run(ablate: String = "") -> Dictionary:
	var rival_params = _rivalry_params()
	var probe = SimRef.new(rival_params, 3103)
	# The label lands within a sixth of a day; the run continues past it only
	# long enough to observe the rivalry being acted on before scarcity kills.
	var steps := _steps(0.5, probe)
	return HarnessRef.run(rival_params, _rivalry_setup, steps, ablate, _rivalry_feed)


func _test_rivalry() -> void:
	var base: Dictionary = _rivalry_run()
	var sim = base["sim"]
	var rival_lines := _log_text(sim, "social", "as a rival")
	var pair: Array = _rival_pair(sim)
	var fled_lines: Array = []
	if pair.size() == 2:
		fled_lines = _log_text(sim, "safety", "Creature %d fled %d" % [int(pair[0]), int(pair[1])])
	print("  rivalry default: %d rival labels, %d harms, %d disputes, %d rival bonds, %d avoid, %d flee, %d flights from the rival" % [
		rival_lines.size(), int(sim.harm_events), int(sim.food_taken_events), int(sim.metrics()["rival_bonds"]),
		int(sim.action_counts[StoreRef.Verb.AVOID]), int(sim.action_counts[StoreRef.Verb.FLEE]), fled_lines.size(),
	])
	_check(rival_lines.size() >= 1, "rivalry story: repeated negative events cross the rival label in the real tick")
	_check(rival_lines.size() > 0 and rival_lines[0].count("disputed meals") >= 3, "rivalry story: the log names all three incidents behind the label")
	_check(int(sim.metrics()["rival_bonds"]) >= 1, "rivalry story: the label is backed by an opinion bond")
	_check(pair.size() == 2 and fled_lines.size() >= 1, "rivalry story: the victim flees the rival named in the memory (log line present)")
	var chain_exposed := false
	if pair.size() == 2:
		var opinion_view: Dictionary = sim.story.inspector_evidence(sim, int(pair[0]))
		var opinions: Array = opinion_view.get("opinions", [])
		if not opinions.is_empty():
			var top: Dictionary = opinions[0]
			var chain: Array = top.get("chain", [])
			var acted: Dictionary = top.get("acted", {})
			var disputes := 0
			for event in chain:
				if String(event["reason"]) == "disputed meals":
					disputes += 1
			# The chain may also contain a positive exchange between the rivals;
			# it must not hide the three disputes that earned the label.
			chain_exposed = int(top["other"]) == int(pair[1]) and String(top["label"]) == "rival" and disputes >= 3 and String(acted.get("label", "")) == "fled"
	_check(chain_exposed, "inspector evidence: the rival opinion exposes all three disputes and the flight they caused")

	var ablated: Dictionary = _rivalry_run("opinion")
	var off = ablated["sim"]
	print("  rivalry opinion off: %d rival labels, %d harms, %d disputes, %d rival bonds" % [
		_log_text(off, "social", "as a rival").size(), int(off.harm_events), int(off.food_taken_events),
		int(off.metrics()["rival_bonds"]),
	])
	_check(_log_text(off, "social", "as a rival").is_empty(), "opinion memory off: no rival label is written")
	_check(int(off.metrics()["rival_bonds"]) == 0, "opinion memory off: the rivalry dissolves")
	_check(int(off.harm_events) > 0 or int(off.food_taken_events) > 0, "opinion memory off isolates memory: the incidents themselves still happen")
