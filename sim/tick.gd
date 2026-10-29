class_name SimTick
extends RefCounted

## The simulation tick pipeline, in one place.
##
## Fixed order:
##   1. advance world time by a fixed step
##   2. material step: flow every material tick, then wetness, drying,
##      compaction, hardening, softening and rot on the slower property cadence
##   3. recompute gradient fields (Phase 3)
##   4. ensure learned stores, decay needs (including safety from remembered
##      threats and exposure), apply starvation/dehydration damage, rebuild the
##      neighbour index
##   5. decide: score every generic verb for every creature
##   6. execute movement and actions, queue events
##   7. apply queued events (deaths)
##   8-9. learning and first-time detectors
##   10. update interface data; the renderer reads the arrays
##
## The unit also owns the material cadence and the phase timing counters, so a
## regression names its own cause without Sim carrying a second set of loose
## timing fields.

const MaterialsRef := preload("res://sim/materials.gd")

var material_hz := 5.0
var material_every := 3
var material_steps := 0
var _material_wait := 0

var last_material_ms := 0.0
var last_needs_ms := 0.0
var last_decide_ms := 0.0
var last_execute_ms := 0.0
var last_material_stats := {}
var last_step_ms := 0.0
var max_step_ms := 0.0
var total_step_ms := 0.0
var steps_taken := 0


func _init(params: SimParams, tick_hz: float) -> void:
	material_hz = clampf(params.f("materials", "material_tick_hz", 5.0), 0.5, tick_hz)
	material_every = maxi(1, int(round(tick_hz / material_hz)))


func step(sim: Sim, step_dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	sim.time += step_dt
	steps_taken += 1
	sim._pending_deaths.clear()
	sim._pending_cause.clear()

	last_material_stats = {}
	var phase := Time.get_ticks_usec()
	_material_wait += 1
	if _material_wait >= material_every:
		# Elapsed time is scaled by how many sim ticks a pass skipped, so a
		# slower cadence changes cost and responsiveness, never rates.
		var mat_dt := step_dt * float(_material_wait)
		var stats: Dictionary = MaterialsRef.flow(sim.grid, sim.params, material_steps, mat_dt)
		stats.merge(MaterialsRef.properties(sim.grid, sim.params, material_steps, mat_dt, sim.hardening_enabled))
		material_steps += 1
		_material_wait = 0
		last_material_stats = stats
	last_material_ms = float(Time.get_ticks_usec() - phase) / 1000.0

	phase = Time.get_ticks_usec()
	# Stores are ensured before needs because a creature born last tick needs
	# opinion slots for safety to read, and the neighbour index is rebuilt after
	# needs as the decision pass's input.
	sim.memory.ensure(sim.store.count)
	sim.opinion.ensure(sim.store.count)
	sim.share.ensure(sim.store.count)
	sim.safety.ensure(sim.store.count)
	sim._decay_needs(step_dt)
	sim._delayed_learning()
	sim.neighbors.rebuild(sim.store)
	last_needs_ms = float(Time.get_ticks_usec() - phase) / 1000.0

	phase = Time.get_ticks_usec()
	sim._decide_all()
	last_decide_ms = float(Time.get_ticks_usec() - phase) / 1000.0

	phase = Time.get_ticks_usec()
	sim._execute_all(step_dt)
	sim._apply_deaths()
	# Causal evidence is read after the world and the actions have settled, so a
	# line never describes a state the tick has not committed yet.
	sim.story.after_tick(sim)
	# Phase 2 detectors observe the committed tick: a first-time pattern can be
	# named only after the world and the story evidence agree.
	sim.detectors.after_tick(sim)
	# Half-day population samples keep the lineage series readable after ids
	# have been reused; it is observation, not a creature input.
	sim.history.after_tick(sim)
	last_execute_ms = float(Time.get_ticks_usec() - phase) / 1000.0

	last_step_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	total_step_ms += last_step_ms
	max_step_ms = maxf(max_step_ms, last_step_ms)
