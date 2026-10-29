extends SceneTree

## Automated legibility walkthrough for the Phase 2 exit criterion.
##
##   godot --headless --path . --script res://tools/phase2_legibility.gd
##
## It follows one creature for five simulated minutes of real-time play
## (4500 ticks at 15 Hz), then prints the same evidence a player sees: the top
## three scores with their components, the creature's last memories, its
## strongest opinion with the events behind it, and any story line naming it.
## This checks that the interface has a causal answer. It is not a substitute
## for the plan's human playtest; only a new player can supply that.

const ParamsRef := preload("res://sim/params.gd")
const SimRef := preload("res://sim/sim.gd")
const StoreRef := preload("res://sim/creature_store.gd")
const MemoryRef := preload("res://sim/memory.gd")
const GridRef := preload("res://sim/grid.gd")


func _initialize() -> void:
	var params = ParamsRef.load_default()
	var sim = SimRef.new(params, 4242)
	sim.generate_world()
	sim.spawn_founders()
	# Let the founders stop mating at the spawn point. Watching the first second
	# of the world would explain two courtship choices, not a life.
	for _s in int(0.20 * sim.day_seconds / sim.dt):
		sim.step(sim.dt)
	var watched := -1
	var hungriest := 2.0
	for i in sim.store.count:
		if sim.store.alive[i] == 0:
			continue
		if float(sim.store.food_level[i]) < hungriest:
			hungriest = float(sim.store.food_level[i])
			watched = i
	if watched < 0:
		printerr("no founder to watch")
		quit(1)
		return
	sim.inspect_id = watched
	self._watched = watched
	self._sim = sim
	var transitions := 0
	var printed := 0
	var later_printed := false
	var previous := int(sim.store.verb[watched])
	var steps := int(5.0 * 60.0 * sim.tick_hz)
	print("Watching creature %d for %.0f real-time seconds (%d ticks, seed %d)." % [
		watched, 5.0 * 60.0, steps, sim.seed_used,
	])
	for s in steps:
		sim.step(sim.dt)
		if sim.store.alive[watched] == 0:
			print("\nCreature %d died after %.0f real-time seconds on day %.2f. Cause: %s." % [
				watched, float(s) * sim.dt, sim.day(), sim.store.death_name(int(sim.store.death_cause[watched])),
			])
			break
		var now := int(sim.store.verb[watched])
		if now != previous:
			transitions += 1
			var elapsed: float = float(s) * sim.dt
			# Two consecutive choices prove the panel explains a change; a third
			# late one is only sampled after two simulated minutes so the report
			# covers the whole five-minute watch instead of its opening seconds.
			if printed < 2 or (not later_printed and elapsed >= 120.0):
				print("\n--- decision %d: %s -> %s at %.0f s (day %.2f) ---" % [
					transitions, sim.store.verb_name(previous), sim.store.verb_name(now), elapsed, sim.day(),
				])
				_print_why(sim, watched, previous, now)
				printed += 1
				if elapsed >= 120.0:
					later_printed = true
			previous = now
	if sim.store.alive[watched] != 0:
		print("\nAfter five real-time minutes: %s, food %.2f, water %.2f, energy %.2f, health %.2f." % [
			sim.store.verb_name(int(sim.store.verb[watched])), float(sim.store.food_level[watched]),
			float(sim.store.water_level[watched]), float(sim.store.energy_level[watched]), float(sim.store.health[watched]),
		])
	print("\nAutomated walkthrough produced %d explained decisions." % printed)
	quit(0 if printed >= 2 else 1)


var _watched := -1
var _sim = null


func _print_why(sim, id: int, previous: int, now: int) -> void:
	var scores: Array = sim.last_inspection.duplicate()
	scores.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	print("  top scores at the choice:")
	for k in mini(3, scores.size()):
		var candidate: Dictionary = scores[k]
		var parts_text := ""
		for key in (candidate.get("parts", {}) as Dictionary).keys():
			if not parts_text.is_empty():
				parts_text += ", "
			parts_text += "%s %.2f" % [key, float(candidate["parts"][key])]
		print("    %-9s %.2f  (%s)" % [String(candidate["label"]), float(candidate["score"]), parts_text])
	var places := int(sim.memory.place_count(id))
	var episodes := int(sim.memory.episode_count(id))
	print("  memory: %d places, %d episodes; last:" % [places, episodes])
	for k in mini(episodes, 3):
		var ep: Dictionary = sim.memory.episode_at(id, episodes - 1 - k)
		print("    day %.2f %s (%s) need %.2f→%.2f stress %.2f" % [
			float(ep["day"]), String(sim.store.verb_name(int(ep["verb"]))),
			String(MemoryRef.CONTEXT_NAMES[clampi(int(ep["context"]), 0, MemoryRef.CONTEXT_NAMES.size() - 1)]),
			float(ep["before"]), float(ep["after"]), float(ep["stress"]),
		])
	var evidence: Dictionary = sim.story.inspector_evidence(sim, id)
	for op in evidence.get("opinions", []):
		print("  strongest opinion: creature %d %s %+.2f (%d events)" % [
			int(op["other"]), String(op["label"]), float(op["valence"]), int(op["events"]),
		])
		for event in op.get("chain", []):
			print("    %s day %.2f %+.2f" % [String(event["reason"]), float(event["day"]), float(event["delta"])])
	for line in sim.log.recent(12):
		var text := String(line["text"])
		if text.contains("Creature %d" % id) or int(line.get("creature", -1)) == id:
			print("  log: %s" % text)
			break
	if int(sim.store.carry_amount[id]) > 0.001:
		print("  carrying %.2f %s" % [
			float(sim.store.carry_amount[id]),
			String(GridRef.MATERIAL_NAMES[int(sim.store.carry_material[id])]),
		])
