class_name SimMemory
extends RefCounted

## Learned state, never inherited. Three stores per creature:
##
##   places   - cells where this creature ate or drank, with the value it found
##              there and the day it was recorded. Recall decays with age, so a
##              dried pond is visited for a while and then forgotten.
##   episodes - a ring of 32 records: verb, context, stress, need before and
##              after, cell and day. High-stress records survive eviction longer.
##   weights  - one learned expectation per (verb, context). The learning rule is
##              weight += rate * stress * (actual improvement - weight), so the
##              weight converges on what the action actually delivers, and a
##              surprising rescue teaches more than routine success.
##
## Children get a reset store: memory is lived, not inherited.

const StoreRef := preload("res://sim/creature_store.gd")

const EPISODE_SLOTS := 32
const EPISODE_FIELDS := 7
const EP_VERB := 0
const EP_CONTEXT := 1
const EP_STRESS := 2
const EP_BEFORE := 3
const EP_AFTER := 4
const EP_CELL := 5
const EP_DAY := 6

const PLACE_SLOTS := 8
const PLACE_FIELDS := 4
const PL_CELL := 0
const PL_MATERIAL := 1
const PL_VALUE := 2
const PL_DAY := 3

const CONTEXTS := 6
const CONTEXT_HUNGRY := 0
const CONTEXT_THIRSTY := 1
const CONTEXT_TIRED := 2
const CONTEXT_CONTENT := 3
const CONTEXT_UNCOMFORTABLE := 4
const CONTEXT_AFRAID := 5
const CONTEXT_NAMES := ["hungry", "thirsty", "tired", "content", "uncomfortable", "afraid"]

var count := 0

var episodes := PackedFloat32Array()
var episode_head := PackedInt32Array()
var episode_used := PackedInt32Array()

var places := PackedFloat32Array()
var place_used := PackedInt32Array()

var weights := PackedFloat32Array()


func ensure(n: int) -> void:
	if count >= n:
		return
	episodes.resize(n * EPISODE_SLOTS * EPISODE_FIELDS)
	episode_head.resize(n)
	episode_used.resize(n)
	places.resize(n * PLACE_SLOTS * PLACE_FIELDS)
	place_used.resize(n)
	weights.resize(n * StoreRef.VERB_COUNT * CONTEXTS)
	count = n


## A reused id starts blank: the previous occupant's learning does not follow
## the slot.
func reset(id: int) -> void:
	if id < 0 or id >= count:
		return
	episode_head[id] = 0
	episode_used[id] = 0
	place_used[id] = 0
	var wbase := id * StoreRef.VERB_COUNT * CONTEXTS
	for k in StoreRef.VERB_COUNT * CONTEXTS:
		weights[wbase + k] = 0.0
	var pbase := id * PLACE_SLOTS * PLACE_FIELDS
	for k in PLACE_SLOTS * PLACE_FIELDS:
		places[pbase + k] = 0.0
	var ebase := id * EPISODE_SLOTS * EPISODE_FIELDS
	for k in EPISODE_SLOTS * EPISODE_FIELDS:
		episodes[ebase + k] = 0.0


# --- places --------------------------------------------------------------

## Records a productive cell. The same cell refreshes rather than duplicate;
## a full store drops the slot with the lowest decayed value.
func remember_place(id: int, cell: int, material: int, value: float, day: float) -> void:
	if id < 0 or id >= count:
		return
	var base := id * PLACE_SLOTS * PLACE_FIELDS
	var used := place_used[id]
	for k in used:
		var at := base + k * PLACE_FIELDS
		if int(places[at + PL_CELL]) == cell:
			places[at + PL_MATERIAL] = float(material)
			places[at + PL_VALUE] = maxf(value, places[at + PL_VALUE])
			places[at + PL_DAY] = day
			return
	if used < PLACE_SLOTS:
		var at := base + used * PLACE_FIELDS
		places[at + PL_CELL] = float(cell)
		places[at + PL_MATERIAL] = float(material)
		places[at + PL_VALUE] = value
		places[at + PL_DAY] = day
		place_used[id] = used + 1
		return
	# Full: replace the weakest slot. Value decays with age, so the oldest and
	# least productive memory is the one that goes.
	var worst := 0
	var worst_score := 1.0e9
	for k in PLACE_SLOTS:
		var at := base + k * PLACE_FIELDS
		var age := maxf(day - places[at + PL_DAY], 0.0)
		var score := places[at + PL_VALUE] * decay_factor(age)
		if score < worst_score:
			worst_score = score
			worst = k
	var at := base + worst * PLACE_FIELDS
	places[at + PL_CELL] = float(cell)
	places[at + PL_MATERIAL] = float(material)
	places[at + PL_VALUE] = value
	places[at + PL_DAY] = day


## A place learned by watching, not by visiting. It never overwrites a personal
## record and carries the weaker confidence the observer's fidelity earned.
func remember_place_seen(id: int, cell: int, material: int, value: float, day: float) -> bool:
	if id < 0 or id >= count:
		return false
	var base := id * PLACE_SLOTS * PLACE_FIELDS
	var used := place_used[id]
	for k in used:
		if int(places[base + k * PLACE_FIELDS + PL_CELL]) == cell:
			return false
	if used < PLACE_SLOTS:
		var at := base + used * PLACE_FIELDS
		places[at + PL_CELL] = float(cell)
		places[at + PL_MATERIAL] = float(material)
		places[at + PL_VALUE] = clampf(value, 0.0, 1.0)
		places[at + PL_DAY] = day
		place_used[id] = used + 1
		return true
	var worst := 0
	var worst_score := 1.0e9
	for k in PLACE_SLOTS:
		var at := base + k * PLACE_FIELDS
		var age := maxf(day - places[at + PL_DAY], 0.0)
		var score := places[at + PL_VALUE] * decay_factor(age)
		if score < worst_score:
			worst_score = score
			worst = k
	var at := base + worst * PLACE_FIELDS
	places[at + PL_CELL] = float(cell)
	places[at + PL_MATERIAL] = float(material)
	places[at + PL_VALUE] = clampf(value, 0.0, 1.0)
	places[at + PL_DAY] = day
	return true


func forget_place(id: int, cell: int) -> void:
	if id < 0 or id >= count:
		return
	var base := id * PLACE_SLOTS * PLACE_FIELDS
	var used := place_used[id]
	for k in used:
		var at := base + k * PLACE_FIELDS
		if int(places[at + PL_CELL]) != cell:
			continue
		# Swap the last valid slot into the hole.
		var last := base + (used - 1) * PLACE_FIELDS
		for f in PLACE_FIELDS:
			places[at + f] = places[last + f]
		place_used[id] = used - 1
		return


## Best remembered cell of a material. Confidence falls with age and distance:
## a memory is a hint, not a map. Empty dictionary when nothing is remembered
## or every record has faded.
func recall(id: int, material: int, x: float, y: float, day: float, decay_days: float, width: int) -> Dictionary:
	if id < 0 or id >= count:
		return {}
	var base := id * PLACE_SLOTS * PLACE_FIELDS
	var used := place_used[id]
	var best := {}
	var best_score := 0.0
	var decay_scale := maxf(decay_days, 0.01)
	for k in used:
		var at := base + k * PLACE_FIELDS
		if int(places[at + PL_MATERIAL]) != material:
			continue
		var age := maxf(day - places[at + PL_DAY], 0.0)
		var confidence := clampf(places[at + PL_VALUE] * pow(0.5, age / decay_scale), 0.0, 1.0)
		if confidence <= 0.01:
			continue
		var cell := int(places[at + PL_CELL])
		var dx := float(cell % width) + 0.5 - x
		var dy := float(cell / width) + 0.5 - y
		var dist := sqrt(dx * dx + dy * dy)
		var score := confidence / (1.0 + dist * 0.03)
		if score > best_score:
			best_score = score
			best = {"cell": cell, "confidence": confidence, "dist": dist, "age_days": age}
	return best


func best_place(id: int, material: int, x: float, y: float, day: float, decay_days: float, width: int) -> int:
	return int(recall(id, material, x, y, day, decay_days, width).get("cell", -1))


func place_count(id: int) -> int:
	if id < 0 or id >= count:
		return 0
	return place_used[id]


func place_at(id: int, k: int) -> Dictionary:
	if id < 0 or id >= count or k < 0 or k >= place_used[id]:
		return {}
	var at := id * PLACE_SLOTS * PLACE_FIELDS + k * PLACE_FIELDS
	return {
		"cell": int(places[at + PL_CELL]),
		"material": int(places[at + PL_MATERIAL]),
		"value": places[at + PL_VALUE],
		"day": places[at + PL_DAY],
	}


static func decay_factor(age_days: float) -> float:
	return pow(0.5, maxf(age_days, 0.0))


# --- episodes ------------------------------------------------------------

## Appends an episode. A full ring evicts the record with the lowest
## stress-weighted recency, which is the plan's "high-stress records decay more
## slowly" expressed as retention rather than a per-tick decay loop.
func record_episode(id: int, verb: int, context: int, stress: float, before: float, after: float, cell: int, day: float) -> void:
	if id < 0 or id >= count:
		return
	var base := id * EPISODE_SLOTS * EPISODE_FIELDS
	var used := episode_used[id]
	var slot: int
	if used < EPISODE_SLOTS:
		slot = episode_head[id]
		episode_head[id] = (slot + 1) % EPISODE_SLOTS
		episode_used[id] = used + 1
	else:
		slot = _weakest_episode(id, day)
	var at := base + slot * EPISODE_FIELDS
	episodes[at + EP_VERB] = float(verb)
	episodes[at + EP_CONTEXT] = float(context)
	episodes[at + EP_STRESS] = clampf(stress, 0.0, 1.0)
	episodes[at + EP_BEFORE] = before
	episodes[at + EP_AFTER] = after
	episodes[at + EP_CELL] = float(cell)
	episodes[at + EP_DAY] = day


func _weakest_episode(id: int, day: float) -> int:
	var base := id * EPISODE_SLOTS * EPISODE_FIELDS
	var worst := 0
	var worst_score := 1.0e9
	for k in EPISODE_SLOTS:
		var at := base + k * EPISODE_FIELDS
		var age := maxf(day - episodes[at + EP_DAY], 0.0)
		# Stress slows forgetting: a 0.9-stress record decays at a third of the
		# rate of a calm one.
		var half_life := 0.5 + 2.5 * episodes[at + EP_STRESS]
		var score := pow(0.5, age / half_life)
		if score < worst_score:
			worst_score = score
			worst = k
	return worst


func episode_count(id: int) -> int:
	if id < 0 or id >= count:
		return 0
	return episode_used[id]


func episode_at(id: int, k: int) -> Dictionary:
	if id < 0 or id >= count or k < 0 or k >= episode_used[id]:
		return {}
	var at := id * EPISODE_SLOTS * EPISODE_FIELDS + k * EPISODE_FIELDS
	return {
		"verb": int(episodes[at + EP_VERB]),
		"context": int(episodes[at + EP_CONTEXT]),
		"stress": episodes[at + EP_STRESS],
		"before": episodes[at + EP_BEFORE],
		"after": episodes[at + EP_AFTER],
		"cell": int(episodes[at + EP_CELL]),
		"day": episodes[at + EP_DAY],
	}


# --- learned weights -----------------------------------------------------

## One update of the plan's rule. `improvement` is the change in the need the
## action serves (or the mean need change for generic verbs).
func learn(id: int, verb: int, context: int, stress: float, improvement: float, rate: float) -> void:
	if id < 0 or id >= count or verb < 0 or verb >= StoreRef.VERB_COUNT:
		return
	if context < 0 or context >= CONTEXTS:
		return
	var idx := id * StoreRef.VERB_COUNT * CONTEXTS + verb * CONTEXTS + context
	var weight := weights[idx]
	weights[idx] = clampf(weight + rate * clampf(stress, 0.0, 1.0) * (improvement - weight), -0.6, 0.6)


func learned(id: int, verb: int, context: int) -> float:
	if id < 0 or id >= count or verb < 0 or verb >= StoreRef.VERB_COUNT:
		return 0.0
	var c := clampi(context, 0, CONTEXTS - 1)
	return weights[id * StoreRef.VERB_COUNT * CONTEXTS + verb * CONTEXTS + c]


## Score multiplier for a candidate: 0.4 .. 1.6. Learning biases a choice; it
## never unlocks or forbids a verb.
func multiplier(id: int, verb: int, context: int) -> float:
	return clampf(1.0 + learned(id, verb, context), 0.4, 1.6)


## The strongest lesson this creature has learned, for the inspector.
func strongest_lesson(id: int) -> Dictionary:
	if id < 0 or id >= count:
		return {}
	var base := id * StoreRef.VERB_COUNT * CONTEXTS
	var best := 0.0
	var best_verb := -1
	var best_context := 0
	for v in StoreRef.VERB_COUNT:
		for c in CONTEXTS:
			var w := absf(weights[base + v * CONTEXTS + c])
			if w > best:
				best = w
				best_verb = v
				best_context = c
	if best_verb < 0:
		return {}
	return {"verb": best_verb, "context": best_context, "weight": best}


## Small deterministic digest, folded into Sim.state_hash so a divergence in
## learning is caught by the determinism test.
func digest(id: int) -> int:
	if id < 0 or id >= count:
		return 0
	var h := 0
	var base := id * StoreRef.VERB_COUNT * CONTEXTS
	for k in StoreRef.VERB_COUNT * CONTEXTS:
		h = (h ^ int(round(weights[base + k] * 1000.0))) * 1099511628211
	return h & 0x7FFFFFFF
