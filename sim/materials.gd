class_name SimMaterials
extends RefCounted

## Material simulation: one general function per property, each serving every
## material that carries it. No step here knows what a shelter is.
##
## Order per material tick:
##   1. flow       - liquids fall, then spread sideways, bottom-up
##   2. wetness    - drain downward, evaporate by exposure; standing water seeps
##                    back toward capacity (flow() runs it before the moves, so
##                    a refilled cell also gets its chance to spread)
##   3. compaction - weight above, while the cell is awake for other reasons
##   4. hardening  - wetness history x compaction x drying; wet hard sand softens
## Rotting and food regrowth run with the property pass over the food-cell list.
##
## Cost control: flow walks the maintained water list (bounded by how much water
## the world holds) and rejects pond interior cells before the precise move
## checks, since a cell surrounded by water at its own level cannot move.
## Everything else walks a work queue of cells that are still changing, and a
## pass takes at most `material_batch_cells` of them. A world with more wet
## ground than one pass can cover degrades into slower material time, never into
## a longer frame.
##
## The hot loops cache the grid's arrays in typed locals: a packed-array element
## through a script property costs roughly five times what the same element
## costs through a local, and this pass touches a cell dozens of times.

const GridRef := preload("res://sim/grid.gd")


## Values read once per tick instead of once per cell. At a few thousand active
## cells the register lookups dominated the material step.
class Settings:
	var day := 480.0
	var drain := 0.04
	var evap := 1.6
	var water_evap := 0.2
	var history_decay := 0.12
	var weight_rate := 0.02
	var weight_cap := 0.20
	var hard_rate := 2.0
	var soft_rate := 0.8
	var compaction_min := 0.25
	var history_min := 0.35
	var absorb := 0.30
	var exposure_falloff := 0.75
	var exposure_min := 0.20
	var batch := 4000
	var dry_epsilon := 0.01
	var move_epsilon := 0.004
	var field_capacity := 0.5
	var water_max := 1.0
	var cap_sand := 1.0
	var cap_food := 0.7
	var hard_max := 0.35
	var hardening := true


static func read_settings(params: SimParams) -> Settings:
	var s := Settings.new()
	s.day = maxf(params.f("sim", "day_seconds", 480.0), 0.001)
	s.drain = params.f("materials", "wetness_drain_per_sec", 0.04)
	s.evap = params.f("materials", "wetness_evaporate_per_day", 1.6)
	s.water_evap = params.f("materials", "water_evaporate_per_day", 0.2)
	s.history_decay = params.f("materials", "wet_history_decay_per_day", 0.12)
	s.weight_rate = params.f("materials", "weight_compaction_per_sec", 0.02)
	s.weight_cap = params.f("materials", "weight_compaction_cap", 0.20)
	s.hard_rate = params.f("materials", "hardening_per_day", 2.0)
	s.soft_rate = params.f("materials", "softening_per_day", 0.8)
	s.compaction_min = params.f("materials", "hardening_compaction_min", 0.25)
	s.history_min = params.f("materials", "hardening_wet_history_min", 0.35)
	s.absorb = params.f("materials", "water_absorb_per_sec", 0.30)
	s.exposure_falloff = params.f("materials", "exposure_depth_falloff", 0.75)
	s.exposure_min = params.f("materials", "exposure_min", 0.20)
	s.batch = maxi(1, int(params.f("materials", "material_batch_cells", 4000.0)))
	s.dry_epsilon = params.f("materials", "wetness_dry_epsilon", 0.01)
	s.move_epsilon = params.f("materials", "wetness_move_epsilon", 0.004)
	s.field_capacity = clampf(params.f("materials", "wetness_field_capacity", 0.5), 0.0, 0.95)
	return s


## One call that does everything, for tests and tools. The live simulation calls
## flow and properties on separate cadences (water needs to move more often than
## slow drying does).
static func step(grid: SimGrid, params: SimParams, tick: int, dt: float) -> Dictionary:
	grid.begin_tick(tick)
	var stats := flow(grid, params, tick, dt)
	stats.merge(properties(grid, params, tick, dt))
	return stats


static func flow(grid: SimGrid, params: SimParams, tick: int, dt: float) -> Dictionary:
	grid.begin_tick(tick)
	var settings := read_settings(params)
	settings.water_max = grid.water_max
	settings.cap_sand = grid.absorb_capacity(GridRef.SAND)
	settings.cap_food = grid.absorb_capacity(GridRef.FOOD)
	settings.hard_max = grid.convert_max_hardness
	var moves := 0
	_regrow_water(grid, params, dt)

	# Liquids move bottom-up so a falling column travels one cell per tick
	# instead of cascading. Cell index ascends with y, so walk the snapshot in
	# reverse; the per-cell stamp prevents double moves.
	var fluid := grid.water_cell_snapshot()
	if not fluid.is_empty():
		fluid.sort()
		for k in range(fluid.size() - 1, -1, -1):
			var i: int = fluid[k]
			if int(grid.material[i]) == GridRef.WATER:
				if _flow_cell(grid, i, tick, settings, dt):
					moves += 1
	return {"moves": moves, "water_cells": grid.water_cell_count()}


## Wetness, drying, compaction, hardening, softening and rot. A pass takes a
## fixed batch; each cell is advanced by the time since *it* was last processed,
## which is what lets a bounded pass stay physically exact.
static func properties(grid: SimGrid, params: SimParams, tick: int, dt: float, hardening_enabled: bool = true) -> Dictionary:
	var settings := read_settings(params)
	settings.hardening = hardening_enabled
	settings.water_max = grid.water_max
	settings.cap_sand = grid.absorb_capacity(GridRef.SAND)
	settings.cap_food = grid.absorb_capacity(GridRef.FOOD)
	settings.hard_max = grid.convert_max_hardness
	var batch := grid.take_material_batch(settings.batch)
	var prop_tick: PackedInt32Array = grid.prop_tick
	for i in batch:
		# Wake sets the clock; max 1 keeps tests and out-of-order ticks sane.
		var waited: int = maxi(tick - prop_tick[i], 1)
		_cell_pass(grid, i, settings, float(waited) * dt)
		prop_tick[i] = tick
	_rot(grid, params, dt)
	_regrow_food(grid, params, dt)
	return {
		"active_cells": grid.active_cell_count(),
		"processed": batch.size(),
	}


# --- flow ----------------------------------------------------------------

## Whether water may move into cell j. Porous material leaves a little headroom:
## absorbing into an already saturated cell only wakes it for a transfer that
## cannot happen.
static func _can_enter(mat: PackedByteArray, amt: PackedFloat32Array, wet: PackedFloat32Array, hard: PackedFloat32Array, j: int, s: Settings) -> bool:
	var m: int = int(mat[j])
	if m == GridRef.AIR:
		return true
	if m == GridRef.WATER:
		return amt[j] < s.water_max - 0.001
	# Hard porous material is a pan: water runs off it, not through it.
	if hard[j] >= s.hard_max:
		return false
	if m == GridRef.SAND:
		return wet[j] < s.cap_sand - 0.02
	if m == GridRef.FOOD:
		return wet[j] < s.cap_food - 0.02
	# A liquid lighter than water would be displaced here; no such material
	# exists yet, so the branch is intentionally absent rather than a stub.
	return false


static func _flow_cell(grid: SimGrid, i: int, tick: int, s: Settings, dt: float) -> bool:
	var mat: PackedByteArray = grid.material
	var amt: PackedFloat32Array = grid.amount
	if grid.stamp[i] == tick:
		return false
	var here: float = amt[i]
	if here <= 0.001:
		return false
	var width: int = grid.width
	var height: int = grid.height
	var x: int = i % width
	var y: int = i / width

	# Fast reject: most water is pond interior, where every destination is water
	# at this level and nothing can move. Proving that costs five small reads,
	# against up to five _can_enter calls plus a _move_water attempt each - and
	# flow walks every water cell, so the interior was most of the material step.
	# The test is deliberately conservative: any non-water neighbour, however
	# unlikely to accept water, sends the cell down the precise path below.
	if _stuck_in_water(mat, amt, i, x, y, width, height, here - 0.02):
		return false

	var wet: PackedFloat32Array = grid.wetness
	var hard: PackedFloat32Array = grid.hardness

	# Alternate the horizontal preference so ponds do not drift one way.
	var dir: int = 1 if ((tick + x + y) % 2 == 0) else -1

	if y + 1 < height:
		if _can_enter(mat, amt, wet, hard, i + width, s) and _move_water(grid, x, y, x, y + 1, tick, s, dt):
			return true
		var lx: int = x - dir
		if lx >= 0 and _can_enter(mat, amt, wet, hard, i + width - dir, s) and _move_water(grid, x, y, lx, y + 1, tick, s, dt):
			return true
		var rx: int = x + dir
		if rx < width and _can_enter(mat, amt, wet, hard, i + width + dir, s) and _move_water(grid, x, y, rx, y + 1, tick, s, dt):
			return true
	var sx: int = x - dir
	if sx >= 0 and sx < width and _can_enter(mat, amt, wet, hard, i - dir, s) and _move_water(grid, x, y, sx, y, tick, s, dt):
		return true
	var tx: int = x + dir
	if tx >= 0 and tx < width and _can_enter(mat, amt, wet, hard, i + dir, s) and _move_water(grid, x, y, tx, y, tick, s, dt):
		return true
	return false


## True when every cell this water could move into already holds water at least
## as full as itself, so the pass has nothing to do. Candidates mirror _flow_cell
## exactly: down, then down-diagonals in its alternating order, then the sides.
## Water never moves up, so the cell above is not a candidate.
static func _stuck_in_water(mat: PackedByteArray, amt: PackedFloat32Array, i: int, x: int, y: int, width: int, height: int, low: float) -> bool:
	if y + 1 < height:
		var b: int = i + width
		if not _water_at_level(mat, amt, b, low):
			return false
		if x > 0 and not _water_at_level(mat, amt, b - 1, low):
			return false
		if x + 1 < width and not _water_at_level(mat, amt, b + 1, low):
			return false
	if x > 0 and not _water_at_level(mat, amt, i - 1, low):
		return false
	if x + 1 < width and not _water_at_level(mat, amt, i + 1, low):
		return false
	return true


static func _water_at_level(mat: PackedByteArray, amt: PackedFloat32Array, j: int, low: float) -> bool:
	return int(mat[j]) == GridRef.WATER and amt[j] >= low


## Moves water from one cell to another. Free water moves whole cells; porous
## material drinks it in at a limited rate, which is why soaking takes time and
## a little water and a lot of water are different actions.
static func _move_water(grid: SimGrid, sx: int, sy: int, dx: int, dy: int, tick: int, settings: Settings, dt: float) -> bool:
	var src: int = grid.index(sx, sy)
	var dst: int = grid.index(dx, dy)
	var available: float = grid.amount[src]
	if available <= 0.0001:
		return false

	var moved := 0.0
	var dm: int = int(grid.material[dst])
	if dm != GridRef.AIR and dm != GridRef.WATER and grid.hardness[dst] >= settings.hard_max:
		return false
	if dm == GridRef.AIR:
		moved = minf(available, settings.water_max)
		grid.material[dst] = GridRef.WATER
		grid.amount[dst] = moved
		grid.wetness[dst] = 0.0
		grid.track_water(dst)
	elif dm == GridRef.WATER:
		# Level only downhill: without this, two nearly equal cells trade water
		# back and forth every tick. Move at most half the difference, so a
		# partially full cell can never empty itself into a neighbour and leave
		# a hole that has no way to refill from below.
		var diff: float = available - grid.amount[dst]
		if diff <= 0.02:
			return false
		var space: float = settings.water_max - grid.amount[dst]
		if space <= 0.0001:
			return false
		moved = minf(minf(diff * 0.5, space), available * 0.5)
		if moved <= 0.0001:
			return false
		grid.amount[dst] += moved
	else:
		var space: float = grid.absorb_capacity(dm) - grid.wetness[dst]
		if space <= 0.0001:
			return false
		moved = minf(minf(available, space), settings.absorb * dt)
		if moved < settings.move_epsilon:
			return false
		grid.wetness[dst] += moved
		grid.wet_history[dst] = maxf(grid.wet_history[dst], grid.wetness[dst])

	grid.amount[src] -= moved
	if grid.amount[src] <= 0.0001:
		grid.amount[src] = 0.0
		grid.material[src] = GridRef.AIR
		grid.wetness[src] = 0.0
		grid.untrack_water(src)
	grid.stamp[src] = tick
	grid.stamp[dst] = tick
	grid.mark_dirty_cell(sx, sy)
	grid.mark_dirty_cell(dx, dy)
	grid.wake_cell(src)
	grid.wake_cell(dst)
	return moved > 0.0


# --- wetness, compaction, hardening, age --------------------------------

static func _cell_pass(grid: SimGrid, i: int, s: Settings, dt: float) -> void:
	var mat: PackedByteArray = grid.material
	var m: int = int(mat[i])
	if m == GridRef.AIR:
		return
	var amt: PackedFloat32Array = grid.amount
	var wet_a: PackedFloat32Array = grid.wetness
	var hist_a: PackedFloat32Array = grid.wet_history
	var comp_a: PackedFloat32Array = grid.compaction
	var hard_a: PackedFloat32Array = grid.hardness
	var coh_a: PackedFloat32Array = grid.cohesion
	var width: int = grid.width
	var y: int = i / width
	var exposure: float = clampf(1.0 - float(y) / float(grid.height) * s.exposure_falloff, s.exposure_min, 1.0)
	var wet: float = wet_a[i]
	var changed := false

	# Free water evaporates slowly, so ponds shrink over days.
	if m == GridRef.WATER:
		var amount: float = amt[i]
		if amount > 0.0:
			var lost: float = minf(amount, s.water_evap * exposure * dt / s.day)
			amount -= lost
			amt[i] = amount
			changed = lost > 0.0
			if amount <= 0.0001:
				amt[i] = 0.0
				mat[i] = GridRef.AIR
				grid.untrack_water(i)
				changed = true
		grid.wake_cell(i)
		if changed:
			_mark_changed(grid, i, y)
		return

	if m == GridRef.SAND or m == GridRef.FOOD:
		# Absorbed water drains down, but only the part above field capacity:
		# sand holds a film against gravity, and without that floor a single
		# drop would walk to the bottom of the map leaving a wake of damp cells.
		var excess: float = wet - s.field_capacity
		if excess > s.move_epsilon and y + 1 < grid.height:
			var below: int = i + width
			var bm: int = int(mat[below])
			# A hard pan does not take water from above either: the shell that
			# holds a pond would otherwise be wetted and softened by the pond.
			if (bm == GridRef.SAND or bm == GridRef.FOOD) and hard_a[below] < s.hard_max:
				var cap: float = s.cap_sand if bm == GridRef.SAND else s.cap_food
				var space: float = cap - wet_a[below]
				if space > s.move_epsilon:
					var flow: float = minf(minf(excess, space), s.drain * dt)
					if flow >= s.move_epsilon:
						wet -= flow
						wet_a[i] = wet
						wet_a[below] += flow
						hist_a[below] = maxf(hist_a[below], wet_a[below])
						grid.wake_cell(below)
						changed = true

		# Whatever is left dries from the exposed surface, held film included.
		var removed: float = minf(wet, s.evap * exposure * dt / s.day)
		if removed > 0.0:
			wet -= removed
			changed = true
		if wet < s.dry_epsilon:
			wet = 0.0
		wet_a[i] = wet

	# Wetness history decays slowly; it is the memory hardening reads.
	var history: float = hist_a[i]
	if history > 0.0:
		history = maxf(wet, history - s.history_decay * dt / s.day)
		hist_a[i] = history

	# Weight above compacts, capped below the hardening threshold so burial
	# alone never turns the world into stone. Applied only while the cell is
	# awake for another reason, which is enough: a cell needs to be wet or
	# drying for compaction to matter.
	if m == GridRef.SAND and y > 0 and comp_a[i] < s.weight_cap:
		var above: int = i - width
		if int(mat[above]) == GridRef.SAND and amt[above] > 0.5:
			comp_a[i] = minf(s.weight_cap, comp_a[i] + s.weight_rate * dt)
			changed = true

	# Hardening: wetness history x compaction x drying. The ablation leaves
	# compaction, wetness and drying intact and removes only this stage.
	if m == GridRef.SAND and s.hardening:
		var compaction: float = comp_a[i]
		var dryness: float = clampf(1.0 - wet / maxf(grid.mud_wetness, 0.01), 0.0, 1.0)
		if dryness > 0.0 and history > s.history_min and compaction > s.compaction_min:
			var comp: float = clampf((compaction - s.compaction_min) / maxf(1.0 - s.compaction_min, 0.01), 0.0, 1.0)
			var hist: float = clampf((history - s.history_min) / maxf(1.0 - s.history_min, 0.01), 0.0, 1.0)
			var gain: float = s.hard_rate * comp * hist * dryness * dt / s.day
			if gain > 0.0:
				hard_a[i] = minf(1.0, hard_a[i] + gain)
				coh_a[i] = minf(1.0, coh_a[i] + gain)
				changed = true
		# Wet hard material softens: this is what a flood does to a hardened
		# structure before anything else happens to it.
		if wet > grid.mud_wetness and hard_a[i] > 0.0:
			var wet_factor: float = clampf((wet - grid.mud_wetness) / maxf(1.0 - grid.mud_wetness, 0.01), 0.0, 1.0)
			var loss: float = s.soft_rate * wet_factor * dt / s.day
			hard_a[i] = maxf(0.0, hard_a[i] - loss)
			coh_a[i] = maxf(0.0, coh_a[i] - loss)
			changed = true
		if hard_a[i] < 0.0005:
			hard_a[i] = 0.0

	grid.age[i] += dt

	if changed:
		_mark_changed(grid, i, y)

	# Keep cells awake only while something is still changing. Hardening is
	# slow, so it must survive the moment wetness reaches zero.
	var keep_awake := false
	if wet > 0.0:
		keep_awake = true
	if m == GridRef.SAND and history > s.history_min and comp_a[i] > s.compaction_min and hard_a[i] < 0.99:
		keep_awake = true
	if keep_awake:
		grid.wake_cell(i)


static func _mark_changed(grid: SimGrid, i: int, y: int) -> void:
	grid.mark_dirty_cell(i % grid.width, y)


# --- water replenishment ---------------------------------------------------

## Standing water seeps back toward its capacity, logistically: the gain is
## proportional to the water a cell already holds and to the room left in it.
## A pond that is merely drawn down therefore refills the holes drinking left
## in it, while one drunk to a puddle recovers only a trickle and can still be
## lost - which is what keeps the drought scenario honest. Without this rule a
## world has no water cycle at all: ponds evaporate and are drunk dry exactly
## once, so any no-input run ends in extinction by arithmetic rather than by
## ecology, whatever the creatures do. Zero restores that finite world.
static func _regrow_water(grid: SimGrid, params: SimParams, dt: float) -> void:
	var rate: float = params.f("materials", "water_regrow_per_day", 0.0)
	if rate <= 0.0:
		return
	var day: float = maxf(params.f("sim", "day_seconds", 480.0), 0.001)
	var step := dt / day
	var cap: float = maxf(grid.water_max, 0.001)
	for i in grid.water_cell_snapshot():
		if int(grid.material[i]) != GridRef.WATER:
			continue
		var before: float = grid.amount[i]
		if before <= 0.0 or before >= cap:
			continue
		var share := before / cap
		var added: float = minf(cap - before, rate * share * (1.0 - share) * step)
		if added <= 0.0:
			continue
		grid.amount[i] = before + added
		grid.mark_dirty_cell(i % grid.width, i / grid.width)


# --- food regrowth --------------------------------------------------------

## Food regrows where food already is: a patch recovers mass at a slow per-day
## rate. New growth is fresh tissue, so it dilutes both rot and toxin in
## proportion to the mass it adds; a full cell gains nothing and keeps rotting.
## It does not create food from bare ground, so the starting patches remain the
## map of where food can be. A grazed cell keeps a living trace (see
## SimGrid.consume), so the patch survives being eaten to the floor and can grow
## back; the trace itself is never edible.
static func _regrow_food(grid: SimGrid, params: SimParams, dt: float) -> void:
	var day: float = maxf(params.f("sim", "day_seconds", 480.0), 0.001)
	var amount_rate: float = params.f("materials", "food_regrow_per_day", 0.15)
	if amount_rate <= 0.0:
		return
	var step := dt / day
	for i in grid.food_cell_snapshot():
		if int(grid.material[i]) != GridRef.FOOD:
			continue
		var before: float = grid.amount[i]
		if before >= grid.food_max:
			continue
		var added: float = minf(grid.food_max - before, amount_rate * step)
		if added <= 0.0:
			continue
		var total := before + added
		grid.amount[i] = total
		# Fresh growth has full nutrition and no toxin, so it dilutes what the
		# old mass accumulated. This is why a grazed patch recovers but a full
		# rotten one does not.
		grid.nutrition[i] = clampf((grid.nutrition[i] * before + added) / total, 0.0, 1.0)
		grid.toxicity[i] = clampf(grid.toxicity[i] * before / total, 0.0, 1.0)
		grid.mark_dirty_cell(i % grid.width, i / grid.width)


# --- rotting -------------------------------------------------------------

static func _rot(grid: SimGrid, params: SimParams, elapsed: float) -> void:
	var day: float = maxf(params.f("sim", "day_seconds", 480.0), 0.001)
	var rate: float = params.f("materials", "rot_per_day", 0.35)
	var wet_mult: float = params.f("materials", "rot_wetness_mult", 1.5)
	var temp_mult: float = params.f("materials", "rot_temperature_mult", 0.6)
	var ambient: float = params.f("materials", "ambient_temperature", 0.55)
	var toxicity_threshold: float = params.f("materials", "rot_toxicity_threshold", 0.40)
	var toxicity_rate: float = params.f("materials", "rot_toxicity_per_day", 0.30)

	# Visits the food cells, not the chunks that contain them: a starting world's
	# 250 food cells in 30 chunks used to cost a 120,000-cell scan per pass.
	for i in grid.food_cell_snapshot():
		if int(grid.material[i]) != GridRef.FOOD:
			continue
		var factor: float = 1.0 + wet_mult * grid.wetness[i] + temp_mult * (ambient - 0.5)
		grid.nutrition[i] = maxf(0.0, grid.nutrition[i] - rate * factor * elapsed / day)
		if grid.nutrition[i] < toxicity_threshold:
			grid.toxicity[i] = minf(1.0, grid.toxicity[i] + toxicity_rate * elapsed / day)
		grid.age[i] += elapsed
		grid.mark_dirty_cell(i % grid.width, i / grid.width)
