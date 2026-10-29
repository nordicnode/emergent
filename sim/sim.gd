class_name Sim
extends RefCounted

## The simulation layer: plain arrays, no scene nodes, no rendering types.
## The fixed-order tick lives in sim/tick.gd; the share, harm and safety/flee
## events each own their state and log writes in sim/share.gd, sim/harm.gd and
## sim/safety.gd. This class keeps the world, the creatures and the actions that
## surround them.

const GridRef := preload("res://sim/grid.gd")
const StoreRef := preload("res://sim/creature_store.gd")
const RngRef := preload("res://sim/rng.gd")
const HashRef := preload("res://sim/spatial_hash.gd")
const BrainRef := preload("res://sim/brain.gd")
const LogRef := preload("res://sim/event_log.gd")
const GenomeRef := preload("res://sim/genome.gd")
const MemoryRef := preload("res://sim/memory.gd")
const OpinionRef := preload("res://sim/opinion.gd")
const ShareRef := preload("res://sim/share.gd")
const HarmRef := preload("res://sim/harm.gd")
const SafetyRef := preload("res://sim/safety.gd")
const StoryRef := preload("res://sim/story.gd")
const DetectorsRef := preload("res://sim/detectors.gd")
const HistoryRef := preload("res://sim/history.gd")
const TickRef := preload("res://sim/tick.gd")

## A stress weight with no contrast behind it, used only when the stress-weight
## ablation is on. It is not a tuned value and never enters the parameter
## register.
const FLAT_STRESS := 0.5

var params: SimParams
var grid: SimGrid
var store: CreatureStore
var rng: SimRng
var neighbors: SpatialHash
var log: SimEventLog
## Learned state lives beside the creatures, never inside the genome.
var memory: SimMemory
## Sparse, asymmetric opinions: who helped, who took a meal, who is kin.
var opinion: SimOpinion
## Per-event units. Each owns its own cooldowns, counters and log writes.
var share
var harm
var safety
## Causal log evidence for the Phase 1 exit stories; no creature reads it.
var story
## First-time pattern detectors and the highlight feed for Phase 2. Observers
## only: no creature reads a highlight, and no action is unlocked by one.
var detectors
## Persistent lineage, extinction and diversity records for the history views
## and the soak suite. Legibility data, never a creature input.
var history
## The fixed-order tick and its phase timings.
var tick
## Ablation switch for soak controls. Off means no recall and no weight updates;
## the memory store still exists so the interface does not need two code paths.
var memory_enabled := true
## Second ablation switch, for the social slice: off removes the social verbs,
## the opinion events and the mate-refusal read, without deleting the store.
var social_enabled := true
## Third ablation switch, for the carrying slice: off removes pick up and pile.
## The comfort need still exists, so a control run still prefers comfortable
## ground; it simply cannot move material to make any.
var carry_enabled := true
## Fourth ablation switch, for the safety slice: off freezes the safety need and
## removes flee. The disable-one-system test for the fear story, not a player
## setting.
var safety_enabled := true
## Phase 3 decision staggering: how many sim ticks pass between a creature's
## decisions. 1 is the Phase 1/2 behaviour (decide every tick). Above 1,
## creatures are split into stable buckets by slot id, one bucket deciding
## per tick, while movement and action execution still run every tick.
## A creature therefore re-decides at most (every - 1) ticks late, including
## the flee interrupt; at every = 3 and 15 Hz that is 0.13 simulated seconds.
var decision_every := 1
var decisions_made := 0
var decisions_last_tick := 0
## Phase 3 tier promotion: decisions a promoted creature made outside its
## bucket. A promoted creature decides every tick, so this counts only the
## extra decisions promotion caused, not the ones its bucket would have made.
var promotions_made := 0
var promotions_last_tick := 0
## Fifth ablation switch, for the Phase 1 exit criteria: off stops new material
## hardening and softening. Compaction, wetness and drying keep running.
var hardening_enabled := true
## Sixth: off replaces each episode's actual stress with one flat weight, so a
## near-crisis lesson teaches no more than a routine one. The learning rule and
## its retention still run.
var stress_weighting := true
## Seventh: off removes the opinion store's reads and writes while leaving the
## social verbs in place. A rivalry can no longer be labelled or acted on.
var opinion_enabled := true

var seed_used := 0
var time := 0.0
var day_seconds := 480.0
var tick_hz := 15.0
var dt := 0.0666667

var speed := 1.0
var paused := false
var _accumulator := 0.0
var dropped_seconds := 0.0

var inspect_id := -1
var last_inspection: Array = []

var action_counts := PackedInt32Array()
var death_counts := PackedInt32Array()

var pond_centers: Array = []
var births := 0
var recall_actions := 0
var social_events := 0
## How often a creature swaps verb. Commitment is meant to keep a creature on
## one action, so this count is the legibility measure of hysteresis: a creature
## that changes twice a second cannot be followed by a player or a story.
var verb_changes := 0

## Read-only views of event state owned by the units above. Keeping the names
## stable is the contract the suite, soak and HUD already use; the values have
## one owner each.
var share_events: int:
	get:
		return share.events
var harm_events: int:
	get:
		return harm.events
var harm_damage_total: float:
	get:
		return harm.damage_total
var food_taken_events: int:
	get:
		return harm.food_taken_events
var flee_starts: int:
	get:
		return safety.flee_starts
var last_step_ms: float:
	get:
		return tick.last_step_ms
var pickup_food_actions := 0
var pickup_sand_actions := 0
var pile_food_actions := 0
var pile_sand_actions := 0
## Completed loads, not decision ticks: a pick-up verb held for a second is one
## load, and a pile that empties the hands is one pile.
var loads_picked_food := 0
var loads_picked_sand := 0
var loads_piled_food := 0
var loads_piled_sand := 0
var _pending_deaths := PackedInt32Array()
var _pending_cause := {}


func _init(p: SimParams, seed_value: int = 12345) -> void:
	params = p
	seed_used = seed_value
	day_seconds = maxf(params.f("sim", "day_seconds", 480.0), 0.001)
	tick_hz = maxf(params.f("sim", "tick_hz", 15.0), 1.0)
	dt = 1.0 / tick_hz
	rng = RngRef.new(seed_value)

	var w := params.i("world", "width", 512)
	var h := params.i("world", "height", 384)
	var cs := params.i("world", "chunk_size", 64)
	var px := params.i("world", "cell_px", 8)
	var capacity := {
		"sand": params.f("world", "sand_max", 4.0),
		"water": params.f("world", "water_max", 1.0),
		"food": params.f("world", "food_max", 1.0),
	}
	grid = GridRef.new(w, h, cs, px, capacity)
	grid.mud_wetness = params.f("materials", "mud_wetness", 0.55)
	grid.hard_sand_threshold = params.f("materials", "hard_sand_threshold", 0.45)
	grid.food_rot_threshold = params.f("materials", "rot_toxicity_threshold", 0.40)
	grid.convert_max_hardness = params.f("materials", "convert_max_hardness", 0.35)
	grid.food_min_amount = params.f("materials", "food_min_amount", 0.02)
	decision_every = clampi(params.i("brain", "decision_every_ticks", 1), 1, 15)
	store = StoreRef.new()
	memory = MemoryRef.new()
	opinion = OpinionRef.new(
		params.f("social", "opinion_decay_days", 3.0),
		params.f("social", "kin_bonus", 0.30),
		params.f("social", "rival_threshold", -0.20),
		params.f("social", "friend_threshold", 0.30),
		params.i("social", "label_min_events", 3)
	)
	neighbors = HashRef.new(float(w), float(h), params.f("perception", "sensory_radius_cells", 18.0))
	log = LogRef.new()
	share = ShareRef.new()
	harm = HarmRef.new()
	safety = SafetyRef.new(params)
	story = StoryRef.new()
	detectors = DetectorsRef.new()
	detectors.configure(params)
	history = HistoryRef.new()
	tick = TickRef.new(params, tick_hz)
	action_counts.resize(StoreRef.VERB_COUNT)
	death_counts.resize(StoreRef.DEATH_NAMES.size())


func is_running() -> bool:
	return not paused


func day() -> float:
	return time / day_seconds


func alive_count() -> int:
	return store.alive_count()


func apply_brush(mat: int, cx: int, cy: int, radius: int, amount: float) -> int:
	if amount <= 0.0 or radius < 0:
		return 0
	var touched := 0
	var reach := float(radius) + 0.5
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			var dx := float(x - cx)
			var dy := float(y - cy)
			var d := sqrt(dx * dx + dy * dy)
			if d > reach:
				continue
			var falloff := clampf(1.0 - d / reach, 0.0, 1.0)
			if falloff <= 0.0:
				continue
			grid.add_material(x, y, mat, amount * falloff)
			touched += 1
	return touched


## Runs real-time seconds of simulation at the current speed, in fixed steps.
func advance(real_delta: float) -> void:
	if paused:
		return
	_accumulator += minf(real_delta, 0.25) * speed
	var budget := params.i("sim", "max_steps_per_advance", 8)
	var taken := 0
	while _accumulator >= dt and taken < budget:
		step(dt)
		_accumulator -= dt
		taken += 1
	if _accumulator >= dt:
		# Budget exhausted: drop the backlog instead of spiralling, and report
		# it. Frame rate must never become an invisible population control.
		dropped_seconds += _accumulator
		_accumulator = 0.0


## One fixed step. The order lives in sim/tick.gd; this method is only the
## stable entry point every caller already uses.
func step(step_dt: float) -> void:
	tick.step(self, step_dt)


func _decay_needs(step_dt: float) -> void:
	var day_len := day_seconds
	var hunger_rate := params.f("needs", "hunger_decay_per_day", 0.5)
	var hunger_active := params.f("needs", "hunger_active_mult", 1.35)
	var thirst_rate := params.f("needs", "thirst_decay_per_day", 0.85)
	var thirst_active := params.f("needs", "thirst_active_mult", 1.4)
	var energy_rate := params.f("needs", "energy_decay_per_day", 1.3)
	var energy_move := params.f("needs", "energy_movement_mult", 0.8)
	var social_rate := params.f("needs", "social_decay_per_day", 0.9)
	var rest_rate := params.f("needs", "energy_rest_recovery_per_day", 5.0)
	var starve_dmg := params.f("needs", "starve_health_per_day", 0.7)
	var dehydrate_dmg := params.f("needs", "dehydrate_health_per_day", 0.9)
	var regen := params.f("needs", "health_regen_per_day", 0.4)
	var regen_threshold := params.f("needs", "health_regen_threshold", 0.45)
	var toxin_clear := params.f("memory", "toxin_clear_per_day", 3.0)
	var toxin_damage := params.f("memory", "toxin_damage_per_day", 1.2)
	var maturity := maxf(params.f("life", "maturity_days", 0.25), 0.01)
	var old_age := maxf(params.f("life", "old_age_days", 4.0), maturity)
	var old_decline := params.f("life", "old_decline_per_day", 0.35)

	for i in store.count:
		if store.alive[i] == 0:
			continue
		var moving := (store.vx[i] * store.vx[i] + store.vy[i] * store.vy[i]) > 0.04
		var metabolism: float = store.body_value(i, GenomeRef.F_METABOLIC)
		var hunger_mult := (hunger_active if moving else 1.0) * metabolism
		var thirst_mult := (thirst_active if moving else 1.0) * metabolism
		store.food_level[i] = maxf(0.0, store.food_level[i] - hunger_rate * step_dt / day_len * hunger_mult)
		store.water_level[i] = maxf(0.0, store.water_level[i] - thirst_rate * step_dt / day_len * thirst_mult)
		if int(store.verb[i]) == StoreRef.Verb.REST:
			store.energy_level[i] = minf(1.0, store.energy_level[i] + rest_rate * step_dt / day_len)
		else:
			var energy_mult := (1.0 + energy_move) if moving else 1.0
			store.energy_level[i] = maxf(0.0, store.energy_level[i] - energy_rate * step_dt / day_len * energy_mult)
		store.social_level[i] = maxf(0.0, store.social_level[i] - social_rate * step_dt / day_len)

		# Comfort follows the ground underfoot: wet or standing water wears it
		# down, and resting on dry, hard, compacted ground restores it. It never
		# damages health; it is the need that makes a hardened place worth
		# returning to. The quality is read from cell properties at query time.
		var ccx := int(floor(store.px[i]))
		var ccy := int(floor(store.py[i]))
		var ground_quality := 0.0
		var protection := 0.0
		if grid.in_bounds(ccx, ccy):
			var ground := grid.index(ccx, ccy)
			ground_quality = grid.comfort_quality(ground)
			protection = grid.protection_quality(ground)
			var comfort_loss := params.f("needs", "comfort_decay_per_day", 0.55)
			if int(grid.material[ground]) == GridRef.WATER:
				comfort_loss += params.f("needs", "comfort_water_decay_per_day", 2.0)
			else:
				comfort_loss += params.f("needs", "comfort_wet_decay_per_day", 1.2) * float(grid.wetness[ground])
			store.comfort_level[i] = maxf(0.0, store.comfort_level[i] - comfort_loss * step_dt / day_len)
		if int(store.verb[i]) == StoreRef.Verb.REST:
			store.comfort_level[i] = minf(1.0, store.comfort_level[i] + params.f("needs", "comfort_rest_recovery_per_day", 2.2) * ground_quality * step_dt / day_len)

		safety.decay(self, i, step_dt, day_len, protection)

		store.age_days[i] += step_dt / day_len
		store.cooldown_days[i] = maxf(0.0, store.cooldown_days[i] - step_dt / day_len)

		# Life stage. Children are smaller and slower through body_scale; the old
		# decline through the same scale and pay a health cost, which is how age
		# kills without a separate behaviour set.
		var age := store.age_days[i]
		if age < maturity:
			store.stage[i] = StoreRef.CHILD
			store.body_scale[i] = 0.62 + 0.38 * clampf(age / maturity, 0.0, 1.0)
		elif age < old_age:
			store.stage[i] = StoreRef.ADULT
			store.body_scale[i] = 1.0
		else:
			store.stage[i] = StoreRef.OLD
			store.body_scale[i] = 1.0 - 0.35 * clampf((age - old_age) / old_age, 0.0, 1.0)

		var starving := store.food_level[i] <= 0.0001
		var dehydrated := store.water_level[i] <= 0.0001
		if starving or dehydrated:
			var damage := 0.0
			if starving:
				damage += starve_dmg
			if dehydrated:
				damage += dehydrate_dmg
			store.health[i] = maxf(0.0, store.health[i] - damage * step_dt / day_len)
		elif store.food_level[i] > regen_threshold and store.water_level[i] > regen_threshold:
			store.health[i] = minf(1.0, store.health[i] + regen * step_dt / day_len)

		# Toxin from rotten food keeps working after the meal. It is the slow half
		# of the poison: a single bad bite is cheap, a diet of it is not, and the
		# load is still present when the delayed evaluation looks.
		if store.toxin[i] > 0.0:
			store.health[i] = maxf(0.0, store.health[i] - store.toxin[i] * toxin_damage * step_dt / day_len)
			store.toxin[i] = maxf(0.0, store.toxin[i] - toxin_clear * step_dt / day_len)
			if store.health[i] <= 0.0 and not _pending_cause.has(i):
				_pending_cause[i] = StoreRef.Death.POISONING

		# Age is applied after recovery so a well-fed old creature still wears
		# down, and the cause is recorded at the moment the damage lands.
		if store.stage[i] == StoreRef.OLD:
			var over := clampf((store.age_days[i] - old_age) / old_age, 0.0, 1.0)
			store.health[i] = maxf(0.0, store.health[i] - old_decline * (0.5 + over) * step_dt / day_len)
			if store.health[i] <= 0.0 and not _pending_cause.has(i):
				_pending_cause[i] = StoreRef.Death.OLD_AGE

		if store.health[i] <= 0.0:
			_pending_deaths.append(i)


func _decide_all() -> void:
	decisions_last_tick = 0
	promotions_last_tick = 0
	var bucket: int = int(tick.steps_taken) % maxi(decision_every, 1)
	var radius := params.f("perception", "sensory_radius_cells", 18.0)
	# Read once per tick, not once per creature per candidate.
	var gate_food := params.f("repro", "gate_food", 0.55)
	var gate_water := params.f("repro", "gate_water", 0.55)
	var gate_energy := params.f("repro", "gate_energy", 0.55)
	var gate_health := params.f("repro", "gate_health", 0.70)
	var mate_search := params.f("repro", "search_radius_cells", 14.0)
	var mate_min_distance := params.f("repro", "min_genetic_distance", 0.04)
	var social_cooldown := params.f("social", "socialise_cooldown_seconds", 20.0)
	for i in store.count:
		if store.alive[i] == 0:
			continue
		# Staggering: only this tick's bucket re-decides. Every other
		# creature keeps its current verb, aim and commitment, and still
		# moves and acts in _execute_all below. Bucket is the slot id,
		# which is stable across a creature's life, so its cadence never
		# jitters; a slot reused by a newborn keeps that slot's bucket.
		# Tier promotion, Phase 3 second slice: a creature that is
		# fleeing, or the one the player is inspecting, decides every
		# tick instead. Both are significance, not a new behaviour: a
		# fleeing creature's threat can move in a tick, and the inspected
		# creature is the one whose scores the panel shows. Promotion is
		# narrow on purpose — a starving population would promote almost
		# everyone, which would just be unstaggering with extra steps.
		var promoted := i == inspect_id or int(store.verb[i]) == StoreRef.Verb.FLEE
		if decision_every > 1 and not promoted and (i % decision_every) != bucket:
			continue
		if decision_every > 1 and promoted and (i % decision_every) != bucket:
			promotions_last_tick += 1
			promotions_made += 1
		decisions_last_tick += 1
		decisions_made += 1
		var prev_verb := int(store.verb[i])
		var ready := _repro_ready_with(i, gate_food, gate_water, gate_energy, gate_health)
		var partner := -1
		var partner_dist := 0.0
		if ready:
			var found := _nearest_mate(i, mate_search, mate_min_distance, gate_food, gate_water, gate_energy, gate_health)
			partner = int(found[0])
			partner_dist = float(found[1])
		var sense := maxf(radius * GenomeRef.sense_factor(store, i), 4.0)
		var recall_store = memory if memory_enabled else null
		var social_view = opinion if social_enabled and opinion_enabled else null
		var social_ready := time - store.social_time[i] >= social_cooldown
		var decision: SimBrain.Decision = BrainRef.decide(
			store, i, grid, params, rng, sense, ready, partner, partner_dist,
			recall_store, day(), social_view, neighbors, social_ready, carry_enabled,
			safety_enabled
		)
		if i == inspect_id:
			last_inspection = decision.scores
		action_counts[decision.verb] += 1
		if decision.label.begins_with("recall"):
			recall_actions += 1
		safety.note_decision(self, i, prev_verb, decision)
		story.note_decision(self, i, prev_verb, decision)
		match decision.label:
			"pickup_food":
				pickup_food_actions += 1
			"pickup_sand":
				pickup_sand_actions += 1
			"pile_food":
				pile_food_actions += 1
			"pile_sand":
				pile_sand_actions += 1

		if decision.verb != prev_verb:
			verb_changes += 1
			_learn_from_action(i, prev_verb)
			_stash_learning(i, decision)
			store.verb[i] = decision.verb
			store.action_time[i] = 0.0
			store.commitment[i] = _commitment_for_aim(i, decision.verb, decision.aim_x, decision.aim_y)
		elif decision.verb == StoreRef.Verb.WANDER and store.commitment[i] > 0.0:
			# Keep walking to the chosen spot instead of re-rolling the
			# destination every decision tick. Movement is cheap; dithering is not.
			decision.aim_x = store.aim_x[i]
			decision.aim_y = store.aim_y[i]

		store.aim_x[i] = clampf(decision.aim_x, 1.0, float(grid.width - 2))
		store.aim_y[i] = clampf(decision.aim_y, 1.0, float(grid.height - 2))
		store.aim_cell[i] = decision.aim_cell
		store.aim_creature[i] = decision.aim_creature
		if decision.label.begins_with("search_"):
			# Remember the direction actually taken, so the next leg turns from
			# here instead of from a fresh random angle.
			store.heading[i] = atan2(store.aim_y[i] - store.py[i], store.aim_x[i] - store.px[i])


## Applies the plan's one learning rule to the verb that just ended:
##   weight += rate * stress * (actual improvement - weight)
## The improvement is the change in the need that verb serves, measured from
## the moment the verb was chosen to the moment it gave way. Routine success
## predicts itself and teaches little; a near-critical rescue teaches a lot.
func _learn_from_action(i: int, verb: int) -> void:
	if not memory_enabled:
		return
	if verb < 0 or verb >= StoreRef.VERB_COUNT or store.mem_tracking[i] == 0:
		return
	var before := 0.0
	var after := 0.0
	match verb:
		StoreRef.Verb.EAT:
			before = store.mem_before_food[i]
			after = store.food_level[i]
		StoreRef.Verb.DRINK:
			before = store.mem_before_water[i]
			after = store.water_level[i]
		StoreRef.Verb.REST:
			# Rest serves energy and comfort. The better of the two is the lesson:
			# a nap on hard dry ground teaches more than the same nap in mud.
			var energy_gain := store.energy_level[i] - store.mem_before_energy[i]
			var comfort_gain := store.comfort_level[i] - store.mem_before_comfort[i]
			before = 0.0
			after = maxf(energy_gain, comfort_gain)
		StoreRef.Verb.FLEE:
			# Flee serves safety, so its lesson is the fear that was relieved.
			before = store.mem_before_safety[i]
			after = store.safety_level[i]
		_:
			before = (store.mem_before_food[i] + store.mem_before_water[i] + store.mem_before_energy[i]) / 3.0
			after = (store.food_level[i] + store.water_level[i] + store.energy_level[i]) / 3.0
	var improvement := clampf(after - before, -1.0, 1.0)
	var stress := store.mem_stress[i] if stress_weighting else FLAT_STRESS
	var context := int(store.mem_context[i])
	# Only verbs that change a need directly teach a weight. Over a seek, a
	# move-to or a wander the mean need always drifts down, so learning from it
	# would teach that looking for food is bad precisely when hungry. Credit for
	# those actions arrives through the eat or drink that follows.
	if verb == StoreRef.Verb.EAT or verb == StoreRef.Verb.DRINK or verb == StoreRef.Verb.REST or verb == StoreRef.Verb.FLEE:
		memory.learn(i, verb, context, stress, improvement, params.f("memory", "learning_rate", 0.25))
	memory.record_episode(
		i, verb, context, stress, before, after,
		int(store.aim_cell[i]), day()
	)


## Opens the observation window for the verb just chosen, and arms the delayed
## re-check when that verb is eating: food that harms health an hour later still
## gets taught, which is the plan's second evaluation.
func _stash_learning(i: int, decision: SimBrain.Decision) -> void:
	store.mem_tracking[i] = 1
	store.mem_before_food[i] = store.food_level[i]
	store.mem_before_water[i] = store.water_level[i]
	store.mem_before_energy[i] = store.energy_level[i]
	store.mem_before_comfort[i] = store.comfort_level[i]
	store.mem_before_safety[i] = store.safety_level[i]
	store.mem_stress[i] = clampf(decision.stress, 0.0, 1.0)
	store.mem_context[i] = decision.context
	if decision.verb == StoreRef.Verb.EAT and store.mem_delay_until[i] <= 0.0:
		# Arm once per bout, not once per decision: a creature that dithers
		# between eating and wandering would otherwise keep moving the baseline
		# forward and never see the toxin it just swallowed.
		store.mem_delay_until[i] = time + params.f("memory", "delayed_check_seconds", 1.0)
		store.mem_delay_health[i] = store.health[i]
		store.mem_delay_toxin[i] = store.toxin[i]
		store.mem_delay_verb[i] = decision.verb
		store.mem_delay_context[i] = decision.context
		store.mem_delay_stress[i] = clampf(decision.stress, 0.0, 1.0)


## Second evaluation. Only a real health loss teaches: the check compares health
## now against health when the meal began, so a creature that ate well learns
## nothing here and a creature poisoned learns to distrust eating in that state.
func _delayed_learning() -> void:
	if not memory_enabled:
		return
	var scale := params.f("memory", "health_lesson_scale", 100.0)
	var threshold := params.f("memory", "health_lesson_threshold", 0.0002)
	for i in store.count:
		if store.alive[i] == 0 or store.mem_delay_until[i] <= 0.0 or time < store.mem_delay_until[i]:
			continue
		var delta := store.health[i] - store.mem_delay_health[i]
		var toxin_gain := maxf(0.0, store.toxin[i] - store.mem_delay_toxin[i])
		store.mem_delay_until[i] = 0.0
		# A toxin load is a stronger signal than a health number that recovery
		# can hide; the health path remains for any other slow harm.
		var lesson := -clampf(toxin_gain * 4.0, 0.0, 0.6)
		if toxin_gain <= 0.005:
			if delta >= -threshold:
				continue
			lesson = clampf(delta * scale, -0.6, 0.0)
		memory.learn(
			i, int(store.mem_delay_verb[i]), int(store.mem_delay_context[i]),
			store.mem_delay_stress[i] if stress_weighting else FLAT_STRESS,
			lesson, params.f("memory", "learning_rate", 0.25)
		)


## Commitment is a minimum, not a cap. A wander leg is held until its target is
## reached, because re-rolling the destination every 1.2 s meant a "6–18 cell"
## leg was in practice three cells, and creatures never covered ground.
func _commitment_for_aim(i: int, verb: int, ax: float, ay: float) -> float:
	var base := _commitment_for(verb)
	if verb != StoreRef.Verb.WANDER:
		return base
	var dx := ax - store.px[i]
	var dy := ay - store.py[i]
	var speed := params.f("movement", "speed_cells_per_sec", 2.5) * GenomeRef.speed_factor(store, i)
	return clampf(sqrt(dx * dx + dy * dy) / maxf(speed, 0.1), base, 24.0)


func _commitment_for(verb: int) -> float:
	match verb:
		StoreRef.Verb.WANDER:
			return params.f("commit", "wander_seconds", 1.2)
		StoreRef.Verb.SEEK:
			return params.f("commit", "seek_seconds", 2.0)
		StoreRef.Verb.MOVE_TO:
			# Travel to a chosen place is the same movement as a seek; its
			# commitment is the same because both re-aim at a fixed cell.
			return params.f("commit", "seek_seconds", 2.0)
		StoreRef.Verb.EAT:
			return params.f("commit", "eat_seconds", 2.0)
		StoreRef.Verb.DRINK:
			return params.f("commit", "drink_seconds", 1.5)
		StoreRef.Verb.REST:
			return params.f("commit", "rest_seconds", 3.0)
		StoreRef.Verb.APPROACH:
			return params.f("commit", "approach_seconds", 2.0)
		StoreRef.Verb.MATE:
			return params.f("commit", "mate_seconds", 0.8)
		StoreRef.Verb.SOCIALISE:
			return params.f("commit", "socialise_seconds", 1.0)
		StoreRef.Verb.AVOID:
			return params.f("commit", "avoid_seconds", 1.0)
		StoreRef.Verb.PICKUP:
			return params.f("commit", "pickup_seconds", 1.5)
		StoreRef.Verb.PILE:
			return params.f("commit", "pile_seconds", 1.5)
		StoreRef.Verb.FLEE:
			return params.f("commit", "flee_seconds", 1.2)
	return 0.0


func _execute_all(step_dt: float) -> void:
	var speed_cells := params.f("movement", "speed_cells_per_sec", 2.5)
	for i in store.count:
		if store.alive[i] == 0:
			continue
		store.action_time[i] += step_dt
		if store.commitment[i] > 0.0:
			store.commitment[i] = maxf(0.0, store.commitment[i] - step_dt)
		store.vx[i] = 0.0
		store.vy[i] = 0.0
		var carry_density := grid.density_of(int(store.carry_material[i]))
		var own_speed := speed_cells * GenomeRef.speed_factor(store, i) * GenomeRef.carry_factor(store, i, carry_density, params.f("carry", "speed_penalty", 0.4))
		match int(store.verb[i]):
			StoreRef.Verb.WANDER:
				if _distance_to_aim(i) <= params.f("movement", "arrive_radius", 1.2):
					store.commitment[i] = 0.0
				else:
					walk_toward(i, store.aim_x[i], store.aim_y[i], step_dt, own_speed)
			StoreRef.Verb.SEEK:
				_do_seek(i, step_dt, own_speed)
			StoreRef.Verb.MOVE_TO:
				_do_seek(i, step_dt, own_speed)
			StoreRef.Verb.EAT:
				_do_eat(i, step_dt)
			StoreRef.Verb.DRINK:
				_do_drink(i, step_dt)
			StoreRef.Verb.REST:
				_do_rest(i, step_dt)
			StoreRef.Verb.APPROACH:
				_do_approach(i, step_dt, own_speed)
			StoreRef.Verb.MATE:
				_do_mate(i)
			StoreRef.Verb.SOCIALISE:
				_do_socialise(i)
			StoreRef.Verb.AVOID:
				_do_avoid(i, step_dt, own_speed)
			StoreRef.Verb.PICKUP:
				_do_pickup(i, step_dt)
			StoreRef.Verb.PILE:
				_do_pile(i, step_dt)
			StoreRef.Verb.FLEE:
				safety.do_flee(self, i, step_dt, own_speed)

	_compact_under_creatures(step_dt)


## Standing on sand compacts it a little; resting compacts it much more. This is
## the world-edit half of the hardening chain, and it costs one array write per
## creature because compaction is not rendered.
func _compact_under_creatures(step_dt: float) -> void:
	var rate := params.f("materials", "creature_compaction_per_sec", 0.02)
	if rate <= 0.0:
		return
	for i in store.count:
		if store.alive[i] == 0:
			continue
		var cx := int(floor(store.px[i]))
		var cy := int(floor(store.py[i]))
		if not grid.in_bounds(cx, cy):
			continue
		var idx := grid.index(cx, cy)
		if int(grid.material[idx]) != GridRef.SAND:
			continue
		var mult := 1.0 if int(store.verb[i]) == StoreRef.Verb.REST else 0.35
		grid.compaction[idx] = minf(1.0, grid.compaction[idx] + rate * mult * step_dt)


func _distance_to_aim(i: int) -> float:
	var dx := store.aim_x[i] - store.px[i]
	var dy := store.aim_y[i] - store.py[i]
	return sqrt(dx * dx + dy * dy)


## Move to a remembered or chosen cell. Seek and move-to share this movement:
## the difference is how the target was found, not how it is walked.
func _do_seek(i: int, step_dt: float, speed_cells: float) -> void:
	var cell := int(store.aim_cell[i])
	if cell >= 0 and cell < grid.material.size() and grid.amount[cell] <= 0.01:
		# A remembered place that turned out empty is forgotten. This is how a
		# dried pond stops attracting visits without a separate rule.
		if memory_enabled:
			memory.forget_place(i, cell)
	if cell < 0 or cell >= grid.material.size() or grid.amount[cell] <= 0.01:
		store.commitment[i] = 0.0
		return
	var tx := float(grid.cell_x(cell)) + 0.5
	var ty := float(grid.cell_y(cell)) + 0.5
	var dx := tx - store.px[i]
	var dy := ty - store.py[i]
	var dist := sqrt(dx * dx + dy * dy)
	if dist <= params.f("movement", "arrive_radius", 1.2):
		store.commitment[i] = 0.0
		return
	walk_toward(i, tx, ty, step_dt, speed_cells)


func _do_eat(i: int, step_dt: float) -> void:
	# A creature eats until its own setpoint, not to full: a small appetite is
	# cheaper to carry and leaves more for everything else.
	if store.food_level[i] >= store.body_value(i, GenomeRef.F_HUNGER_SET):
		store.commitment[i] = 0.0
		return
	var food_before := store.food_level[i]
	var cell := _reachable_resource(i, GridRef.FOOD)
	if cell < 0:
		# No food in reach: a carried meal is still a meal. The same eat verb
		# consumes the load, so a starving carrier is never stranded beside its
		# own food by a rule about where food is allowed to be.
		if int(store.carry_material[i]) == GridRef.FOOD and store.carry_amount[i] > 0.0:
			_eat_carried(i, step_dt)
		else:
			store.commitment[i] = 0.0
		return
	var cell_amount_before := float(grid.amount[cell])
	var nutr := float(grid.nutrition[cell])
	var toxicity := float(grid.toxicity[cell])
	var intake := 0.7 + 0.5 * store.body_value(i, GenomeRef.F_STOMACH)
	var want := params.f("metabolism", "eat_rate_per_sec", 0.6) * step_dt * intake
	var taken := grid.consume(grid.cell_x(cell), grid.cell_y(cell), want)
	if taken <= 0.0:
		store.commitment[i] = 0.0
		return
	store.food_level[i] = minf(1.0, store.food_level[i] + taken * nutr * params.f("metabolism", "hunger_relief_per_food", 1.4))
	store.aim_cell[i] = cell
	# A cache is a physical place, so any creature that eats from one is part of
	# the storing story; the log names both the eater and the builder.
	story.note_cache_eaten(self, i, cell, food_before)
	# Delayed evaluation of the store action: eating from a cache this creature
	# piled earlier credits the pick-up and pile weights that made the cache
	# exist. The formula is the same one rule, applied to the action whose
	# outcome arrived late; the context and stress are the ones at piling time.
	if memory_enabled and cell == store.pile_cell[i] and day() - store.pile_day[i] <= params.f("carry", "cache_lesson_days", 1.0):
		var gain := clampf(store.food_level[i] - food_before, 0.0, 1.0)
		if gain > 0.001:
			var rate := params.f("memory", "learning_rate", 0.25)
			memory.learn(i, StoreRef.Verb.PILE, int(store.pile_context[i]), store.pile_stress[i], gain, rate)
			memory.learn(i, StoreRef.Verb.PICKUP, int(store.pile_context[i]), store.pile_stress[i], gain, rate)
			store.pile_cell[i] = -1
	if toxicity > 0.0:
		var gain: float = params.f("memory", "toxin_gain_per_food", 4.0)
		store.toxin[i] = minf(1.0, store.toxin[i] + taken * toxicity * gain)
	# Remember where the meal was, and how much was standing there. The record
	# is refreshed while the creature keeps eating from the same cell.
	var found_value := clampf(float(grid.amount[cell]) * nutr, 0.0, 1.0)
	if memory_enabled:
		memory.remember_place(i, cell, GridRef.FOOD, found_value, day())
		_teach_place(i, cell, GridRef.FOOD, found_value)
	# The same bite is a social event for anyone beside the eater who was also
	# heading into this patch. It costs nothing to notice and is the only
	# negative event in the slice, so rivalries have to come from real
	# competition over a finite meal rather than a coded dislike.
	if social_enabled and taken > 0.0:
		harm.contest_food(self, i, cell, cell_amount_before)
	# Rot is a property of the cell, not knowledge the creature has. Nothing
	# avoids it yet; that arrives with the learning rule.
	if toxicity > 0.0:
		var damage := toxicity * params.f("materials", "eat_toxicity_damage_per_sec", 0.06) * step_dt
		store.health[i] = maxf(0.0, store.health[i] - damage)
		if store.health[i] <= 0.0:
			_pending_deaths.append(i)
			_pending_cause[i] = StoreRef.Death.POISONING


## Eating from the load, when no cell is in reach. Same relief and same toxin
## as a cell meal; the difference is only where the material is.
func _eat_carried(i: int, step_dt: float) -> void:
	var intake := 0.7 + 0.5 * store.body_value(i, GenomeRef.F_STOMACH)
	var want := params.f("metabolism", "eat_rate_per_sec", 0.6) * step_dt * intake
	var taken := minf(store.carry_amount[i], want)
	if taken <= 0.0001:
		store.commitment[i] = 0.0
		return
	var nutr := store.carry_nutrition[i]
	var toxicity := store.carry_toxicity[i]
	store.carry_amount[i] -= taken
	if store.carry_amount[i] <= 0.001:
		clear_carry(i)
	store.food_level[i] = minf(1.0, store.food_level[i] + taken * nutr * params.f("metabolism", "hunger_relief_per_food", 1.4))
	store.aim_cell[i] = -1
	if toxicity > 0.0:
		store.toxin[i] = minf(1.0, store.toxin[i] + taken * toxicity * params.f("memory", "toxin_gain_per_food", 4.0))
		var damage := toxicity * params.f("materials", "eat_toxicity_damage_per_sec", 0.06) * step_dt
		store.health[i] = maxf(0.0, store.health[i] - damage)
		if store.health[i] <= 0.0:
			_pending_deaths.append(i)
			_pending_cause[i] = StoreRef.Death.POISONING


func clear_carry(i: int) -> void:
	store.carry_material[i] = 0
	store.carry_amount[i] = 0.0
	store.carry_wetness[i] = 0.0
	store.carry_nutrition[i] = 0.0
	store.carry_toxicity[i] = 0.0


## Takes material from the target cell into the load, up to what the body can
## carry. The load keeps the source cell's properties, so wet sand stays wet, and
## food keeps the nutrition and toxin it had where it was found.
func _do_pickup(i: int, step_dt: float) -> void:
	if not carry_enabled:
		store.commitment[i] = 0.0
		return
	var cell := int(store.aim_cell[i])
	if cell < 0 or cell >= grid.material.size():
		store.commitment[i] = 0.0
		return
	var mat := int(grid.material[cell])
	if mat != GridRef.SAND and mat != GridRef.FOOD:
		store.commitment[i] = 0.0
		return
	# One material at a time: a creature can keep filling a load of the same
	# material over several ticks, but cannot mix sand into a carried meal.
	if store.carry_amount[i] > 0.001 and int(store.carry_material[i]) != mat:
		store.commitment[i] = 0.0
		return
	if mat == GridRef.SAND and grid.hardness[cell] >= grid.convert_max_hardness:
		store.commitment[i] = 0.0
		return
	var density := grid.density_of(mat)
	var capacity := maxf(GenomeRef.carry_capacity(store, i), 0.01)
	var room := capacity / maxf(density, 0.01) - store.carry_amount[i]
	if room <= 0.001:
		store.commitment[i] = 0.0
		return
	var amount := minf(room, params.f("carry", "pickup_rate_per_sec", 0.9) * step_dt * (0.7 + 0.6 * store.body_value(i, GenomeRef.F_SIZE)))
	var sample: Dictionary = grid.extract(grid.cell_x(cell), grid.cell_y(cell), amount)
	if sample.is_empty():
		store.commitment[i] = 0.0
		return
	var taken := float(sample["amount"])
	if store.carry_amount[i] <= 0.001:
		store.carry_material[i] = mat
		store.carry_amount[i] = taken
		store.carry_wetness[i] = float(sample["wetness"])
		store.carry_nutrition[i] = float(sample["nutrition"])
		store.carry_toxicity[i] = float(sample["toxicity"])
		if mat == GridRef.FOOD:
			loads_picked_food += 1
		else:
			loads_picked_sand += 1
	else:
		var total := store.carry_amount[i] + taken
		store.carry_wetness[i] = (store.carry_wetness[i] * store.carry_amount[i] + float(sample["wetness"]) * taken) / total
		store.carry_nutrition[i] = (store.carry_nutrition[i] * store.carry_amount[i] + float(sample["nutrition"]) * taken) / total
		store.carry_toxicity[i] = (store.carry_toxicity[i] * store.carry_amount[i] + float(sample["toxicity"]) * taken) / total
		store.carry_amount[i] = total
	if store.carry_amount[i] >= capacity / maxf(density, 0.01) - 0.01:
		store.commitment[i] = 0.0


## Puts the load into the target cell. Piling is the world-edit that makes the
## rest of this slice accumulate: a cache is food in a cell, a structure is sand
## in a cell, and both outlive the action.
func _do_pile(i: int, step_dt: float) -> void:
	if not carry_enabled or store.carry_amount[i] <= 0.001:
		store.commitment[i] = 0.0
		return
	var cell := int(store.aim_cell[i])
	if cell < 0 or cell >= grid.material.size():
		store.commitment[i] = 0.0
		return
	var mat := int(store.carry_material[i])
	var want := minf(store.carry_amount[i], params.f("carry", "deposit_rate_per_sec", 2.0) * step_dt * (0.7 + 0.6 * store.body_value(i, GenomeRef.F_SIZE)))
	var deposited := grid.deposit(
		grid.cell_x(cell), grid.cell_y(cell), mat, want,
		store.carry_wetness[i], store.carry_nutrition[i], store.carry_toxicity[i]
	)
	if deposited <= 0.0001:
		store.commitment[i] = 0.0
		return
	store.carry_amount[i] -= deposited
	# The outcome record the delayed learning rule reads if this creature later
	# eats from its own food cache. It also gives the store sequence a short
	# hysteresis: the cell just piled into is not immediately picked up again.
	# Nothing selects an action from the material name.
	store.pile_cell[i] = cell
	store.pile_day[i] = day()
	store.pile_context[i] = store.mem_context[i]
	store.pile_stress[i] = store.mem_stress[i]
	if store.carry_amount[i] <= 0.001:
		if mat == GridRef.FOOD:
			loads_piled_food += 1
			store.piled_food[i] += 1
		else:
			loads_piled_sand += 1
		story.note_pile(self, i, cell, mat, store.carry_wetness[i])
		clear_carry(i)
		store.commitment[i] = 0.0


func _do_drink(i: int, step_dt: float) -> void:
	if store.water_level[i] >= store.body_value(i, GenomeRef.F_THIRST_SET):
		store.commitment[i] = 0.0
		return
	var cell := _reachable_resource(i, GridRef.WATER)
	if cell < 0:
		store.commitment[i] = 0.0
		return
	var intake := 0.7 + 0.5 * store.body_value(i, GenomeRef.F_STOMACH)
	var want := params.f("metabolism", "drink_rate_per_sec", 0.9) * step_dt * intake
	var taken := grid.consume(grid.cell_x(cell), grid.cell_y(cell), want)
	if taken <= 0.0:
		store.commitment[i] = 0.0
		return
	store.water_level[i] = minf(1.0, store.water_level[i] + taken * params.f("metabolism", "thirst_relief_per_water", 1.2))
	store.aim_cell[i] = cell
	var found_value := clampf(float(grid.amount[cell]), 0.0, 1.0)
	if memory_enabled:
		memory.remember_place(i, cell, GridRef.WATER, found_value, day())
		_teach_place(i, cell, GridRef.WATER, found_value)


## Observation, not language: a creature that visibly feeds or drinks teaches
## everyone close enough to watch. The copy is weaker than firsthand knowledge,
## scaled by the observer's imitation-fidelity gene, by how close it was, and by
## youth (children copy more readily). A place already known personally is never
## overwritten by a weaker copy.
func _teach_place(source: int, cell: int, material: int, value: float) -> void:
	if not memory_enabled:
		return
	var radius := params.f("imitation", "teach_radius_cells", 9.0)
	if radius <= 0.0 or value < 0.02:
		return
	var cooldown := params.f("imitation", "teach_cooldown_seconds", 1.0)
	if time - store.teach_time[source] < cooldown:
		return
	store.teach_time[source] = time
	var fraction := params.f("imitation", "copy_fraction", 0.5)
	var youth := params.f("imitation", "youth_multiplier", 1.4)
	var minimum := params.f("imitation", "min_copy_value", 0.02)
	var sx := store.px[source]
	var sy := store.py[source]
	for j in neighbors.query_radius(store, sx, sy, radius):
		if j == source or j < 0 or j >= store.count or store.alive[j] == 0:
			continue
		var dx := store.px[j] - sx
		var dy := store.py[j] - sy
		var dist := sqrt(dx * dx + dy * dy)
		var fidelity: float = store.body_value(j, GenomeRef.F_IMITATION)
		var age_mult := 1.0
		if int(store.stage[j]) == StoreRef.CHILD:
			age_mult = youth
		elif int(store.stage[j]) == StoreRef.OLD:
			age_mult = 0.8
		var copied := value * fraction * fidelity * age_mult * (1.0 - clampf(dist / radius, 0.0, 1.0))
		if copied < minimum:
			continue
		memory.remember_place_seen(j, cell, material, copied, day())


func _do_rest(i: int, _step_dt: float) -> void:
	var energy_done: bool = store.energy_level[i] >= store.body_value(i, GenomeRef.F_REST_SET)
	var cx := int(floor(store.px[i]))
	var cy := int(floor(store.py[i]))
	var quality := 0.0
	if grid.in_bounds(cx, cy):
		quality = grid.comfort_quality(grid.index(cx, cy))
	# Comfort can keep a rested creature on good ground, but a cell with no
	# affordance at all (water or air) ends the rest once energy is done. Poor
	# ground is a trade-off the brain has to weigh, not a hidden veto here.
	if energy_done and (store.comfort_level[i] >= 0.98 or quality <= 0.05):
		store.commitment[i] = 0.0
		return
	# Resting holds a creature still in one place. Phase 1 turns that into the
	# main compaction source for hardening ground, so the effect is already
	# expressed by not asking the creature to move.


func _do_approach(i: int, step_dt: float, speed_cells: float) -> void:
	var j := int(store.aim_creature[i])
	if j < 0 or j >= store.count or store.alive[j] == 0:
		store.commitment[i] = 0.0
		store.aim_creature[i] = -1
		return
	var dx := store.px[j] - store.px[i]
	var dy := store.py[j] - store.py[i]
	if sqrt(dx * dx + dy * dy) <= params.f("movement", "arrive_radius", 1.2) + 0.35:
		store.commitment[i] = 0.0
		return
	walk_toward(i, store.px[j], store.py[j], step_dt, speed_cells)


func _do_socialise(i: int) -> void:
	var j := int(store.aim_creature[i])
	if j < 0 or j >= store.count or store.alive[j] == 0 or j == i:
		store.commitment[i] = 0.0
		store.aim_creature[i] = -1
		return
	var dx := store.px[j] - store.px[i]
	var dy := store.py[j] - store.py[i]
	if sqrt(dx * dx + dy * dy) > params.f("social", "contact_radius_cells", 2.5):
		store.commitment[i] = 0.0
		return
	# One exchange per tick. If the partner already initiated against this
	# creature, the second half of the pair records nothing and does not double
	# every opinion in the world.
	if store.social_time[j] >= time - 0.0001:
		store.commitment[i] = 0.0
		return
	var urgency_i := 1.0 - store.social_level[i]
	var urgency_j := 1.0 - store.social_level[j]
	var relief := params.f("social", "socialise_relief", 0.45)
	var gain := params.f("social", "socialise_gain", 0.10)
	var sociality_i := store.body_value(i, GenomeRef.F_SOCIALITY)
	var sociality_j := store.body_value(j, GenomeRef.F_SOCIALITY)
	var social_read := social_enabled and opinion_enabled
	var opinion_i := opinion.opinion(store, i, j, day()) if social_read else 0.0
	var opinion_j := opinion.opinion(store, j, i, day()) if social_read else 0.0
	store.social_time[i] = time
	store.social_time[j] = time
	store.social_level[i] = minf(1.0, store.social_level[i] + relief * (0.7 + 0.6 * sociality_i))
	store.social_level[j] = minf(1.0, store.social_level[j] + relief * (0.7 + 0.6 * sociality_j))
	if social_enabled:
		# Valence is asymmetric on purpose: the same meeting is worth more to
		# the lonelier creature and to the one that already likes the company.
		add_opinion(i, j, gain * (0.35 + 0.65 * clampf(urgency_i, 0.0, 1.0)) * (1.0 + 0.25 * sociality_i) * (1.0 + 0.4 * maxf(opinion_i, 0.0)), "shared company")
		add_opinion(j, i, gain * (0.35 + 0.65 * clampf(urgency_j, 0.0, 1.0)) * (1.0 + 0.25 * sociality_j) * (1.0 + 0.4 * maxf(opinion_j, 0.0)), "shared company")
		# A share is the same exchange with a meal in it. The normal company
		# credit above already happened; this adds the food-specific credit and
		# moves the material. It is one event, not a second social exchange.
		share.try_share(self, i, j)
		social_events += 1
	store.commitment[i] = 0.0
	store.aim_creature[i] = -1


func _do_avoid(i: int, step_dt: float, speed_cells: float) -> void:
	var j := int(store.aim_creature[i])
	if j < 0 or j >= store.count or store.alive[j] == 0:
		store.commitment[i] = 0.0
		store.aim_creature[i] = -1
		return
	var dx := store.px[i] - store.px[j]
	var dy := store.py[i] - store.py[j]
	var dist := sqrt(dx * dx + dy * dy)
	var retreat := params.f("social", "avoid_radius_cells", 4.5)
	if dist >= retreat:
		store.commitment[i] = 0.0
		return
	if dist < 0.0001:
		dx = 1.0
		dy = 0.0
		dist = 1.0
	var tx := clampf(store.px[i] + dx / dist * retreat, 1.0, float(grid.width - 2))
	var ty := clampf(store.py[i] + dy / dist * retreat, 1.0, float(grid.height - 2))
	walk_toward(i, tx, ty, step_dt, speed_cells)


## Public view for the inspector; SimSafety owns the calculation.
func nearest_threat(id: int) -> Dictionary:
	return safety.nearest_threat(self, id)


## One opinion event, logged only when it changes how the creature would treat
## the other: crossing a label threshold is the causal step worth showing, not
## every bite or meeting.
func add_opinion(a: int, b: int, delta: float, reason: String) -> void:
	if not social_enabled or not opinion_enabled:
		return
	var result: Dictionary = opinion.add(a, b, delta, day())
	if result.is_empty():
		return
	story.note_opinion(a, b, reason, delta, day())
	if bool(result.get("rival", false)):
		log.push(
			time,
			"social",
			"Creature %d now treats %d as a rival — %d events (%s), opinion %+.2f." % [
				a, b, int(result["events"]), story.negative_chain(a, b), float(result["valence"])
			],
			a
		)
	elif bool(result.get("friend", false)):
		log.push(
			time,
			"social",
			"Creature %d now counts %d as a friend after %s — %d events, opinion %+.2f." % [
				a, b, reason, int(result["events"]), float(result["valence"])
			],
			a
		)


func _do_mate(i: int) -> void:
	var j := int(store.aim_creature[i])
	if j < 0 or j >= store.count or store.alive[j] == 0:
		store.commitment[i] = 0.0
		store.aim_creature[i] = -1
		return
	var child := mate(i, j)
	if child >= 0 and social_enabled:
		var gain := params.f("social", "mate_opinion_gain", 0.12)
		add_opinion(i, j, gain, "mating")
		add_opinion(j, i, gain, "mating")
	store.commitment[i] = 0.0
	store.aim_creature[i] = -1


## Whether a creature may breed right now. The gate is generic: past childhood,
## rested, fed, watered, healthy, off cooldown. There is no breeding season and
## no species-specific trigger; scarcity closes the gate by emptying the needs.
## Old age is a decline, not a reproductive cutoff: a healthy old creature can
## still breed, so adult and old cohorts overlap while health allows it.
func is_repro_ready(id: int) -> bool:
	return _repro_ready_with(
		id,
		params.f("repro", "gate_food", 0.55),
		params.f("repro", "gate_water", 0.55),
		params.f("repro", "gate_energy", 0.55),
		params.f("repro", "gate_health", 0.70)
	)


## Gate with the thresholds already read. The mate search checks this for every
## nearby creature, and four register lookups per candidate per tick was most of
## the decision cost once the population passed twenty.
func _repro_ready_with(id: int, gate_food: float, gate_water: float, gate_energy: float, gate_health: float) -> bool:
	if id < 0 or id >= store.count or store.alive[id] == 0:
		return false
	if int(store.stage[id]) == StoreRef.CHILD:
		return false
	if store.cooldown_days[id] > 0.0:
		return false
	if store.health[id] < gate_health:
		return false
	# The gate reads "adequately fed" as the creature's own setpoint, not a
	# global number. A small-appetite creature that stops eating at 0.40 was
	# previously sterile forever because the fixed 0.55 floor was above what its
	# own body would ever hold; the high-appetite floor still applies above it.
	var food_need := minf(gate_food, store.body_value(id, GenomeRef.F_HUNGER_SET) * 0.90)
	var water_need := minf(gate_water, store.body_value(id, GenomeRef.F_THIRST_SET) * 0.90)
	var rest_need := minf(gate_energy, store.body_value(id, GenomeRef.F_REST_SET) * 0.90)
	if store.food_level[id] < food_need:
		return false
	if store.water_level[id] < water_need:
		return false
	if store.energy_level[id] < rest_need:
		return false
	return true


## Nearest willing, compatible adult within reproductive range. Returns
## [id, distance], id -1 when there is none. Perception is the same kind of
## approximation as food search: the creature knows who is close, not who
## exists.
func _nearest_mate(i: int, search: float, min_distance: float, gate_food: float, gate_water: float, gate_energy: float, gate_health: float) -> Array:
	var best := -1
	var best_d := 1.0e9
	for j in neighbors.query_radius(store, store.px[i], store.py[i], search):
		if j == i or not _repro_ready_with(j, gate_food, gate_water, gate_energy, gate_health):
			continue
		if not _kin_ok(i, j):
			continue
		# A creature does not choose a partner it has come to dislike, even if
		# every physical condition of the gate is met. The gate stays generic.
		if social_enabled and opinion_enabled and opinion.opinion(store, i, j, day()) < params.f("social", "mate_refuse_opinion", -0.4):
			continue
		if GenomeRef.distance_store(store, i, j) < min_distance:
			continue
		var dx := store.px[j] - store.px[i]
		var dy := store.py[j] - store.py[i]
		var d := sqrt(dx * dx + dy * dy)
		if d < best_d:
			best_d = d
			best = j
	return [best, best_d]


## Close kin do not pair: parent/child and siblings are excluded. Mating
## probability also falls with genetic distance in _nearest_mate, which keeps
## recognisably different lineages instead of one blended population.
func _kin_ok(a: int, b: int) -> bool:
	if store.mother[a] == b or store.father[a] == b:
		return false
	if store.mother[b] == a or store.father[b] == a:
		return false
	if store.mother[a] >= 0 and (store.mother[a] == store.mother[b] or store.mother[a] == store.father[b]):
		return false
	if store.father[a] >= 0 and (store.father[a] == store.mother[b] or store.father[a] == store.father[b]):
		return false
	return true


## Reproduction gate in action: both creatures must pass it at the moment of
## contact. Returns the child id, or -1 when the attempt does not produce one.
## Preference for a partner lives in the brain; the gate lives here so no verb
## can bypass it.
func mate(mother_id: int, father_id: int) -> int:
	if mother_id == father_id:
		return -1
	if not is_repro_ready(mother_id) or not is_repro_ready(father_id):
		return -1
	if not _kin_ok(mother_id, father_id):
		return -1
	if GenomeRef.distance_store(store, mother_id, father_id) < params.f("repro", "min_genetic_distance", 0.04):
		return -1
	var dx := store.px[father_id] - store.px[mother_id]
	var dy := store.py[father_id] - store.py[mother_id]
	if sqrt(dx * dx + dy * dy) > params.f("repro", "contact_radius_cells", 2.5):
		return -1

	var genes := GenomeRef.child(store.genome_at(mother_id), store.genome_at(father_id), rng, params)
	var spot := _birth_position(mother_id)
	var start: float = params.f("repro", "child_need_start", 0.85)
	var child := store.spawn_genome(
		spot.x,
		spot.y,
		genes["genome"],
		start,
		start,
		start,
		mother_id,
		father_id,
		maxi(int(store.generation[mother_id]), int(store.generation[father_id])) + 1,
		int(genes["mutations"]),
		time
	)
	store.offspring[mother_id] += 1
	store.offspring[father_id] += 1
	# A child starts with a blank memory store. The slot may have held a dead
	# creature's learning, so it is cleared explicitly.
	memory.ensure(store.count)
	memory.reset(child)
	opinion.ensure(store.count)
	opinion.reset(child)
	history.note_birth(self, child, mother_id, father_id)
	# A longer refractory period, drawn independently for each parent, keeps
	# births from returning as one synchronized pulse. The jitter is a real
	# spread in the interval, not a smaller cooldown with a different label.
	var cooldown: float = params.f("repro", "cooldown_days", 0.65)
	var jitter: float = maxf(params.f("repro", "cooldown_jitter_days", 0.05), 0.0)
	store.cooldown_days[mother_id] = maxf(0.05, cooldown + rng.randf_range(-jitter, jitter))
	store.cooldown_days[father_id] = maxf(0.05, cooldown + rng.randf_range(-jitter, jitter))
	var cost: float = params.f("repro", "energy_cost", 0.30)
	store.energy_level[mother_id] = maxf(0.0, store.energy_level[mother_id] - cost)
	store.energy_level[father_id] = maxf(0.0, store.energy_level[father_id] - cost)
	births += 1
	log.push(
		time,
		"birth",
		"Creature %d born to %d and %d — generation %d, %d mutations, near %d,%d." % [
			child,
			mother_id,
			father_id,
			int(store.generation[child]),
			int(store.mutations[child]),
			int(store.px[child]),
			int(store.py[child]),
		],
		child
	)
	return child


## A free, dry cell near the mother. Occupancy is checked so a birth does not
## put two creatures in the same spot.
func _birth_position(mother_id: int) -> Vector2:
	var cx := int(floor(store.px[mother_id]))
	var cy := int(floor(store.py[mother_id]))
	var reach := params.i("repro", "birth_radius_cells", 2)
	for _attempt in 12:
		var tx := cx + rng.randi_range(-reach, reach)
		var ty := cy + rng.randi_range(-reach, reach)
		if not grid.in_bounds(tx, ty):
			continue
		if grid.material_at(tx, ty) == GridRef.WATER:
			continue
		var fx := float(tx) + 0.5
		var fy := float(ty) + 0.5
		if not neighbors.query_radius(store, fx, fy, 0.6).is_empty():
			continue
		return Vector2(fx, fy)
	return Vector2(store.px[mother_id], store.py[mother_id])


func _reachable_resource(i: int, mat: int) -> int:
	var cx := int(floor(store.px[i]))
	var cy := int(floor(store.py[i]))
	var best := -1
	var best_value := 0.0
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var tx := cx + ox
			var ty := cy + oy
			if not grid.in_bounds(tx, ty):
				continue
			var idx := grid.index(tx, ty)
			if int(grid.material[idx]) != mat:
				continue
			if mat == GridRef.FOOD and grid.amount[idx] <= grid.food_min_amount:
				continue
			var value := float(grid.amount[idx])
			if mat == GridRef.FOOD:
				value *= float(grid.nutrition[idx])
			if value > best_value:
				best_value = value
				best = idx
	return best


## Shared movement primitive: walk toward a point with separation, used by
## seek, avoid and flee.
func walk_toward(i: int, tx: float, ty: float, step_dt: float, speed_cells: float) -> void:
	var x := store.px[i]
	var y := store.py[i]
	var dx := tx - x
	var dy := ty - y
	var dist := sqrt(dx * dx + dy * dy)
	var desired_x := 0.0
	var desired_y := 0.0
	if dist > 0.0001:
		desired_x = dx / dist
		desired_y = dy / dist

	# Separation: the only thing stopping twenty creatures converging on one
	# cell. It is a steering term, not a repulsion rule with a special case.
	var sep_radius := params.f("movement", "separation_radius", 1.6)
	var sep_strength := params.f("movement", "separation_strength", 1.2)
	var sep_x := 0.0
	var sep_y := 0.0
	var near := neighbors.query_radius(store, x, y, sep_radius)
	for j in near:
		if j == i:
			continue
		var ox := x - store.px[j]
		var oy := y - store.py[j]
		var d2 := ox * ox + oy * oy
		if d2 < 0.0001:
			# Deterministic nudge so two creatures in the same spot separate.
			ox = float((i % 7) - 3) * 0.01 + 0.02
			oy = float((j % 5) - 2) * 0.01 + 0.02
			d2 = ox * ox + oy * oy
			if d2 < 0.0001:
				d2 = 0.0001
		var d := sqrt(d2)
		if d < sep_radius:
			var push := 1.0 - d / sep_radius
			sep_x += (ox / d) * push
			sep_y += (oy / d) * push

	var vx := desired_x * speed_cells + sep_x * sep_strength * speed_cells * 0.5
	var vy := desired_y * speed_cells + sep_y * sep_strength * speed_cells * 0.5
	store.vx[i] = vx
	store.vy[i] = vy
	var nx := clampf(x + vx * step_dt, 1.0, float(grid.width - 2))
	var ny := clampf(y + vy * step_dt, 1.0, float(grid.height - 2))
	store.path_travelled[i] += sqrt((nx - x) * (nx - x) + (ny - y) * (ny - y))
	store.px[i] = nx
	store.py[i] = ny


## Queue one death with its proximate cause. Harm uses this; the apply pass
## remains the only place that mutates alive state.
func queue_death(id: int, cause: int) -> void:
	if _pending_cause.has(id):
		return
	_pending_deaths.append(id)
	_pending_cause[id] = cause


func _apply_deaths() -> void:
	for i in _pending_deaths:
		if store.alive[i] == 0:
			continue
		# A death is also a world edit: whatever the creature was carrying falls
		# where it stood. The cell keeps it if it can accept the material, and
		# the loss otherwise is honest.
		if store.carry_amount[i] > 0.001:
			var dx := int(floor(store.px[i]))
			var dy := int(floor(store.py[i]))
			if grid.in_bounds(dx, dy):
				grid.deposit(
					dx, dy, int(store.carry_material[i]), store.carry_amount[i],
					store.carry_wetness[i], store.carry_nutrition[i], store.carry_toxicity[i]
				)
		var cause := -1
		if _pending_cause.has(i):
			cause = int(_pending_cause[i])
		else:
			var starving := store.food_level[i] <= 0.0001
			var dehydrated := store.water_level[i] <= 0.0001
			cause = StoreRef.Death.STARVATION
			if starving and dehydrated:
				cause = StoreRef.Death.STARVATION_AND_DEHYDRATION
			elif dehydrated:
				cause = StoreRef.Death.DEHYDRATION
		store.kill(i, cause, time)
		death_counts[cause] += 1
		history.note_death(self, i, cause)
		log.push(
			time,
			"death",
			"Creature %d died of %s at day %.1f." % [i, store.death_name(cause), day()],
			i
		)


func generate_world() -> void:
	var margin := params.i("world_gen", "edge_margin", 28)
	pond_centers.clear()

	# Mostly open ground: loose sand everywhere, then dunes on top of it.
	for y in grid.height:
		for x in grid.width:
			grid.set_cell(x, y, GridRef.SAND, 0.25)

	var dune_count := params.i("world_gen", "dunes", 70)
	for k in dune_count:
		var cx := rng.randi_range(margin, grid.width - margin)
		var cy := rng.randi_range(margin, grid.height - margin)
		var radius := rng.randf_range(5.0, 22.0)
		var height := rng.randf_range(0.4, 1.1)
		_raise_sand(cx, cy, radius, height)

	# Ponds. Placed apart from each other so water is a journey, not a puddle.
	var pond_count := params.i("world_gen", "ponds", 4)
	var ponds_placed := 0
	var attempts := 0
	while ponds_placed < pond_count and attempts < 200:
		attempts += 1
		var cx := rng.randi_range(margin, grid.width - margin)
		var cy := rng.randi_range(margin, grid.height - margin)
		var too_close := false
		for other in pond_centers:
			if Vector2(other).distance_to(Vector2(cx, cy)) < 70.0:
				too_close = true
				break
		if too_close:
			continue
		var rx := rng.randf_range(6.0, 11.0)
		var ry := rng.randf_range(5.0, 9.0)
		for y in range(cy - int(ry) - 1, cy + int(ry) + 2):
			for x in range(cx - int(rx) - 1, cx + int(rx) + 2):
				if not grid.in_bounds(x, y):
					continue
				var nx := float(x - cx) / rx
				var ny := float(y - cy) / ry
				if nx * nx + ny * ny <= 1.0:
					grid.set_cell(x, y, GridRef.WATER, rng.randf_range(0.85, 1.0))
		_harden_pond_bed(cx, cy, rx, ry)
		_wet_pond_surroundings(cx, cy, rx, ry)
		pond_centers.append(Vector2i(cx, cy))
		ponds_placed += 1

	# Food patches. Player placement is the real food source; these seed the
	# first session so the toy can be watched without input. A few patches in
	# sight of the founding site make eating and drinking observable in the
	# first minutes; the rest are scattered so discovery still costs a walk.
	var patch_count := params.i("world_gen", "food_patches", 20)
	for k in patch_count:
		var cx := rng.randi_range(margin, grid.width - margin)
		var cy := rng.randi_range(margin, grid.height - margin)
		_place_food_patch(cx, cy, rng.randf_range(1.3, 2.8))

	var nearby := params.i("world_gen", "nearby_food_patches", 6)
	var home := _founder_center()
	for k in nearby:
		var angle := rng.randf_range(0.0, TAU)
		var distance := rng.randf_range(9.0, 22.0)
		var cx := int(clampf(home.x + cos(angle) * distance, float(margin), float(grid.width - margin)))
		var cy := int(clampf(home.y + sin(angle) * distance, float(margin), float(grid.height - margin)))
		_place_food_patch(cx, cy, rng.randf_range(2.2, 3.2))

	grid.mark_all_dirty()
	# World generation touches every chunk; only water and wet ground need to
	# simulate on the first tick.
	grid.clear_activity()
	grid.activate_dynamic()
	log.push(0.0, "world", "World seeded: %d ponds, %d food patches, seed %d." % [ponds_placed, patch_count, seed_used])


## A pond in loose sand drains into the ground in minutes and is gone before
## anyone can learn where it was. The pond floor and rim start as hard sand, a
## pan the water cannot soak through; flooding it softens it again, which is the
## material system doing the work rather than a special case in flow.
func _harden_pond_bed(cx: int, cy: int, rx: float, ry: float) -> void:
	var reach_x := int(rx) + 2
	var reach_y := int(ry) + 2
	for y in range(cy - reach_y, cy + reach_y + 1):
		for x in range(cx - reach_x, cx + reach_x + 1):
			if not grid.in_bounds(x, y):
				continue
			var i := grid.index(x, y)
			if int(grid.material[i]) != GridRef.SAND:
				continue
			if not _touches_water(x, y):
				continue
			grid.hardness[i] = 0.9
			grid.cohesion[i] = 0.9
			grid.compaction[i] = 0.7
			grid.wet_history[i] = maxf(grid.wet_history[i], 0.7)


func _touches_water(x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if grid.material_at(x + dx, y + dy) == GridRef.WATER:
				return true
	return false


## Ponds start with saturated surroundings, otherwise the first ticks drain the
## pond into dry sand and the founding water disappears before anyone drinks.
func _wet_pond_surroundings(cx: int, cy: int, rx: float, ry: float) -> void:
	var reach_x := int(rx) + 5
	var reach_y := int(ry) + 9
	for y in range(cy - reach_y, cy + reach_y + 1):
		for x in range(cx - reach_x, cx + reach_x + 1):
			if not grid.in_bounds(x, y):
				continue
			var i := grid.index(x, y)
			if int(grid.material[i]) != GridRef.SAND:
				continue
			# The pan stays dry behind its hard face: wetting it would soften the
			# very shell that holds the pond, and the pond would drain itself.
			if grid.hardness[i] >= grid.convert_max_hardness:
				continue
			var nx := float(x - cx) / (rx + 4.0)
			var ny := float(y - cy) / (ry + 8.0)
			if nx * nx + ny * ny > 1.0:
				continue
			grid.wetness[i] = maxf(grid.wetness[i], 0.9)
			grid.wet_history[i] = maxf(grid.wet_history[i], 0.55)


func _place_food_patch(cx: int, cy: int, radius: float) -> void:
	for y in range(cy - 4, cy + 5):
		for x in range(cx - 4, cx + 5):
			if not grid.in_bounds(x, y):
				continue
			var dx := float(x - cx)
			var dy := float(y - cy)
			if dx * dx + dy * dy > radius * radius:
				continue
			if grid.material_at(x, y) == GridRef.WATER:
				continue
			grid.add_material(x, y, GridRef.FOOD, rng.randf_range(0.5, 1.0))


func _raise_sand(cx: int, cy: int, radius: float, height: float) -> void:
	for y in range(cy - int(radius) - 1, cy + int(radius) + 2):
		for x in range(cx - int(radius) - 1, cx + int(radius) + 2):
			if not grid.in_bounds(x, y):
				continue
			var dx := float(x - cx)
			var dy := float(y - cy)
			var d := sqrt(dx * dx + dy * dy)
			if d > radius:
				continue
			var falloff := 1.0 - d / radius
			grid.add_material(x, y, GridRef.SAND, height * falloff)


func spawn_founders(total: int = -1) -> void:
	var n := total if total > 0 else params.i("spawn", "founders", 20)
	var center := _founder_center()
	var radius := params.f("spawn", "cluster_radius_cells", 34.0)
	var need_min := params.f("spawn", "need_min", 0.65)
	var need_max := params.f("spawn", "need_max", 1.0)
	var maturity := params.f("life", "maturity_days", 0.25)
	var spawned := 0
	for k in n:
		for attempt in 80:
			var x := clampf(center.x + rng.randf_range(-radius, radius), 2.0, float(grid.width - 3))
			var y := clampf(center.y + rng.randf_range(-radius, radius), 2.0, float(grid.height - 3))
			if grid.material_at(int(floor(x)), int(floor(y))) == GridRef.WATER:
				continue
			var id := store.spawn_genome(
				x,
				y,
				GenomeRef.random(rng),
				rng.randf_range(need_min, need_max),
				rng.randf_range(need_min, need_max),
				rng.randf_range(need_min, need_max),
				-1,
				-1,
				0,
				0,
				time
			)
			# Founders start adult: the first generation must not need a parent to
			# reach breeding age before the player has seen anything happen.
			store.age_days[id] = maturity
			store.stage[id] = StoreRef.ADULT
			store.body_scale[id] = 1.0
			memory.ensure(store.count)
			memory.reset(id)
			_remember_home_water(id)
			opinion.ensure(store.count)
			opinion.reset(id)
			history.note_birth(self, id, -1, -1)
			spawned += 1
			break
	log.push(0.0, "world", "%d founders placed near the first water." % spawned)


## Founders are placed beside the first pond, and knowing where home water is
## is a starting condition rather than perception cheating: a creature that has
## drunk there all its life does not have to rediscover the pond by wandering.
## Without it most founders began more than a sensory radius from the water they
## were born beside and died of thirst in a world holding 950 water cells.
func _remember_home_water(id: int) -> void:
	if pond_centers.is_empty():
		return
	var best_cell := -1
	var best_dist := 1.0e9
	for p in pond_centers:
		var d := Vector2(store.px[id] - float(p.x), store.py[id] - float(p.y)).length()
		if d < best_dist and int(grid.material[grid.index(p.x, p.y)]) == GridRef.WATER:
			best_dist = d
			best_cell = grid.index(p.x, p.y)
	if best_cell >= 0:
		memory.remember_place(id, best_cell, GridRef.WATER, float(grid.amount[best_cell]), day())


func _founder_center() -> Vector2:
	if pond_centers.is_empty():
		return Vector2(float(grid.width) * 0.5, float(grid.height) * 0.5)
	var p: Vector2i = pond_centers[0]
	return Vector2(float(p.x + 14), float(p.y + 6))


## Deterministic fingerprint of the simulation state, used by the determinism
## test. Quantised so float formatting never matters.
func state_hash() -> int:
	var h := 1469598103934665603
	for i in store.count:
		if store.alive[i] == 0:
			h = h ^ 0x51ED270B
			continue
		h = _hash_int(h, int(round(store.px[i] * 1000.0)))
		h = _hash_int(h, int(round(store.py[i] * 1000.0)))
		h = _hash_int(h, int(round(store.food_level[i] * 1000.0)))
		h = _hash_int(h, int(round(store.water_level[i] * 1000.0)))
		h = _hash_int(h, int(round(store.energy_level[i] * 1000.0)))
		h = _hash_int(h, int(round(store.social_level[i] * 1000.0)))
		h = _hash_int(h, int(round(store.comfort_level[i] * 1000.0)))
		h = _hash_int(h, int(round(store.safety_level[i] * 1000.0)))
		h = _hash_int(h, int(round(store.health[i] * 1000.0)))
		h = _hash_int(h, int(store.verb[i]))
		h = _hash_int(h, int(store.carry_material[i]))
		h = _hash_int(h, int(round(store.carry_amount[i] * 1000.0)))
		h = _hash_int(h, int(store.pile_cell[i]))
		h = _hash_int(h, int(round(store.aim_x[i] * 100.0)))
		h = _hash_int(h, int(round(store.aim_y[i] * 100.0)))
		h = _hash_int(h, int(store.generation[i]))
		h = _hash_int(h, int(round(store.genome[i * GenomeRef.LOCI + GenomeRef.SPEED] * 10000.0)))
		if memory_enabled:
			h = _hash_int(h, memory.digest(i))
		if social_enabled:
			h = _hash_int(h, opinion.digest(i))
	return h & 0x7FFFFFFFFFFFFFFF


func _hash_int(h: int, v: int) -> int:
	return (h ^ v) * 1099511628211


## Mean pairwise genetic distance among the living, for the Phase 2 diversity
## metric and history view. One living creature has no pair, so it reports 0.0
## and the caller treats a tiny sample as unknown rather than collapsed.
func genetic_diversity() -> float:
	return history.diversity(self)


## Compact metrics block for soak runs and reports.
func metrics() -> Dictionary:
	var mix := {}
	var total := 0
	for v in StoreRef.VERB_COUNT:
		total += action_counts[v]
	for v in StoreRef.VERB_COUNT:
		mix[StoreRef.VERB_NAMES[v]] = 0.0 if total == 0 else float(action_counts[v]) / float(total)

	var alive := 0
	var food_sum := 0.0
	var water_sum := 0.0
	var energy_sum := 0.0
	var social_sum := 0.0
	var comfort_sum := 0.0
	var safety_sum := 0.0
	var carried := 0
	var health_sum := 0.0
	var generation_sum := 0
	var max_generation := 0
	var children := 0
	var adults := 0
	var old := 0
	for i in store.count:
		if store.alive[i] == 0:
			continue
		alive += 1
		food_sum += store.food_level[i]
		water_sum += store.water_level[i]
		energy_sum += store.energy_level[i]
		social_sum += store.social_level[i]
		comfort_sum += store.comfort_level[i]
		safety_sum += store.safety_level[i]
		if store.carry_amount[i] > 0.001:
			carried += 1
		health_sum += store.health[i]
		generation_sum += int(store.generation[i])
		max_generation = maxi(max_generation, int(store.generation[i]))
		match int(store.stage[i]):
			StoreRef.CHILD:
				children += 1
			StoreRef.OLD:
				old += 1
			_:
				adults += 1
	var denom := float(maxi(alive, 1))
	var deaths := 0
	for c in range(1, StoreRef.DEATH_NAMES.size()):
		deaths += int(death_counts[c])

	var places := 0
	var learned_creatures := 0
	var opinion_entries := 0
	var friend_bonds := 0
	var rival_bonds := 0
	for i in store.count:
		if store.alive[i] == 0:
			continue
		places += memory.place_count(i)
		if not memory.strongest_lesson(i).is_empty():
			learned_creatures += 1
		for k in opinion.entry_count(i):
			var record := opinion.entry_at(i, k)
			if int(record["events"]) < opinion.min_events:
				continue
			opinion_entries += 1
			var value := opinion.opinion(store, i, int(record["other"]), day())
			if value <= opinion.rival_threshold:
				rival_bonds += 1
			elif value >= opinion.friend_threshold:
				friend_bonds += 1

	return {
		"seed": seed_used,
		"day": day(),
		"alive": alive_count(),
		"births": births,
		"generation": generation_sum / maxi(alive, 1),
		"max_generation": max_generation,
		"children": children,
		"adults": adults,
		"old": old,
		"deaths": deaths,
		"starved": int(death_counts[StoreRef.Death.STARVATION]),
		"dehydrated": int(death_counts[StoreRef.Death.DEHYDRATION]),
		"starved_and_dehydrated": int(death_counts[StoreRef.Death.STARVATION_AND_DEHYDRATION]),
		"poisoned": int(death_counts[StoreRef.Death.POISONING]),
		"aged": int(death_counts[StoreRef.Death.OLD_AGE]),
		"harmed": int(death_counts[StoreRef.Death.HARM]),
		"materials": grid.counts(),
		"action_mix": mix,
		"recall_actions": recall_actions,
		"verb_changes": verb_changes,
		"memory_places": float(places) / denom,
		"memory_learned": learned_creatures,
		"mean_food": food_sum / denom,
		"mean_water": water_sum / denom,
		"mean_energy": energy_sum / denom,
		"mean_social": social_sum / denom,
		"mean_comfort": comfort_sum / denom,
		"mean_safety": safety_sum / denom,
		"flee_starts": safety.flee_starts,
		"flee_actions": int(action_counts[StoreRef.Verb.FLEE]),
		"carried": carried,
		"pickup_actions": int(action_counts[StoreRef.Verb.PICKUP]),
		"pile_actions": int(action_counts[StoreRef.Verb.PILE]),
		"pickup_food_actions": pickup_food_actions,
		"pickup_sand_actions": pickup_sand_actions,
		"pile_food_actions": pile_food_actions,
		"pile_sand_actions": pile_sand_actions,
		"loads_picked_food": loads_picked_food,
		"loads_picked_sand": loads_picked_sand,
		"loads_piled_food": loads_piled_food,
		"loads_piled_sand": loads_piled_sand,
		"mean_health": health_sum / denom,
		"social_events": social_events,
		"food_taken_events": harm.food_taken_events,
		"share_events": share.events,
		"harm_events": harm.events,
		"harm_damage": harm.damage_total,
		"hardening_events": story.hardening_events,
		"shelter_events": story.shelter_events,
		"storing_events": story.storing_events,
		"opinion_entries": opinion_entries,
		"friend_bonds": friend_bonds,
		"rival_bonds": rival_bonds,
		"lineages": history.living_lineages(self),
		"lineages_total": history.lineage_rows(self, 100000).size(),
		"genetic_diversity": history.diversity(self),
		"firsts": detectors.firsts.size(),
		"last_step_ms": tick.last_step_ms,
		"mean_step_ms": tick.total_step_ms / float(maxi(tick.steps_taken, 1)),
		"max_step_ms": tick.max_step_ms,
		"material_ms": tick.last_material_ms,
		"needs_ms": tick.last_needs_ms,
		"decide_ms": tick.last_decide_ms,
		"decisions_made": decisions_made,
		"decisions_last_tick": decisions_last_tick,
		"decision_every_ticks": decision_every,
		"promotions_made": promotions_made,
		"promotions_last_tick": promotions_last_tick,
		"execute_ms": tick.last_execute_ms,
		"material_processed": int(tick.last_material_stats.get("processed", 0)),
		"material_pending": int(tick.last_material_stats.get("active_cells", grid.active_cell_count())),
		"material_moves": int(tick.last_material_stats.get("moves", 0)),
	}
