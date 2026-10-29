class_name SimDetectors
extends RefCounted

## First-time pattern detectors for the Phase 2 legibility layer.
##
## These are observers, not a behaviour system. They read the same grid, story
## records and opinion values that the simulation already writes, and they name
## a pattern only after it has happened. No creature reads this unit, and no
## action is unlocked or weighted by it.
##
## Phase 2 asks for highlights and first-time detectors. The practice detector
## is deliberately not here: the plan schedules practices and the spread overlay
## for Phase 4, once artefact decay and the youth imitation window are tuned.

const GridRef := preload("res://sim/grid.gd")
const StoreRef := preload("res://sim/creature_store.gd")

const HIGHLIGHT_CAP := 8
const FIRST_CAP := 32

## Active flashes, newest last. The view reads `x`, `y`, `kind`, `text`,
## `creature`, `until` and `serial`; a serial lets the UI notice a new one.
var highlights: Array = []
## Ever-first events, kept for the history panel and the soak report. Unlike a
## highlight these do not expire: they are part of the world's story.
var firsts: Array = []

var scan_interval_days := 0.05
var stockpile_min_cells := 6
var stockpile_min_amount := 0.75
var stockpile_radius_cells := 3
var highlight_seconds := 12.0

var _serial := 0
var _last_scan_day := -1000.0
var _hardening_seen := false
var _shelter_seen := false
var _stockpile_seen := false
var _rival_seen := false
var _last_food_piles := 0


func configure(params: SimParams) -> void:
	scan_interval_days = maxf(params.f("detectors", "scan_interval_days", 0.05), 0.001)
	stockpile_min_cells = maxi(params.i("detectors", "stockpile_min_cells", 6), 2)
	stockpile_min_amount = clampf(params.f("detectors", "stockpile_min_amount", 0.75), 0.05, 1.0)
	stockpile_radius_cells = clampi(params.i("detectors", "stockpile_radius_cells", 3), 1, 12)
	highlight_seconds = maxf(params.f("detectors", "highlight_seconds", 12.0), 1.0)


## Called at the end of the fixed tick, after the story pass has read the
## committed world. The scans are rate-limited because a first can only happen
## once; the event checks are one integer comparison each.
func after_tick(sim: Sim) -> void:
	_check_hardening(sim)
	_check_shelter(sim)
	_prune_highlights(sim.time)
	if int(sim.story.food_pile_events) != _last_food_piles:
		_last_food_piles = int(sim.story.food_pile_events)
		_last_scan_day = -1000.0
	var d := sim.day()
	if d - _last_scan_day < scan_interval_days:
		return
	_last_scan_day = d
	_check_stockpile(sim)
	_check_rivalry(sim)


func _check_hardening(sim: Sim) -> void:
	if _hardening_seen or sim.story.hardening_events <= 0:
		return
	var first: Dictionary = sim.story.first_hardening()
	if first.is_empty():
		return
	_hardening_seen = true
	var cell := int(first.get("cell", -1))
	_fire(
		sim, "hardening",
		"First hard ground: wet sand piled by creature %d at %d,%d dried hard (hardness %.2f, compaction %.2f)." % [
			int(first.get("creature", -1)),
			sim.grid.cell_x(cell), sim.grid.cell_y(cell),
			float(first.get("hardness", 0.0)), float(first.get("compaction", 0.0)),
		],
		cell, int(first.get("creature", -1))
	)


func _check_shelter(sim: Sim) -> void:
	if _shelter_seen or sim.story.shelter_events <= 0:
		return
	var first: Dictionary = sim.story.first_shelter()
	if first.is_empty():
		return
	_shelter_seen = true
	var cell := int(first.get("cell", -1))
	_fire(
		sim, "shelter",
		"First shelter-like rest: creature %d rested on ground creature %d had piled and dried at %d,%d (protection %.2f)." % [
			int(first.get("rester", -1)), int(first.get("builder", -1)),
			sim.grid.cell_x(cell), sim.grid.cell_y(cell),
			float(first.get("protection", 0.0)),
		],
		cell, int(first.get("rester", -1))
	)


## A stockpile is a cluster of full food cells, not a cell flag. The detector
## counts high-value food cells inside a small radius and only names the pattern
## for the player after the cluster exists in the world.
func _check_stockpile(sim: Sim) -> void:
	if _stockpile_seen:
		return
	var cells: PackedInt32Array = sim.grid.food_cell_snapshot()
	if cells.size() < stockpile_min_cells:
		return
	var candidates := {}
	for i in cells:
		if sim.grid.amount[i] >= stockpile_min_amount and sim.grid.nutrition[i] >= 0.30:
			candidates[i] = true
	if candidates.size() < stockpile_min_cells:
		return
	# A candidate is the centre of its own neighbourhood count; a cluster of six
	# or more around any one full cell is a stockpile the player can see as one.
	var radius := stockpile_radius_cells
	for i in candidates:
		var cx := sim.grid.cell_x(i)
		var cy := sim.grid.cell_y(i)
		var count := 0
		var creature_piled := false
		for oy in range(-radius, radius + 1):
			for ox in range(-radius, radius + 1):
				var tx := cx + ox
				var ty := cy + oy
				if not sim.grid.in_bounds(tx, ty):
					continue
				var near := sim.grid.index(tx, ty)
				if candidates.has(near):
					count += 1
					if sim.story.was_food_piled(near):
						creature_piled = true
		# A starting food patch is not a stockpile. At least one full cell in
		# the cluster must have been put there by a creature's pile verb, so the
		# first named stockpile is an accumulated outcome rather than map gen.
		if count >= stockpile_min_cells and creature_piled:
			_stockpile_seen = true
			_fire(
				sim, "stockpile",
				"First food stockpile: %d full food cells within %d cells of %d,%d." % [
					count, radius, cx, cy,
				],
				i, -1
			)
			return


## The first pair whose remembered disputes cross the rival label. The label is
## computed from the same opinion value the brain reads; the detector adds no
## negative opinion of its own.
func _check_rivalry(sim: Sim) -> void:
	if _rival_seen or not sim.social_enabled or not sim.opinion_enabled:
		return
	for id in sim.store.count:
		if sim.store.alive[id] == 0:
			continue
		for k in sim.opinion.entry_count(id):
			var record: Dictionary = sim.opinion.entry_at(id, k)
			var other := int(record.get("other", -1))
			if other < 0 or other >= sim.store.count or sim.store.alive[other] == 0:
				continue
			var value: float = sim.opinion.opinion(sim.store, id, other, sim.day())
			if sim.opinion.label_for(value, int(record.get("events", 0))) != "rival":
				continue
			_rival_seen = true
			var cell := sim.grid.index(int(floor(sim.store.px[id])), int(floor(sim.store.py[id])))
			_fire(
				sim, "rivalry",
				"First rivalry: creature %d now treats %d as a rival after %s (opinion %+.2f)." % [
					id, other, sim.story.negative_chain(id, other), value,
				],
				cell, id
			)
			return


func _fire(sim: Sim, kind: String, text: String, cell: int, creature: int) -> void:
	_serial += 1
	var x := -1
	var y := -1
	if cell >= 0 and cell < sim.grid.material.size():
		x = sim.grid.cell_x(cell)
		y = sim.grid.cell_y(cell)
	var record := {
		"serial": _serial,
		"kind": kind,
		"text": text,
		"x": x,
		"y": y,
		"creature": creature,
		"day": sim.day(),
		"start": sim.time,
		"until": sim.time + highlight_seconds,
	}
	highlights.append(record)
	while highlights.size() > HIGHLIGHT_CAP:
		highlights.pop_front()
	firsts.append(record.duplicate())
	while firsts.size() > FIRST_CAP:
		firsts.pop_front()
	sim.log.push(sim.time, "first", text, creature)


func _prune_highlights(at_time: float) -> void:
	while not highlights.is_empty() and float(highlights[0]["until"]) <= at_time:
		highlights.pop_front()


## Active flashes only; the view asks once a frame and does not need expired
## entries it would immediately skip.
func active_highlights(at_time: float) -> Array:
	var out: Array = []
	for entry in highlights:
		if float(entry["until"]) > at_time:
			out.append(entry)
	return out
