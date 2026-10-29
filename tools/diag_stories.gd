extends SceneTree

## Temporary: run only the Phase 1 stories, which is where a material or score
## change shows up first. Prints the same counters the suite prints, and with
## `--dump=rivalry` prints the whole opinion store at the end of the rivalry run.
##   godot --headless --path . --script res://tools/diag_stories.gd

const ParamsRef := preload("res://sim/params.gd")
const SimRef := preload("res://sim/sim.gd")
const HarnessRef := preload("res://sim/tests/story_harness.gd")
const StoriesRef := preload("res://sim/tests/phase1_stories.gd")


func _initialize() -> void:
	var params = ParamsRef.load_default()
	var dump := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dump="):
			dump = arg.substr("--dump=".length())
		elif arg.begins_with("--param="):
			# section.key=value, one run only, like phase2_soak.gd.
			var spec := arg.substr("--param=".length())
			var equals := spec.find("=")
			var path := spec.substr(0, equals).split(".")
			if equals > 0 and path.size() == 2:
				var value := spec.substr(equals + 1)
				(params.data as Dictionary)[path[0]][path[1]] = float(value) if value.is_valid_float() else value
	if dump == "rivalry":
		_dump_rivalry(params)
		quit(0)
		return
	var stories = StoriesRef.new()
	stories.set_params(params)
	var result: Array = stories.run_all()
	quit(1 if int(result[1]) > 0 else 0)


func _dump_rivalry(params) -> void:
	var stories = StoriesRef.new()
	stories.set_params(params)
	var base: Dictionary = stories._rivalry_run()
	var window := 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--days="):
			window = float(arg.substr("--days=".length()))
	if window > 0.0:
		var rival_params = stories._rivalry_params()
		var probe = SimRef.new(rival_params, 3103)
		base = HarnessRef.run(rival_params, stories._rivalry_setup, int(window * float(probe.day_seconds) / probe.dt), "", stories._rivalry_feed)
	var sim = base["sim"]
	print("day %.3f alive %d disputes %d flee %d avoid %d" % [
		sim.day(), sim.alive_count(), int(sim.food_taken_events),
		int(sim.action_counts[2]), int(sim.action_counts[3]),
	])
	for i in sim.store.count:
		if int(sim.store.alive[i]) == 0:
			continue
		print("creature %d at (%.2f, %.2f) food %.2f water %.2f health %.2f stage %d age %.2f" % [
			i, float(sim.store.px[i]), float(sim.store.py[i]), float(sim.store.food_level[i]),
			float(sim.store.water_level[i]), float(sim.store.health[i]), int(sim.store.stage[i]),
			float(sim.store.age_days[i]),
		])
		for k in sim.opinion.entry_count(i):
			var record: Dictionary = sim.opinion.entry_at(i, k)
			var other := int(record["other"])
			print("   -> %d  value %.3f  events %d  label %s" % [
				other, sim.opinion.opinion(sim.store, i, other, sim.day()), int(record["events"]),
				sim.opinion.label_for(sim.opinion.opinion(sim.store, i, other, sim.day()), int(record["events"])),
			])
