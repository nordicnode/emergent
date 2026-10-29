class_name SimStory
extends RefCounted

## Causal evidence for the three Phase 1 exit stories. This unit owns only the
## log lines and counters that connect an action to its delayed outcome:
##
##   shelter - wet sand a creature piled, dried hard, and the same creature
##             later rested on it;
##   storing - a food cache a creature piled, and its later meal from that cell;
##   rivalry - the negative events behind an opinion that crossed the rival
##             label threshold.
##
## It never chooses an action and no creature reads it. The lines are generated
## from the same grid and opinion values the simulation used, so the log cannot
## claim a cause the world does not hold.

const GridRef := preload("res://sim/grid.gd")
const StoreRef := preload("res://sim/creature_store.gd")

var shelter_events := 0
var storing_events := 0
var hardening_events := 0
## One completed food pile. The stockpile detector scans immediately after a
## new pile instead of waiting out its normal cadence, so a cache that forms
## and is eaten between scans can still be the first named stockpile.
var food_pile_events := 0

## Pending piles are keyed by cell, not by creature: a builder may pile early
## and the cell may harden after it has moved on. The cap bounds both the scan
## and the log; the first cells are the ones a story is most likely to use.
const PENDING_CAP := 128
const HARD_LOG_CAP := 16

## The inspector reads the same events the log and the label read. These caps
## keep that readable evidence bounded: three incidents per remembered pair,
## the most recent pairs, and the most recent completed places.
const OPINION_EVIDENCE_PAIRS := 512
## Five events, not three: a positive exchange between two rivals is part of
## the relationship and must not push an earlier dispute out of the inspector's
## evidence. The log line for the label still names the negative events alone.
const OPINION_CHAIN_CAP := 5
const SHELTER_HISTORY_CAP := 64
const CACHE_HISTORY_CAP := 64

var _piles := {}
var _hardened := {}
var _cache := {}
## Food cells a creature has piled at least once. The stockpile detector uses
## this to tell a cache from the world generator's starting food patch; the
## brain never reads it.
var _creature_food_cells := {}
## The first completed event of each kind, kept for the Phase 2 first-time
## detectors. They are records of what already happened, never a state the
## brain or a creature reads.
var _first_hardened := {}
var _first_shelter := {}
var _rest_logged := {}
var _hard_logged := 0
## Every opinion event, not only a negative one: the inspector must be able to
## explain a friendship built by sharing as well as a rivalry built by disputes.
var _opinion_events := {}
var _opinion_order: Array = []
## Completed outcomes keep their place and their days after the pending pile or
## cache has been consumed, because that is the chain the inspector shows.
var _shelter_outcomes: Array = []
var _cache_outcomes: Array = []
## Per-cell dispute history for the place view and the contested tint. It is
## recorded from the same event that changes opinion; the brain never reads it.
var _place_contests := {}
var current_day := 0.0


func note_pile(sim: Sim, id: int, cell: int, material: int, wetness: float) -> void:
	if sim == null or id < 0 or cell < 0:
		return
	if material == GridRef.SAND:
		if wetness < 0.15:
			return
		if _piles.has(cell) or _piles.size() < PENDING_CAP:
			_piles[cell] = {
				"creature": id,
				"day": sim.day(),
				"wetness": wetness,
			}
	elif material == GridRef.FOOD:
		_creature_food_cells[cell] = sim.day()
		food_pile_events += 1
		if _cache.has(cell) or _cache.size() < PENDING_CAP:
			_cache[cell] = {
				"creature": id,
				"day": sim.day(),
			}


## Called from the real tick. A pile that has crossed the hard-sand threshold is
## the middle of the shelter chain; write that step once, then see whether its
## builder is already resting there or arrives later.
func after_tick(sim: Sim) -> void:
	current_day = sim.day()
	_refresh_contests(sim)
	if _piles.is_empty():
		return
	for cell in _piles.keys():
		if cell < 0 or cell >= sim.grid.material.size():
			_piles.erase(cell)
			continue
		if int(sim.grid.material[cell]) != GridRef.SAND:
			_piles.erase(cell)
			continue
		if float(sim.grid.hardness[cell]) < sim.grid.hard_sand_threshold:
			continue
		var pile: Dictionary = _piles[cell]
		_piles.erase(cell)
		var builder: int = int(pile["creature"])
		_hardened[cell] = {
			"cell": cell,
			"creature": builder,
			"day": float(pile["day"]),
			"hard_day": sim.day(),
			"wetness": float(pile["wetness"]),
			"hardness": float(sim.grid.hardness[cell]),
			"compaction": float(sim.grid.compaction[cell]),
		}
		if _first_hardened.is_empty():
			_first_hardened = _hardened[cell].duplicate()
		hardening_events += 1
		if _hard_logged < HARD_LOG_CAP:
			_hard_logged += 1
			sim.log.push(
				sim.time,
				"story",
				"Wet sand Creature %d piled at %d,%d dried hard — hardness %.2f, compaction %.2f." % [
					builder,
					sim.grid.cell_x(cell),
					sim.grid.cell_y(cell),
					float(sim.grid.hardness[cell]),
					float(sim.grid.compaction[cell]),
				],
				builder
			)
		# A creature that stayed asleep through the hardening still completes
		# the chain; do not require it to stand up and lie down again.
		_maybe_rest(sim, cell)


## Called once per decision, next to the safety logger. A rest on ground this
## creature made hard is the end of the shelter chain.
func note_decision(sim: Sim, id: int, prev_verb: int, decision: SimBrain.Decision) -> void:
	if decision.verb != StoreRef.Verb.REST or prev_verb == StoreRef.Verb.REST:
		return
	var cell := sim.grid.index(int(floor(sim.store.px[id])), int(floor(sim.store.py[id])))
	_maybe_rest(sim, cell)


## A meal taken from the creature's own cache, after enough time that returning
## to it is a delayed outcome rather than eating where one already stands.
func note_cache_eaten(sim: Sim, id: int, cell: int, food_before: float) -> void:
	if not _cache.has(cell):
		return
	var cache: Dictionary = _cache[cell]
	var elapsed := sim.day() - float(cache["day"])
	if elapsed < 0.005:
		return
	_cache.erase(cell)
	var builder: int = int(cache["creature"])
	storing_events += 1
	_cache_outcomes.append({
		"cell": cell,
		"x": sim.grid.cell_x(cell),
		"y": sim.grid.cell_y(cell),
		"builder": builder,
		"eater": id,
		"pile_day": float(cache["day"]),
		"eat_day": sim.day(),
		"hours": elapsed * 24.0,
		"hunger_before": food_before,
		"hunger_after": sim.store.food_level[id],
	})
	if _cache_outcomes.size() > CACHE_HISTORY_CAP:
		_cache_outcomes.pop_front()
	sim.log.push(
		sim.time,
		"story",
		"Creature %d ate from the food cache at %d,%d piled by %d after %.1f hours — hunger %d%% to %d%%." % [
			id,
			sim.grid.cell_x(cell),
			sim.grid.cell_y(cell),
			builder,
			elapsed * 24.0,
			int(round((1.0 - food_before) * 100.0)),
			int(round((1.0 - sim.store.food_level[id]) * 100.0)),
		],
		id
	)


## A dispute over a food cell, recorded where it happened. This is the place
## history's contested column, not a second grievance: the opinion event is
## written by the caller, and this only remembers the location.
func note_contest(sim: Sim, cell: int, attacker: int, victim: int, injured: bool) -> void:
	if sim == null or cell < 0 or cell >= sim.grid.material.size():
		return
	var record: Dictionary = _place_contests.get(cell, {
		"cell": cell,
		"events": 0,
		"injuries": 0,
		"last_day": 0.0,
		"last_attacker": -1,
		"last_victim": -1,
		"last_dirty_day": -1.0,
	})
	record["events"] = int(record["events"]) + 1
	if injured:
		record["injuries"] = int(record["injuries"]) + 1
	record["last_day"] = sim.day()
	record["last_attacker"] = attacker
	record["last_victim"] = victim
	_place_contests[cell] = record
	sim.grid.mark_dirty_cell(sim.grid.cell_x(cell), sim.grid.cell_y(cell))


func _refresh_contests(sim: Sim) -> void:
	for cell in _place_contests.keys():
		var record: Dictionary = _place_contests[cell]
		if current_day - float(record["last_day"]) >= 2.0:
			continue
		if current_day - float(record["last_dirty_day"]) < 0.1:
			continue
		record["last_dirty_day"] = current_day
		sim.grid.mark_dirty_cell(sim.grid.cell_x(cell), sim.grid.cell_y(cell))


## Red heat for a recently contested cell, fading by half each half-day. This
## is what the terrain view paints; there is no "contested" cell flag.
func contest_heat(cell: int) -> float:
	if not _place_contests.has(cell):
		return 0.0
	var record: Dictionary = _place_contests[cell]
	var age := maxf(current_day - float(record["last_day"]), 0.0)
	var strength := clampf(float(record["events"]) * 0.18, 0.0, 0.55)
	return strength * pow(0.5, age / 0.5)


func _contest_summary(cell: int) -> Dictionary:
	if not _place_contests.has(cell):
		return {"events": 0, "injuries": 0, "day": 0.0, "attacker": -1, "victim": -1}
	var record: Dictionary = _place_contests[cell]
	return {
		"events": int(record["events"]),
		"injuries": int(record["injuries"]),
		"day": float(record["last_day"]),
		"attacker": int(record["last_attacker"]),
		"victim": int(record["last_victim"]),
	}


## Remembers the event behind an opinion change. Only the label and the
## inspector read this; the brain keeps reading the opinion number alone.
func note_opinion(a: int, b: int, reason: String, delta: float, at_day: float) -> void:
	if a < 0 or b < 0 or a == b:
		return
	var key := "%d:%d" % [a, b]
	if not _opinion_events.has(key):
		if _opinion_order.size() >= OPINION_EVIDENCE_PAIRS:
			_opinion_events.erase(_opinion_order.pop_front())
		_opinion_order.append(key)
	var chain: Array = _opinion_events.get(key, [])
	chain.append({"reason": reason, "delta": delta, "day": at_day})
	while chain.size() > OPINION_CHAIN_CAP:
		chain.pop_front()
	_opinion_events[key] = chain


## The negative reasons only, for the rival label's one-line causal claim.
func negative_chain(a: int, b: int) -> String:
	var reasons: Array = []
	for event in _opinion_events.get("%d:%d" % [a, b], []):
		if float(event["delta"]) < 0.0:
			reasons.append(String(event["reason"]))
	if reasons.is_empty():
		return "no recorded incidents"
	return ", ".join(reasons)


func _maybe_rest(sim: Sim, cell: int) -> void:
	if not _hardened.has(cell):
		return
	if _rest_logged.has(cell):
		return
	var hard: Dictionary = _hardened[cell]
	var builder: int = int(hard["creature"])
	for id in sim.store.count:
		if sim.store.alive[id] == 0 or int(sim.store.verb[id]) != StoreRef.Verb.REST:
			continue
		if sim.grid.index(int(floor(sim.store.px[id])), int(floor(sim.store.py[id]))) != cell:
			continue
		_rest_logged[cell] = true
		shelter_events += 1
		var outcome := {
			"cell": cell,
			"x": sim.grid.cell_x(cell),
			"y": sim.grid.cell_y(cell),
			"builder": builder,
			"rester": id,
			"pile_day": float(hard["day"]),
			"hard_day": float(hard.get("hard_day", hard["day"])),
			"rest_day": sim.day(),
			"hardness": float(sim.grid.hardness[cell]),
			"protection": float(sim.grid.protection_quality(cell)),
			"comfort": float(sim.grid.comfort_quality(cell)),
			"safety": float(sim.store.safety_level[id]),
		}
		if _first_shelter.is_empty():
			_first_shelter = outcome.duplicate()
		_shelter_outcomes.append(outcome)
		if _shelter_outcomes.size() > SHELTER_HISTORY_CAP:
			_shelter_outcomes.pop_front()
		sim.log.push(
			sim.time,
			"story",
			"Creature %d rests on hard ground at %d,%d piled by %d — hardness %.2f, protection %.2f, comfort %.2f, safety %d%%." % [
				id,
				sim.grid.cell_x(cell),
				sim.grid.cell_y(cell),
				builder,
				float(sim.grid.hardness[cell]),
				float(sim.grid.protection_quality(cell)),
				float(sim.grid.comfort_quality(cell)),
				int(round(sim.store.safety_level[id] * 100.0)),
			],
			id
		)
		return


## The first event of each completed story. The detectors name a pattern from
## these records; they never influence it.
func first_hardening() -> Dictionary:
	return _first_hardened.duplicate()


func first_shelter() -> Dictionary:
	return _first_shelter.duplicate()


func was_food_piled(cell: int) -> bool:
	return _creature_food_cells.has(cell)


## Completed place outcomes for the world history panel, newest first. This is
## the same evidence the inspector shows one creature at a time.
func place_history(sim: Sim, limit: int = 6) -> Array:
	var out: Array = []
	for record in _shelter_outcomes:
		var shelter_cell := int(record.get("cell", -1))
		var shelter_contest := _contest_summary(shelter_cell)
		out.append({
			"kind": "shelter",
			"cell": shelter_cell,
			"x": int(record.get("x", 0)),
			"y": int(record.get("y", 0)),
			"builder": int(record.get("builder", -1)),
			"user": int(record.get("rester", -1)),
			"day": float(record.get("rest_day", 0.0)),
			"detail": "hardness %.2f · protection %.2f" % [float(record.get("hardness", 0.0)), float(record.get("protection", 0.0))],
			"contests": int(shelter_contest["events"]),
			"injuries": int(shelter_contest["injuries"]),
			"contest_day": float(shelter_contest["day"]),
		})
	for record in _cache_outcomes:
		var cache_cell := int(record.get("cell", -1))
		var cache_contest := _contest_summary(cache_cell)
		out.append({
			"kind": "cache",
			"cell": cache_cell,
			"x": int(record.get("x", 0)),
			"y": int(record.get("y", 0)),
			"builder": int(record.get("builder", -1)),
			"user": int(record.get("eater", -1)),
			"day": float(record.get("eat_day", 0.0)),
			"detail": "eaten after %.1f h · hunger %d%%→%d%%" % [
				float(record.get("hours", 0.0)),
				int(round((1.0 - float(record.get("hunger_before", 0.0))) * 100.0)),
				int(round((1.0 - float(record.get("hunger_after", 0.0))) * 100.0)),
			],
			"contests": int(cache_contest["events"]),
			"injuries": int(cache_contest["injuries"]),
			"contest_day": float(cache_contest["day"]),
		})
	# Contested cells with no completed shelter or cache are places too: the
	# last water in a drought is a place because of the fights, not because a
	# creature built there.
	var covered := {}
	for entry in out:
		covered[int(entry.get("cell", -1))] = true
	for cell in _place_contests:
		if covered.has(cell):
			continue
		var record: Dictionary = _place_contests[cell]
		out.append({
			"kind": "contest",
			"cell": cell,
			"x": sim.grid.cell_x(cell),
			"y": sim.grid.cell_y(cell),
			"builder": -1,
			"user": int(record.get("last_victim", -1)),
			"day": float(record.get("last_day", 0.0)),
			"detail": "%d disputes · %d injuries · last attacker %d, loser %d" % [
				int(record.get("events", 0)), int(record.get("injuries", 0)),
				int(record.get("last_attacker", -1)), int(record.get("last_victim", -1)),
			],
			"contests": int(record.get("events", 0)),
			"injuries": int(record.get("injuries", 0)),
			"contest_day": float(record.get("last_day", 0.0)),
		})
	out.sort_custom(func(a, b): return float(a["day"]) > float(b["day"]))
	return out.slice(0, maxi(limit, 0))


## One read for the inspector: the strongest opinion with the events behind it,
## plus this creature's completed shelter and cache outcomes. The panel formats
## this; it does not query the log, opinion store or story records separately.
func inspector_evidence(sim: Sim, id: int) -> Dictionary:
	var out := {"opinions": [], "shelters": [], "caches": []}
	if sim == null or id < 0 or id >= sim.store.count:
		return out

	var top: Array = sim.opinion.top_opinions(sim.store, id, sim.day(), 1)
	if not top.is_empty():
		var record: Dictionary = top[0]
		var other := int(record["other"])
		var chain: Array = []
		for event in _opinion_events.get("%d:%d" % [id, other], []):
			chain.append({
				"reason": String(event["reason"]),
				"delta": float(event["delta"]),
				"day": float(event["day"]),
			})
		var acted := {}
		for i in range(sim.log.entries.size() - 1, -1, -1):
			var entry: Dictionary = sim.log.entries[i]
			if String(entry["kind"]) != "safety":
				continue
			if String(entry["text"]).contains("Creature %d fled %d" % [id, other]):
				acted = {"label": "fled", "day": float(entry["time"]) / maxf(sim.day_seconds, 0.001)}
				break
		out["opinions"].append({
			"other": other,
			"label": String(record["label"]),
			"valence": float(record["valence"]),
			"events": int(record["events"]),
			"kin": bool(record["kin"]),
			"chain": chain,
			"acted": acted,
		})

	for record in _shelter_outcomes:
		var builder := int(record["builder"])
		var rester := int(record["rester"])
		if builder != id and rester != id:
			continue
		var cell := int(record["cell"])
		out["shelters"].append({
			"x": sim.grid.cell_x(cell),
			"y": sim.grid.cell_y(cell),
			"builder": builder,
			"rester": rester,
			"pile_day": float(record["pile_day"]),
			"hard_day": float(record["hard_day"]),
			"rest_day": float(record["rest_day"]),
			"hardness": float(record["hardness"]),
			"protection": float(record["protection"]),
			"comfort": float(record["comfort"]),
			"safety": float(record["safety"]),
		})
	out["shelters"].sort_custom(func(a, b): return float(a["rest_day"]) > float(b["rest_day"]))
	out["shelters"] = out["shelters"].slice(0, 2)

	for record in _cache_outcomes:
		var builder := int(record["builder"])
		var eater := int(record["eater"])
		if builder != id and eater != id:
			continue
		var cell := int(record["cell"])
		out["caches"].append({
			"x": sim.grid.cell_x(cell),
			"y": sim.grid.cell_y(cell),
			"builder": builder,
			"eater": eater,
			"pile_day": float(record["pile_day"]),
			"eat_day": float(record["eat_day"]),
			"hours": float(record["hours"]),
			"hunger_before": float(record["hunger_before"]),
			"hunger_after": float(record["hunger_after"]),
		})
	out["caches"].sort_custom(func(a, b): return float(a["eat_day"]) > float(b["eat_day"]))
	out["caches"] = out["caches"].slice(0, 2)
	return out
