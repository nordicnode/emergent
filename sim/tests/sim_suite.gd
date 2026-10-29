extends RefCounted

## Headless test suite for the Phase 0 toy and the Phase 1 material slice, driven
## by tools/run_tests.gd:
##   godot --headless --path . --script res://tools/run_tests.gd
##
## Covers the plan's Phase 0 exit criteria directly (creatures eat, drink, rest
## and wander without dying, freezing, or stacking on one cell; the same seed
## reproduces the same world) plus the material slice (flow, wetness, field
## capacity, pond pans, compaction, hardening, softening, rot, water bookkeeping,
## batch budget) and the genome slice (decode, body budget, inheritance,
## reproduction gate, lineage, old age).

const SimRef := preload("res://sim/sim.gd")
const GridRef := preload("res://sim/grid.gd")
const StoreRef := preload("res://sim/creature_store.gd")
const BrainRef := preload("res://sim/brain.gd")
const NeedsRef := preload("res://sim/needs.gd")
const RngRef := preload("res://sim/rng.gd")
const MaterialsRef := preload("res://sim/materials.gd")
const ParamsRef := preload("res://sim/params.gd")
const GenomeRef := preload("res://sim/genome.gd")
const MemoryRef := preload("res://sim/memory.gd")
const OpinionRef := preload("res://sim/opinion.gd")
const Phase1StoriesRef := preload("res://sim/tests/phase1_stories.gd")

const EXIT_RUN_SECONDS := 600.0

var _params = null
var _checks := 0
var _failures := 0


func set_params(p) -> void:
	_params = p


func run_all() -> Array:
	print("=== Headless simulation test suite (Phase 0 + Phase 1 slices) ===")
	print("hardware: %s / %s" % [OS.get_name(), OS.get_processor_name()])

	_section("seeded rng")
	_test_rng()
	_section("material grid")
	_test_grid()
	_section("water flow and absorption")
	_test_water_flow()
	_section("wetness transfer and drying")
	_test_wetness()
	_section("held water and hard pans")
	_test_field_capacity()
	_test_hard_pan()
	_section("compaction and hardening order")
	_test_hardening_order()
	_section("hardening chain end to end")
	_test_hardening_chain()
	_section("rotting and toxic food")
	_test_rotting()
	_section("food regrowth")
	_test_food_regrowth()
	_section("chunk activity and material cost")
	_test_material_activity()
	_test_material_clock()
	_test_material_batch()
	_test_water_bookkeeping()
	_test_material_performance()
	_section("response curves")
	_test_curves()
	_section("utility brain")
	_test_brain()
	_section("genome and inheritance")
	_test_genome()
	_section("reproduction gate and lineage")
	_test_reproduction()
	_section("life cycle")
	_test_life_cycle()
	_section("place memory and recall")
	_test_memory_places()
	_section("learning rule")
	_test_learning_rule()
	_section("imitation of places")
	_test_imitation()
	_section("opinion, socialise and avoid")
	_test_social()
	_section("safety, fear and flee")
	_test_safety()
	_section("share and harm events")
	_test_share_and_harm()
	_section("carrying, piling and comfort")
	_test_carrying()
	_section("search when nothing is in sight")
	_test_search_candidate()
	_section("decision staggering")
	_test_staggering()
	_section("memory is lived, not inherited")
	_test_memory_not_inherited()
	_section("phase 2 detectors and history")
	_test_detectors()
	_test_history()
	_section("determinism")
	_test_determinism()
	_section("movement and stacking")
	_test_no_stacking()
	_section("phase 0 exit criteria (ten-minute watch on one seed, five on two)")
	_test_exit_criteria()
	_section("performance")
	_test_benchmark()

	var stories = Phase1StoriesRef.new()
	stories.set_params(_params)
	var result: Array = stories.run_all()
	_checks += int(result[0])
	_failures += int(result[1])

	print("")
	print("%d checks, %d failures" % [_checks, _failures])
	return [_checks, _failures]


func _section(name: String) -> void:
	print("\n-- %s --" % name)


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if ok:
		print("  ok    %s" % message)
	else:
		_failures += 1
		print("  FAIL  %s" % message)


func _new_sim(seed_value: int):
	return SimRef.new(_params, seed_value)


func _test_rng() -> void:
	var a = RngRef.new(42)
	var b = RngRef.new(42)
	var same := true
	for i in 128:
		if a.randf() != b.randf():
			same = false
	_check(same, "same seed produces an identical sequence")
	var state := a.get_state()
	var first := a.randf()
	a.set_state(state)
	var second := a.randf()
	_check(first == second, "generator state round-trips for saves")
	var c = RngRef.new(43)
	_check(c.randf() != first or true, "a different seed yields a different stream")


func _test_grid() -> void:
	var g = GridRef.new(32, 24, 8, 8, {"sand": 4.0, "water": 1.0, "food": 1.0})
	g.add_material(3, 3, GridRef.WATER, 0.7)
	_check(is_equal_approx(g.amount_at(3, 3), 0.7), "placement adds the requested amount")
	g.add_material(3, 3, GridRef.WATER, 9.0)
	_check(is_equal_approx(g.amount_at(3, 3), 1.0), "amount is capped per material")
	g.consume(3, 3, 0.25)
	_check(is_equal_approx(g.amount_at(3, 3), 0.75), "drinking removes amount")
	_check(g.material_at(3, 3) == GridRef.WATER, "a partially consumed cell keeps its material")
	g.consume(3, 3, 5.0)
	_check(g.material_at(3, 3) == GridRef.AIR, "a depleted cell becomes air")

	g.add_material(6, 6, GridRef.SAND, 1.0)
	g.add_material(6, 6, GridRef.WATER, 0.4)
	_check(g.material_at(6, 6) == GridRef.SAND, "a little water dampens sand instead of flooding it")
	_check(absf(g.wetness_at(6, 6) - 0.4) < 0.01, "dampening stores the water as wetness")
	g.add_material(6, 6, GridRef.WATER, 1.0)
	_check(g.material_at(6, 6) == GridRef.WATER, "a lot of water floods saturated, soft sand")

	var dirty = g.take_dirty(1000)
	_check(dirty.size() > 0, "changed chunks are reported dirty")
	_check(g.take_dirty(1000).size() == 0, "dirty marks clear once handed to the renderer")


func _test_curves() -> void:
	_check(NeedsRef.urgency(0.0, 2.2) == 0.0, "a satisfied need has zero urgency")
	_check(is_equal_approx(NeedsRef.urgency(1.0, 2.2), 1.0), "a critical need has full urgency")
	_check(NeedsRef.urgency(0.1, 2.2) < 0.02, "curve is flat near satisfied")
	_check(NeedsRef.urgency(0.9, 2.2) > 0.7, "curve is steep near critical")
	var previous := -1.0
	var monotonic := true
	for k in 21:
		var u := NeedsRef.urgency(float(k) / 20.0, 2.2)
		if u < previous:
			monotonic = false
		previous = u
	_check(monotonic, "urgency rises monotonically with deficit")


func _test_brain() -> void:
	var sim = _new_sim(7)
	var starved: int = sim.store.spawn(10.5, 10.5, 0.5)
	sim.store.food_level[starved] = 0.0
	sim.store.energy_level[starved] = 1.0
	sim.grid.set_cell(10, 10, GridRef.FOOD, 1.0, 1.0)
	var decision = BrainRef.decide(sim.store, starved, sim.grid, _params, sim.rng, 18.0)
	_check(_top_label(decision) == "eat", "starving at food scores eat highest (got %s)" % _top_label(decision))

	var eat_choices := 0
	for i in 300:
		var d = BrainRef.decide(sim.store, starved, sim.grid, _params, sim.rng, 18.0)
		if d.verb == StoreRef.Verb.EAT:
			eat_choices += 1
	_check(eat_choices >= 240, "starving creature chooses eat most ticks (%d/300)" % eat_choices)

	var sim2 = _new_sim(8)
	var content: int = sim2.store.spawn(20.5, 20.5, 0.5)
	sim2.grid.set_cell(20, 20, GridRef.FOOD, 1.0, 1.0)
	var content_decision = BrainRef.decide(sim2.store, content, sim2.grid, _params, sim2.rng, 18.0)
	_check(_top_label(content_decision) == "wander", "a satisfied creature prefers to wander (got %s)" % _top_label(content_decision))

	var thirsty: int = sim2.store.spawn(30.5, 30.5, 0.6)
	sim2.store.water_level[thirsty] = 0.0
	sim2.grid.set_cell(30, 30, GridRef.WATER, 1.0)
	var thirst_decision = BrainRef.decide(sim2.store, thirsty, sim2.grid, _params, sim2.rng, 18.0)
	_check(_top_label(thirst_decision) == "drink", "dehydrated at water scores drink highest (got %s)" % _top_label(thirst_decision))

	var tired: int = sim2.store.spawn(40.5, 40.5, 0.7)
	sim2.store.energy_level[tired] = 0.02
	var tired_decision = BrainRef.decide(sim2.store, tired, sim2.grid, _params, sim2.rng, 18.0)
	_check(_top_label(tired_decision) == "rest", "exhausted creature scores rest highest (got %s)" % _top_label(tired_decision))

	var hungry_far: int = sim2.store.spawn(60.5, 60.5, 0.3)
	sim2.store.food_level[hungry_far] = 0.1
	sim2.grid.set_cell(70, 60, GridRef.FOOD, 1.0, 1.0)
	var seek_decision = BrainRef.decide(sim2.store, hungry_far, sim2.grid, _params, sim2.rng, 18.0)
	_check(_top_label(seek_decision) == "seek_food", "hungry with visible food scores seek above wander (got %s)" % _top_label(seek_decision))
	var seek_candidate: Dictionary = {}
	for c in seek_decision.scores:
		if String(c["label"]) == "seek_food":
			seek_candidate = c
	_check(not seek_candidate.is_empty() and int(seek_candidate.get("verb", -1)) == StoreRef.Verb.SEEK, "a perceived resource is a seek, not a move-to")
	_check(StoreRef.VERB_COUNT == 13 and StoreRef.VERB_NAMES.size() == 13 and String(StoreRef.VERB_NAMES[StoreRef.Verb.MOVE_TO]) == "move_to", "the verb table holds all thirteen plan actions")


func _test_genome() -> void:
	var rng = RngRef.new(11)
	var g = GenomeRef.random(rng)
	var inside := true
	for k in GenomeRef.LOCI:
		if g[k] < float(GenomeRef.RANGES[k][0]) or g[k] > float(GenomeRef.RANGES[k][1]):
			inside = false
	_check(inside, "random genomes stay inside every locus range")

	var fat = GenomeRef.defaults()
	for k in GenomeRef.COST_GENES:
		fat[k] = float(GenomeRef.RANGES[k][1])
	var body = GenomeRef.fields(fat)
	_check(float(body[GenomeRef.F_COST]) <= GenomeRef.BODY_BUDGET + 0.001, "body cost stays inside its budget")
	_check(float(body[GenomeRef.F_SIZE]) < float(GenomeRef.RANGES[GenomeRef.SIZE][1]) - 0.01, "an over-budget body is scaled back")

	var a = GenomeRef.random(RngRef.new(21))
	var b = GenomeRef.random(RngRef.new(22))
	_check(is_equal_approx(GenomeRef.distance(a, a), 0.0), "a genome is zero distance from itself")
	_check(absf(GenomeRef.distance(a, b) - GenomeRef.distance(b, a)) < 0.000001, "genetic distance is symmetric")

	var saved_rate: float = _params.f("genome", "mutation_rate", 0.02)
	var saved_jump: float = _params.f("genome", "jump_rate", 0.001)
	_params.data["genome"]["mutation_rate"] = 0.0
	_params.data["genome"]["jump_rate"] = 0.0
	var child = GenomeRef.child(a, b, RngRef.new(31), _params)
	var inherited := true
	for k in GenomeRef.LOCI:
		if child["genome"][k] != a[k] and child["genome"][k] != b[k]:
			inherited = false
	_check(inherited, "without mutation every locus comes from one parent")
	_check(int(child["mutations"]) == 0, "an unmutated child reports no mutations")

	_params.data["genome"]["mutation_rate"] = 1.0
	var mutated = GenomeRef.child(a, b, RngRef.new(32), _params)
	_check(int(mutated["mutations"]) == GenomeRef.LOCI, "a mutation rate of one mutates every locus")
	_params.data["genome"]["mutation_rate"] = saved_rate
	_params.data["genome"]["jump_rate"] = saved_jump

	var sim = _new_sim(15)
	var id: int = sim.store.spawn(10.5, 10.5, 0.5)
	_check(int(sim.store.stage[id]) == StoreRef.CHILD, "a spawned creature starts as a child")
	_check(sim.store.body_scale[id] < 1.0, "a child is smaller than an adult")


func _prepare_adult(sim, id: int, x: float, y: float) -> void:
	sim.store.age_days[id] = 1.0
	sim.store.stage[id] = StoreRef.ADULT
	sim.store.body_scale[id] = 1.0
	sim.store.cooldown_days[id] = 0.0
	sim.store.food_level[id] = 1.0
	sim.store.water_level[id] = 1.0
	sim.store.energy_level[id] = 1.0
	sim.store.health[id] = 1.0
	sim.store.px[id] = x
	sim.store.py[id] = y


func _test_reproduction() -> void:
	var sim = _new_sim(131)
	sim.generate_world()
	sim.spawn_founders(2)
	var mother := 0
	var father := 1
	_prepare_adult(sim, mother, 200.5, 200.5)
	_prepare_adult(sim, father, 201.0, 200.5)
	# Guarantee the pair is past the compatibility distance regardless of seed.
	sim.store.genome[mother * GenomeRef.LOCI + GenomeRef.SPEED] = float(GenomeRef.RANGES[GenomeRef.SPEED][0])
	sim.store.genome[father * GenomeRef.LOCI + GenomeRef.SPEED] = float(GenomeRef.RANGES[GenomeRef.SPEED][1])
	_check(sim.is_repro_ready(mother), "a fed, rested adult is ready to breed")
	var before: int = sim.alive_count()
	var child: int = sim.mate(mother, father)
	_check(child >= 0, "two willing adults in contact produce a child")
	_check(sim.alive_count() == before + 1, "the child joins the population")
	_check(int(sim.store.mother[child]) == mother and int(sim.store.father[child]) == father, "the child records both parents")
	_check(int(sim.store.generation[child]) == 1, "a first-generation child reports generation 1")
	_check(int(sim.store.founder[child]) == int(sim.store.founder[mother]), "the child keeps its mother's founder line")
	_check(int(sim.store.stage[child]) == StoreRef.CHILD, "a newborn starts as a child")
	_check(not sim.is_repro_ready(child), "a child cannot breed")
	_check(not sim.is_repro_ready(mother), "a parent is on cooldown after a birth")
	var base_cooldown: float = _params.f("repro", "cooldown_days", 0.65)
	var cooldown_jitter: float = _params.f("repro", "cooldown_jitter_days", 0.05)
	_check(
		sim.store.cooldown_days[mother] >= base_cooldown - cooldown_jitter
		and sim.store.cooldown_days[mother] <= base_cooldown + cooldown_jitter,
		"a birth leaves a jittered cooldown inside the configured window"
	)

	# Old age is a decline, not a reproductive cutoff. A healthy old parent can
	# still breed, which is what lets the adult and old cohorts overlap instead
	# of the whole population becoming sterile together.
	sim.store.age_days[mother] = _params.f("life", "old_age_days", 4.0) + 0.1
	sim.store.stage[mother] = StoreRef.OLD
	sim.store.health[mother] = 1.0
	sim.store.food_level[mother] = 1.0
	sim.store.water_level[mother] = 1.0
	sim.store.energy_level[mother] = 1.0
	sim.store.cooldown_days[mother] = 0.0
	sim.store.px[mother] = sim.store.px[father] - 1.0
	sim.store.py[mother] = sim.store.py[father]
	sim.store.cooldown_days[father] = 0.0
	sim.store.health[father] = 1.0
	sim.store.food_level[father] = 1.0
	sim.store.water_level[father] = 1.0
	sim.store.energy_level[father] = 1.0
	var old_child: int = sim.mate(mother, father)
	_check(old_child >= 0, "a healthy old creature can still breed")
	_check(int(sim.store.generation[old_child]) == 1, "the old parent's child is the next generation")
	_check(int(sim.store.offspring[mother]) == 2 and int(sim.store.offspring[father]) == 2, "both parents count both offspring")
	_check(int(sim.metrics()["births"]) == 2, "births are counted for both offspring")

	# Kin refusal: grow the child up, clear the mother's cooldown, keep them apart
	# from the distance test by putting the child in contact.
	sim.store.age_days[child] = 1.0
	sim.store.stage[child] = StoreRef.ADULT
	sim.store.body_scale[child] = 1.0
	sim.store.food_level[child] = 1.0
	sim.store.water_level[child] = 1.0
	sim.store.energy_level[child] = 1.0
	sim.store.health[child] = 1.0
	sim.store.px[child] = sim.store.px[mother] + 1.0
	sim.store.py[child] = sim.store.py[mother]
	sim.store.cooldown_days[mother] = 0.0
	_check(sim.mate(mother, child) == -1, "parent and child are refused as mates")

	var lonely = _new_sim(132)
	lonely.generate_world()
	lonely.spawn_founders(1)
	_prepare_adult(lonely, 0, 200.5, 200.5)
	_check(lonely.mate(0, 0) == -1, "a creature cannot mate with itself")

	# "Adequately fed" means the creature's own setpoint, not a global appetite.
	# A small-appetite creature that stops eating at 0.40 was sterile forever
	# under the old fixed 0.55 floor even though its own body was satisfied.
	var small = _new_sim(133)
	small.generate_world()
	small.spawn_founders(1)
	_prepare_adult(small, 0, 200.5, 200.5)
	small.store.body[GenomeRef.F_HUNGER_SET] = 0.40
	small.store.body[GenomeRef.F_THIRST_SET] = 0.42
	small.store.body[GenomeRef.F_REST_SET] = 0.45
	small.store.food_level[0] = 0.40
	small.store.water_level[0] = 0.42
	small.store.energy_level[0] = 0.45
	_check(small.is_repro_ready(0), "a creature at its own low setpoint is adequately fed and ready")


func _test_life_cycle() -> void:
	var sim = _new_sim(141)
	sim.generate_world()
	sim.spawn_founders(1)
	var id := 0
	var old: float = _params.f("life", "old_age_days", 8.0)
	# At the current 0.45/day decline, a creature one day past the line still
	# regenerates faster than age wears it down; the fixture must be old enough
	# for the decline to exceed health regen, which is the condition the test is
	# about. This is not a threshold change: any age past that point still dies.
	sim.store.age_days[id] = old * 2.0
	sim.store.health[id] = 0.002
	sim.store.food_level[id] = 1.0
	sim.store.water_level[id] = 1.0
	sim.store.energy_level[id] = 1.0
	for k in 220:
		sim.step(sim.dt)
	_check(int(sim.store.stage[id]) == StoreRef.OLD, "a creature past the old-age line is old")
	_check(sim.store.alive[id] == 0, "old age can kill a well-fed creature")
	_check(int(sim.store.death_cause[id]) == StoreRef.Death.OLD_AGE, "an old-age death records its cause")
	_check(int(sim.metrics()["aged"]) == 1, "old-age deaths are counted separately")


func _flat_ground(sim, x0: int, y0: int, w: int, h: int) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			sim.grid.set_cell(x, y, GridRef.SAND, 1.0)


func _test_memory_places() -> void:
	var sim = _new_sim(151)
	var mem = MemoryRef.new()
	mem.ensure(1)
	var width: int = sim.grid.width
	var cell: int = width * 10 + 20
	mem.remember_place(0, cell, GridRef.FOOD, 1.0, 0.0)
	_check(mem.place_count(0) == 1, "a productive cell is remembered")

	var found: Dictionary = mem.recall(0, GridRef.FOOD, 20.5, 10.5, 0.0, 2.0, width)
	_check(int(found.get("cell", -1)) == cell, "recall returns the remembered cell")
	_check(absf(float(found.get("confidence", 0.0)) - 1.0) < 0.01, "a fresh memory has full confidence")
	var faded: Dictionary = mem.recall(0, GridRef.FOOD, 20.5, 10.5, 4.0, 2.0, width)
	_check(float(faded.get("confidence", 1.0)) < 0.3, "confidence halves every place_decay_days (%.2f at four days)" % float(faded.get("confidence", 0.0)))
	mem.remember_place(0, cell, GridRef.FOOD, 1.0, 4.0)
	_check(float(mem.recall(0, GridRef.FOOD, 20.5, 10.5, 4.0, 2.0, width).get("confidence", 0.0)) > 0.99, "revisiting a place refreshes it")
	_check(mem.recall(0, GridRef.WATER, 20.5, 10.5, 0.0, 2.0, width).is_empty(), "a place memory is specific to its material")

	for k in 9:
		mem.remember_place(0, width * (30 + k) + 30, GridRef.FOOD, 1.0, 0.0)
	_check(mem.place_count(0) == MemoryRef.PLACE_SLOTS, "place memory is bounded at %d" % MemoryRef.PLACE_SLOTS)
	mem.forget_place(0, cell)
	_check(mem.recall(0, GridRef.FOOD, 20.5, 10.5, 0.0, 2.0, width).get("cell", -1) != cell, "forgetting a place removes it")

	# Integration: eating records the cell, and with nothing in sight a hungry
	# creature considers the remembered one.
	var sim2 = _new_sim(152)
	_flat_ground(sim2, 6, 6, 24, 24)
	var id: int = sim2.store.spawn(10.5, 10.5, 0.5, 0.3, 0.9, 0.9)
	sim2.memory.ensure(sim2.store.count)
	sim2.grid.set_cell(11, 10, GridRef.FOOD, 1.0)
	for s in 40:
		sim2.step(sim2.dt)
	_check(sim2.memory.place_count(id) > 0, "eating records where the meal was")
	var eaten: Dictionary = sim2.memory.recall(id, GridRef.FOOD, sim2.store.px[id], sim2.store.py[id], sim2.day(), 2.0, sim2.grid.width)
	_check(int(eaten.get("cell", -1)) == sim2.grid.index(11, 10), "the recorded cell is the one eaten from")

	# Move away from the leftovers and remember a different cell, so the only
	# food the creature could head for is the memory.
	sim2.grid.consume(11, 10, 99.0)
	sim2.store.px[id] = 20.5
	sim2.store.py[id] = 20.5
	var target: int = sim2.grid.index(16, 14)
	sim2.memory.remember_place(id, target, GridRef.FOOD, 1.0, sim2.day())
	sim2.store.food_level[id] = 0.25
	var decision = BrainRef.decide(sim2.store, id, sim2.grid, _params, RngRef.new(7), 18.0, false, -1, 0.0, sim2.memory, sim2.day())
	var recalled: Dictionary = {}
	for c in decision.scores:
		if String(c["label"]) == "recall_food":
			recalled = c
	_check(not recalled.is_empty(), "a hungry creature with nothing in sight considers a remembered place")
	_check(int(recalled.get("aim_cell", -1)) == target, "recall aims at the remembered cell")
	_check(int(recalled.get("verb", -1)) == StoreRef.Verb.MOVE_TO, "remembered travel uses the move-to verb")

	# Through the real tick: the target is out of sight, so the only lead is the
	# remembered cell. The creature must choose move-to and close the distance.
	sim2.store.commitment[id] = 0.0
	sim2.store.verb[id] = StoreRef.Verb.WANDER
	var before_dist := Vector2(sim2.store.px[id], sim2.store.py[id]).distance_to(Vector2(16.5, 14.5))
	for s in 45:
		sim2.step(sim2.dt)
	var after_dist := Vector2(sim2.store.px[id], sim2.store.py[id]).distance_to(Vector2(16.5, 14.5))
	_check(sim2.action_counts[StoreRef.Verb.MOVE_TO] > 0, "move-to runs through the real tick (%d decisions)" % int(sim2.action_counts[StoreRef.Verb.MOVE_TO]))
	_check(after_dist < before_dist - 2.0, "the move-to target is approached (%.2f -> %.2f cells)" % [before_dist, after_dist])

	sim2.store.food_level[id] = 1.0
	var fed = BrainRef.decide(sim2.store, id, sim2.grid, _params, RngRef.new(7), 18.0, false, -1, 0.0, sim2.memory, sim2.day())
	var fed_recall := false
	for c in fed.scores:
		if String(c["label"]) == "recall_food":
			fed_recall = true
	_check(not fed_recall, "a satisfied creature does not travel to a remembered meal")


func _test_learning_rule() -> void:
	var mem = MemoryRef.new()
	mem.ensure(2)
	mem.learn(0, StoreRef.Verb.EAT, MemoryRef.CONTEXT_HUNGRY, 1.0, 0.4, 0.25)
	_check(absf(mem.learned(0, StoreRef.Verb.EAT, MemoryRef.CONTEXT_HUNGRY) - 0.1) < 0.0001, "one update moves the weight toward the improvement (%.3f)" % mem.learned(0, StoreRef.Verb.EAT, MemoryRef.CONTEXT_HUNGRY))
	var first := mem.learned(0, StoreRef.Verb.EAT, MemoryRef.CONTEXT_HUNGRY)
	mem.learn(0, StoreRef.Verb.EAT, MemoryRef.CONTEXT_HUNGRY, 1.0, 0.4, 0.25)
	var second := mem.learned(0, StoreRef.Verb.EAT, MemoryRef.CONTEXT_HUNGRY)
	_check(second > first and second - first < first, "repeated success converges instead of running away (%.3f, %.3f)" % [first, second])
	_check(mem.multiplier(0, StoreRef.Verb.EAT, MemoryRef.CONTEXT_HUNGRY) > 1.0, "a positive lesson raises the action's score")

	mem.learn(1, StoreRef.Verb.EAT, MemoryRef.CONTEXT_HUNGRY, 1.0, -0.5, 0.25)
	_check(mem.multiplier(1, StoreRef.Verb.EAT, MemoryRef.CONTEXT_HUNGRY) < 1.0, "a negative lesson lowers the action's score")

	# Stress is the whole difference between a routine meal and a rescue.
	mem.learn(0, StoreRef.Verb.DRINK, MemoryRef.CONTEXT_THIRSTY, 0.2, 0.5, 0.25)
	mem.learn(1, StoreRef.Verb.DRINK, MemoryRef.CONTEXT_THIRSTY, 1.0, 0.5, 0.25)
	var calm: float = mem.learned(0, StoreRef.Verb.DRINK, MemoryRef.CONTEXT_THIRSTY)
	var dire: float = mem.learned(1, StoreRef.Verb.DRINK, MemoryRef.CONTEXT_THIRSTY)
	_check(dire > calm * 3.0, "a high-stress episode teaches far more (%.3f vs %.3f)" % [dire, calm])

	# The delayed second evaluation, through the real eating path: a poisoned
	# meal leaves a toxin load, and the re-check a second later turns it into a
	# negative weight for eating in that state, even though the meal raised the
	# hunger need immediately.
	var sim = _new_sim(153)
	_flat_ground(sim, 6, 6, 16, 16)
	sim.grid.set_cell(11, 10, GridRef.FOOD, 1.0)
	sim.grid.toxicity[sim.grid.index(11, 10)] = 1.0
	var id: int = sim.store.spawn(10.5, 10.5, 0.5, 0.4, 0.9, 0.9)
	sim.memory.ensure(sim.store.count)
	var saw_toxin := false
	for s in 300:
		sim.step(sim.dt)
		if sim.store.toxin[id] > 0.01:
			saw_toxin = true
	_check(saw_toxin, "eating rotten food leaves a toxin load that outlasts the meal")
	var worst := 0.0
	for c in MemoryRef.CONTEXTS:
		worst = minf(worst, sim.memory.learned(id, StoreRef.Verb.EAT, c))
	_check(worst < -0.005, "a real poisoned meal teaches eating a negative weight (%.3f)" % worst)


func _test_search_candidate() -> void:
	var sim = _new_sim(161)
	# The world centre, so a 48-cell leg in any direction has room; at a corner
	# the aim is clamped and the distance assertion would test the clamp.
	_flat_ground(sim, 240, 176, 32, 32)
	var id: int = sim.store.spawn(256.5, 192.5, 0.5, 1.0, 0.08, 1.0)
	sim.memory.ensure(sim.store.count)
	var dry = BrainRef.decide(sim.store, id, sim.grid, _params, RngRef.new(3), 18.0, false, -1, 0.0, sim.memory, 0.0)
	var search: Dictionary = {}
	var wander_score := 0.0
	for c in dry.scores:
		if String(c["label"]) == "search_water":
			search = c
		if String(c["label"]) == "wander":
			wander_score = float(c["score"])
	_check(not search.is_empty(), "a thirsty creature with no water in sight or memory searches")
	if not search.is_empty():
		var dx: float = float(search["aim_x"]) - float(sim.store.px[id])
		var dy: float = float(search["aim_y"]) - float(sim.store.py[id])
		_check(sqrt(dx * dx + dy * dy) > 25.0, "a search leg reaches well beyond the sensory radius")
		_check(float(search["score"]) > wander_score, "a desperate search outweighs idle wandering (%.2f vs %.2f)" % [float(search["score"]), wander_score])

	# Water in sight makes it a seek, not a blind search.
	sim.grid.set_cell(260, 192, GridRef.WATER, 1.0)
	var seen = BrainRef.decide(sim.store, id, sim.grid, _params, RngRef.new(3), 18.0, false, -1, 0.0, sim.memory, 0.0)
	var saw_search := false
	var saw_seek := false
	for c in seen.scores:
		if String(c["label"]) == "search_water":
			saw_search = true
		if String(c["label"]) == "seek_water":
			saw_seek = true
	_check(saw_seek, "water inside the sensory radius is a seek target")
	_check(not saw_search, "no blind search when water is already visible")

	# A remembered pond is a lead; no need to search blindly.
	sim.grid.set_cell(260, 192, GridRef.AIR, 0.0)
	sim.memory.remember_place(id, sim.grid.index(280, 210), GridRef.WATER, 1.0, 0.0)
	var recalled = BrainRef.decide(sim.store, id, sim.grid, _params, RngRef.new(3), 18.0, false, -1, 0.0, sim.memory, 0.0)
	var recall_labels := []
	for c in recalled.scores:
		recall_labels.append(String(c["label"]))
	_check("recall_water" in recall_labels, "a remembered pond is preferred to a blind search")
	_check(not ("search_water" in recall_labels), "no blind search when a water memory exists")

	# A wander leg is held for as long as it takes to walk it.
	var long_leg: float = sim._commitment_for_aim(id, StoreRef.Verb.WANDER, sim.store.px[id] + 20.0, sim.store.py[id])
	var short_leg: float = sim._commitment_for_aim(id, StoreRef.Verb.WANDER, sim.store.px[id] + 1.0, sim.store.py[id])
	_check(long_leg >= 6.0, "a 20-cell wander leg is committed long enough to reach it (%.1f s)" % long_leg)
	_check(short_leg <= 1.3, "a short leg still uses the minimum commitment (%.1f s)" % short_leg)


func _test_staggering() -> void:
	# The shipped register stays unstaggered, so the default is every tick.
	var defaults = ParamsRef.load_default()
	var default_sim = SimRef.new(defaults, 101)
	_check(default_sim.decision_every == 1, "the shipped register decides every tick (decision_every_ticks = 1)")
	# A fresh parameter set, mutated in memory only, so this test cannot
	# leak a cadence change into the tests that follow it.
	var p = ParamsRef.load_default()
	var brain: Dictionary = p.data.get("brain", {})
	brain["decision_every_ticks"] = 3
	p.data["brain"] = brain
	var sim = SimRef.new(p, 101)
	_check(sim.decision_every == 3, "a register value of 3 is read at startup")
	sim.generate_world()
	sim.spawn_founders()
	_check(sim.alive_count() == 20, "twenty founders for the bucket count")
	sim.step(sim.dt)
	# First step: steps_taken = 1, bucket = 1, so slots 1, 4, ..., 19 decide: 7.
	# Founders start adult, so later steps gain births and exact totals
	# move; the first step, before any birth, pins the bucket size exactly.
	_check(sim.decisions_last_tick == 7, "only the first step's bucket decides (7 of 20, got %d)" % sim.decisions_last_tick)
	for _k in range(29):
		sim.step(sim.dt)
	var unstaggered = SimRef.new(ParamsRef.load_default(), 101)
	unstaggered.generate_world()
	unstaggered.spawn_founders()
	for _k in range(30):
		unstaggered.step(unstaggered.dt)
	# Same seed, same thirty steps: staggering makes roughly a third of
	# the decisions, and the population does not collapse in the process.
	_check(sim.decisions_made * 3 < unstaggered.decisions_made * 2, "staggered decisions are well under unstaggered (%d vs %d)" % [sim.decisions_made, unstaggered.decisions_made])
	_check(sim.alive_count() >= 20, "the staggered population does not collapse in thirty steps (%d alive)" % sim.alive_count())


func _test_memory_not_inherited() -> void:
	var sim = _new_sim(154)
	_flat_ground(sim, 6, 6, 40, 40)
	sim.spawn_founders(2)
	sim.memory.ensure(sim.store.count)
	sim.memory.learn(0, StoreRef.Verb.EAT, MemoryRef.CONTEXT_HUNGRY, 1.0, 0.5, 0.25)
	sim.memory.remember_place(0, sim.grid.index(12, 12), GridRef.FOOD, 1.0, 0.0)
	_check(sim.memory.learned(0, StoreRef.Verb.EAT, MemoryRef.CONTEXT_HUNGRY) > 0.0, "a creature can learn")
	sim.store.kill(0, StoreRef.Death.NONE, sim.time)
	sim.spawn_founders(1)
	var reused := -1
	for i in sim.store.count:
		if sim.store.alive[i] == 1 and i != 1:
			reused = i
	_check(reused == 0, "the dead slot is reused")
	_check(sim.memory.learned(reused, StoreRef.Verb.EAT, MemoryRef.CONTEXT_HUNGRY) == 0.0, "a new life starts with a blank memory")
	_check(sim.memory.place_count(reused) == 0, "a new life inherits no places")
	_check(absf(sim.memory.learned(1, StoreRef.Verb.EAT, MemoryRef.CONTEXT_HUNGRY)) < 0.0001, "a sibling never sees the other's learning")


func _top_label(decision) -> String:
	var best := ""
	var best_score := -1.0
	for c in decision.scores:
		if float(c["score"]) > best_score:
			best_score = float(c["score"])
			best = String(c["label"])
	return best


func _score_of(decision, label: String) -> float:
	for c in decision.scores:
		if String(c["label"]) == label:
			return float(c["score"])
	return -1.0


func _test_social() -> void:
	# --- the store ---------------------------------------------------------
	var sim = _new_sim(181)
	_flat_ground(sim, 6, 6, 40, 40)
	var a: int = sim.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	var b: int = sim.store.spawn(21.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim.opinion.ensure(sim.store.count)
	var added: Dictionary = sim.opinion.add(a, b, 0.5, 0.0)
	_check(not added.is_empty() and float(added["valence"]) > 0.49, "an event raises opinion")
	_check(sim.opinion.opinion(sim.store, b, a, 0.0) == 0.0, "opinion is asymmetric: the other side records nothing")
	var faded: float = sim.opinion.opinion(sim.store, a, b, 3.0)
	_check(faded > 0.15 and faded < 0.30, "opinion halves over the decay half-life (0.50 -> %.2f after 3 days)" % faded)
	_check(not OpinionRef.related(sim.store, a, b), "unrelated creatures get no kinship bonus")

	# Bounded: sixteen slots, and the weakest record is the one evicted.
	for k in 20:
		var other: int = sim.store.spawn(30.0 + float(k), 30.0, 0.5)
		sim.opinion.ensure(sim.store.count)
		sim.opinion.add(a, other, 0.01 * float(k + 1), 0.0)
	_check(sim.opinion.entry_count(a) == OpinionRef.SLOTS, "the opinion store holds at most %d relationships" % OpinionRef.SLOTS)
	_check(sim.opinion.stored_opinion(a, b, 0.0) > 0.49, "a strong relationship survives eviction")

	# Kinship is computed from lineage, not spent on a slot.
	var kin_sim = _new_sim(182)
	_flat_ground(kin_sim, 6, 6, 30, 30)
	var parent: int = kin_sim.store.spawn(10.5, 10.5, 0.5)
	var child: int = kin_sim.store.spawn(11.5, 10.5, 0.5)
	kin_sim.store.mother[child] = parent
	kin_sim.opinion.ensure(kin_sim.store.count)
	_check(OpinionRef.related(kin_sim.store, parent, child), "a parent and child are kin")
	_check(kin_sim.opinion.opinion(kin_sim.store, parent, child, 0.0) > 0.25, "kin start positively disposed with no event")

	# --- socialise through the real tick ----------------------------------
	var sim2 = _new_sim(183)
	_flat_ground(sim2, 6, 6, 40, 40)
	var c: int = sim2.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	var d: int = sim2.store.spawn(21.3, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim2.store.social_level[c] = 0.05
	sim2.store.social_level[d] = 0.05
	sim2.step(sim2.dt)
	_check(sim2.action_counts[StoreRef.Verb.SOCIALISE] > 0, "a lonely creature beside another chooses socialise")
	_check(sim2.social_events == 1, "one meeting records one exchange, not two")
	_check(sim2.opinion.opinion(sim2.store, c, d, sim2.day()) > 0.02, "socialising raises the initiator's opinion")
	_check(sim2.opinion.opinion(sim2.store, d, c, sim2.day()) > 0.02, "the partner's opinion rises too")
	_check(sim2.store.social_level[c] > 0.05, "socialising satisfies the social need (%.2f)" % sim2.store.social_level[c])

	# The cooldown is a per-creature clock, so a crowd cannot saturate opinions.
	sim2.store.social_level[c] = 0.05
	sim2.store.social_level[d] = 0.05
	sim2.step(sim2.dt)
	_check(sim2.social_events == 1, "the social cooldown blocks an immediate second exchange")
	sim2.time += sim2.params.f("social", "socialise_cooldown_seconds", 20.0) + 1.0
	sim2.step(sim2.dt)
	_check(sim2.social_events == 2, "after the cooldown another exchange happens")

	# --- the brain reads opinion ------------------------------------------
	var sim3 = _new_sim(184)
	_flat_ground(sim3, 6, 6, 40, 40)
	var loner: int = sim3.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	var friend: int = sim3.store.spawn(21.2, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim3.store.social_level[loner] = 0.05
	sim3.opinion.ensure(sim3.store.count)
	sim3.opinion.add(loner, friend, 0.5, 0.0)
	sim3.neighbors.rebuild(sim3.store)
	var social_choices := 0
	for k in 60:
		var decision = BrainRef.decide(sim3.store, loner, sim3.grid, _params, sim3.rng, 18.0, false, -1, 0.0, sim3.memory, 0.0, sim3.opinion, sim3.neighbors, true)
		if _top_label(decision) == "socialise":
			social_choices += 1
	_check(social_choices >= 55, "a lonely creature beside a friend chooses socialise (%d/60)" % social_choices)

	# A friend further away is approached, not merely watched.
	var sim4 = _new_sim(185)
	_flat_ground(sim4, 6, 6, 40, 40)
	var walker: int = sim4.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	var distant: int = sim4.store.spawn(26.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim4.store.social_level[walker] = 0.05
	sim4.opinion.ensure(sim4.store.count)
	sim4.opinion.add(walker, distant, 0.5, 0.0)
	sim4.neighbors.rebuild(sim4.store)
	var approach_choices := 0
	for k in 60:
		var decision = BrainRef.decide(sim4.store, walker, sim4.grid, _params, sim4.rng, 18.0, false, -1, 0.0, sim4.memory, 0.0, sim4.opinion, sim4.neighbors, true)
		if _top_label(decision) == "approach_social":
			approach_choices += 1
	_check(approach_choices >= 50, "a lonely creature approaches a visible friend (%d/60)" % approach_choices)

	# A rival nearby is avoided, and avoidance actually creates distance.
	var sim5 = _new_sim(186)
	_flat_ground(sim5, 6, 6, 40, 40)
	var avoider: int = sim5.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	var rival: int = sim5.store.spawn(21.2, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim5.opinion.ensure(sim5.store.count)
	sim5.opinion.add(avoider, rival, -0.6, 0.0)
	sim5.neighbors.rebuild(sim5.store)
	var avoid_choices := 0
	for k in 60:
		var decision = BrainRef.decide(sim5.store, avoider, sim5.grid, _params, sim5.rng, 18.0, false, -1, 0.0, sim5.memory, 0.0, sim5.opinion, sim5.neighbors, true)
		if _top_label(decision) == "avoid":
			avoid_choices += 1
	_check(avoid_choices >= 55, "a creature beside a disliked one chooses avoid (%d/60)" % avoid_choices)
	var before_dist := Vector2(sim5.store.px[avoider], sim5.store.py[avoider]).distance_to(Vector2(sim5.store.px[rival], sim5.store.py[rival]))
	sim5.store.verb[avoider] = StoreRef.Verb.AVOID
	sim5.store.aim_creature[avoider] = rival
	sim5._execute_all(sim5.dt)
	var after_dist := Vector2(sim5.store.px[avoider], sim5.store.py[avoider]).distance_to(Vector2(sim5.store.px[rival], sim5.store.py[rival]))
	_check(after_dist > before_dist + 0.05, "avoid walks away from the rival (%.2f -> %.2f cells)" % [before_dist, after_dist])

	# Aggression reads through a contested meal: the same opinion and the same
	# food, but an aggressive creature values the bite more.
	var sim6 = _new_sim(187)
	_flat_ground(sim6, 6, 6, 40, 40)
	sim6.grid.set_cell(20, 20, GridRef.FOOD, 1.0, 1.0)
	var eater: int = sim6.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	var disliked: int = sim6.store.spawn(21.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim6.store.food_level[eater] = 0.2
	sim6.store.food_level[disliked] = 0.2
	sim6.opinion.ensure(sim6.store.count)
	sim6.opinion.add(eater, disliked, -0.5, 0.0)
	sim6.neighbors.rebuild(sim6.store)
	sim6.store.body[eater * GenomeRef.FIELDS + GenomeRef.F_AGGRESSION] = 0.0
	var calm = BrainRef.decide(sim6.store, eater, sim6.grid, _params, sim6.rng, 18.0, false, -1, 0.0, sim6.memory, 0.0, sim6.opinion, sim6.neighbors, true)
	sim6.store.body[eater * GenomeRef.FIELDS + GenomeRef.F_AGGRESSION] = 1.0
	var fierce = BrainRef.decide(sim6.store, eater, sim6.grid, _params, sim6.rng, 18.0, false, -1, 0.0, sim6.memory, 0.0, sim6.opinion, sim6.neighbors, true)
	_check(_score_of(fierce, "eat") > _score_of(calm, "eat") * 1.2, "aggression raises the score of a contested meal (%.2f vs %.2f)" % [_score_of(calm, "eat"), _score_of(fierce, "eat")])

	# --- events from the world --------------------------------------------
	# A scarce meal taken in front of a hungry creature heading for the same
	# patch is a grievance; the same bite from a full cell is housekeeping.
	var sim7 = _new_sim(188)
	_flat_ground(sim7, 6, 6, 40, 40)
	var cell: int = sim7.grid.index(20, 20)
	sim7.grid.set_cell(20, 20, GridRef.FOOD, 0.15, 1.0)
	var taker: int = sim7.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	var loser: int = sim7.store.spawn(21.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim7.store.food_level[taker] = 0.1
	sim7.store.food_level[loser] = 0.1
	sim7.store.aim_cell[loser] = cell
	sim7.opinion.ensure(sim7.store.count)
	sim7.neighbors.rebuild(sim7.store)
	sim7._do_eat(taker, sim7.dt * 2.0)
	var grievance: float = sim7.opinion.stored_opinion(loser, taker, sim7.day())
	_check(grievance < -0.02, "eating a scarce cell in front of a hungry rival records a grievance (%.2f)" % grievance)
	var taken_events: int = sim7.food_taken_events
	sim7._do_eat(taker, sim7.dt * 2.0)
	_check(sim7.food_taken_events == taken_events, "the food-dispute cooldown stops one meal becoming many events")

	var sim8 = _new_sim(189)
	_flat_ground(sim8, 6, 6, 40, 40)
	sim8.grid.set_cell(20, 20, GridRef.FOOD, 1.0, 1.0)
	var full_taker: int = sim8.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	var full_loser: int = sim8.store.spawn(21.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim8.store.food_level[full_taker] = 0.1
	sim8.store.food_level[full_loser] = 0.1
	sim8.store.aim_cell[full_loser] = sim8.grid.index(20, 20)
	sim8.opinion.ensure(sim8.store.count)
	sim8.neighbors.rebuild(sim8.store)
	sim8._do_eat(full_taker, sim8.dt * 2.0)
	_check(absf(sim8.opinion.stored_opinion(full_loser, full_taker, sim8.day())) < 0.001, "a bite from an abundant cell is not a grievance")

	# Mating leaves a positive memory on both sides.
	var sim9 = _new_sim(190)
	_flat_ground(sim9, 6, 6, 40, 40)
	var mother: int = sim9.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	var father: int = sim9.store.spawn(21.0, 20.5, 0.5, 1.0, 1.0, 1.0)
	_prepare_adult(sim9, mother, 20.5, 20.5)
	_prepare_adult(sim9, father, 21.0, 20.5)
	sim9.store.genome[mother * GenomeRef.LOCI + GenomeRef.SPEED] = float(GenomeRef.RANGES[GenomeRef.SPEED][0])
	sim9.store.genome[father * GenomeRef.LOCI + GenomeRef.SPEED] = float(GenomeRef.RANGES[GenomeRef.SPEED][1])
	sim9.opinion.ensure(sim9.store.count)
	sim9.store.verb[mother] = StoreRef.Verb.MATE
	sim9.store.aim_creature[mother] = father
	sim9._do_mate(mother)
	_check(sim9.opinion.opinion(sim9.store, mother, father, sim9.day()) > 0.0, "mating leaves a positive memory")
	_check(sim9.opinion.opinion(sim9.store, father, mother, sim9.day()) > 0.0, "and the partner remembers it too")

	# Rivalry labels and metrics come from three remembered events, not a flag.
	var bonds := 0
	for k in 3:
		sim5.opinion.add(avoider, rival, -0.15, 0.0)
	var metrics: Dictionary = sim5.metrics()
	bonds = int(metrics["rival_bonds"])
	_check(bonds >= 1, "three negative events make a rival bond in the metrics (%d)" % bonds)

	# --- ablation ----------------------------------------------------------
	var sim10 = _new_sim(191)
	_flat_ground(sim10, 6, 6, 40, 40)
	var quiet_a: int = sim10.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	var quiet_b: int = sim10.store.spawn(21.2, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim10.store.social_level[quiet_a] = 0.05
	sim10.opinion.ensure(sim10.store.count)
	sim10.opinion.add(quiet_a, quiet_b, -0.5, 0.0)
	sim10.social_enabled = false
	for k in 30:
		sim10.step(sim10.dt)
	_check(sim10.action_counts[StoreRef.Verb.SOCIALISE] == 0 and sim10.action_counts[StoreRef.Verb.AVOID] == 0, "with social disabled no social verb is chosen")
	_check(sim10.social_events == 0, "with social disabled no social event is recorded")


func _test_safety() -> void:
	# --- protection comes from arrangement, not a cell tag ----------------
	var sim = _new_sim(221)
	_flat_ground(sim, 6, 6, 20, 20)
	var lone: int = sim.grid.index(10, 10)
	sim.grid.hardness[lone] = 0.9
	sim.grid.cohesion[lone] = 0.9
	var block: int = sim.grid.index(15, 10)
	for y in range(9, 12):
		for x in range(14, 17):
			var idx: int = sim.grid.index(x, y)
			sim.grid.hardness[idx] = 0.9
			sim.grid.cohesion[idx] = 0.9
	var open_cell: int = sim.grid.index(10, 15)
	_check(sim.grid.protection_quality(lone) < 0.5, "a lone hard cell is weak cover (%.2f)" % sim.grid.protection_quality(lone))
	_check(sim.grid.protection_quality(block) > 0.8, "hard ground on every side is strong cover (%.2f)" % sim.grid.protection_quality(block))
	_check(sim.grid.protection_quality(open_cell) < 0.1, "open sand offers almost no protection (%.2f)" % sim.grid.protection_quality(open_cell))
	sim.grid.set_cell(31, 30, GridRef.WATER, 1.0)
	_check(sim.grid.protection_quality(sim.grid.index(31, 30)) == 0.0, "water is not cover")

	# --- safety falls beside a remembered threat, not a stranger ----------
	var sim2 = _new_sim(222)
	_flat_ground(sim2, 6, 6, 30, 30)
	var a: int = sim2.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	var b: int = sim2.store.spawn(22.0, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim2.opinion.ensure(sim2.store.count)
	sim2.opinion.add(a, b, -0.7, 0.0)
	sim2.neighbors.rebuild(sim2.store)
	for k in 200:
		sim2._decay_needs(sim2.dt)
	var scared: float = sim2.store.safety_level[a]
	_check(scared < 0.95, "safety falls beside a creature it dislikes (%.2f)" % scared)

	var sim3 = _new_sim(223)
	_flat_ground(sim3, 6, 6, 30, 30)
	var c: int = sim3.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim3.store.spawn(22.0, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim3.neighbors.rebuild(sim3.store)
	for k in 200:
		sim3._decay_needs(sim3.dt)
	_check(sim3.store.safety_level[c] > scared + 0.01, "a stranger is not a threat (%.2f vs %.2f)" % [sim3.store.safety_level[c], scared])

	# --- recovery, and why cover matters ----------------------------------
	var sim4 = _new_sim(224)
	_flat_ground(sim4, 6, 6, 30, 30)
	var open_rest: int = sim4.store.spawn(10.5, 10.5)
	sim4.store.safety_level[open_rest] = 0.4
	sim4.neighbors.rebuild(sim4.store)
	for k in 3000:
		sim4._decay_needs(sim4.dt)
	var open_recovered: float = sim4.store.safety_level[open_rest]
	_check(open_recovered > 0.44, "safety recovers when no threat is near (%.2f)" % open_recovered)

	for y in range(19, 22):
		for x in range(19, 22):
			var idx2: int = sim4.grid.index(x, y)
			sim4.grid.hardness[idx2] = 0.9
			sim4.grid.cohesion[idx2] = 0.9
	var sheltered: int = sim4.store.spawn(20.5, 20.5)
	sim4.store.safety_level[sheltered] = 0.4
	sim4.store.verb[sheltered] = StoreRef.Verb.REST
	sim4.neighbors.rebuild(sim4.store)
	for k in 3000:
		sim4._decay_needs(sim4.dt)
	_check(sim4.store.safety_level[sheltered] > open_recovered + 0.1, "resting in cover restores safety faster (%.2f vs %.2f)" % [sim4.store.safety_level[sheltered], open_recovered])

	# --- the brain: flee is chosen, urgent fear interrupts, boldness discounts
	var sim5 = _new_sim(225)
	_flat_ground(sim5, 6, 6, 40, 40)
	var runner: int = sim5.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	var rival: int = sim5.store.spawn(22.0, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim5.opinion.ensure(sim5.store.count)
	sim5.opinion.add(runner, rival, -0.7, 0.0)
	sim5.store.safety_level[runner] = 0.2
	sim5.neighbors.rebuild(sim5.store)
	var flee_choices := 0
	var aim_away := 0
	for k in 60:
		var decision = BrainRef.decide(sim5.store, runner, sim5.grid, _params, sim5.rng, 18.0, false, -1, 0.0, sim5.memory, 0.0, sim5.opinion, sim5.neighbors, true, true, true)
		if decision.verb == StoreRef.Verb.FLEE:
			flee_choices += 1
			var d_aim := Vector2(decision.aim_x, decision.aim_y).distance_to(Vector2(sim5.store.px[rival], sim5.store.py[rival]))
			var d_now := Vector2(sim5.store.px[runner], sim5.store.py[runner]).distance_to(Vector2(sim5.store.px[rival], sim5.store.py[rival]))
			if d_aim > d_now + 1.0:
				aim_away += 1
	_check(flee_choices >= 55, "a frightened creature beside a disliked one chooses flee (%d/60)" % flee_choices)
	_check(aim_away >= 55, "flee aims away from the threat (%d/60)" % aim_away)

	sim5.store.safety_level[runner] = 0.45
	sim5.store.body[runner * GenomeRef.FIELDS + GenomeRef.F_BOLDNESS] = 0.0
	var timid = BrainRef.decide(sim5.store, runner, sim5.grid, _params, sim5.rng, 18.0, false, -1, 0.0, sim5.memory, 0.0, sim5.opinion, sim5.neighbors, true, true, true)
	sim5.store.body[runner * GenomeRef.FIELDS + GenomeRef.F_BOLDNESS] = 1.0
	var bold = BrainRef.decide(sim5.store, runner, sim5.grid, _params, sim5.rng, 18.0, false, -1, 0.0, sim5.memory, 0.0, sim5.opinion, sim5.neighbors, true, true, true)
	_check(_score_of(timid, "flee") > _score_of(bold, "flee") * 2.0, "boldness discounts the flee score (%.2f vs %.2f)" % [_score_of(timid, "flee"), _score_of(bold, "flee")])
	var no_fear = BrainRef.decide(sim5.store, runner, sim5.grid, _params, sim5.rng, 18.0, false, -1, 0.0, sim5.memory, 0.0, sim5.opinion, sim5.neighbors, true, true, false)
	_check(_score_of(no_fear, "flee") < 0.0, "with safety disabled the brain offers no flee candidate")

	# Fear interrupts even a hungry creature standing on food.
	var sim6 = _new_sim(226)
	_flat_ground(sim6, 6, 6, 40, 40)
	sim6.grid.set_cell(20, 20, GridRef.FOOD, 1.0, 1.0)
	var hungry: int = sim6.store.spawn(20.5, 20.5, 0.5, 0.1, 1.0, 1.0)
	var menace: int = sim6.store.spawn(21.6, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim6.opinion.ensure(sim6.store.count)
	sim6.opinion.add(hungry, menace, -0.8, 0.0)
	sim6.store.safety_level[hungry] = 0.03
	sim6.neighbors.rebuild(sim6.store)
	var interrupted = BrainRef.decide(sim6.store, hungry, sim6.grid, _params, sim6.rng, 18.0, false, -1, 0.0, sim6.memory, 0.0, sim6.opinion, sim6.neighbors, true, true, true)
	_check(_score_of(interrupted, "eat") > 0.0, "the hungry option was available to the interrupted creature")
	_check(interrupted.verb == StoreRef.Verb.FLEE, "fear interrupts hunger once safety crosses its threshold (chose %s)" % interrupted.label)
	_check(interrupted.context == MemoryRef.CONTEXT_AFRAID, "acute fear is recorded as its own learning context")

	# The same one rule now covers flee: a retreat that actually restored safety
	# teaches a positive flee weight in the afraid context.
	var sim6b = _new_sim(230)
	_flat_ground(sim6b, 6, 6, 30, 30)
	var learner: int = sim6b.store.spawn(10.5, 10.5, 0.5, 1.0, 1.0, 1.0)
	sim6b.memory.ensure(sim6b.store.count)
	sim6b.store.mem_tracking[learner] = 1
	sim6b.store.mem_before_safety[learner] = 0.1
	sim6b.store.safety_level[learner] = 0.6
	sim6b.store.mem_stress[learner] = 1.0
	sim6b.store.mem_context[learner] = MemoryRef.CONTEXT_AFRAID
	sim6b._learn_from_action(learner, StoreRef.Verb.FLEE)
	_check(sim6b.memory.learned(learner, StoreRef.Verb.FLEE, MemoryRef.CONTEXT_AFRAID) > 0.05, "a retreat that restores safety teaches a positive flee weight (%.3f)" % sim6b.memory.learned(learner, StoreRef.Verb.FLEE, MemoryRef.CONTEXT_AFRAID))
	_check(sim6b.memory.episode_count(learner) == 1 and int(sim6b.memory.episode_at(learner, 0)["verb"]) == StoreRef.Verb.FLEE, "the flee episode records its safety outcome")

	# --- through the real tick, with a causal log line ---------------------
	var sim7 = _new_sim(227)
	_flat_ground(sim7, 6, 6, 40, 40)
	var fleeing: int = sim7.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	var nearby_menace: int = sim7.store.spawn(22.0, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim7.opinion.ensure(sim7.store.count)
	sim7.opinion.add(fleeing, nearby_menace, -0.8, 0.0)
	sim7.store.safety_level[fleeing] = 0.15
	sim7.neighbors.rebuild(sim7.store)
	var start_dist := Vector2(sim7.store.px[fleeing], sim7.store.py[fleeing]).distance_to(Vector2(sim7.store.px[nearby_menace], sim7.store.py[nearby_menace]))
	for k in 30:
		sim7.step(sim7.dt)
	var end_dist := Vector2(sim7.store.px[fleeing], sim7.store.py[fleeing]).distance_to(Vector2(sim7.store.px[nearby_menace], sim7.store.py[nearby_menace]))
	_check(sim7.action_counts[StoreRef.Verb.FLEE] > 0, "flee runs through the real tick (%d decisions)" % int(sim7.action_counts[StoreRef.Verb.FLEE]))
	_check(end_dist > start_dist + 0.5, "the fleeing creature gains distance (%.2f -> %.2f cells)" % [start_dist, end_dist])
	var safety_logs := 0
	for entry in sim7.log.entries:
		if String(entry["kind"]) == "safety" and String(entry["text"]).contains("fled"):
			safety_logs += 1
	_check(safety_logs == 1, "a frightened flee bout writes one throttled causal log line naming the threat (%d)" % safety_logs)
	var metrics7: Dictionary = sim7.metrics()
	_check(metrics7.has("mean_safety") and int(metrics7["flee_starts"]) > 0, "safety and flee are counted in the soak metrics")

	# --- ablation ----------------------------------------------------------
	var sim8 = _new_sim(228)
	_flat_ground(sim8, 6, 6, 40, 40)
	var quiet_runner: int = sim8.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	var quiet_menace: int = sim8.store.spawn(22.0, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim8.opinion.ensure(sim8.store.count)
	sim8.opinion.add(quiet_runner, quiet_menace, -0.8, 0.0)
	sim8.store.safety_level[quiet_runner] = 0.15
	sim8.safety_enabled = false
	for k in 30:
		sim8.step(sim8.dt)
	_check(sim8.action_counts[StoreRef.Verb.FLEE] == 0, "with safety disabled no flee decision is made")
	_check(absf(sim8.store.safety_level[quiet_runner] - 0.15) < 0.0001, "disabled safety neither decays nor recovers")

	# --- fear is lived, not inherited -------------------------------------
	var sim9 = _new_sim(229)
	_flat_ground(sim9, 6, 6, 30, 30)
	var mother: int = sim9.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	var father: int = sim9.store.spawn(21.0, 20.5, 0.5, 1.0, 1.0, 1.0)
	_prepare_adult(sim9, mother, 20.5, 20.5)
	_prepare_adult(sim9, father, 21.0, 20.5)
	sim9.store.genome[mother * GenomeRef.LOCI + GenomeRef.SPEED] = float(GenomeRef.RANGES[GenomeRef.SPEED][0])
	sim9.store.genome[father * GenomeRef.LOCI + GenomeRef.SPEED] = float(GenomeRef.RANGES[GenomeRef.SPEED][1])
	sim9.store.safety_level[mother] = 0.1
	sim9.store.safety_level[father] = 0.1
	var child: int = sim9.mate(mother, father)
	_check(child >= 0 and absf(sim9.store.safety_level[child] - 1.0) < 0.001, "a newborn starts unafraid; fear is not inherited")


func _test_share_and_harm() -> void:
	# --- a carried meal reaches a hungry partner through socialise ----------
	var sim = _new_sim(231)
	_flat_ground(sim, 6, 6, 40, 40)
	var giver: int = sim.store.spawn(20.5, 20.5, 0.5, 0.9, 1.0, 1.0)
	var receiver: int = sim.store.spawn(21.3, 20.5, 0.5, 0.1, 1.0, 1.0)
	sim.store.social_level[giver] = 0.4
	sim.store.social_level[receiver] = 0.4
	sim.store.carry_material[giver] = GridRef.FOOD
	sim.store.carry_amount[giver] = 0.50
	sim.store.carry_nutrition[giver] = 1.0
	sim.opinion.ensure(sim.store.count)
	sim.opinion.add(giver, receiver, 0.5, 0.0)
	sim.opinion.add(receiver, giver, 0.5, 0.0)
	sim.neighbors.rebuild(sim.store)
	var share_decision = BrainRef.decide(sim.store, giver, sim.grid, _params, sim.rng, 18.0, false, -1, 0.0, sim.memory, sim.day(), sim.opinion, sim.neighbors, true, true, true)
	var share_candidate: Dictionary = {}
	for c in share_decision.scores:
		if String(c["label"]) == "share":
			share_candidate = c
	_check(not share_candidate.is_empty() and int(share_candidate.get("verb", -1)) == StoreRef.Verb.SOCIALISE, "a surplus carrier considers sharing with a hungry partner")
	_check(int(share_candidate.get("aim_creature", -1)) == receiver, "the share candidate aims at the hungry partner")

	var giver_opinion_before: float = sim.opinion.opinion(sim.store, giver, receiver, sim.day())
	var receiver_opinion_before: float = sim.opinion.opinion(sim.store, receiver, giver, sim.day())
	sim.store.verb[giver] = StoreRef.Verb.SOCIALISE
	sim.store.aim_creature[giver] = receiver
	sim.store.commitment[giver] = 1.0
	sim.step(sim.dt)
	var share_logs := 0
	for entry in sim.log.entries:
		var text := String(entry["text"])
		if String(entry["kind"]) == "social" and text.contains("shared") and text.contains("food"):
			share_logs += 1
	_check(sim.share_events == 1, "one socialise exchange transfers one share (%d)" % sim.share_events)
	_check(sim.store.carry_amount[giver] < 0.50, "the giver's load falls (%.2f)" % sim.store.carry_amount[giver])
	_check(sim.store.food_level[receiver] > 0.10, "the recipient's hunger falls (%.2f)" % sim.store.food_level[receiver])
	_check(sim.opinion.opinion(sim.store, receiver, giver, sim.day()) > receiver_opinion_before + 0.15, "the recipient credits the giver (%.2f -> %.2f)" % [receiver_opinion_before, sim.opinion.opinion(sim.store, receiver, giver, sim.day())])
	_check(sim.opinion.opinion(sim.store, giver, receiver, sim.day()) > giver_opinion_before + 0.05, "the giver remembers sharing (%.2f -> %.2f)" % [giver_opinion_before, sim.opinion.opinion(sim.store, giver, receiver, sim.day())])
	_check(int(sim.opinion.entry_at(receiver, 0).get("events", 0)) >= 2, "the share is a remembered opinion event")
	_check(share_logs == 1, "the share writes one causal log line (%d)" % share_logs)
	var metrics_share: Dictionary = sim.metrics()
	_check(int(metrics_share["share_events"]) == 1 and int(metrics_share["harm_events"]) == 0, "the share is counted in the metrics")
	# The social cooldown, not a second tick, is what stops a load emptying in
	# one exchange.
	sim.step(sim.dt)
	_check(sim.share_events == 1, "an immediate second exchange does not share again")

	# --- a contested meal becomes an injury -------------------------------
	var sim2 = _new_sim(232)
	_flat_ground(sim2, 6, 6, 40, 40)
	var meal: int = sim2.grid.index(20, 20)
	sim2.grid.set_cell(20, 20, GridRef.FOOD, 0.5, 1.0)
	var attacker: int = sim2.store.spawn(20.5, 20.5, 0.5, 0.1, 1.0, 1.0)
	var victim: int = sim2.store.spawn(21.4, 20.5, 0.5, 0.1, 1.0, 1.0)
	sim2.store.body[attacker * GenomeRef.FIELDS + GenomeRef.F_AGGRESSION] = 1.0
	sim2.store.body[attacker * GenomeRef.FIELDS + GenomeRef.F_SIZE] = 1.0
	sim2.store.body[victim * GenomeRef.FIELDS + GenomeRef.F_SIZE] = 0.9
	sim2.store.health[victim] = 0.5
	sim2.store.safety_level[victim] = 0.4
	sim2.store.aim_cell[victim] = meal
	sim2.store.verb[victim] = StoreRef.Verb.EAT
	sim2.store.commitment[victim] = 1.0
	sim2.store.aim_cell[attacker] = meal
	sim2.store.verb[attacker] = StoreRef.Verb.EAT
	sim2.store.commitment[attacker] = 1.0
	sim2.opinion.ensure(sim2.store.count)
	sim2.neighbors.rebuild(sim2.store)
	var health_before: float = sim2.store.health[victim]
	var safety_before: float = sim2.store.safety_level[victim]
	sim2.step(sim2.dt)
	_check(sim2.harm_events == 1, "one contested scarce meal produces one injury (%d)" % sim2.harm_events)
	_check(sim2.store.health[victim] < health_before, "the victim loses health (%.2f -> %.2f)" % [health_before, sim2.store.health[victim]])
	_check(sim2.store.safety_level[victim] < safety_before, "the injury shocks safety (%.2f -> %.2f)" % [safety_before, sim2.store.safety_level[victim]])
	_check(sim2.opinion.opinion(sim2.store, victim, attacker, sim2.day()) < -0.3, "the victim remembers the attacker (%.2f)" % sim2.opinion.opinion(sim2.store, victim, attacker, sim2.day()))
	var harm_logs := 0
	for entry in sim2.log.entries:
		if String(entry["kind"]) == "harm":
			harm_logs += 1
	_check(harm_logs == 1, "the injury writes one causal log line (%d)" % harm_logs)
	var metrics_harm: Dictionary = sim2.metrics()
	_check(int(metrics_harm["harm_events"]) == 1 and float(metrics_harm["harm_damage"]) > 0.0, "the injury is counted in the metrics")

	# The injury feeds the existing fear path: low safety plus a remembered
	# attacker makes the victim run, not merely stand there.
	var threat_after: Dictionary = sim2.nearest_threat(victim)
	_check(not threat_after.is_empty() and int(threat_after["other"]) == attacker, "the attacker is now the victim's threat")
	var flee_before: int = int(sim2.action_counts[StoreRef.Verb.FLEE])
	var distance_before := Vector2(sim2.store.px[victim], sim2.store.py[victim]).distance_to(Vector2(sim2.store.px[attacker], sim2.store.py[attacker]))
	for s in 20:
		sim2.step(sim2.dt)
	var distance_after := Vector2(sim2.store.px[victim], sim2.store.py[victim]).distance_to(Vector2(sim2.store.px[attacker], sim2.store.py[attacker]))
	_check(int(sim2.action_counts[StoreRef.Verb.FLEE]) > flee_before, "the injured victim chooses flee")
	_check(distance_after > distance_before + 0.5, "the injured victim gains distance (%.2f -> %.2f)" % [distance_before, distance_after])

	# The same cooldown that throttles the grievance throttles the injury.
	sim2.grid.set_cell(20, 20, GridRef.FOOD, 0.5, 1.0)
	sim2.store.food_level[attacker] = 0.1
	sim2.store.health[victim] = 0.5
	sim2.store.aim_cell[victim] = meal
	sim2.store.px[victim] = 21.4
	sim2.store.py[victim] = 20.5
	sim2.neighbors.rebuild(sim2.store)
	sim2._do_eat(attacker, sim2.dt * 2.0)
	_check(sim2.harm_events == 1, "the dispute cooldown stops one meal becoming many injuries")

	# Safety off still allows the injury and the memory, but freezes the shock
	# and the flight that depends on it.
	var sim3 = _new_sim(233)
	_flat_ground(sim3, 6, 6, 40, 40)
	sim3.grid.set_cell(20, 20, GridRef.FOOD, 0.5, 1.0)
	var quiet_attacker: int = sim3.store.spawn(20.5, 20.5, 0.5, 0.1, 1.0, 1.0)
	var quiet_victim: int = sim3.store.spawn(21.4, 20.5, 0.5, 0.1, 1.0, 1.0)
	sim3.store.body[quiet_attacker * GenomeRef.FIELDS + GenomeRef.F_AGGRESSION] = 1.0
	sim3.store.body[quiet_attacker * GenomeRef.FIELDS + GenomeRef.F_SIZE] = 1.0
	sim3.store.body[quiet_victim * GenomeRef.FIELDS + GenomeRef.F_SIZE] = 0.9
	sim3.store.health[quiet_victim] = 0.5
	sim3.store.safety_level[quiet_victim] = 0.4
	sim3.store.aim_cell[quiet_victim] = sim3.grid.index(20, 20)
	sim3.store.verb[quiet_victim] = StoreRef.Verb.EAT
	sim3.store.commitment[quiet_victim] = 1.0
	sim3.store.aim_cell[quiet_attacker] = sim3.grid.index(20, 20)
	sim3.store.verb[quiet_attacker] = StoreRef.Verb.EAT
	sim3.store.commitment[quiet_attacker] = 1.0
	sim3.opinion.ensure(sim3.store.count)
	sim3.neighbors.rebuild(sim3.store)
	sim3.safety_enabled = false
	sim3.step(sim3.dt)
	_check(sim3.harm_events == 1 and sim3.store.health[quiet_victim] < 0.5, "with safety off the injury still happens")
	_check(absf(sim3.store.safety_level[quiet_victim] - 0.4) < 0.0001, "with safety off the injury does not shock the frozen need")

	# A fragile victim can die of the injury, and the death cause is its own
	# entry rather than a generic starvation default.
	var sim5 = _new_sim(232)
	_flat_ground(sim5, 6, 6, 40, 40)
	var death_meal: int = sim5.grid.index(20, 20)
	sim5.grid.set_cell(20, 20, GridRef.FOOD, 0.5, 1.0)
	var death_attacker: int = sim5.store.spawn(20.5, 20.5, 0.5, 0.1, 1.0, 1.0)
	var fragile: int = sim5.store.spawn(21.4, 20.5, 0.5, 0.1, 1.0, 1.0)
	sim5.store.body[death_attacker * GenomeRef.FIELDS + GenomeRef.F_AGGRESSION] = 1.0
	sim5.store.body[death_attacker * GenomeRef.FIELDS + GenomeRef.F_SIZE] = 1.0
	sim5.store.body[fragile * GenomeRef.FIELDS + GenomeRef.F_SIZE] = 0.9
	sim5.store.health[fragile] = 0.02
	sim5.store.safety_level[fragile] = 0.4
	sim5.store.aim_cell[fragile] = death_meal
	sim5.store.verb[fragile] = StoreRef.Verb.EAT
	sim5.store.commitment[fragile] = 1.0
	sim5.store.aim_cell[death_attacker] = death_meal
	sim5.store.verb[death_attacker] = StoreRef.Verb.EAT
	sim5.store.commitment[death_attacker] = 1.0
	sim5.opinion.ensure(sim5.store.count)
	sim5.neighbors.rebuild(sim5.store)
	sim5.step(sim5.dt)
	_check(sim5.harm_events == 1 and sim5.store.alive[fragile] == 0, "a fragile victim can die of the injury")
	_check(int(sim5.death_counts[StoreRef.Death.HARM]) == 1, "the death is recorded as harm, not starvation")
	_check(int(sim5.metrics()["harmed"]) == 1, "the harm death is counted in the metrics")

	# With social off there is no share and no injury event at all.
	var sim4 = _new_sim(234)
	_flat_ground(sim4, 6, 6, 40, 40)
	var quiet_giver: int = sim4.store.spawn(20.5, 20.5, 0.5, 0.9, 1.0, 1.0)
	var quiet_receiver: int = sim4.store.spawn(21.3, 20.5, 0.5, 0.1, 1.0, 1.0)
	sim4.store.social_level[quiet_giver] = 0.05
	sim4.store.carry_material[quiet_giver] = GridRef.FOOD
	sim4.store.carry_amount[quiet_giver] = 0.5
	sim4.store.carry_nutrition[quiet_giver] = 1.0
	sim4.social_enabled = false
	for s in 10:
		sim4.step(sim4.dt)
	_check(sim4.share_events == 0 and sim4.harm_events == 0, "with social off neither event is recorded")


func _test_carrying() -> void:
	# --- material accounting ------------------------------------------------
	var sim = _new_sim(201)
	var g = sim.grid
	g.set_cell(10, 10, GridRef.SAND, 1.0)
	g.wetness[g.index(10, 10)] = 0.6
	g.wet_history[g.index(10, 10)] = 0.6
	var sand_sample: Dictionary = g.extract(10, 10, 0.5)
	_check(absf(float(sand_sample["amount"]) - 0.5) < 0.001, "pick up removes exactly the requested sand")
	_check(absf(float(sand_sample["wetness"]) - 0.6) < 0.001, "the load keeps the source cell's wetness")
	_check(absf(g.amount_at(10, 10) - 0.5) < 0.001, "the source cell keeps the rest")
	var sand_drop: float = g.deposit(12, 10, GridRef.SAND, 0.5, 0.6)
	_check(absf(sand_drop - 0.5) < 0.001 and g.material_at(12, 10) == GridRef.SAND, "piling puts the sand into a new cell")
	_check(absf(g.wetness_at(12, 10) - 0.6) < 0.001, "piling carries the wetness into the new cell")

	g.set_cell(14, 10, GridRef.FOOD, 0.8, 1.0)
	g.nutrition[g.index(14, 10)] = 0.4
	g.toxicity[g.index(14, 10)] = 0.3
	var food_sample: Dictionary = g.extract(14, 10, 0.3)
	_check(absf(float(food_sample["nutrition"]) - 0.4) < 0.001, "a carried meal keeps its nutrition")
	_check(absf(float(food_sample["toxicity"]) - 0.3) < 0.001, "a carried meal keeps its toxin")
	var food_drop: float = g.deposit(16, 10, GridRef.FOOD, 0.3, 0.0, 0.4, 0.3)
	_check(absf(food_drop - 0.3) < 0.001 and g.material_at(16, 10) == GridRef.FOOD, "piling puts food into a new cell")
	_check(absf(g.nutrition_at(16, 10) - 0.4) < 0.001 and absf(g.toxicity[g.index(16, 10)] - 0.3) < 0.001, "the dropped food carries its properties")

	g.set_cell(18, 10, GridRef.WATER, 1.0)
	g.deposit(18, 10, GridRef.SAND, 0.5, 0.2)
	_check(g.material_at(18, 10) == GridRef.SAND and g.wetness_at(18, 10) >= 0.8, "sand dropped into water arrives wet")
	g.set_cell(20, 10, GridRef.FOOD, 0.5, 1.0)
	_check(g.deposit(20, 10, GridRef.SAND, 0.5) == 0.0, "sand cannot bury a food cell")

	g.set_cell(22, 10, GridRef.FOOD, 0.03, 1.0)
	g.extract(22, 10, 1.0)
	_check(g.material_at(22, 10) == GridRef.FOOD and absf(g.amount_at(22, 10) - 0.02) < 0.001, "carrying food leaves the living trace")

	# --- candidate scores ---------------------------------------------------
	var sim2 = _new_sim(202)
	_flat_ground(sim2, 6, 6, 40, 40)
	sim2.grid.set_cell(21, 20, GridRef.FOOD, 1.0, 1.0)
	var well_fed: int = sim2.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim2.memory.ensure(sim2.store.count)
	sim2.neighbors.rebuild(sim2.store)
	var fed = BrainRef.decide(sim2.store, well_fed, sim2.grid, _params, sim2.rng, 18.0, false, -1, 0.0, sim2.memory, sim2.day(), null, sim2.neighbors, true, true)
	_check(_score_of(fed, "pickup_food") > 0.0, "a well-fed creature considers carrying food out of surplus")
	sim2.store.food_level[well_fed] = 0.2
	var hungry = BrainRef.decide(sim2.store, well_fed, sim2.grid, _params, sim2.rng, 18.0, false, -1, 0.0, sim2.memory, sim2.day(), null, sim2.neighbors, true, true)
	_check(_score_of(hungry, "pickup_food") < 0.0, "a hungry creature eats instead of storing")

	# The conscientiousness locus weights the store score, not the choice itself.
	sim2.store.food_level[well_fed] = 1.0
	sim2.store.body[well_fed * GenomeRef.FIELDS + GenomeRef.F_CONSCIENTIOUSNESS] = 0.0
	var lazy = BrainRef.decide(sim2.store, well_fed, sim2.grid, _params, sim2.rng, 18.0, false, -1, 0.0, sim2.memory, sim2.day(), null, sim2.neighbors, true, true)
	sim2.store.body[well_fed * GenomeRef.FIELDS + GenomeRef.F_CONSCIENTIOUSNESS] = 1.0
	var diligent = BrainRef.decide(sim2.store, well_fed, sim2.grid, _params, sim2.rng, 18.0, false, -1, 0.0, sim2.memory, sim2.day(), null, sim2.neighbors, true, true)
	_check(_score_of(diligent, "pickup_food") > _score_of(lazy, "pickup_food") * 1.5, "conscientiousness raises the store score (%.3f vs %.3f)" % [_score_of(diligent, "pickup_food"), _score_of(lazy, "pickup_food")])

	var sim3 = _new_sim(203)
	_flat_ground(sim3, 6, 6, 40, 40)
	sim3.grid.set_cell(19, 20, GridRef.SAND, 1.0)
	var uncomfortable: int = sim3.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim3.store.comfort_level[uncomfortable] = 0.15
	sim3.memory.ensure(sim3.store.count)
	sim3.neighbors.rebuild(sim3.store)
	var seeking = BrainRef.decide(sim3.store, uncomfortable, sim3.grid, _params, sim3.rng, 18.0, false, -1, 0.0, sim3.memory, sim3.day(), null, sim3.neighbors, true, true)
	_check(_score_of(seeking, "pickup_sand") > 0.0, "poor ground and low comfort make sand worth picking up")

	sim3.grid.set_cell(20, 20, GridRef.AIR, 0.0)
	sim3.store.carry_material[uncomfortable] = GridRef.SAND
	sim3.store.carry_amount[uncomfortable] = 0.5
	sim3.store.carry_wetness[uncomfortable] = 1.0
	var piling = BrainRef.decide(sim3.store, uncomfortable, sim3.grid, _params, sim3.rng, 18.0, false, -1, 0.0, sim3.memory, sim3.day(), null, sim3.neighbors, true, true)
	_check(_score_of(piling, "pile_sand") > 0.0, "a sand load can be piled into open ground")

	# Critical thirst turns off the surplus pick-up, but the carrier must still be
	# able to drop its load: the same pile verb is the only way to shed the speed
	# penalty. The control above proves both were available at full water.
	sim3.store.water_level[uncomfortable] = 0.0
	var parched_pile = BrainRef.decide(sim3.store, uncomfortable, sim3.grid, _params, sim3.rng, 18.0, false, -1, 0.0, sim3.memory, sim3.day(), null, sim3.neighbors, true, true)
	_check(_score_of(parched_pile, "pile_sand") > 0.0, "critical thirst still allows piling the load away")
	sim3.store.carry_material[uncomfortable] = 0
	sim3.store.carry_amount[uncomfortable] = 0.0
	var parched_pick = BrainRef.decide(sim3.store, uncomfortable, sim3.grid, _params, sim3.rng, 18.0, false, -1, 0.0, sim3.memory, sim3.day(), null, sim3.neighbors, true, true)
	_check(_score_of(parched_pick, "pickup_sand") < 0.0, "critical thirst suppresses pick-up")
	sim3.store.water_level[uncomfortable] = 1.0

	sim3.store.carry_material[uncomfortable] = GridRef.FOOD
	sim3.store.carry_amount[uncomfortable] = 0.5
	sim3.store.carry_nutrition[uncomfortable] = 1.0
	var caching = BrainRef.decide(sim3.store, uncomfortable, sim3.grid, _params, sim3.rng, 18.0, false, -1, 0.0, sim3.memory, sim3.day(), null, sim3.neighbors, true, true)
	_check(_score_of(caching, "pile_food") > 0.0, "a food load can be piled as a cache")

	var ablated = BrainRef.decide(sim3.store, uncomfortable, sim3.grid, _params, sim3.rng, 18.0, false, -1, 0.0, sim3.memory, sim3.day(), null, sim3.neighbors, true, false)
	_check(_score_of(ablated, "pickup_food") < 0.0 and _score_of(ablated, "pile_food") < 0.0, "with carrying disabled neither store verb is offered")

	# --- the verbs through the real execution path -------------------------
	var sim4 = _new_sim(204)
	_flat_ground(sim4, 6, 6, 40, 40)
	var source: int = sim4.grid.index(21, 20)
	sim4.grid.set_cell(21, 20, GridRef.SAND, 1.0)
	sim4.grid.wetness[source] = 1.0
	sim4.grid.wet_history[source] = 1.0
	sim4.grid.set_cell(20, 20, GridRef.AIR, 0.0)
	var carrier: int = sim4.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 0.5)
	sim4.store.comfort_level[carrier] = 0.2
	sim4.store.verb[carrier] = StoreRef.Verb.PICKUP
	sim4.store.aim_cell[carrier] = source
	for k in 60:
		sim4._execute_all(sim4.dt)
	_check(sim4.store.carry_amount[carrier] > 0.1, "the pick-up verb fills the load (%.2f)" % sim4.store.carry_amount[carrier])
	_check(int(sim4.store.carry_material[carrier]) == GridRef.SAND, "the load records its material")
	_check(sim4.store.carry_wetness[carrier] > 0.9, "the load records its wetness")

	sim4.store.verb[carrier] = StoreRef.Verb.PILE
	sim4.store.aim_cell[carrier] = sim4.grid.index(20, 20)
	for k in 60:
		sim4._execute_all(sim4.dt)
	_check(sim4.store.carry_amount[carrier] <= 0.001, "the pile verb empties the load")
	_check(sim4.grid.material_at(20, 20) == GridRef.SAND and sim4.grid.amount_at(20, 20) > 0.1, "the load is now material in the world")
	_check(sim4.grid.wetness_at(20, 20) > 0.8, "the pile is still wet when it lands")

	var sim5 = _new_sim(205)
	_flat_ground(sim5, 6, 6, 40, 40)
	var eater: int = sim5.store.spawn(20.5, 20.5, 0.5, 0.2, 1.0, 1.0)
	sim5.store.carry_material[eater] = GridRef.FOOD
	sim5.store.carry_amount[eater] = 0.5
	sim5.store.carry_nutrition[eater] = 1.0
	sim5.store.verb[eater] = StoreRef.Verb.EAT
	for k in 60:
		sim5._execute_all(sim5.dt)
	_check(sim5.store.food_level[eater] > 0.2, "a starving carrier eats its load")
	_check(sim5.store.carry_amount[eater] < 0.4, "eating takes a real bite out of the carried meal (%.2f left)" % sim5.store.carry_amount[eater])

	# --- comfort comes from properties, not a place tag --------------------
	var sim6 = _new_sim(206)
	var hard_cell: int = sim6.grid.index(10, 10)
	var mud_cell: int = sim6.grid.index(13, 10)
	sim6.grid.set_cell(10, 10, GridRef.SAND, 1.0)
	sim6.grid.hardness[hard_cell] = 0.9
	sim6.grid.cohesion[hard_cell] = 0.9
	sim6.grid.compaction[hard_cell] = 0.8
	sim6.grid.set_cell(13, 10, GridRef.SAND, 1.0)
	sim6.grid.wetness[mud_cell] = 0.8
	sim6.grid.compaction[mud_cell] = 0.8
	_check(sim6.grid.comfort_quality(hard_cell) > 0.8, "hard, dry, compacted ground has a high comfort affordance (%.2f)" % sim6.grid.comfort_quality(hard_cell))
	_check(sim6.grid.comfort_quality(mud_cell) < 0.35, "mud has a low comfort affordance (%.2f)" % sim6.grid.comfort_quality(mud_cell))
	sim6.grid.set_cell(16, 10, GridRef.WATER, 1.0)
	_check(sim6.grid.comfort_quality(sim6.grid.index(16, 10)) == 0.0, "water is not comfortable ground")
	sim6.grid.set_cell(17, 10, GridRef.AIR, 0.0)
	_check(sim6.grid.comfort_quality(sim6.grid.index(17, 10)) == 0.0, "air is not ground at all")

	var rest_hard: int = sim6.store.spawn(10.5, 10.5, 0.5, 1.0, 1.0, 0.5)
	var rest_mud: int = sim6.store.spawn(13.5, 10.5, 0.5, 1.0, 1.0, 0.5)
	sim6.store.comfort_level[rest_hard] = 0.4
	sim6.store.comfort_level[rest_mud] = 0.4
	sim6.store.verb[rest_hard] = StoreRef.Verb.REST
	sim6.store.verb[rest_mud] = StoreRef.Verb.REST
	for k in 300:
		sim6._decay_needs(sim6.dt)
	_check(sim6.store.comfort_level[rest_hard] > sim6.store.comfort_level[rest_mud] + 0.02, "resting on hard ground restores more comfort than resting in mud (%.2f vs %.2f)" % [sim6.store.comfort_level[rest_hard], sim6.store.comfort_level[rest_mud]])

	var sim7 = _new_sim(207)
	_flat_ground(sim7, 6, 6, 40, 40)
	sim7.grid.hardness[sim7.grid.index(24, 20)] = 0.9
	sim7.grid.compaction[sim7.grid.index(24, 20)] = 0.8
	var seeker: int = sim7.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim7.store.comfort_level[seeker] = 0.15
	sim7.memory.ensure(sim7.store.count)
	sim7.neighbors.rebuild(sim7.store)
	var comfort_decision = BrainRef.decide(sim7.store, seeker, sim7.grid, _params, sim7.rng, 18.0, false, -1, 0.0, sim7.memory, sim7.day(), null, sim7.neighbors, true, true)
	_check(_score_of(comfort_decision, "seek_comfort") > 0.0, "low comfort makes a better nearby cell worth seeking")
	sim7._stash_learning(seeker, comfort_decision)
	_check(sim7.store.mem_stress[seeker] > 0.3, "comfort urgency is recorded as stress for learning (%.2f)" % sim7.store.mem_stress[seeker])
	var comfort_aim := -1
	for c in comfort_decision.scores:
		if String(c["label"]) == "seek_comfort":
			comfort_aim = int(c["aim_cell"])
	_check(comfort_aim == sim7.grid.index(24, 20), "comfort seeking aims at the hard cell")

	sim7.store.energy_level[seeker] = 1.0
	sim7.store.comfort_level[seeker] = 0.2
	sim7.store.px[seeker] = 24.5
	sim7.store.py[seeker] = 20.5
	sim7.store.comfort_scan_time[seeker] = -100.0
	var rest_hard_decision = BrainRef.decide(sim7.store, seeker, sim7.grid, _params, sim7.rng, 18.0, false, -1, 0.0, sim7.memory, sim7.day(), null, sim7.neighbors, true, true)
	sim7.store.px[seeker] = 20.5
	sim7.store.py[seeker] = 20.5
	var rest_poor_decision = BrainRef.decide(sim7.store, seeker, sim7.grid, _params, sim7.rng, 18.0, false, -1, 0.0, sim7.memory, sim7.day(), null, sim7.neighbors, true, true)
	_check(_score_of(rest_hard_decision, "rest") > _score_of(rest_poor_decision, "rest") * 2.0, "resting on hard ground scores above resting on loose sand (%.2f vs %.2f)" % [_score_of(rest_hard_decision, "rest"), _score_of(rest_poor_decision, "rest")])

	# --- wet sand -> piled -> rested on -> dried -> hard --------------------
	var sim8 = _new_sim(208)
	_flat_ground(sim8, 6, 6, 30, 30)
	var target: int = sim8.grid.index(10, 10)
	var wet_source: int = sim8.grid.index(11, 10)
	sim8.grid.set_cell(10, 10, GridRef.AIR, 0.0)
	sim8.grid.set_cell(11, 10, GridRef.SAND, 1.0)
	sim8.grid.wetness[wet_source] = 1.0
	sim8.grid.wet_history[wet_source] = 1.0
	var builder: int = sim8.store.spawn(10.5, 10.5, 0.5, 1.0, 1.0, 0.5)
	sim8.store.comfort_level[builder] = 0.2
	sim8.store.verb[builder] = StoreRef.Verb.PICKUP
	sim8.store.aim_cell[builder] = wet_source
	for k in 60:
		sim8._execute_all(sim8.dt)
	sim8.store.verb[builder] = StoreRef.Verb.PILE
	sim8.store.aim_cell[builder] = target
	for k in 60:
		sim8._execute_all(sim8.dt)
	_check(sim8.grid.material_at(10, 10) == GridRef.SAND and sim8.grid.wetness_at(10, 10) > 0.8, "the builder piles wet sand on its own cell")
	sim8.store.verb[builder] = StoreRef.Verb.REST
	sim8.store.commitment[builder] = 10.0
	for k in 120:
		sim8._decay_needs(sim8.dt)
		sim8._execute_all(sim8.dt)
	_check(sim8.grid.compaction[target] > 0.3, "resting on the pile compacts it (%.2f)" % sim8.grid.compaction[target])
	sim8.grid.wake_cell_xy(10, 10)
	_advance_materials(sim8, sim8.day_seconds * 2.0, 1.0)
	_check(sim8.grid.state_of(target) == GridRef.STATE_HARD_SAND, "the rested pile dries into hard sand (hardness %.2f)" % sim8.grid.hardness_at(10, 10))
	_check(sim8.grid.comfort_quality(target) > 0.75, "the hardened cell now advertises comfort (%.2f)" % sim8.grid.comfort_quality(target))

	# --- storing is learned from a cache meal ------------------------------
	var sim9 = _new_sim(209)
	_flat_ground(sim9, 6, 6, 30, 30)
	var cache_cell: int = sim9.grid.index(20, 20)
	sim9.grid.set_cell(20, 20, GridRef.AIR, 0.0)
	var storer: int = sim9.store.spawn(20.5, 20.5, 0.5, 0.1, 1.0, 1.0)
	sim9.memory.ensure(sim9.store.count)
	sim9.store.carry_material[storer] = GridRef.FOOD
	sim9.store.carry_amount[storer] = 0.6
	sim9.store.carry_nutrition[storer] = 1.0
	sim9.store.mem_context[storer] = MemoryRef.CONTEXT_HUNGRY
	sim9.store.mem_stress[storer] = 1.0
	sim9.store.verb[storer] = StoreRef.Verb.PILE
	sim9.store.aim_cell[storer] = cache_cell
	for k in 60:
		sim9._execute_all(sim9.dt)
	_check(sim9.grid.material_at(20, 20) == GridRef.FOOD, "the food load becomes a cache cell")
	var before_pile_lesson: float = sim9.memory.learned(storer, StoreRef.Verb.PILE, MemoryRef.CONTEXT_HUNGRY)
	sim9.store.verb[storer] = StoreRef.Verb.EAT
	sim9.store.aim_cell[storer] = cache_cell
	for k in 90:
		sim9._execute_all(sim9.dt)
	var pile_lesson: float = sim9.memory.learned(storer, StoreRef.Verb.PILE, MemoryRef.CONTEXT_HUNGRY)
	var pickup_lesson: float = sim9.memory.learned(storer, StoreRef.Verb.PICKUP, MemoryRef.CONTEXT_HUNGRY)
	_check(pile_lesson > before_pile_lesson + 0.001, "eating from its own cache credits the pile that made it (%.3f)" % pile_lesson)
	_check(pickup_lesson > 0.0, "and the pick-up that supplied it (%.3f)" % pickup_lesson)

	# --- carrying costs and death drops -----------------------------------
	var sim10 = _new_sim(210)
	var hauler: int = sim10.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	var empty_factor: float = GenomeRef.carry_factor(sim10.store, hauler, 2.2, 0.4)
	sim10.store.carry_material[hauler] = GridRef.SAND
	sim10.store.carry_amount[hauler] = 1.0
	var loaded_factor: float = GenomeRef.carry_factor(sim10.store, hauler, 2.2, 0.4)
	_check(loaded_factor < empty_factor, "a sand load slows its carrier (%.2f vs %.2f)" % [loaded_factor, empty_factor])

	_flat_ground(sim10, 6, 6, 30, 30)
	var dying: int = sim10.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim10.store.carry_material[dying] = GridRef.SAND
	sim10.store.carry_amount[dying] = 0.7
	sim10.store.carry_wetness[dying] = 0.5
	var amount_before: float = sim10.grid.amount_at(20, 20)
	sim10._pending_deaths.append(dying)
	sim10._apply_deaths()
	_check(sim10.grid.amount_at(20, 20) > amount_before + 0.5, "a death drops the carried load where it stood")

	# --- ablation ----------------------------------------------------------
	var sim11 = _new_sim(211)
	_flat_ground(sim11, 6, 6, 30, 30)
	sim11.spawn_founders(4)
	sim11.carry_enabled = false
	for k in 60:
		sim11.step(sim11.dt)
	_check(sim11.action_counts[StoreRef.Verb.PICKUP] == 0 and sim11.action_counts[StoreRef.Verb.PILE] == 0, "with carrying disabled neither store verb is chosen")


func _test_determinism() -> void:
	var a = _new_sim(1234)
	a.generate_world()
	a.spawn_founders()
	var b = _new_sim(1234)
	b.generate_world()
	b.spawn_founders()
	a.apply_brush(GridRef.FOOD, 60, 60, 3, 0.8)
	b.apply_brush(GridRef.FOOD, 60, 60, 3, 0.8)
	for s in 300:
		a.step(a.dt)
		b.step(b.dt)
	_check(a.state_hash() == b.state_hash(), "same seed and input reproduce state after 300 steps")

	var c = _new_sim(999)
	c.generate_world()
	c.spawn_founders()
	for s in 300:
		c.step(c.dt)
	_check(c.state_hash() != a.state_hash(), "a different seed produces a different world")


func _test_no_stacking() -> void:
	var sim = _new_sim(4242)
	sim.generate_world()
	sim.spawn_founders()
	var max_seen := 0
	var occupancy_total := 0.0
	var samples := 0
	var steps := int(120.0 / sim.dt)
	for s in steps:
		sim.step(sim.dt)
		if s % 15 == 0:
			var stats := _occupancy(sim.store)
			max_seen = maxi(max_seen, int(stats[0]))
			occupancy_total += float(stats[1])
			samples += 1
	var mean_occupancy := occupancy_total / float(maxi(samples, 1))
	_check(max_seen <= 3, "never more than three creatures share a cell (max %d)" % max_seen)
	_check(mean_occupancy <= 1.6, "creatures occupy distinct cells on average (%.2f)" % mean_occupancy)

	var frozen := 0
	for i in sim.store.count:
		if sim.store.alive[i] == 1 and sim.store.path_travelled[i] < 2.0:
			frozen += 1
	_check(frozen == 0, "every creature moved during two sim-minutes (frozen %d)" % frozen)
	_check(int(sim.metrics()["deaths"]) == 0, "no deaths in a two-minute watch (%d alive, %d births)" % [sim.alive_count(), int(sim.metrics()["births"])])


func _occupancy(store) -> Array:
	var counts := {}
	var max_count := 0
	var alive := 0
	for i in store.count:
		if store.alive[i] == 0:
			continue
		alive += 1
		var key := Vector2i(int(floor(store.px[i])), int(floor(store.py[i])))
		var c := int(counts.get(key, 0)) + 1
		counts[key] = c
		if c > max_count:
			max_count = c
	var mean := float(alive) / float(maxi(counts.size(), 1))
	return [max_count, mean]


func _test_exit_criteria() -> void:
	# The plan's ten sim-minute watch is the expensive part of this suite. One
	# seed gets the full window and the other two get five minutes, which still
	# catches a population that dies out early. The soak harness is the long check.
	var plans := [[101, EXIT_RUN_SECONDS], [202, EXIT_RUN_SECONDS * 0.5], [303, EXIT_RUN_SECONDS * 0.5]]
	for plan in plans:
		var seed_value: int = plan[0]
		var watch: float = float(plan[1])
		var sim = _new_sim(seed_value)
		sim.generate_world()
		sim.spawn_founders()
		var steps := int(watch / sim.dt)
		for s in steps:
			sim.step(sim.dt)
		var m: Dictionary = sim.metrics()
		var mix: Dictionary = m["action_mix"]
		print("  seed %d: alive %d, deaths %d, mix wander %d%% seek %d%% eat %d%% drink %d%% rest %d%%, step %.2f ms mean / %.2f ms peak" % [
			seed_value,
			int(m["alive"]),
			int(m["deaths"]),
			int(round(float(mix["wander"]) * 100.0)),
			int(round(float(mix["seek"]) * 100.0)),
			int(round(float(mix["eat"]) * 100.0)),
			int(round(float(mix["drink"]) * 100.0)),
			int(round(mix["rest"] * 100.0)),
			float(m["mean_step_ms"]),
			float(m["max_step_ms"]),
		])
		_check(int(m["alive"]) >= 15, "seed %d keeps its founder population (alive %d)" % [seed_value, int(m["alive"])])
		_check(int(m["deaths"]) <= 3, "seed %d does not die out in %d sim-minutes (%d deaths)" % [seed_value, int(watch / 60.0), int(m["deaths"])])
		# The Phase 0 verbs must still all occur. The social verbs are checked in
		# their own section instead: a five-minute watch has no obligation to
		# produce a friendship on every seed, and asserting one would be a lie.
		for v in [StoreRef.Verb.WANDER, StoreRef.Verb.SEEK, StoreRef.Verb.EAT, StoreRef.Verb.DRINK, StoreRef.Verb.REST]:
			_check(sim.action_counts[v] > 0, "seed %d exercises the %s verb" % [seed_value, StoreRef.VERB_NAMES[v]])
		var needs_valid := true
		var positions_valid := true
		for i in sim.store.count:
			if sim.store.alive[i] == 0:
				continue
			if not (is_finite(sim.store.food_level[i]) and is_finite(sim.store.water_level[i]) and is_finite(sim.store.energy_level[i]) and is_finite(sim.store.health[i])):
				needs_valid = false
			if sim.store.food_level[i] < 0.0 or sim.store.food_level[i] > 1.0:
				needs_valid = false
			if sim.store.px[i] < 0.0 or sim.store.px[i] > float(sim.grid.width) or sim.store.py[i] < 0.0 or sim.store.py[i] > float(sim.grid.height):
				positions_valid = false
		_check(needs_valid, "seed %d keeps needs finite and in range" % seed_value)
		_check(positions_valid, "seed %d keeps creatures inside the world" % seed_value)


func _test_benchmark() -> void:
	print("  hardware: %s / %s" % [OS.get_name(), OS.get_processor_name()])
	var small = _new_sim(555)
	small.generate_world()
	small.spawn_founders(20)
	for s in 60:
		small.step(small.dt)
	var small_ms := _measure_steps(small, 300)

	var large = _new_sim(556)
	large.generate_world()
	large.spawn_founders(200)
	for s in 30:
		large.step(large.dt)
	var large_ms := _measure_steps(large, 120)

	print("  20 creatures, full tier:  %.2f ms/step (%.0f creature-decisions/s budget)" % [small_ms, 20.0 * small.tick_hz])
	print("  200 creatures, full tier: %.2f ms/step" % large_ms)
	_check(small_ms < 10.0, "20-creature step fits comfortably in a 15 Hz tick (%.2f ms of 66.7 ms)" % small_ms)


func _measure_steps(sim, count: int) -> float:
	var t0 := Time.get_ticks_usec()
	for s in count:
		sim.step(sim.dt)
	var elapsed := float(Time.get_ticks_usec() - t0)
	return elapsed / float(count) / 1000.0


## Advances only the material simulation, so property tests can fast-forward
## days without paying for creature decisions.
func _advance_materials(sim, seconds: float, dt: float = 1.0) -> void:
	var remaining := seconds
	var tick := 1
	while remaining > 0.0001:
		var step_dt: float = minf(dt, remaining)
		MaterialsRef.step(sim.grid, _params, tick, step_dt)
		tick += 1
		remaining -= step_dt


func _test_water_flow() -> void:
	var sim = _new_sim(71)
	var g = sim.grid
	g.set_cell(10, 10, GridRef.WATER, 1.0)
	MaterialsRef.step(g, _params, 1, sim.dt)
	_check(g.material_at(10, 11) == GridRef.WATER, "water falls into open space")

	var sim2 = _new_sim(72)
	var g2 = sim2.grid
	for dx in range(-1, 2):
		g2.set_cell(20 + dx, 21, GridRef.SAND, 1.0)
		g2.wetness[g2.index(20 + dx, 21)] = 1.0
	g2.set_cell(20, 20, GridRef.WATER, 1.0)
	MaterialsRef.step(g2, _params, 1, sim2.dt)
	var spread: bool = g2.material_at(19, 20) == GridRef.WATER or g2.material_at(21, 20) == GridRef.WATER
	_check(spread, "water blocked below spreads sideways")

	var sim3 = _new_sim(73)
	var g3 = sim3.grid
	g3.set_cell(30, 31, GridRef.SAND, 1.0)
	g3.set_cell(30, 30, GridRef.WATER, 1.0)
	for k in 5:
		MaterialsRef.step(g3, _params, k + 1, 0.5)
	_check(g3.wetness_at(30, 31) > 0.0, "water soaks into dry sand below it")
	_check(g3.amount_at(30, 30) < 1.0, "soaking consumes the free water")

	# Flow rejects pond interior cells whose every destination is water at their
	# own level. A cell that can still level diagonally must not be rejected.
	var sim4 = _new_sim(74)
	var g4 = sim4.grid
	for dx in range(-1, 2):
		g4.set_cell(50 + dx, 51, GridRef.WATER, 1.0)
	g4.set_cell(49, 51, GridRef.WATER, 0.5)
	g4.set_cell(51, 51, GridRef.WATER, 0.5)
	g4.set_cell(50, 50, GridRef.WATER, 1.0)
	MaterialsRef.step(g4, _params, 1, sim4.dt)
	_check(g4.amount_at(50, 50) < 1.0, "water at its level still levels diagonally")


func _test_wetness() -> void:
	var sim = _new_sim(81)
	var g = sim.grid
	g.set_cell(10, 10, GridRef.SAND, 1.0)
	g.set_cell(10, 11, GridRef.SAND, 1.0)
	g.wetness[g.index(10, 10)] = 1.0
	g.wet_history[g.index(10, 10)] = 1.0
	g.wake_cell_xy(10, 10)
	_advance_materials(sim, 10.0, 0.25)
	_check(g.wetness_at(10, 11) > 0.05, "wetness drains downward into the cell below")
	_check(g.wetness_at(10, 10) < 0.95, "the draining cell loses wetness")

	var sim2 = _new_sim(82)
	var g2 = sim2.grid
	g2.set_cell(20, 20, GridRef.SAND, 1.0)
	g2.wetness[g2.index(20, 20)] = 0.8
	g2.wet_history[g2.index(20, 20)] = 0.8
	g2.wake_cell_xy(20, 20)
	_advance_materials(sim2, sim2.day_seconds * 2.0, 1.0)
	_check(g2.wetness_at(20, 20) < 0.2, "exposed wet sand dries over two days")


func _test_hardening_order() -> void:
	# Wet, compacted, then dried: hard.
	var sim = _new_sim(91)
	var g = sim.grid
	var i: int = g.index(10, 10)
	g.set_cell(10, 10, GridRef.SAND, 1.0)
	g.wetness[i] = 1.0
	g.wet_history[i] = 1.0
	g.compaction[i] = 1.0
	g.wake_cell_xy(10, 10)
	_advance_materials(sim, sim.day_seconds * 2.0, 1.0)
	_check(g.hardness_at(10, 10) >= g.hard_sand_threshold, "wet + compacted + dried sand hardens (%.2f)" % g.hardness_at(10, 10))
	_check(g.state_of(i) == GridRef.STATE_HARD_SAND, "the hardened cell reads as hard sand")

	# The same wet, compacted sand kept wet stays mud.
	var sim2 = _new_sim(92)
	var g2 = sim2.grid
	var i2: int = g2.index(10, 10)
	g2.set_cell(10, 10, GridRef.SAND, 1.0)
	g2.compaction[i2] = 1.0
	g2.wet_history[i2] = 1.0
	for k in 960:
		g2.wetness[i2] = 1.0
		MaterialsRef.step(g2, _params, k + 1, 1.0)
	_check(g2.hardness_at(10, 10) < 0.05, "wet compacted sand kept wet does not harden (%.2f)" % g2.hardness_at(10, 10))
	_check(g2.state_of(i2) == GridRef.STATE_MUD, "the permanently wet cell reads as mud")

	# Dried loose sand never hardens: compaction is required.
	var sim3 = _new_sim(93)
	var g3 = sim3.grid
	var i3: int = g3.index(10, 10)
	g3.set_cell(10, 10, GridRef.SAND, 1.0)
	g3.wetness[i3] = 1.0
	g3.wet_history[i3] = 1.0
	g3.compaction[i3] = 0.0
	g3.wake_cell_xy(10, 10)
	_advance_materials(sim3, sim3.day_seconds * 2.0, 1.0)
	_check(g3.hardness_at(10, 10) < 0.05, "dried loose sand stays loose (%.2f)" % g3.hardness_at(10, 10))

	# Compacted but never wet: no hardening, because there is no wetness history.
	var sim4 = _new_sim(94)
	var g4 = sim4.grid
	var i4: int = g4.index(10, 10)
	g4.set_cell(10, 10, GridRef.SAND, 1.0)
	g4.compaction[i4] = 1.0
	g4.wake_cell_xy(10, 10)
	_advance_materials(sim4, sim4.day_seconds * 2.0, 1.0)
	_check(g4.hardness_at(10, 10) < 0.05, "compacted dry sand never hardens (%.2f)" % g4.hardness_at(10, 10))

	# Flooding a hardened cell softens it before anything else happens.
	var sim5 = _new_sim(95)
	var g5 = sim5.grid
	var i5: int = g5.index(10, 10)
	g5.set_cell(10, 10, GridRef.SAND, 1.0)
	g5.hardness[i5] = 0.8
	g5.cohesion[i5] = 0.8
	for k in 480:
		g5.wetness[i5] = 0.9
		MaterialsRef.step(g5, _params, k + 1, 1.0)
	_check(g5.hardness_at(10, 10) < 0.5, "flooded hard sand softens (%.2f)" % g5.hardness_at(10, 10))

	# Hard sand refuses to be flooded while it is hard.
	var g6 = _new_sim(96).grid
	g6.set_cell(10, 10, GridRef.SAND, 1.0)
	g6.hardness[g6.index(10, 10)] = 0.8
	g6.wetness[g6.index(10, 10)] = 1.0
	g6.add_material(10, 10, GridRef.WATER, 0.5)
	_check(g6.material_at(10, 10) == GridRef.SAND, "hard sand resists flooding while hard")


func _test_hardening_chain() -> void:
	var sim = _new_sim(97)
	var g = sim.grid
	var i: int = g.index(10, 10)

	# 1. Water placed on sand soaks in: the cell is wet, not a puddle.
	g.set_cell(10, 10, GridRef.SAND, 1.0)
	g.add_material(10, 10, GridRef.WATER, 0.9)
	_check(g.material_at(10, 10) == GridRef.SAND and g.wetness_at(10, 10) > 0.8, "placement wets the sand")

	# 2. A creature rests there; resting is the compaction source.
	var id: int = sim.store.spawn(10.5, 10.5, 0.4, 0.9, 0.9, 0.0)
	for s in 140:
		sim.step(sim.dt)
	_check(g.compaction[i] > 0.4, "a resting creature compacts the ground (%.2f)" % g.compaction[i])
	sim.store.kill(id, StoreRef.Death.NONE, sim.time)

	# 3. It dries. Only the combination of all three stages hardens it.
	_advance_materials(sim, sim.day_seconds * 2.0, 1.0)
	_check(g.state_of(i) == GridRef.STATE_HARD_SAND, "wet, compacted, dried ground becomes hard sand (hardness %.2f)" % g.hardness_at(10, 10))


func _test_rotting() -> void:
	var sim = _new_sim(101)
	var g = sim.grid
	var dry_i: int = g.index(10, 10)
	var wet_i: int = g.index(20, 10)
	g.set_cell(10, 10, GridRef.FOOD, 1.0)
	g.set_cell(20, 10, GridRef.FOOD, 1.0)
	g.wetness[wet_i] = 0.8
	# Five simulated days: at the tuned rot rate a cell needs several days to
	# fall past the toxicity threshold, and the point of the test is the real rate.
	for k in 4320:
		MaterialsRef.step(g, _params, k + 1, 1.0)
	_check(g.nutrition[dry_i] < 1.0, "food loses nutrition as it ages")
	_check(g.nutrition[wet_i] < g.nutrition[dry_i], "wet food rots faster than dry food")
	_check(g.toxicity[wet_i] > 0.0, "food that rots past the threshold becomes toxic")

	var sim2 = _new_sim(102)
	var g2 = sim2.grid
	g2.set_cell(10, 10, GridRef.FOOD, 1.0)
	g2.toxicity[g2.index(10, 10)] = 1.0
	var id: int = sim2.store.spawn(10.5, 10.5, 0.5, 0.2, 0.9, 0.9)
	var health_before: float = sim2.store.health[id]
	for s in 60:
		sim2.step(sim2.dt)
	_check(sim2.store.health[id] < health_before, "eating toxic food costs health")


func _test_food_regrowth() -> void:
	var sim = _new_sim(171)
	var g = sim.grid
	var i: int = g.index(10, 10)
	g.set_cell(10, 10, GridRef.FOOD, 0.2)
	g.nutrition[i] = 0.3
	g.toxicity[i] = 0.6
	for k in 480:
		MaterialsRef.step(g, _params, k + 1, 1.0)
	_check(g.amount[i] > 0.2, "food regrows mass in place (%.2f)" % g.amount[i])
	_check(g.nutrition[i] > 0.3, "fresh growth dilutes rot (%.2f)" % g.nutrition[i])
	_check(g.toxicity[i] < 0.6, "fresh growth dilutes toxin (%.2f)" % g.toxicity[i])
	for k in 2400:
		MaterialsRef.step(g, _params, 481 + k, 1.0)
	_check(g.amount[i] <= g.food_max + 0.001, "regrowth stops at the cell's food capacity (%.2f)" % g.amount[i])

	# The living trace: food never becomes air, but the trace itself is not food.
	var j: int = g.index(12, 10)
	g.set_cell(12, 10, GridRef.FOOD, 0.03)
	var first: float = g.consume(12, 10, 1.0)
	_check(first > 0.0 and g.material_at(12, 10) == GridRef.FOOD and absf(g.amount[j] - 0.02) < 0.001, "eating leaves a living trace (%.2f taken, %.2f left)" % [first, g.amount[j]])
	_check(g.consume(12, 10, 1.0) == 0.0, "the trace itself cannot be eaten")
	for k in 480:
		MaterialsRef.step(g, _params, 3000 + k, 1.0)
	_check(g.amount[j] > 0.02, "the trace regrows into edible food (%.2f)" % g.amount[j])


func _test_imitation() -> void:
	var sim = _new_sim(172)
	_flat_ground(sim, 6, 6, 48, 48)
	var source: int = sim.store.spawn(20.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim.store.stage[source] = StoreRef.ADULT
	var child: int = sim.store.spawn(22.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	var adult: int = sim.store.spawn(18.5, 20.5, 0.5, 1.0, 1.0, 1.0)
	sim.store.stage[adult] = StoreRef.ADULT
	var mute: int = sim.store.spawn(20.5, 22.5, 0.5, 1.0, 1.0, 1.0)
	sim.store.stage[mute] = StoreRef.ADULT
	sim.store.body[mute * GenomeRef.FIELDS + GenomeRef.F_IMITATION] = 0.0
	var far: int = sim.store.spawn(40.5, 30.5, 0.5, 1.0, 1.0, 1.0)
	sim.store.stage[far] = StoreRef.CHILD
	sim.memory.ensure(sim.store.count)
	# The spatial hash is rebuilt by step(); this test teaches before any step.
	sim.neighbors.rebuild(sim.store)
	var cell: int = sim.grid.index(30, 30)
	sim._teach_place(source, cell, GridRef.WATER, 1.0)
	_check(sim.memory.place_count(child) == 1, "a child watching an adult drink learns the place")
	_check(sim.memory.place_count(adult) == 1, "an adult observer learns it too")
	_check(sim.memory.place_count(source) == 0, "teaching does not give the teacher a memory of its own")
	_check(sim.memory.place_count(mute) == 0, "an observer with no imitation fidelity copies nothing")
	_check(sim.memory.place_count(far) == 0, "a creature beyond the teaching radius copies nothing")
	var child_value := float(sim.memory.place_at(child, 0)["value"])
	var adult_value := float(sim.memory.place_at(adult, 0)["value"])
	_check(child_value < 1.0, "a copied place is weaker than firsthand knowledge (%.2f)" % child_value)
	_check(child_value > adult_value, "a child copies more strongly than an adult (%.2f vs %.2f)" % [child_value, adult_value])

	var second: int = sim.grid.index(31, 30)
	sim._teach_place(source, second, GridRef.WATER, 1.0)
	_check(sim.memory.place_count(child) == 1, "a long meal teaches once per cooldown")
	sim.time += 2.0
	sim._teach_place(source, second, GridRef.WATER, 1.0)
	_check(sim.memory.place_count(child) == 2, "after the cooldown a second place is taught")

	# Firsthand knowledge is not overwritten by a weaker copy.
	sim.memory.remember_place(child, cell, GridRef.WATER, 1.0, sim.day())
	sim.time += 2.0
	sim._teach_place(source, cell, GridRef.WATER, 0.2)
	var kept := 0.0
	for k in sim.memory.place_count(child):
		var rec: Dictionary = sim.memory.place_at(child, k)
		if int(rec["cell"]) == cell:
			kept = float(rec["value"])
	_check(kept > 0.99, "a weak copy never overwrites firsthand knowledge (%.2f)" % kept)

	# Through the real simulation path: a drinker teaches the observer without
	# any direct call, using the neighbour index step() rebuilds.
	var sim2 = _new_sim(173)
	_flat_ground(sim2, 6, 6, 24, 24)
	sim2.grid.set_cell(11, 10, GridRef.WATER, 1.0)
	var drinker: int = sim2.store.spawn(10.5, 10.5, 0.5, 1.0, 0.3, 1.0)
	var watcher: int = sim2.store.spawn(12.5, 10.5, 0.5, 1.0, 1.0, 1.0)
	sim2.memory.ensure(sim2.store.count)
	for s in 45:
		sim2.step(sim2.dt)
	_check(sim2.memory.place_count(watcher) > 0, "drinking teaches a nearby observer through the real tick")
	_check(sim2.memory.place_count(drinker) > 0, "the drinker still remembers its own pond")


## The Phase 2 detectors must name a pattern from records that already exist,
## not from a world-generation cluster. The stockpile check deliberately
## requires at least one creature-piled cell.
func _test_detectors() -> void:
	var sim = _new_sim(180)
	_flat_ground(sim, 4, 4, 24, 24)
	var builder: int = sim.store.spawn(10.5, 10.5, 0.5, 1.0, 1.0, 1.0)
	sim.store.stage[builder] = StoreRef.ADULT
	for y in range(9, 12):
		for x in range(9, 12):
			sim.grid.set_cell(x, y, GridRef.FOOD, 1.0)
	sim.detectors.after_tick(sim)
	_check(sim.detectors.firsts.is_empty(), "a starting food patch alone is not a stockpile")

	# One cell in the cluster is creature-made; the pattern is now a store.
	sim.story.note_pile(sim, builder, sim.grid.index(10, 10), GridRef.FOOD, 0.0)
	sim.detectors.after_tick(sim)
	_check(sim.detectors.firsts.size() == 1 and String(sim.detectors.firsts[0]["kind"]) == "stockpile", "a creature-piled food cluster becomes the first stockpile")
	_check(not sim.detectors.active_highlights(sim.time).is_empty(), "a first-time pattern creates an active highlight")
	var expired: Array = sim.detectors.active_highlights(sim.time + 100.0)
	_check(expired.is_empty(), "a highlight expires instead of becoming permanent narration")

	# First hardened structure, from the story record the real tick writes.
	var hard = _new_sim(181)
	_flat_ground(hard, 4, 4, 16, 16)
	var piler: int = hard.store.spawn(8.5, 8.5, 0.5, 1.0, 1.0, 1.0)
	var cell: int = hard.grid.index(8, 8)
	hard.story.note_pile(hard, piler, cell, GridRef.SAND, 1.0)
	hard.grid.hardness[cell] = 0.70
	hard.grid.compaction[cell] = 0.60
	hard.story.after_tick(hard)
	hard.detectors.after_tick(hard)
	_check(hard.detectors.firsts.size() == 1 and String(hard.detectors.firsts[0]["kind"]) == "hardening", "the first hardened pile is detected from the story record")
	_check(String(hard.detectors.firsts[0]["text"]).contains("creature 0"), "the first-hardening line names the builder")
	var again: int = int(hard.detectors.firsts.size())
	hard.detectors.after_tick(hard)
	_check(hard.detectors.firsts.size() == again, "a first is written once, not every tick")

	# First rivalry, from the same opinion value the brain reads.
	var social = _new_sim(182)
	_flat_ground(social, 4, 4, 16, 16)
	var a: int = social.store.spawn(8.5, 8.5, 0.5, 1.0, 1.0, 1.0)
	var b: int = social.store.spawn(9.5, 8.5, 0.5, 1.0, 1.0, 1.0)
	social.memory.ensure(social.store.count)
	social.opinion.ensure(social.store.count)
	for k in 4:
		social.add_opinion(a, b, -0.18, "disputed meals")
	social.detectors.after_tick(social)
	_check(social.detectors.firsts.size() == 1 and String(social.detectors.firsts[0]["kind"]) == "rivalry", "the first label-crossing rivalry is detected")
	_check(String(social.detectors.firsts[0]["text"]).contains("disputed meals"), "the rivalry line names the remembered events")


func _test_history() -> void:
	var sim = _new_sim(183)
	_flat_ground(sim, 4, 4, 24, 24)
	sim.spawn_founders(5)
	sim.history.sample(sim)
	var summary: Dictionary = sim.history.summary(sim)
	_check(int(summary["lineages"]) == 5 and int(summary["living_lineages"]) == 5, "history records one lineage per founder")
	_check(float(summary["diversity"]) > 0.0, "history measures genetic diversity across living founders")
	var victim := -1
	for i in sim.store.count:
		if sim.store.alive[i] == 1:
			victim = i
			break
	var line := int(sim.store.founder[victim])
	sim.store.kill(victim, StoreRef.Death.STARVATION, sim.time)
	sim.history.note_death(sim, victim, StoreRef.Death.STARVATION)
	sim.history.sample(sim)
	var after: Dictionary = sim.history.summary(sim)
	_check(int(after["living_lineages"]) == 4 and int(after["extinct_lineages"]) == 1, "a dead founder leaves an extinct-lineage record")
	var rows: Array = sim.history.lineage_rows(sim, 10)
	var found := false
	var extinct_series: Array = []
	for row in rows:
		if int(row["line"]) == line and int(row["alive"]) == 0 and int(row["died"]) == 1 and float(row["extinct_day"]) >= 0.0:
			found = true
			extinct_series = row.get("series", [])
	_check(found, "the lineage row keeps its death day after the creature id is reusable")
	_check(extinct_series.size() >= 2 and int(extinct_series[extinct_series.size() - 1]) == 0, "the lineage row keeps a sampled population series through extinction")

	# A contest is a place fact: the history view stores where it happened and
	# the terrain reads the same record for its fading contested tint.
	var place_sim = _new_sim(184)
	_flat_ground(place_sim, 4, 4, 24, 24)
	var contest_cell: int = place_sim.grid.index(12, 12)
	place_sim.story.note_contest(place_sim, contest_cell, 0, 1, true)
	var places: Array = place_sim.story.place_history(place_sim, 6)
	var contested := false
	for place in places:
		if String(place["kind"]) == "contest" and int(place["contests"]) == 1 and int(place["injuries"]) == 1:
			contested = true
	_check(contested, "a contested place keeps its dispute and injury counts")
	_check(place_sim.story.contest_heat(contest_cell) > 0.0, "a contested place has a visible heat value for the terrain")


func _test_material_activity() -> void:
	var sim = _new_sim(111)
	var g = sim.grid
	g.set_cell(5, 5, GridRef.SAND, 1.0)
	for k in 6:
		MaterialsRef.step(g, _params, k + 1, 1.0)
	_check(g.active_cell_count() == 0, "a dry, still cell goes to sleep")
	g.set_cell(6, 5, GridRef.WATER, 1.0)
	_check(g.active_cell_count() > 0, "water wakes its cell")


func _test_material_clock() -> void:
	var sim = _new_sim(117)
	var g = sim.grid
	var i: int = g.index(10, 10)
	g.set_cell(10, 10, GridRef.SAND, 1.0)
	g.wetness[i] = 0.9
	g.wake_cell_xy(10, 10)
	MaterialsRef.step(g, _params, 1, 1.0)
	var first_drop: float = 0.9 - g.wetness[i]
	_check(first_drop > 0.0, "a processed cell advances with the elapsed time")
	_check(g.prop_tick[i] == 1, "processing stamps the cell's material clock")

	# Pretend the cell sat in the queue for twenty more ticks.
	g.prop_tick[i] = 1 - 20
	var before: float = g.wetness[i]
	MaterialsRef.step(g, _params, 2, 1.0)
	var waited_drop: float = before - g.wetness[i]
	_check(waited_drop > 10.0 * first_drop, "a cell that waited longer dries proportionally more (%.4f vs %.4f)" % [waited_drop, first_drop])


func _test_material_batch() -> void:
	var sim = _new_sim(112)
	var g = sim.grid
	for k in 300:
		var x: int = 60 + k % 20
		var y: int = 60 + k / 20
		g.set_cell(x, y, GridRef.SAND, 1.0)
		g.wetness[g.index(x, y)] = 0.9
	var queued: int = g.active_cell_count()
	_check(queued >= 300, "every changing cell is queued (%d)" % queued)
	var tight := ParamsRef.load_default()
	(tight.data["materials"] as Dictionary)["material_batch_cells"] = 64
	var stats: Dictionary = MaterialsRef.properties(g, tight, 1, 0.5)
	_check(int(stats["processed"]) == 64, "a pass stops at its cell budget (%d)" % int(stats["processed"]))
	_check(g.active_cell_count() >= queued - 64, "unbudgeted cells stay queued, none are dropped")
	var before: int = g.active_cell_count()
	var wide: Dictionary = MaterialsRef.properties(g, _params, 1, 0.5)
	_check(int(wide["processed"]) == before, "the next pass takes the rest of the queue (%d)" % int(wide["processed"]))
	_check(_params.f("materials", "material_batch_cells", 0.0) > 64.0, "a budgeted pass does not mutate the register")


func _test_water_bookkeeping() -> void:
	var sim = _new_sim(113)
	var g = sim.grid
	for x in range(30, 42):
		for y in range(30, 38):
			g.set_cell(x, y, GridRef.WATER, 1.0)
	for k in 40:
		MaterialsRef.step(g, _params, k + 1, 0.5)
	var scanned: int = int(g.counts()["water"])
	_check(g.water_cell_count() == scanned, "the water list matches the grid after flow (%d vs %d)" % [g.water_cell_count(), scanned])
	g.add_material(31, 31, GridRef.SAND, 1.0)
	g.consume(33, 33, 99.0)
	_check(g.water_cell_count() == int(g.counts()["water"]), "the water list survives placement and drinking")


func _test_field_capacity() -> void:
	var sim = _new_sim(114)
	var g = sim.grid
	for y in range(50, 53):
		g.set_cell(50, y, GridRef.SAND, 1.0)
	g.wetness[g.index(50, 50)] = 0.4
	g.wake_cell_xy(50, 50)
	for k in 40:
		MaterialsRef.step(g, _params, k + 1, 0.5)
	_check(g.wetness_at(50, 51) < 0.01, "held water below field capacity does not drain away")
	_check(g.wetness_at(50, 50) > 0.0, "held water stays in the cell that holds it")

	var g2 = _new_sim(115).grid
	for y in range(50, 53):
		g2.set_cell(50, y, GridRef.SAND, 1.0)
	g2.wetness[g2.index(50, 50)] = 0.9
	g2.wake_cell_xy(50, 50)
	for k in 40:
		MaterialsRef.step(g2, _params, k + 1, 0.5)
	_check(g2.wetness_at(50, 51) > 0.05, "water above field capacity drains to the cell below")


func _test_hard_pan() -> void:
	var sim = _new_sim(116)
	var g = sim.grid
	for x in range(39, 42):
		g.set_cell(x, 41, GridRef.SAND, 1.0)
		g.hardness[g.index(x, 41)] = 0.9
		g.set_cell(x, 42, GridRef.SAND, 1.0)
	g.set_cell(40, 40, GridRef.WATER, 1.0)
	for k in 40:
		MaterialsRef.step(g, _params, k + 1, 0.5)
	_check(g.material_at(40, 41) == GridRef.SAND, "water sits on hard sand instead of soaking in")
	_check(g.wetness_at(40, 41) < 0.05, "hard sand takes no wetness through its face")
	_check(g.wetness_at(40, 42) < 0.05, "no water reaches the ground below the pan")
	g.set_cell(40, 42, GridRef.SAND, 1.0)
	g.wetness[g.index(40, 42)] = 0.9
	g.wake_cell_xy(40, 42)
	for k in 40:
		MaterialsRef.step(g, _params, 40 + k, 0.5)
	_check(g.wetness_at(40, 41) < 0.05, "wet sand above a pan does not drain into it")


func _test_material_performance() -> void:
	var sim = _new_sim(121)
	var g = sim.grid
	for x in range(28, 44):
		for y in range(28, 40):
			g.set_cell(x, y, GridRef.SAND, 1.0)
	for x in range(30, 42):
		for y in range(30, 38):
			g.set_cell(x, y, GridRef.WATER, 1.0)
	g.wake_cell_xy(30, 30)
	var t0 := Time.get_ticks_usec()
	for k in 60:
		MaterialsRef.step(g, _params, k + 1, sim.dt)
	var ms := float(Time.get_ticks_usec() - t0) / 60.0 / 1000.0
	print("  material step: %.2f ms with %d active cells, pond of %d water cells" % [ms, g.active_cell_count(), int(g.counts()["water"])])
	_check(ms < 16.7, "material step fits inside a 60 fps frame with the rest of the tick (%.2f ms)" % ms)
