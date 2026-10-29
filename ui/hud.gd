extends CanvasLayer

## Read-only interface strip. It reads recorded state and the last decision
## components; it never reaches into creature internals to change behaviour.

const GridRef := preload("res://sim/grid.gd")
const StoreRef := preload("res://sim/creature_store.gd")
const GenomeRef := preload("res://sim/genome.gd")
const MemoryRef := preload("res://sim/memory.gd")
const InspectorPanelRef := preload("res://ui/inspector_panel.gd")
const HistoryPanelRef := preload("res://ui/history_panel.gd")

var _label: Label
var _inspector = null
var _history = null
var _sim = null
var _selected := -1
var _shown := true


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(14.0, 12.0)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.90, 0.92, 0.86))
	_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.add_theme_constant_override("line_spacing", 2)
	add_child(_label)

	_inspector = InspectorPanelRef.new()
	_inspector.visible = false
	add_child(_inspector)

	_history = HistoryPanelRef.new()
	_history.visible = false
	add_child(_history)


func setup(sim) -> void:
	_sim = sim
	if _selected >= 0:
		_inspector.refresh(_sim, _selected)


func set_selected(id: int) -> void:
	_selected = id
	if _inspector == null:
		return
	if _sim == null or id < 0:
		_inspector.visible = false
	else:
		_inspector.refresh(_sim, id)


func toggle() -> void:
	_shown = not _shown
	_label.visible = _shown
	if _inspector != null:
		_inspector.visible = _shown and _selected >= 0
	if _history != null and not _shown:
		_history.visible = false


## The world history panel is an observation surface, like the inspector: it
## opens on request and never changes what the simulation does.
func toggle_history() -> void:
	if _history == null:
		return
	_history.visible = not _history.visible
	if _history.visible and _sim != null:
		_history.refresh(_sim)


func brush_name(material: int) -> String:
	match material:
		GridRef.SAND:
			return "sand"
		GridRef.WATER:
			return "water"
		GridRef.FOOD:
			return "food"
		_:
			return "?"


func update_text(brush_material: int, brush_radius: int, brush_amount: float, cell: Vector2i) -> void:
	if _sim == null or not _shown:
		return
	var lines: Array = []

	var d: float = _sim.day()
	var day_index := int(floor(d)) + 1
	var minute_of_day := int((d - floor(d)) * 24.0 * 60.0)
	var clock := "%02d:%02d" % [int(minute_of_day / 60), minute_of_day % 60]
	var speed_text := "paused" if _sim.paused else "%sx" % String.num(_sim.speed, 2)
	lines.append("day %d  %s      population %d      %s      step %.2f ms" % [day_index, clock, _sim.alive_count(), speed_text, _sim.last_step_ms])
	if _sim.dropped_seconds > 0.05:
		lines.append("simulation throttled: %.1f s of backlog dropped so far" % _sim.dropped_seconds)

	lines.append("")
	lines.append("brush: %s   size %d   amount %.1f/s" % [brush_name(brush_material), brush_radius, brush_amount])
	lines.append("1/2/3 sand/water/food   Q/E size   Z/X amount   space pause   [ ] speed")
	lines.append("LMB paint   RMB drag pan   RMB click inspect   wheel zoom   shift+wheel amount   F1 hide")
	lines.append("H world history   Esc clear selection")

	if _history != null and _history.visible:
		_history.refresh(_sim)

	var selected_alive: bool = _selected >= 0 and _selected < int(_sim.store.count) and _sim.store.alive[_selected] == 1
	if _inspector != null:
		if selected_alive:
			_inspector.refresh(_sim, _selected)
		else:
			_inspector.visible = false
	if selected_alive:
		var s = _sim.store
		lines.append("")
		lines.append("creature %d — %s — %s — age %.2f days — health %d%%" % [
			_selected,
			String(s.verb_name(int(s.verb[_selected]))),
			String(s.stage_name(int(s.stage[_selected]))),
			float(s.age_days[_selected]),
			int(round(float(s.health[_selected]) * 100.0)),
		])
		lines.append("  generation %d   offspring %d   founder line %d   born day %.2f" % [
			int(s.generation[_selected]),
			int(s.offspring[_selected]),
			int(s.founder[_selected]),
			float(s.birth_time[_selected]) / maxf(float(_sim.day_seconds), 0.001),
		])
		lines.append("  genes: " + String(GenomeRef.gene_string(s, _selected)))
		lines.append("  breeding: %s" % ("ready" if _sim.is_repro_ready(_selected) else "waiting"))
		# Learned state: what this creature has been taught by its own life.
		# Nothing here is inherited, so two siblings can disagree.
		var carry_mat := int(s.carry_material[_selected])
		if s.carry_amount[_selected] > 0.001:
			lines.append("  carrying %.2f %s%s" % [
				float(s.carry_amount[_selected]),
				String(GridRef.MATERIAL_NAMES[carry_mat]) if carry_mat >= 0 and carry_mat < GridRef.MATERIAL_NAMES.size() else "material",
				"  (wet)" if float(s.carry_wetness[_selected]) > 0.2 else "",
			])
		else:
			lines.append("  carrying nothing")
		lines.append("  memory: %d places, %d episodes" % [
			_sim.memory.place_count(_selected), _sim.memory.episode_count(_selected)
		])
		var lesson: Dictionary = _sim.memory.strongest_lesson(_selected)
		if not lesson.is_empty() and absf(float(lesson["weight"])) >= 0.01:
			lines.append("  lesson: %s (%s) %+.2f" % [
				String(s.verb_name(int(lesson["verb"]))),
				String(MemoryRef.CONTEXT_NAMES[int(lesson["context"])]),
				float(lesson["weight"]),
			])
		var episodes: int = _sim.memory.episode_count(_selected)
		if episodes > 0:
			var ep: Dictionary = _sim.memory.episode_at(_selected, episodes - 1)
			lines.append("  last episode: %s, stress %.2f, need %.2f→%.2f, day %.2f" % [
				String(s.verb_name(int(ep["verb"]))),
				float(ep["stress"]),
				float(ep["before"]),
				float(ep["after"]),
				float(ep["day"]),
			])
		lines.append("  deficits: hunger %3d  thirst %3d  energy %3d  social %3d  comfort %3d  safety %3d  toxin %3d" % [
			int(round((1.0 - float(s.food_level[_selected])) * 100.0)),
			int(round((1.0 - float(s.water_level[_selected])) * 100.0)),
			int(round((1.0 - float(s.energy_level[_selected])) * 100.0)),
			int(round((1.0 - float(s.social_level[_selected])) * 100.0)),
			int(round((1.0 - float(s.comfort_level[_selected])) * 100.0)),
			int(round((1.0 - float(s.safety_level[_selected])) * 100.0)),
			int(round(float(s.toxin[_selected]) * 100.0)),
		])
		# Opinions are shown as the creature holds them, not as a global
		# relationship: the other side may feel something different. The right
		# panel carries the event chain behind the strongest one.
		var ops: Array = _sim.opinion.top_opinions(s, _selected, _sim.day(), 3)
		if not ops.is_empty():
			lines.append("  opinions:")
			for op in ops:
				lines.append("    creature %d — %s %+.2f (%d events)%s" % [
					int(op["other"]),
					String(op["label"]),
					float(op["valence"]),
					int(op["events"]),
					"  kin" if bool(op["kin"]) else "",
				])
		# A threat is what the fear need and the flee verb are reading right now:
		# a disliked creature, its opinion, how far away it is, and the strength
		# that opinion contributes once distance and body size are counted.
		var threat: Dictionary = _sim.nearest_threat(_selected)
		if not threat.is_empty():
			lines.append("  threat: creature %d — opinion %+.2f — %.1f cells — strength %.2f" % [
				int(threat["other"]), float(threat["opinion"]), float(threat["distance"]), float(threat["strength"])
			])
		var scores: Array = _sim.last_inspection.duplicate()
		scores.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
		lines.append("  top scores:")
		var shown := mini(3, scores.size())
		for k in shown:
			var c: Dictionary = scores[k]
			var parts_text := ""
			var parts: Dictionary = c["parts"]
			for key in parts.keys():
				if not String(parts_text).is_empty():
					parts_text += ", "
				parts_text += "%s %.2f" % [key, float(parts[key])]
			lines.append("    %-9s %.3f   (%s)" % [String(c["label"]), float(c["score"]), parts_text])
	else:
		lines.append("")
		lines.append("RMB click a creature to inspect why it acted.")

	var g = _sim.grid
	if g.in_bounds(cell.x, cell.y):
		var ci: int = g.index(cell.x, cell.y)
		var mat: int = int(g.material[ci])
		lines.append("")
		lines.append("cell %d,%d — %s" % [cell.x, cell.y, g.state_name(ci)])
		if mat != GridRef.AIR:
			lines.append("  amount %.2f   wet %.2f   compact %.2f   hard %.2f" % [
				float(g.amount[ci]), float(g.wetness[ci]), float(g.compaction[ci]), float(g.hardness[ci])
			])
		if mat == GridRef.FOOD:
			lines.append("  nutrition %.2f   toxicity %.2f" % [float(g.nutrition[ci]), float(g.toxicity[ci])])
		lines.append("  comfort affordance %.2f   protection affordance %.2f" % [
			float(g.comfort_quality(ci)), float(g.protection_quality(ci))
		])

	var recent: Array = _sim.log.recent(3)
	if not recent.is_empty():
		lines.append("")
		for entry in recent:
			lines.append("· " + String(entry["text"]))

	_label.text = "\n".join(lines)
