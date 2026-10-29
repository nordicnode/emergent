extends SceneTree

## Phase 2 soak suite: ten seeds, thirty simulated days, no player input.
##
##   godot --headless --path . --script res://tools/phase2_soak.gd
##   godot --headless --path . --script res://tools/phase2_soak.gd -- --days=30 --seeds=10
##   godot --headless --path . --script res://tools/phase2_soak.gd -- --seed=101 --out=/tmp/soak-101.json
##   godot --headless --path . --script res://tools/phase2_soak.gd -- --merge-dir=/tmp/soak --out=docs/phase2-soak.json
##
## A knob can be swept without editing the live register, so an A/B pair uses
## the same file and the register keeps the values that shipped:
##   godot ... phase2_soak.gd -- --days=10 --seed=101 --param=repro.cooldown_days=1.5
##
## The merged report is the gate the plan asks for: population must oscillate or
## stabilise without collapsing on every seed or exploding, no single cause of
## death may exceed 80%, and genetic diversity must not collapse to a point.
## A single-seed run is provided so the ten seeds can be run in parallel.

const ParamsRef := preload("res://sim/params.gd")
const SimRef := preload("res://sim/sim.gd")

const SEEDS := [101, 202, 303, 404, 505, 606, 707, 808, 909, 1010]
const DAYS := 30.0
const SAMPLE_DAYS := 0.5
const COLLAPSE_SHARE := 0.30
const MAX_PEAK := 120
const DEATH_CAUSE_CAP := 0.80
const MIN_DIVERSITY := 0.03


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var merge_dir := _arg(args, "--merge-dir=", "")
	if not merge_dir.is_empty():
		_merge(merge_dir, _arg(args, "--out=", ""))
		quit(0)
		return

	var days := float(_arg(args, "--days=", str(DAYS)))
	var seeds := _seeds(args)
	var out_path := _arg(args, "--out=", "")
	var sample_days := maxf(float(_arg(args, "--sample-days=", str(SAMPLE_DAYS))), 0.05)
	var params = ParamsRef.load_default()
	_apply_overrides(params, args)
	print("=== Phase 2 soak: %d seeds x %.2f simulated days, no player input ===" % [seeds.size(), days])
	print("hardware: %s / %s" % [OS.get_name(), OS.get_processor_name()])
	var overrides := _override_list(args)
	if not overrides.is_empty():
		print("overrides: %s" % ", ".join(overrides))
	print("")

	var results: Array = []
	for seed_value in seeds:
		var result := _run_seed(params, int(seed_value), days, sample_days)
		results.append(result)
		_print_seed(result)
		if not out_path.is_empty() and seeds.size() == 1:
			_write_json(out_path, result)
	if not out_path.is_empty() and seeds.size() > 1:
		_write_json(out_path, {"days": days, "results": results})
	if seeds.size() > 1:
		_print_summary(results, days)
	quit(0)


func _run_seed(params, seed_value: int, days: float, sample_days: float) -> Dictionary:
	var sim = SimRef.new(params, seed_value)
	sim.generate_world()
	sim.spawn_founders()
	var steps := int(round(days * sim.day_seconds / sim.dt))
	var sample_every := maxi(1, int(round(sample_days * sim.day_seconds / sim.dt)))
	var population: Array = []
	var diversity: Array = []
	var water: Array = []
	var food: Array = []
	var peak_alive := 0
	var peak_day := 0.0
	var day_every := maxi(1, int(round(sim.day_seconds / sim.dt)))
	for s in steps:
		sim.step(sim.dt)
		if (s + 1) % day_every == 0:
			# A long gate is unusable if it reports only at the end. One line per
			# simulated day lets a failed seed be read while the others run.
			var live: Dictionary = sim.metrics()
			print("  seed %d day %2d  pop %3d  mean food %.2f water %.2f energy %.2f  deaths %3d  water cells %4d  food cells %4d" % [
				seed_value, (s + 1) / day_every, sim.alive_count(), float(live["mean_food"]), float(live["mean_water"]),
				float(live["mean_energy"]), int(live["deaths"]), sim.grid.water_cell_count(), sim.grid.food_cell_count(),
			])
		if (s + 1) % sample_every == 0 or s == steps - 1:
			var alive := sim.alive_count()
			population.append(alive)
			diversity.append(sim.genetic_diversity() if alive >= 2 else 0.0)
			water.append(sim.grid.water_cell_count())
			food.append(sim.grid.food_cell_count())
			if alive > peak_alive:
				peak_alive = alive
				peak_day = sim.day()
	var m: Dictionary = sim.metrics()
	var summary: Dictionary = sim.history.summary(sim)
	# Hysteresis, expressed per creature-minute so seeds with different
	# populations are comparable: one vote per creature, not per tick.
	var mean_alive := 0.0
	for sample in population:
		mean_alive += float(sample)
	mean_alive /= float(maxi(population.size(), 1))
	var creature_minutes: float = mean_alive * days * float(sim.day_seconds) / 60.0
	var verb_changes := int(m["verb_changes"])
	var causes := {
		"starvation": int(m["starved"]),
		"dehydration": int(m["dehydrated"]),
		"starvation_and_dehydration": int(m["starved_and_dehydrated"]),
		"poisoning": int(m["poisoned"]),
		"old_age": int(m["aged"]),
		"harm": int(m["harmed"]),
	}
	var final_diversity := float(summary["diversity"])
	var firsts: Array = []
	for entry in sim.detectors.firsts:
		firsts.append({
			"kind": String(entry["kind"]),
			"day": float(entry["day"]),
			"text": String(entry["text"]),
		})
	var birth_log: Array = []
	for entry in sim.log.entries:
		if String(entry["kind"]) == "birth":
			birth_log.append({"day": float(entry["time"]) / maxf(sim.day_seconds, 0.001), "text": String(entry["text"])})
	return {
		"seed": seed_value,
		"days": days,
		"alive": int(m["alive"]),
		"births": int(m["births"]),
		"deaths": int(m["deaths"]),
		"max_generation": maxi(int(m["max_generation"]), int(summary["max_generation"])),
		"children": int(m["children"]),
		"adults": int(m["adults"]),
		"old": int(m["old"]),
		"peak_alive": peak_alive,
		"peak_day": peak_day,
		"population": population,
		"diversity_curve": diversity,
		"water_curve": water,
		"food_curve": food,
		"final_diversity": final_diversity,
		"lineages": int(summary["lineages"]),
		"living_lineages": int(summary["living_lineages"]),
		"extinct_lineages": int(summary["extinct_lineages"]),
		"causes": causes,
		"action_mix": m["action_mix"],
		"mean_food": float(m["mean_food"]),
		"mean_water": float(m["mean_water"]),
		"mean_energy": float(m["mean_energy"]),
		"verb_changes": verb_changes,
		"verb_changes_per_creature_minute": float(verb_changes) / maxf(creature_minutes, 0.001),
		"mean_step_ms": float(m["mean_step_ms"]),
		"max_step_ms": float(m["max_step_ms"]),
		"decide_ms": float(m["decide_ms"]),
		"firsts": firsts,
		"birth_log": birth_log,
		"swings": _swings(population),
	}


func _swings(curve: Array) -> Dictionary:
	var peaks := 0
	var troughs := 0
	var max_rise := 0
	var max_fall := 0
	for i in range(1, curve.size() - 1):
		var v := int(curve[i])
		var prev := int(curve[i - 1])
		var next := int(curve[i + 1])
		if v >= prev and v > next:
			peaks += 1
		if v <= prev and v < next:
			troughs += 1
		max_rise = maxi(max_rise, v - prev)
		max_fall = maxi(max_fall, prev - v)
	var lo := 999999
	var hi := 0
	var total := 0.0
	for v in curve:
		lo = mini(lo, int(v))
		hi = maxi(hi, int(v))
		total += float(v)
	var mean := total / float(maxi(curve.size(), 1))
	var variance := 0.0
	for v in curve:
		var d := float(v) - mean
		variance += d * d
	var cv := sqrt(variance / float(maxi(curve.size(), 1))) / maxf(mean, 0.001)
	return {"peaks": peaks, "troughs": troughs, "max_rise": max_rise, "max_fall": max_fall, "range": hi - lo, "cv": cv}


func _print_seed(r: Dictionary) -> void:
	var causes: Dictionary = r["causes"]
	print("seed %d: alive %d / peak %d @ day %.2f / births %d / deaths %d / gen %d / diversity %.3f" % [
		int(r["seed"]), int(r["alive"]), int(r["peak_alive"]), float(r["peak_day"]),
		int(r["births"]), int(r["deaths"]), int(r["max_generation"]), float(r["final_diversity"]),
	])
	print("  causes: starved %d, dehydrated %d, both %d, poison %d, old age %d, harm %d" % [
		int(causes["starvation"]), int(causes["dehydration"]), int(causes["starvation_and_dehydration"]),
		int(causes["poisoning"]), int(causes["old_age"]), int(causes["harm"]),
	])
	print("  lineages %d (%d living, %d extinct) · step mean %.2f ms, max %.2f ms" % [
		int(r["lineages"]), int(r["living_lineages"]), int(r["extinct_lineages"]),
		float(r["mean_step_ms"]), float(r["max_step_ms"]),
	])
	print("  verb changes %d (%.2f per creature-minute)" % [
		int(r.get("verb_changes", 0)), float(r.get("verb_changes_per_creature_minute", 0.0)),
	])
	print("  population: %s" % str(r["population"]))
	print("  firsts: %d" % (r["firsts"] as Array).size())


func _print_summary(results: Array, days: float) -> void:
	var n := results.size()
	var alive := 0
	var extinct := 0
	var exploded := 0
	var max_peak := 0
	var total_deaths := 0
	var cause_totals := {}
	var diversity_sum := 0.0
	var diversity_n := 0
	var swings := 0
	var step_sum := 0.0
	for r in results:
		if int(r["alive"]) > 0:
			alive += 1
		else:
			extinct += 1
		max_peak = maxi(max_peak, int(r["peak_alive"]))
		if int(r["peak_alive"]) > MAX_PEAK:
			exploded += 1
		total_deaths += int(r["deaths"])
		for key in (r["causes"] as Dictionary):
			cause_totals[key] = int(cause_totals.get(key, 0)) + int((r["causes"] as Dictionary)[key])
		if int(r["alive"]) >= 2:
			diversity_sum += float(r["final_diversity"])
			diversity_n += 1
		var sw: Dictionary = r["swings"]
		if int(sw["peaks"]) >= 1 and int(sw["range"]) >= 3:
			swings += 1
		step_sum += float(r["mean_step_ms"])

	var mean_diversity := diversity_sum / float(maxi(diversity_n, 1))
	var worst_cause := ""
	var worst_share := 0.0
	for key in cause_totals:
		var share := float(cause_totals[key]) / float(maxi(total_deaths, 1))
		if share > worst_share:
			worst_share = share
			worst_cause = String(key)

	print("")
	print("--- Phase 2 soak summary (%.1f simulated days, %d seeds) ---" % [days, n])
	print("population: %d/%d seeds alive at end, %d extinct, peak %d, exploded %d" % [alive, n, extinct, max_peak, exploded])
	print("oscillation: %d/%d seeds have at least one peak and a population range of >= 3" % [swings, n])
	print("cause of death: %d total, largest %s at %.0f%% (cap %.0f%%)" % [
		total_deaths, worst_cause, worst_share * 100.0, DEATH_CAUSE_CAP * 100.0,
	])
	print("diversity: mean final %.3f (floor %.3f, %d seeds measured)" % [mean_diversity, MIN_DIVERSITY, diversity_n])
	print("step: mean %.2f ms across seeds" % (step_sum / float(maxi(n, 1))))

	var population_ok := extinct <= int(ceil(float(n) * COLLAPSE_SHARE)) and alive >= int(ceil(float(n) * 0.70))
	var explosion_ok := exploded == 0
	var cause_ok := total_deaths == 0 or worst_share <= DEATH_CAUSE_CAP
	var diversity_ok := diversity_n == 0 or mean_diversity >= MIN_DIVERSITY
	var oscillation_ok := swings >= int(ceil(float(n) * 0.60))
	print("")
	print("PASS population band: %s" % ("yes" if population_ok else "no"))
	print("PASS no explosion: %s" % ("yes" if explosion_ok else "no"))
	print("PASS cause-of-death band: %s" % ("yes" if cause_ok else "no"))
	print("PASS diversity band: %s" % ("yes" if diversity_ok else "no"))
	print("PASS oscillation: %s" % ("yes" if oscillation_ok else "no"))
	print("PHASE 2 SOAK: %s" % ("PASS" if population_ok and explosion_ok and cause_ok and diversity_ok and oscillation_ok else "FAIL"))


func _merge(dir_path: String, out_path: String) -> void:
	var results: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		printerr("cannot open merge directory: %s" % dir_path)
		return
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var f := FileAccess.open(dir_path.path_join(file), FileAccess.READ)
		if f == null:
			continue
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			if (parsed as Dictionary).has("results"):
				for row in (parsed as Dictionary)["results"]:
					results.append(row)
			elif (parsed as Dictionary).has("seed"):
				results.append(parsed)
	results.sort_custom(func(a, b): return int(a["seed"]) < int(b["seed"]))
	if results.is_empty():
		printerr("no seed results in %s" % dir_path)
		return
	for r in results:
		_print_seed(r)
	_print_summary(results, float(results[0].get("days", DAYS)))
	if not out_path.is_empty():
		_write_json(out_path, {"days": float(results[0].get("days", DAYS)), "results": results})


func _write_json(path: String, data) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("cannot write %s" % path)
		return
	f.store_string(JSON.stringify(data, "\t"))
	print("wrote %s" % path)


func _seeds(args: PackedStringArray) -> Array:
	for arg in args:
		if arg.begins_with("--seed="):
			return [int(arg.split("=")[1])]
	for arg in args:
		if arg.begins_with("--seeds="):
			var count := clampi(int(arg.split("=")[1]), 1, SEEDS.size())
			return SEEDS.slice(0, count)
	return SEEDS


## Saves a knob for one run only: --param=section.key=value, repeatable.
## The register stays the record of what shipped; an experiment is a flag away.
func _apply_overrides(params, args: PackedStringArray) -> void:
	for entry in _override_list(args):
		var spec: String = entry
		var equals := spec.find("=")
		var path := spec.substr(0, equals).split(".")
		if equals <= 0 or path.size() != 2:
			printerr("bad --param (expected section.key=value): %s" % spec)
			continue
		var value := spec.substr(equals + 1)
		if not (params.data as Dictionary).has(path[0]):
			(params.data as Dictionary)[path[0]] = {}
		var section: Dictionary = params.data[path[0]]
		section[path[1]] = float(value) if value.is_valid_float() else value


func _override_list(args: PackedStringArray) -> Array:
	var out: Array = []
	for arg in args:
		if arg.begins_with("--param="):
			out.append(arg.substr("--param=".length()))
	return out


func _arg(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for arg in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback
