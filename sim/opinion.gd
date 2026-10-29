class_name SimOpinion
extends RefCounted

## Sparse, asymmetric opinion store. One record per creature it has actually
## clashed or socialised with, never a full N x N table: the interesting pairs
## are the ones that happened.
##
## A record holds signed valence, the day it was last touched, and an event
## count. Valence decays toward indifference on a half-life, so a feud cools
## when the creatures stop meeting and can be rekindled by a new event. Kinship
## is not stored: it is computed from lineage, so a parent or sibling starts
## positively disposed without spending a memory slot and without an entry that
## could go stale.
##
## The brain reads opinion at encounter time. Nothing here names a friend, a
## rival, or a behaviour; labels exist for the interface only.
##
## The read path is allocation-free on purpose. `opinion()` runs for every
## nearby creature of every decision tick; building a dictionary per read put
## enough garbage in the collector to show up as an 81 ms step spike, against a
## 10 ms mean.

const StoreRef := preload("res://sim/creature_store.gd")

const SLOTS := 16
const OTHERS := 0
const VALENCE := 1
const LAST_DAY := 2
const EVENTS := 3
const FIELDS := 4

var count := 0
var used := PackedInt32Array()
var records := PackedFloat32Array()
## Creature ids are integers and 0 is valid, so an empty slot is -1.
var others := PackedInt32Array()

var decay_days := 3.0
var kin_bonus := 0.30
var rival_threshold := -0.20
var friend_threshold := 0.30
var min_events := 3


func _init(decay: float = 3.0, kin: float = 0.30, rival: float = -0.20, friend: float = 0.30, events: int = 3) -> void:
	decay_days = maxf(decay, 0.05)
	kin_bonus = kin
	rival_threshold = rival
	friend_threshold = friend
	min_events = maxi(events, 1)


func ensure(n: int) -> void:
	if count >= n:
		return
	var from := count * SLOTS
	var to := n * SLOTS
	records.resize(n * SLOTS * FIELDS)
	others.resize(n * SLOTS)
	used.resize(n)
	for k in range(from, to):
		others[k] = -1
	count = n


## A reused id starts with no history: the previous occupant's relationships do
## not follow the slot.
func reset(id: int) -> void:
	if id < 0 or id >= count:
		return
	var base := id * SLOTS
	for k in SLOTS:
		others[base + k] = -1
		for f in FIELDS:
			records[(base + k) * FIELDS + f] = 0.0
	used[id] = 0


## Relative slot index for `other`, or -1.
func _find(id: int, other: int) -> int:
	var base := id * SLOTS
	for k in used[id]:
		if others[base + k] == other:
			return k
	return -1


func _decayed(id: int, slot: int, day: float) -> float:
	var at := (id * SLOTS + slot) * FIELDS
	var age := maxf(day - records[at + LAST_DAY], 0.0)
	return records[at + VALENCE] * pow(0.5, age / decay_days)


## Decayed opinion of `other`, including the lineage bonus. This is what the
## brain reads; it is a hint about a creature, not a stored label.
func opinion(store: CreatureStore, id: int, other: int, day: float) -> float:
	var value := stored_opinion(id, other, day)
	if related(store, id, other):
		value += kin_bonus
	return clampf(value, -1.0, 1.0)


## Opinion with no kinship added, for logs, tests and the decay check.
func stored_opinion(id: int, other: int, day: float) -> float:
	if id < 0 or id >= count or other < 0 or other == id:
		return 0.0
	var slot := _find(id, other)
	if slot < 0:
		return 0.0
	return _decayed(id, slot, day)


## Applies one event and returns what changed. Crossing a label threshold is
## reported once, at the moment it happens, so the log can show the causal step
## rather than repeating the state every tick.
func add(id: int, other: int, delta: float, day: float) -> Dictionary:
	if id < 0 or id >= count or other < 0 or other == id:
		return {}
	var base := id * SLOTS
	var slot := _find(id, other)
	var before := 0.0
	var events := 0
	if slot >= 0:
		before = _decayed(id, slot, day)
		events = int(records[(base + slot) * FIELDS + EVENTS])
	else:
		if used[id] < SLOTS:
			slot = used[id]
			used[id] = used[id] + 1
		else:
			slot = _weakest(id, day) - base
		before = 0.0
		events = 0
	var after := clampf(before + delta, -1.0, 1.0)
	events += 1
	var at := (base + slot) * FIELDS
	others[base + slot] = other
	records[at + VALENCE] = after
	records[at + LAST_DAY] = day
	records[at + EVENTS] = float(events)
	return {
		"other": other,
		"valence": after,
		"events": events,
		"rival": before > rival_threshold and after <= rival_threshold and events >= min_events,
		"friend": before < friend_threshold and after >= friend_threshold and events >= min_events,
	}


## Absolute slot index of the relationship that matters least.
func _weakest(id: int, day: float) -> int:
	var base := id * SLOTS
	var worst := 0
	var worst_score := 1.0e9
	for k in used[id]:
		var score := absf(_decayed(id, k, day))
		if score < worst_score:
			worst_score = score
			worst = k
	return base + worst


func last_day(id: int, other: int) -> float:
	if id < 0 or id >= count:
		return -1000.0
	var slot := _find(id, other)
	if slot < 0:
		return -1000.0
	return records[(id * SLOTS + slot) * FIELDS + LAST_DAY]


func entry_count(id: int) -> int:
	if id < 0 or id >= count:
		return 0
	return used[id]


## Direct slot reads for hot loops (the safety need walks every remembered
## relationship each tick). Unlike entry_at, these allocate nothing.
func other_at(id: int, k: int) -> int:
	if id < 0 or id >= count or k < 0 or k >= used[id]:
		return -1
	return others[id * SLOTS + k]


## Decayed valence without the kinship bonus, for callers that want the stored
## grievance itself.
func decayed_entry(id: int, k: int, day: float) -> float:
	if id < 0 or id >= count or k < 0 or k >= used[id]:
		return 0.0
	var at := (id * SLOTS + k) * FIELDS
	var age := maxf(day - records[at + LAST_DAY], 0.0)
	return records[at + VALENCE] * pow(0.5, age / decay_days)


## The value the brain would read for slot `k`, including the lineage bonus,
## without searching for the slot again. Safety uses this so its threat read
## cannot disagree with the flee candidate's opinion read.
func opinion_slot(store: CreatureStore, id: int, k: int, day: float) -> float:
	var other := other_at(id, k)
	var value := decayed_entry(id, k, day)
	if other >= 0 and related(store, id, other):
		value += kin_bonus
	return clampf(value, -1.0, 1.0)


func entry_at(id: int, k: int) -> Dictionary:
	if id < 0 or id >= count or k < 0 or k >= used[id]:
		return {}
	var at := (id * SLOTS + k) * FIELDS
	return {
		"other": others[id * SLOTS + k],
		"valence": records[at + VALENCE],
		"day": records[at + LAST_DAY],
		"events": int(records[at + EVENTS]),
	}


func label_for(value: float, events: int) -> String:
	if events < min_events:
		return "neutral"
	if value <= rival_threshold:
		return "rival"
	if value >= friend_threshold:
		return "friend"
	return "neutral"


## Strongest relationships for the inspector, sorted by how much they matter.
func top_opinions(store: CreatureStore, id: int, day: float, limit: int = 3) -> Array:
	var out: Array = []
	if id < 0 or id >= count:
		return out
	for k in used[id]:
		var record := entry_at(id, k)
		var other := int(record["other"])
		var value := opinion(store, id, other, day)
		var events := int(record["events"])
		out.append({
			"other": other,
			"valence": value,
			"events": events,
			"kin": related(store, id, other),
			"label": label_for(value, events),
		})
	out.sort_custom(func(a, b): return absf(float(a["valence"])) > absf(float(b["valence"])))
	return out.slice(0, maxi(limit, 0))


## Kinship is a starting condition, not a relationship: parents, children and
## siblings are related, and the bonus is applied whenever opinion is read.
static func related(store: CreatureStore, a: int, b: int) -> bool:
	if a < 0 or b < 0 or a == b or a >= store.count or b >= store.count:
		return false
	if store.mother[a] == b or store.father[a] == b:
		return true
	if store.mother[b] == a or store.father[b] == a:
		return true
	if store.mother[a] >= 0 and (store.mother[a] == store.mother[b] or store.mother[a] == store.father[b]):
		return true
	if store.father[a] >= 0 and (store.father[a] == store.mother[b] or store.father[a] == store.father[b]):
		return true
	return false


## Folded into Sim.state_hash so a divergence in social memory is caught by the
## determinism test, the same way learned weights are.
func digest(id: int) -> int:
	if id < 0 or id >= count:
		return 0
	var h := 0
	for k in used[id]:
		var at := (id * SLOTS + k) * FIELDS
		h = (h ^ others[id * SLOTS + k]) * 1099511628211
		h = (h ^ int(round(records[at + VALENCE] * 1000.0))) * 1099511628211
		h = (h ^ int(records[at + EVENTS])) * 1099511628211
	return h & 0x7FFFFFFF
