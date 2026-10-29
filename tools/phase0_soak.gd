extends SceneTree

## Soak harness. Ten seeds, no player input, a fixed simulated window, material
## counts and per-seed mean/peak step times. The plan's full soak (10 seeds x
## 30 days) is a Phase 2 gate; this is the same harness at a shorter length.
##
##   godot --headless --path . --script res://tools/phase0_soak.gd -- --days=1.25
##   godot --headless --path . --script res://tools/phase0_soak.gd -- --days=3 --seeds=3
##   godot --headless --path . --script res://tools/phase0_soak.gd -- --days=3 --seeds=3 --no-memory
##   godot --headless --path . --script res://tools/phase0_soak.gd -- --days=3 --seeds=3 --no-search
##   godot --headless --path . --script res://tools/phase0_soak.gd -- --days=3 --seeds=3 --no-social
##   godot --headless --path . --script res://tools/phase0_soak.gd -- --days=3 --seeds=3 --no-carry
##   godot --headless --path . --script res://tools/phase0_soak.gd -- --days=3 --seeds=3 --no-safety
##   godot --headless --path . --script res://tools/phase0_soak.gd -- --days=5 --seed=202

const ParamsRef := preload("res://sim/params.gd")
const SimRef := preload("res://sim/sim.gd")
const StoreRef := preload("res://sim/creature_store.gd")

const SEEDS := [101, 202, 303, 404, 505, 606, 707, 808, 909, 1010]
const DAYS := 1.25

var _params = null


func _initialize() -> void:
	_params = ParamsRef.load_default()
	var days := _days_from_cmdline(DAYS)
	var seeds := _seeds_from_cmdline()
	var memory_off := _no_memory_from_cmdline()
	var social_on := not _flag_from_cmdline("--no-social")
	var carry_on := not _flag_from_cmdline("--no-carry")
	var safety_on := not _flag_from_cmdline("--no-safety")
	if _flag_from_cmdline("--no-search"):
		# Ablation: the search candidates are gated by thresholds, so raising
		# them above 1.0 disables the behaviour without a second code path.
		(_params.data["brain"] as Dictionary)["search_food_threshold"] = 10.0
		(_params.data["brain"] as Dictionary)["search_water_threshold"] = 10.0
	var search_on := not _flag_from_cmdline("--no-search")
	print("=== Soak: %d seeds x %.2f simulated days, no player input, memory %s, search %s, social %s, carry %s, safety %s ===" % [seeds.size(), days, "off" if memory_off else "on", "on" if search_on else "off", "on" if social_on else "off", "on" if carry_on else "off", "on" if safety_on else "off"])
	print("hardware: %s / %s" % [OS.get_name(), OS.get_processor_name()])
	print("")
	print("seed  alive  born  gen  deaths  starved  dehy  pois  aged  child  adult  old  recall  places  lessons  food  water  energy  social  safety  rivals  flee  mean_ms  peak_ms")

	var totals := {"alive": 0, "deaths": 0, "min_alive": 999, "max_alive": 0}
	var step_ms_total := 0.0

	for seed_value in seeds:
		var sim = SimRef.new(_params, seed_value)
		sim.memory_enabled = not memory_off
		sim.social_enabled = social_on
		sim.carry_enabled = carry_on
		sim.safety_enabled = safety_on
		sim.generate_world()
		sim.spawn_founders()
		var seconds: float = days * float(sim.day_seconds)
		var steps := int(seconds / sim.dt)
		var population_curve: Array = []
		var sample_every := maxi(1, int(steps / 8))
		for s in steps:
			sim.step(sim.dt)
			if s % sample_every == 0:
				population_curve.append(sim.alive_count())
		var m: Dictionary = sim.metrics()
		var mix: Dictionary = m["action_mix"]
		var alive := int(m["alive"])
		totals["alive"] = int(totals["alive"]) + alive
		totals["deaths"] = int(totals["deaths"]) + int(m["deaths"])
		totals["min_alive"] = mini(int(totals["min_alive"]), alive)
		totals["max_alive"] = maxi(int(totals["max_alive"]), alive)
		step_ms_total += float(m["mean_step_ms"])

		print("%5d  %5d  %4d  %3d  %6d  %7d  %4d  %4d  %4d  %5d  %5d  %3d  %6d  %6.1f  %7d  %4.2f  %5.2f  %6.2f  %6.2f  %6.2f  %6d  %4d  %6.2f  %7.2f" % [
			seed_value,
			alive,
			int(m["births"]),
			int(m["max_generation"]),
			int(m["deaths"]),
			int(m["starved"]),
			int(m["dehydrated"]),
			int(m["poisoned"]),
			int(m["aged"]),
			int(m["children"]),
			int(m["adults"]),
			int(m["old"]),
			int(m["recall_actions"]),
			float(m["memory_places"]),
			int(m["memory_learned"]),
			float(m["mean_food"]),
			float(m["mean_water"]),
			float(m["mean_energy"]),
			float(m["mean_social"]),
			float(m["mean_safety"]),
			int(m["rival_bonds"]),
			int(m["flee_starts"]),
			float(m["mean_step_ms"]),
			float(m["max_step_ms"]),
		])
		# Socialise and avoid are brief acts in a world of mostly idle ticks, so a
		# percentage rounds to zero and hides that they happened at all. Count
		# exchanges and avoidance decisions instead.
		print("       action mix: wander %d%%, move_to %d%%, seek %d%%, eat %d%%, drink %d%%, rest %d%%, approach %d%%, mate %d%%, pickup %d%%, pile %d%%, flee %d%%; socialise %d exchanges, avoid %d decisions" % [
			int(round(float(mix["wander"]) * 100.0)),
			int(round(float(mix.get("move_to", 0.0)) * 100.0)),
			int(round(float(mix["seek"]) * 100.0)),
			int(round(float(mix["eat"]) * 100.0)),
			int(round(float(mix["drink"]) * 100.0)),
			int(round(float(mix["rest"]) * 100.0)),
			int(round(float(mix.get("approach", 0.0)) * 100.0)),
			int(round(float(mix.get("mate", 0.0)) * 100.0)),
			int(round(float(mix.get("pickup", 0.0)) * 100.0)),
			int(round(float(mix.get("pile", 0.0)) * 100.0)),
			int(round(float(mix.get("flee", 0.0)) * 100.0)),
			int(m["social_events"]),
			int(sim.action_counts[StoreRef.Verb.AVOID]),
		])
		print("       social: %d exchanges, %d food disputes, %d shares, %d harms (%d harm deaths), %d friend bonds, %d rival bonds, %d opinions" % [
			int(m["social_events"]), int(m["food_taken_events"]),
			int(m["share_events"]), int(m["harm_events"]), int(m["harmed"]),
			int(m["friend_bonds"]), int(m["rival_bonds"]), int(m["opinion_entries"]),
		])
		print("       carrying: %d carried, %d loads picked (%d food, %d sand), %d loads piled (%d food, %d sand), mean comfort %.2f" % [
			int(m["carried"]),
			int(m["loads_picked_food"]) + int(m["loads_picked_sand"]),
			int(m["loads_picked_food"]), int(m["loads_picked_sand"]),
			int(m["loads_piled_food"]) + int(m["loads_piled_sand"]),
			int(m["loads_piled_food"]), int(m["loads_piled_sand"]),
			float(m["mean_comfort"]),
		])
		print("       safety: mean %.2f, %d flee bouts, %d flee decisions" % [
			float(m["mean_safety"]), int(m["flee_starts"]), int(m["flee_actions"]),
		])
		# The log is a 256-entry ring: show how much of it the two new events
		# occupy, so a slice that logged every exchange would be visible here.
		var log_shares := 0
		var log_harms := 0
		for entry in sim.log.entries:
			if String(entry["kind"]) == "harm":
				log_harms += 1
			elif String(entry["kind"]) == "social" and String(entry["text"]).contains("shared ") and String(entry["text"]).contains(" food with "):
				log_shares += 1
		print("       event log: %d/%d lines kept (%d share, %d harm), %d written in total" % [
			sim.log.entries.size(), sim.log.CAPACITY, log_shares, log_harms, sim.log.total_written,
		])
		print("       population over time: %s" % str(population_curve))
		var mats: Dictionary = m["materials"]
		print("       materials: water %d, wet %d, mud %d, hard %d, food %d (rotten %d)" % [
			int(mats["water"]), int(mats["wet"]), int(mats["mud"]), int(mats["hard"]),
			int(mats["food"]), int(mats["rotten_food"]),
		])

	var n := float(seeds.size())
	print("")
	print("summary: mean alive %.1f, alive range %d..%d, total deaths %d, mean step %.2f ms" % [
		float(totals["alive"]) / n,
		int(totals["min_alive"]),
		int(totals["max_alive"]),
		int(totals["deaths"]),
		step_ms_total / n,
	])
	quit(0)


func _days_from_cmdline(fallback: float) -> float:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--days="):
			return float(arg.split("=")[1])
	return fallback


func _no_memory_from_cmdline() -> bool:
	return _flag_from_cmdline("--no-memory")


func _flag_from_cmdline(flag: String) -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == flag:
			return true
	return false


## A shorter run for iterating on a change; the release soak is all ten seeds.
func _seeds_from_cmdline() -> Array:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			return [int(arg.split("=")[1])]
		if arg.begins_with("--seeds="):
			var count := clampi(int(arg.split("=")[1]), 1, SEEDS.size())
			return SEEDS.slice(0, count)
	return SEEDS
