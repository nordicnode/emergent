class_name SimSafety
extends RefCounted

## Safety and flight, in one place.
##
## The need, the remembered-threat scan, the flee bout counter and its throttled
## log all live here. The brain still scores the flee candidate, but this unit
## owns what the need does each tick and what a chosen flee executes.

const StoreRef := preload("res://sim/creature_store.gd")
const GenomeRef := preload("res://sim/genome.gd")

var flee_starts := 0
var _last_log_day := PackedFloat32Array()
var _log_birth := PackedFloat32Array()

var _threat_decay := 10.0
var _exposure := 0.15
var _passive := 0.30
var _rest_recovery := 1.8
var _notice := 12.0
var _opinion_floor := 0.0
var _log_below := 0.35
var _log_gap := 0.05
var _flee_exit := 9.0
var _flee_distance := 8.0
var _flee_speed := 1.4


## The parameter register is loaded once at startup; cache the values this unit
## reads every tick so the need does not repeat dictionary lookups per creature.
func _init(params: SimParams) -> void:
	_threat_decay = params.f("safety", "threat_decay_per_day", 10.0)
	_exposure = params.f("safety", "exposure_decay_per_day", 0.15)
	_passive = params.f("safety", "passive_recovery_per_day", 0.30)
	_rest_recovery = params.f("safety", "rest_recovery_per_day", 1.8)
	_notice = params.f("safety", "notice_radius_cells", 12.0)
	_opinion_floor = params.f("safety", "threat_opinion_threshold", 0.0)
	_log_below = params.f("safety", "log_below_safety", 0.35)
	_log_gap = params.f("safety", "log_min_gap_days", 0.05)
	_flee_exit = params.f("safety", "flee_exit_cells", 9.0)
	_flee_distance = params.f("safety", "flee_distance_cells", 8.0)
	_flee_speed = params.f("safety", "flee_speed_mult", 1.4)


func ensure(n: int) -> void:
	if _last_log_day.size() >= n:
		return
	var old := _last_log_day.size()
	_last_log_day.resize(n)
	_log_birth.resize(n)
	for k in range(old, n):
		_last_log_day[k] = -100.0
		_log_birth[k] = -1.0


## The day of this creature's last logged flee. A reused slot starts blank, so
## the previous occupant's throttle does not silence the new body.
func last_log_day(sim: Sim, id: int) -> float:
	ensure(sim.store.count)
	if _log_birth[id] != sim.store.birth_time[id]:
		_last_log_day[id] = -100.0
		_log_birth[id] = sim.store.birth_time[id]
	return _last_log_day[id]


## One tick of the safety need. It falls when a creature this one has come to
## dislike is close, and slowly when the position is exposed. Resting in a
## protected arrangement is the generic satisfier; fleeing and avoiding work by
## putting distance between the creature and the threat. The scan walks this
## creature's own remembered relationships (at most sixteen), not the
## neighbourhood: fear is about the enemy you remember, and it costs a handful
## of reads instead of a second spatial query every tick.
func decay(sim: Sim, i: int, step_dt: float, day_len: float, protection: float) -> void:
	if not sim.safety_enabled:
		return
	var threat := 0.0
	if sim.social_enabled and sim.opinion_enabled and _threat_decay > 0.0:
		var size_me: float = maxf(sim.store.body_value(i, GenomeRef.F_SIZE), 0.01)
		for k in sim.opinion.entry_count(i):
			var j: int = sim.opinion.other_at(i, k)
			if j < 0 or j >= sim.store.count or sim.store.alive[j] == 0:
				continue
			var value: float = sim.opinion.opinion_slot(sim.store, i, k, sim.day())
			if value >= _opinion_floor:
				continue
			var ddx: float = sim.store.px[j] - sim.store.px[i]
			var ddy: float = sim.store.py[j] - sim.store.py[i]
			var dist: float = sqrt(ddx * ddx + ddy * ddy)
			if dist > _notice:
				continue
			var proximity: float = 1.0 - clampf(dist / maxf(_notice, 0.5), 0.0, 1.0)
			var size_factor: float = clampf(sim.store.body_value(j, GenomeRef.F_SIZE) / size_me, 0.6, 1.6)
			threat = maxf(threat, (-value) * size_factor * (0.25 + 0.75 * proximity))
	var loss: float = _threat_decay * threat + _exposure * (1.0 - protection)
	var gain: float = 0.0
	if threat <= 0.001:
		gain += _passive
	if int(sim.store.verb[i]) == StoreRef.Verb.REST:
		gain += _rest_recovery * protection
	sim.store.safety_level[i] = clampf(sim.store.safety_level[i] + (gain - loss) * step_dt / day_len, 0.0, 1.0)


## A single injury shock, kept here so harm does not touch the safety column
## directly. With the need ablated, the injury still happens but does not move
## the frozen value.
func shock(sim: Sim, id: int, amount: float) -> void:
	if not sim.safety_enabled:
		return
	sim.store.safety_level[id] = maxf(0.0, sim.store.safety_level[id] - amount)


## Count a new flee bout and write its throttled causal line. The line names the
## threat, the safety level and the opinion that produced it; ordinary retreats
## are not news, and a flood of them would push deaths and births out of the
## ring.
func note_decision(sim: Sim, i: int, prev_verb: int, decision: SimBrain.Decision) -> void:
	if decision.verb != StoreRef.Verb.FLEE or prev_verb == StoreRef.Verb.FLEE:
		return
	flee_starts += 1
	var threat_id: int = int(decision.aim_creature)
	var now: float = sim.day()
	if sim.store.safety_level[i] < _log_below and now - last_log_day(sim, i) >= _log_gap and threat_id >= 0 and threat_id < sim.store.count and sim.store.alive[threat_id] == 1:
		var threat_opinion: float = sim.opinion.opinion(sim.store, i, threat_id, now) if sim.social_enabled else 0.0
		_last_log_day[i] = now
		sim.log.push(
			sim.time,
			"safety",
			"Creature %d fled %d — safety %d%%, opinion %+.2f." % [
				i, threat_id, int(round(sim.store.safety_level[i] * 100.0)), threat_opinion
			],
			i
		)


## What this creature currently treats as a threat, for the inspector. It reads
## the same opinion, distance and body terms the need and the brain read, so the
## panel cannot tell a different story from the simulation.
func nearest_threat(sim: Sim, id: int) -> Dictionary:
	if not sim.safety_enabled or not sim.social_enabled or not sim.opinion_enabled:
		return {}
	if id < 0 or id >= sim.store.count or sim.store.alive[id] == 0:
		return {}
	var best := {}
	var best_strength: float = 0.0
	var size_me: float = maxf(sim.store.body_value(id, GenomeRef.F_SIZE), 0.01)
	for k in sim.opinion.entry_count(id):
		var j: int = sim.opinion.other_at(id, k)
		if j < 0 or j >= sim.store.count or sim.store.alive[j] == 0:
			continue
		var value: float = sim.opinion.opinion_slot(sim.store, id, k, sim.day())
		if value >= _opinion_floor:
			continue
		var dx: float = sim.store.px[j] - sim.store.px[id]
		var dy: float = sim.store.py[j] - sim.store.py[id]
		var dist: float = sqrt(dx * dx + dy * dy)
		if dist > _notice:
			continue
		var proximity: float = 1.0 - clampf(dist / maxf(_notice, 0.5), 0.0, 1.0)
		var size_factor: float = clampf(sim.store.body_value(j, GenomeRef.F_SIZE) / size_me, 0.6, 1.6)
		var strength: float = (-value) * size_factor * (0.25 + 0.75 * proximity)
		if strength > best_strength:
			best_strength = strength
			best = {"other": j, "opinion": value, "distance": dist, "strength": strength}
	return best


## Run from the remembered threat. Flee holds a retreat point away from it and
## pays a speed multiplier for the burst; it ends when the threat is gone or the
## gap is wide enough. The aim is refreshed every tick so the inspector's line
## shows where the creature is actually going, not the spot it first chose.
func do_flee(sim: Sim, i: int, step_dt: float, speed_cells: float) -> void:
	var j: int = int(sim.store.aim_creature[i])
	if j < 0 or j >= sim.store.count or sim.store.alive[j] == 0:
		sim.store.commitment[i] = 0.0
		sim.store.aim_creature[i] = -1
		return
	var dx: float = sim.store.px[i] - sim.store.px[j]
	var dy: float = sim.store.py[i] - sim.store.py[j]
	var dist: float = sqrt(dx * dx + dy * dy)
	if dist >= _flee_exit:
		sim.store.commitment[i] = 0.0
		return
	if dist < 0.0001:
		dx = 1.0
		dy = 0.0
		dist = 1.0
	var tx: float = clampf(sim.store.px[i] + dx / dist * _flee_distance, 1.0, float(sim.grid.width - 2))
	var ty: float = clampf(sim.store.py[i] + dy / dist * _flee_distance, 1.0, float(sim.grid.height - 2))
	sim.store.aim_x[i] = tx
	sim.store.aim_y[i] = ty
	sim.walk_toward(i, tx, ty, step_dt, speed_cells * _flee_speed)
