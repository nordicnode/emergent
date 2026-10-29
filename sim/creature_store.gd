class_name CreatureStore
extends RefCounted

## Structure-of-arrays creature storage. Creature ids are stable integers;
## dead slots go on a free list instead of shifting the arrays, so ids,
## lineage references and the inspector survive death.
##
## The genome is inherited data and the body is its decode; learned values, when
## they arrive, will live in their own store so inheritance can never carry a
## parent's learning.

const GenomeRef := preload("res://sim/genome.gd")

enum Verb { WANDER = 0, SEEK = 1, EAT = 2, DRINK = 3, REST = 4, APPROACH = 5, MATE = 6, SOCIALISE = 7, AVOID = 8, PICKUP = 9, PILE = 10, FLEE = 11, MOVE_TO = 12 }

const VERB_NAMES := ["wander", "seek", "eat", "drink", "rest", "approach", "mate", "socialise", "avoid", "pickup", "pile", "flee", "move_to"]
const VERB_COUNT := 13

enum Death { NONE = 0, STARVATION = 1, DEHYDRATION = 2, STARVATION_AND_DEHYDRATION = 3, POISONING = 4, OLD_AGE = 5, HARM = 6 }

const DEATH_NAMES := ["none", "starvation", "dehydration", "starvation and dehydration", "poisoning", "old age", "harm"]

const CHILD := 0
const ADULT := 1
const OLD := 2

const STAGE_NAMES := ["child", "adult", "old"]

var count := 0

var alive := PackedByteArray()
var px := PackedFloat32Array()
var py := PackedFloat32Array()
var vx := PackedFloat32Array()
var vy := PackedFloat32Array()

## Need satisfaction levels, 1.0 = fully satisfied, 0.0 = critical.
var food_level := PackedFloat32Array()
var water_level := PackedFloat32Array()
var energy_level := PackedFloat32Array()
## Social need. It never kills; an unmet one only removes social actions from
## reach, so isolation costs opportunity rather than health.
var social_level := PackedFloat32Array()
## Comfort need: wet, cold or poor ground wears it down, and resting on dry,
## hard, compacted ground restores it. It never damages health; it is what gives
## the material chain a place the brain prefers to be.
var comfort_level := PackedFloat32Array()
## Safety need: nearby creatures this one has come to dislike erode it, exposure
## does so slowly, and resting where hard ground cuts the exposure restores it.
## It never damages health on its own; it is what makes flee urgent.
var safety_level := PackedFloat32Array()
var health := PackedFloat32Array()
## Toxin load from eating rotten food: 0 clean, 1.0 heavily poisoned. It drains
## health over hours and is what turns one bad meal into a lesson.
var toxin := PackedFloat32Array()

var verb := PackedByteArray()
var aim_x := PackedFloat32Array()
var aim_y := PackedFloat32Array()
var aim_cell := PackedInt32Array()
var aim_creature := PackedInt32Array()
var action_time := PackedFloat32Array()
var commitment := PackedFloat32Array()

var age_days := PackedFloat32Array()
var stage := PackedByteArray()
var body_scale := PackedFloat32Array()
var cooldown_days := PackedFloat32Array()

## Carrying is material accounting, not an item system: one material and an
## amount held by the creature, with the properties that material had where it
## was picked up. A load is deposited into a cell by the pile verb.
var carry_material := PackedByteArray()
var carry_amount := PackedFloat32Array()
var carry_wetness := PackedFloat32Array()
var carry_nutrition := PackedFloat32Array()
var carry_toxicity := PackedFloat32Array()

## The last cell this creature piled food into. When it later eats from that
## cache, the delayed half of the learning rule credits the store action. These
## fields are the outcome record, not a hoarding flag: nothing reads them to
## choose or forbid an action.
var pile_cell := PackedInt32Array()
var pile_day := PackedFloat32Array()
var pile_context := PackedByteArray()
var pile_stress := PackedFloat32Array()
## Lifetime count of completed food piles. Legibility only: the disaster
## scenario uses it to compare storers with non-storers through a famine, and
## no brain or need reads it.
var piled_food := PackedInt32Array()

## Observation window for the learning rule. The needs at the moment a verb was
## chosen are kept here so the next decision can score what the action actually
## delivered; the delay fields arm the second, later evaluation that catches
## slow effects such as food that harms health.
var mem_tracking := PackedByteArray()
var mem_before_food := PackedFloat32Array()
var mem_before_water := PackedFloat32Array()
var mem_before_energy := PackedFloat32Array()
var mem_before_comfort := PackedFloat32Array()
var mem_before_safety := PackedFloat32Array()
var mem_stress := PackedFloat32Array()
var mem_context := PackedByteArray()
var mem_delay_until := PackedFloat32Array()
var mem_delay_health := PackedFloat32Array()
var mem_delay_toxin := PackedFloat32Array()
var mem_delay_verb := PackedByteArray()
var mem_delay_context := PackedByteArray()
var mem_delay_stress := PackedFloat32Array()

## Inherited data: LOCI floats per creature, decoded to FIELDS floats per
## creature. Children are decoded at birth, never mutated afterwards.
var genome := PackedFloat32Array()
var body := PackedFloat32Array()

var mother := PackedInt32Array()
var father := PackedInt32Array()
var founder := PackedInt32Array()
var generation := PackedInt32Array()
var mutations := PackedInt32Array()
var offspring := PackedInt32Array()
var birth_time := PackedFloat32Array()

var hue := PackedFloat32Array()
## Persistent search direction, radians. A desperate creature turns gradually
## instead of re-rolling a fresh random direction every time it decides.
var heading := PackedFloat32Array()
## Last time this creature taught a place to an observer, so a long meal does
## not run the observer scan every tick.
var teach_time := PackedFloat32Array()
## Last social exchange, for the per-creature cooldown that stops a crowd from
## socialising every tick and saturating every opinion.
var social_time := PackedFloat32Array()
## Last comfort scan and its cached target. Material affordances are re-read
## when a creature enters a new neighbourhood, not for every cell it crosses,
## so the scan has a cooldown and the chosen cell is held between scans.
var comfort_scan_time := PackedFloat32Array()
var comfort_cell := PackedInt32Array()
var death_cause := PackedByteArray()
var death_time := PackedFloat32Array()
var path_travelled := PackedFloat32Array()

var free_slots := PackedInt32Array()


func _ensure(n: int) -> void:
	if count >= n:
		return
	alive.resize(n)
	px.resize(n)
	py.resize(n)
	vx.resize(n)
	vy.resize(n)
	food_level.resize(n)
	water_level.resize(n)
	energy_level.resize(n)
	social_level.resize(n)
	comfort_level.resize(n)
	safety_level.resize(n)
	health.resize(n)
	toxin.resize(n)
	verb.resize(n)
	aim_x.resize(n)
	aim_y.resize(n)
	aim_cell.resize(n)
	aim_creature.resize(n)
	action_time.resize(n)
	commitment.resize(n)
	age_days.resize(n)
	stage.resize(n)
	body_scale.resize(n)
	cooldown_days.resize(n)
	carry_material.resize(n)
	carry_amount.resize(n)
	carry_wetness.resize(n)
	carry_nutrition.resize(n)
	carry_toxicity.resize(n)
	pile_cell.resize(n)
	pile_day.resize(n)
	pile_context.resize(n)
	pile_stress.resize(n)
	piled_food.resize(n)
	mem_tracking.resize(n)
	mem_before_food.resize(n)
	mem_before_water.resize(n)
	mem_before_energy.resize(n)
	mem_before_comfort.resize(n)
	mem_before_safety.resize(n)
	mem_stress.resize(n)
	mem_context.resize(n)
	mem_delay_until.resize(n)
	mem_delay_health.resize(n)
	mem_delay_toxin.resize(n)
	mem_delay_verb.resize(n)
	mem_delay_context.resize(n)
	mem_delay_stress.resize(n)
	genome.resize(n * GenomeRef.LOCI)
	body.resize(n * GenomeRef.FIELDS)
	mother.resize(n)
	father.resize(n)
	founder.resize(n)
	generation.resize(n)
	mutations.resize(n)
	offspring.resize(n)
	birth_time.resize(n)
	hue.resize(n)
	heading.resize(n)
	teach_time.resize(n)
	social_time.resize(n)
	comfort_scan_time.resize(n)
	comfort_cell.resize(n)
	death_cause.resize(n)
	death_time.resize(n)
	path_travelled.resize(n)
	count = n


func _take_slot() -> int:
	if free_slots.size() > 0:
		var id: int = free_slots[free_slots.size() - 1]
		free_slots.remove_at(free_slots.size() - 1)
		return id
	_ensure(count + 1)
	return count - 1


## Spawn with a caller-supplied genome. Founders pass mother/father -1 and their
## own id becomes their founder line; children pass their parents and inherit
## the mother's line.
func spawn_genome(
	x: float,
	y: float,
	genome_value: PackedFloat32Array,
	food: float = 1.0,
	water: float = 1.0,
	energy: float = 1.0,
	mother_id: int = -1,
	father_id: int = -1,
	generation_value: int = 0,
	mutation_count: int = 0,
	at_time: float = 0.0
) -> int:
	var id := _take_slot()
	alive[id] = 1
	px[id] = x
	py[id] = y
	vx[id] = 0.0
	vy[id] = 0.0
	food_level[id] = clampf(food, 0.0, 1.0)
	water_level[id] = clampf(water, 0.0, 1.0)
	energy_level[id] = clampf(energy, 0.0, 1.0)
	social_level[id] = 1.0
	comfort_level[id] = 1.0
	safety_level[id] = 1.0
	health[id] = 1.0
	toxin[id] = 0.0
	verb[id] = Verb.WANDER
	aim_x[id] = x
	aim_y[id] = y
	aim_cell[id] = -1
	aim_creature[id] = -1
	action_time[id] = 0.0
	commitment[id] = 0.0
	age_days[id] = 0.0
	stage[id] = CHILD
	body_scale[id] = 0.62
	cooldown_days[id] = 0.0
	carry_material[id] = 0
	carry_amount[id] = 0.0
	carry_wetness[id] = 0.0
	carry_nutrition[id] = 0.0
	carry_toxicity[id] = 0.0
	pile_cell[id] = -1
	pile_day[id] = -1000.0
	pile_context[id] = 0
	pile_stress[id] = 0.0
	piled_food[id] = 0
	mem_tracking[id] = 0
	mem_before_food[id] = 0.0
	mem_before_water[id] = 0.0
	mem_before_energy[id] = 0.0
	mem_before_comfort[id] = 0.0
	mem_before_safety[id] = 0.0
	mem_stress[id] = 0.0
	mem_context[id] = 0
	mem_delay_until[id] = 0.0
	mem_delay_health[id] = 0.0
	mem_delay_toxin[id] = 0.0
	mem_delay_verb[id] = 0
	mem_delay_context[id] = 0
	mem_delay_stress[id] = 0.0
	for k in GenomeRef.LOCI:
		genome[id * GenomeRef.LOCI + k] = genome_value[k]
	var decoded := GenomeRef.fields(genome_value)
	for k in GenomeRef.FIELDS:
		body[id * GenomeRef.FIELDS + k] = decoded[k]
	mother[id] = mother_id
	father[id] = father_id
	founder[id] = int(founder[mother_id]) if mother_id >= 0 else id
	generation[id] = generation_value
	mutations[id] = mutation_count
	offspring[id] = 0
	birth_time[id] = at_time
	hue[id] = clampf(genome_value[GenomeRef.HUE], 0.0, 1.0)
	heading[id] = clampf(genome_value[GenomeRef.HUE], 0.0, 1.0) * TAU
	teach_time[id] = -100.0
	social_time[id] = -100.0
	comfort_scan_time[id] = -100.0
	comfort_cell[id] = -1
	death_cause[id] = Death.NONE
	death_time[id] = 0.0
	path_travelled[id] = 0.0
	return id


## Spawn with a neutral genome and the given appearance hue, for tools and tests
## that do not care about inheritance.
func spawn(x: float, y: float, hue_value: float = 0.5, food: float = 1.0, water: float = 1.0, energy: float = 1.0) -> int:
	var g := GenomeRef.defaults()
	g[GenomeRef.HUE] = clampf(hue_value, 0.0, 1.0)
	return spawn_genome(x, y, g, food, water, energy)


func kill(id: int, cause: int, at_time: float) -> void:
	if id < 0 or id >= count or alive[id] == 0:
		return
	alive[id] = 0
	vx[id] = 0.0
	vy[id] = 0.0
	commitment[id] = 0.0
	aim_cell[id] = -1
	aim_creature[id] = -1
	carry_material[id] = 0
	carry_amount[id] = 0.0
	carry_wetness[id] = 0.0
	carry_nutrition[id] = 0.0
	carry_toxicity[id] = 0.0
	pile_cell[id] = -1
	pile_day[id] = -1000.0
	comfort_cell[id] = -1
	death_cause[id] = cause
	death_time[id] = at_time
	free_slots.append(id)


func alive_count() -> int:
	var n := 0
	for i in count:
		if alive[i] == 1:
			n += 1
	return n


func verb_name(v: int) -> String:
	if v >= 0 and v < VERB_NAMES.size():
		return VERB_NAMES[v]
	return "unknown"


func death_name(c: int) -> String:
	if c >= 0 and c < DEATH_NAMES.size():
		return DEATH_NAMES[c]
	return "unknown"


func stage_name(s: int) -> String:
	if s >= 0 and s < STAGE_NAMES.size():
		return STAGE_NAMES[s]
	return "unknown"


func genome_at(id: int) -> PackedFloat32Array:
	return genome.slice(id * GenomeRef.LOCI, (id + 1) * GenomeRef.LOCI)


func body_value(id: int, field: int) -> float:
	return body[id * GenomeRef.FIELDS + field]
