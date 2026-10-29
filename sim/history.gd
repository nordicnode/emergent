class_name SimHistory
extends RefCounted

## Persistent lineage and diversity records for the Phase 2 history views and
## the soak suite. Creature ids are reused, so a lineage summary cannot be
## rebuilt from the live store after a death: this unit records births and
## deaths when they happen, and the panel reads those records afterwards.
##
## It is legibility data. No creature reads it, and it never changes a decision.

const GenomeRef := preload("res://sim/genome.gd")
const StoreRef := preload("res://sim/creature_store.gd")

## One population sample per half-day, kept with each lineage. The panel shows
## the series the plan asks for (population over time) without pretending to
## reconstruct it from live ids after those ids have been reused.
const SERIES_CAP := 60
const SAMPLE_DAYS := 0.5

var lineages := {}
var total_births := 0
var total_deaths := 0
var _next_sample_day := 0.0


func note_birth(sim: Sim, id: int, mother_id: int, father_id: int) -> void:
	if id < 0 or id >= sim.store.count:
		return
	var founder := int(sim.store.founder[id])
	var record := _record(founder, sim.day())
	record["born"] = int(record["born"]) + 1
	record["max_generation"] = maxi(int(record["max_generation"]), int(sim.store.generation[id]))
	record["last_birth_day"] = sim.day()
	if int(record["born"]) == 1:
		record["first_day"] = sim.day()
	if mother_id < 0:
		# A founder's genome is the drift reference for its whole line.
		record["founder_genome"] = sim.store.genome_at(id)
		record["founder_place"] = Vector2(sim.store.px[id], sim.store.py[id])
	total_births += 1


func note_death(sim: Sim, id: int, cause: int) -> void:
	if id < 0 or id >= sim.store.count:
		return
	var founder := int(sim.store.founder[id])
	var record := _record(founder, sim.day())
	record["died"] = int(record["died"]) + 1
	record["last_day"] = sim.day()
	record["last_x"] = sim.store.px[id]
	record["last_y"] = sim.store.py[id]
	record["last_generation"] = maxi(int(record["last_generation"]), int(sim.store.generation[id]))
	var causes: Dictionary = record["causes"]
	var cause_name := String(sim.store.death_name(cause))
	causes[cause_name] = int(causes.get(cause_name, 0)) + 1
	record["causes"] = causes
	total_deaths += 1


func _record(founder: int, at_day: float) -> Dictionary:
	if not lineages.has(founder):
		lineages[founder] = {
			"founder": founder,
			"first_day": at_day,
			"last_birth_day": at_day,
			"last_day": at_day,
			"born": 0,
			"died": 0,
			"max_generation": 0,
			"last_generation": 0,
			"last_x": 0.0,
			"last_y": 0.0,
			"founder_genome": PackedFloat32Array(),
			"founder_place": Vector2.ZERO,
			"series": [],
			"causes": {},
		}
	return lineages[founder]


## A half-day population sample for every lineage, living or extinct. The
## series is bounded; it is a readable recent history, not a full archive.
func after_tick(sim: Sim) -> void:
	var d := sim.day()
	if d < _next_sample_day:
		return
	_next_sample_day = d + SAMPLE_DAYS
	sample(sim)


func sample(sim: Sim) -> void:
	var counts := {}
	for i in sim.store.count:
		if sim.store.alive[i] == 0:
			continue
		var founder := int(sim.store.founder[i])
		counts[founder] = int(counts.get(founder, 0)) + 1
	for founder in lineages.keys():
		var record: Dictionary = lineages[founder]
		var series: Array = record["series"]
		series.append(int(counts.get(founder, 0)))
		while series.size() > SERIES_CAP:
			series.pop_front()


## Mean pairwise genetic distance among the living. Zero or one living creature
## has no pair to measure, so the caller must treat a tiny sample as unknown
## rather than as a collapsed population.
func diversity(sim: Sim) -> float:
	var ids: Array = []
	for i in sim.store.count:
		if sim.store.alive[i] == 1:
			ids.append(i)
	if ids.size() < 2:
		return 0.0
	var total := 0.0
	var pairs := 0
	for a in ids.size():
		for b in range(a + 1, ids.size()):
			total += GenomeRef.distance_store(sim.store, int(ids[a]), int(ids[b]))
			pairs += 1
	return total / float(maxi(pairs, 1))


## One row per founder line, live aggregation merged with the persistent record.
## Rows with no living member keep their birth, death and cause history; rows
## created by a direct test spawn with no history still appear while alive.
func lineage_rows(sim: Sim, limit: int = 8) -> Array:
	var live := {}
	for i in sim.store.count:
		if sim.store.alive[i] == 0:
			continue
		var founder := int(sim.store.founder[i])
		if not live.has(founder):
			live[founder] = {
				"alive": 0,
				"sum_x": 0.0,
				"sum_y": 0.0,
				"sum_x2": 0.0,
				"sum_y2": 0.0,
				"max_generation": 0,
				"drift_sum": 0.0,
				"drift_n": 0,
				"oldest": 0.0,
			}
		var row: Dictionary = live[founder]
		row["alive"] = int(row["alive"]) + 1
		row["sum_x"] = float(row["sum_x"]) + float(sim.store.px[i])
		row["sum_y"] = float(row["sum_y"]) + float(sim.store.py[i])
		row["sum_x2"] = float(row["sum_x2"]) + float(sim.store.px[i]) * float(sim.store.px[i])
		row["sum_y2"] = float(row["sum_y2"]) + float(sim.store.py[i]) * float(sim.store.py[i])
		row["max_generation"] = maxi(int(row["max_generation"]), int(sim.store.generation[i]))
		row["oldest"] = maxf(float(row["oldest"]), float(sim.store.age_days[i]))
		var record: Dictionary = lineages.get(founder, {})
		var stored_genome = record.get("founder_genome", PackedFloat32Array())
		if stored_genome is PackedFloat32Array and stored_genome.size() == GenomeRef.LOCI:
			var founder_genome: PackedFloat32Array = stored_genome
			row["drift_sum"] = float(row["drift_sum"]) + GenomeRef.distance(founder_genome, sim.store.genome_at(i))
			row["drift_n"] = int(row["drift_n"]) + 1

	var out: Array = []
	var seen := {}
	for founder in live.keys():
		seen[founder] = true
		var row: Dictionary = live[founder]
		var n := float(int(row["alive"]))
		var record: Dictionary = lineages.get(founder, {})
		var spread := 0.0
		if n > 0.0:
			var mean_x := float(row["sum_x"]) / n
			var mean_y := float(row["sum_y"]) / n
			var var_x := maxf(float(row["sum_x2"]) / n - mean_x * mean_x, 0.0)
			var var_y := maxf(float(row["sum_y2"]) / n - mean_y * mean_y, 0.0)
			spread = 2.0 * sqrt(var_x + var_y)
		var drift_n := int(row["drift_n"])
		out.append({
			"line": founder,
			"alive": int(row["alive"]),
			"born": maxi(int(record.get("born", 0)), int(row["alive"])),
			"died": int(record.get("died", 0)),
			"max_generation": maxi(int(row["max_generation"]), int(record.get("max_generation", 0))),
			"spread": spread,
			"drift": (float(row["drift_sum"]) / float(drift_n)) if drift_n > 0 else 0.0,
			"oldest": float(row["oldest"]),
			"first_day": float(record.get("first_day", 0.0)),
			"last_day": float(record.get("last_day", 0.0)),
			"extinct_day": -1.0,
			"series": record.get("series", []),
			"causes": record.get("causes", {}),
		})
	for founder in lineages.keys():
		if seen.has(founder):
			continue
		var record: Dictionary = lineages[founder]
		out.append({
			"line": founder,
			"alive": 0,
			"born": int(record.get("born", 0)),
			"died": int(record.get("died", 0)),
			"max_generation": int(record.get("max_generation", 0)),
			"spread": 0.0,
			"drift": 0.0,
			"oldest": 0.0,
			"first_day": float(record.get("first_day", 0.0)),
			"last_day": float(record.get("last_day", 0.0)),
			"extinct_day": float(record.get("last_day", 0.0)),
			"series": record.get("series", []),
			"causes": record.get("causes", {}),
		})
	out.sort_custom(func(a, b):
		if int(a["alive"]) != int(b["alive"]):
			return int(a["alive"]) > int(b["alive"])
		return int(a["born"]) > int(b["born"])
	)
	return out.slice(0, maxi(limit, 0))


func living_lineages(sim: Sim) -> int:
	var seen := {}
	for i in sim.store.count:
		if sim.store.alive[i] == 1:
			seen[int(sim.store.founder[i])] = true
	return seen.size()


func extinct_lineages(sim: Sim, rows: Array = []) -> int:
	if rows.is_empty():
		rows = lineage_rows(sim, 100000)
	var n := 0
	for row in rows:
		if int(row["alive"]) == 0 and int(row["died"]) > 0:
			n += 1
	return n


func summary(sim: Sim) -> Dictionary:
	var rows := lineage_rows(sim, 100000)
	var max_generation := 0
	for row in rows:
		max_generation = maxi(max_generation, int(row["max_generation"]))
	return {
		"lineages": rows.size(),
		"living_lineages": living_lineages(sim),
		"extinct_lineages": extinct_lineages(sim, rows),
		"diversity": diversity(sim),
		"total_births": total_births,
		"total_deaths": total_deaths,
		"max_generation": max_generation,
	}
