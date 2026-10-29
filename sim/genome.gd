class_name SimGenome
extends RefCounted

## The inherited parameter vector: a fixed set of loci, each clamped to a viable
## range and decoded through a body-cost budget. Genes are parameters of general
## systems (needs, perception, movement, curves), never behaviours, action lists
## or brain topology, so a mutation cannot produce a creature that plays a
## different game.
##
## Body cost: size, speed, sense and stomach share a budget below the sum of
## their maximums. A mutation that pushes one up is paid for by the others
## through the decode, so no birth is best at everything. Metabolism then carries
## the running cost of a larger body.
##
## All loci are read by a live system today. Social and carrying loci arrived
## with the systems that read them; memory and learning are parameters rather
## than loci because no gene reads them.

## Locus indices in the raw genome.
const SIZE := 0
const SPEED := 1
const SENSE := 2
const METABOLIC := 3
const HUNGER_SET := 4
const THIRST_SET := 5
const REST_SET := 6
const STOMACH := 7
const HUNGER_EXP := 8
const THIRST_EXP := 9
const ENERGY_EXP := 10
const BOLDNESS := 11
const CURIOSITY := 12
const HUE := 13
const IMITATION := 14
## Personality axes read at encounter time: sociality weights the social need and
## social actions, aggression weights contesting a disputed meal, and
## conscientiousness weights the generic store action (pick up and pile).
const SOCIALITY := 15
const AGGRESSION := 16
const CONSCIENTIOUSNESS := 17
## Curve shape for the safety need. A steep exponent means a creature that is
## only mildly frightened still acts on it; a shallow one tolerates fear until it
## is nearly critical. Read by the flee candidate and by rest on protected ground.
const SAFETY_EXP := 18

const LOCI := 19

## Inclusive [min, max] per locus. Order matches the indices above.
const RANGES := [
	[0.35, 1.00],  # size
	[0.35, 1.00],  # speed
	[0.35, 1.00],  # sense
	[0.70, 1.40],  # metabolic rate
	[0.35, 0.80],  # hunger setpoint: stop eating here
	[0.40, 0.85],  # thirst setpoint
	[0.45, 0.90],  # rest setpoint
	[0.60, 1.40],  # stomach / intake rate
	[1.40, 3.00],  # hunger curve exponent
	[1.60, 3.40],  # thirst curve exponent
	[1.20, 2.60],  # energy curve exponent
	[0.00, 1.00],  # boldness: discounts distance cost
	[0.00, 1.00],  # curiosity: longer, more varied wandering
	[0.00, 1.00],  # hue (appearance)
	[0.00, 1.00],  # imitation fidelity: how much a watched meal is copied
	[0.00, 1.00],  # sociality: weight of the social need and social actions
	[0.00, 1.00],  # aggression: willingness to contest a disputed meal
	[0.00, 1.00],  # conscientiousness: weight of storing and piling
	[1.60, 3.20],  # safety curve exponent: how fast fear becomes urgency
]

## Decoded fields, computed once per creature at spawn. Age scaling is applied
## at read time from CreatureStore.body_scale.
const F_SIZE := 0
const F_SPEED := 1
const F_SENSE := 2
const F_METABOLIC := 3
const F_HUNGER_SET := 4
const F_THIRST_SET := 5
const F_REST_SET := 6
const F_STOMACH := 7
const F_HUNGER_EXP := 8
const F_THIRST_EXP := 9
const F_ENERGY_EXP := 10
const F_BOLDNESS := 11
const F_CURIOSITY := 12
const F_HUE := 13
const F_IMITATION := 14
const F_SOCIALITY := 15
const F_AGGRESSION := 16
const F_CONSCIENTIOUSNESS := 17
const F_SAFETY_EXP := 18
const F_COST := 19
const FIELDS := 20

## The four cost genes and their share of the budget.
const COST_GENES := [SIZE, SPEED, SENSE, STOMACH]
const COST_WEIGHTS := [0.30, 0.30, 0.20, 0.20]
const BODY_BUDGET := 0.72


static func defaults() -> PackedFloat32Array:
	var g := PackedFloat32Array()
	g.resize(LOCI)
	for k in LOCI:
		g[k] = (float(RANGES[k][0]) + float(RANGES[k][1])) * 0.5
	return g


static func random(rng: SimRng) -> PackedFloat32Array:
	var g := PackedFloat32Array()
	g.resize(LOCI)
	for k in LOCI:
		g[k] = rng.randf_range(float(RANGES[k][0]), float(RANGES[k][1]))
	return g


static func clamp_locus(k: int, v: float) -> float:
	return clampf(v, float(RANGES[k][0]), float(RANGES[k][1]))


## Raw genome -> decoded body fields, with the body-cost budget applied.
static func fields(genome: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(FIELDS)
	var cost := 0.0
	for k in COST_GENES.size():
		out[COST_GENES[k]] = genome[COST_GENES[k]]
		cost += float(COST_WEIGHTS[k]) * _normalized(COST_GENES[k], genome[COST_GENES[k]])
	if cost > BODY_BUDGET:
		# Over budget: scale the cost genes back toward their minimums together.
		var scale := BODY_BUDGET / cost
		for k in COST_GENES.size():
			var locus: int = COST_GENES[k]
			var v := float(RANGES[locus][0]) + _normalized(locus, genome[locus]) * scale * (float(RANGES[locus][1]) - float(RANGES[locus][0]))
			out[locus] = clamp_locus(locus, v)
		cost = BODY_BUDGET
	out[F_METABOLIC] = genome[METABOLIC] * (0.80 + 0.40 * (cost / BODY_BUDGET))
	out[F_COST] = cost
	for k in LOCI:
		if not (k in COST_GENES) and k != METABOLIC:
			out[k] = genome[k]
	return out


static func _normalized(k: int, v: float) -> float:
	var lo := float(RANGES[k][0])
	var hi := float(RANGES[k][1])
	return clampf((v - lo) / maxf(hi - lo, 0.0001), 0.0, 1.0)


## One child from two parents. Each locus is taken from one parent (a pick, not
## an average, so lineages stay interpretable), then mutated: a common small
## step and a rare large one. Returns {"genome", "mutations"}.
static func child(a: PackedFloat32Array, b: PackedFloat32Array, rng: SimRng, params: SimParams) -> Dictionary:
	var rate := params.f("genome", "mutation_rate", 0.02)
	var size := params.f("genome", "mutation_size", 0.05)
	var jump_rate := params.f("genome", "jump_rate", 0.001)
	var jump_size := params.f("genome", "jump_size", 0.25)
	var g := PackedFloat32Array()
	g.resize(LOCI)
	var mutations := 0
	for k in LOCI:
		var span := float(RANGES[k][1]) - float(RANGES[k][0])
		var v: float = a[k] if rng.chance(0.5) else b[k]
		if rng.chance(jump_rate):
			v += rng.gaussian(0.0, jump_size * span)
			mutations += 1
		elif rng.chance(rate):
			v += rng.gaussian(0.0, size * span)
			mutations += 1
		g[k] = clamp_locus(k, v)
	return {"genome": g, "mutations": mutations}


## Normalised RMS difference over the loci, 0 for identical genomes. Used for
## mate compatibility and for watching diversity in a soak.
static func distance(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var total := 0.0
	for k in LOCI:
		var span := maxf(float(RANGES[k][1]) - float(RANGES[k][0]), 0.0001)
		var d := (a[k] - b[k]) / span
		total += d * d
	return sqrt(total / float(LOCI))


## Inverse locus spans, so the hot distance loop does no range lookups. A mate
## search compares every nearby pair each tick; two array reads and a multiply
## per locus is the difference between 0.2 and several microseconds a pair.
static var _inverse_spans := PackedFloat32Array()


static func _ensure_spans() -> void:
	if not _inverse_spans.is_empty():
		return
	_inverse_spans.resize(LOCI)
	for k in LOCI:
		_inverse_spans[k] = 1.0 / maxf(float(RANGES[k][1]) - float(RANGES[k][0]), 0.0001)


## Same measure without copying either genome out of the store.
static func distance_store(store: CreatureStore, id_a: int, id_b: int) -> float:
	_ensure_spans()
	var genes: PackedFloat32Array = store.genome
	var base_a := id_a * LOCI
	var base_b := id_b * LOCI
	var total := 0.0
	for k in LOCI:
		var d := (genes[base_a + k] - genes[base_b + k]) * _inverse_spans[k]
		total += d * d
	return sqrt(total / float(LOCI))


## The genome translated into the words the inspector uses, thresholded from
## decoded values. This is a reading of the genes, never a hand-written label
## per creature or a behaviour switch.
static func words(store: CreatureStore, id: int) -> String:
	var words: Array = []
	var size := store.body[id * FIELDS + F_SIZE]
	var speed := store.body[id * FIELDS + F_SPEED]
	var sense := store.body[id * FIELDS + F_SENSE]
	var metabolic := store.body[id * FIELDS + F_METABOLIC]
	var bold := store.body[id * FIELDS + F_BOLDNESS]
	var curious := store.body[id * FIELDS + F_CURIOSITY]
	var social := store.body[id * FIELDS + F_SOCIALITY]
	var aggressive := store.body[id * FIELDS + F_AGGRESSION]
	var careful := store.body[id * FIELDS + F_CONSCIENTIOUSNESS]
	var imitation := store.body[id * FIELDS + F_IMITATION]
	var safety_exp := store.body[id * FIELDS + F_SAFETY_EXP]
	words.append("large" if size > 0.78 else ("small" if size < 0.52 else "mid-sized"))
	words.append("fast" if speed > 0.78 else ("slow" if speed < 0.52 else "steady"))
	words.append("far-seeing" if sense > 0.78 else ("shortsighted" if sense < 0.52 else "average-eyed"))
	words.append("fast metabolism" if metabolic > 1.12 else ("slow metabolism" if metabolic < 0.88 else "middle metabolism"))
	words.append("bold" if bold > 0.65 else ("timid" if bold < 0.35 else "watchful"))
	words.append("curious" if curious > 0.65 else ("incurious" if curious < 0.35 else "moderately curious"))
	words.append("social" if social > 0.65 else ("solitary" if social < 0.35 else "companionable"))
	words.append("aggressive" if aggressive > 0.65 else ("peaceable" if aggressive < 0.35 else "assertive"))
	words.append("careful" if careful > 0.65 else ("careless" if careful < 0.35 else "practical"))
	words.append("quick to copy" if imitation > 0.65 else ("poor at copying" if imitation < 0.35 else "copies sometimes"))
	words.append("easily frightened" if safety_exp > 2.60 else ("hard to frighten" if safety_exp < 2.00 else "ordinarily cautious"))
	return ", ".join(words)


static func gene_string(store: CreatureStore, id: int) -> String:
	return "size %.2f  speed %.2f  sense %.2f  metabolic %.2f  imitation %.2f  social %.2f  aggression %.2f  conscientious %.2f  safety curve %.2f" % [
		store.body[id * FIELDS + F_SIZE],
		store.body[id * FIELDS + F_SPEED],
		store.body[id * FIELDS + F_SENSE],
		store.body[id * FIELDS + F_METABOLIC],
		store.body[id * FIELDS + F_IMITATION],
		store.body[id * FIELDS + F_SOCIALITY],
		store.body[id * FIELDS + F_AGGRESSION],
		store.body[id * FIELDS + F_CONSCIENTIOUSNESS],
		store.body[id * FIELDS + F_SAFETY_EXP],
	]


## Effective movement speed: gene x body scale (children are smaller and slower,
## the old decline through the same scale).
static func speed_factor(store: CreatureStore, id: int) -> float:
	return (0.55 + 0.90 * store.body[id * FIELDS + F_SPEED]) * store.body_scale[id]


static func sense_factor(store: CreatureStore, id: int) -> float:
	return store.body[id * FIELDS + F_SENSE] * store.body_scale[id]


## Carrying capacity in material mass. Size is the strength proxy, so a large
## body can haul more; the material's density decides how much of it fits.
static func carry_capacity(store: CreatureStore, id: int) -> float:
	return 1.4 + 2.6 * store.body[id * FIELDS + F_SIZE] * store.body_scale[id]


## Speed multiplier for a load. A dense material costs more to carry than a
## light one, and a bigger body pays less. The factor never reaches zero.
static func carry_factor(store: CreatureStore, id: int, density: float, penalty_max: float = 0.4) -> float:
	var capacity := maxf(carry_capacity(store, id), 0.01)
	var load := store.carry_amount[id] * density
	var penalty: float = clampf(load / capacity, 0.0, 1.0) * clampf(penalty_max, 0.0, 0.9)
	return 1.0 - penalty
