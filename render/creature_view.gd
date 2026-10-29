extends Node2D

## Creature view: one MultiMeshInstance2D per world chunk. Never one scene node
## per creature. Instances carry transform, tint and per-instance custom data
## (atlas frame, hunger), and a shader advances the frame. Batch granularity is
## the chunk so chunk-level culling stays possible later.

const AtlasRef := preload("res://render/sprite_atlas.gd")
const StoreRef := preload("res://sim/creature_store.gd")
const GridRef := preload("res://sim/grid.gd")
const GenomeRef := preload("res://sim/genome.gd")

var _grid = null
var _store = null
var _material: ShaderMaterial
var _quad: QuadMesh
var _batches: Array = []
var _cell_px := 8


func setup(grid, store) -> void:
	_grid = grid
	_store = store
	_cell_px = grid.cell_px

	_material = ShaderMaterial.new()
	_material.shader = load("res://render/creature.gdshader")
	_material.set_shader_parameter("atlas", AtlasRef.build())
	_material.set_shader_parameter("frame_count", float(AtlasRef.FRAME_COUNT))

	_quad = QuadMesh.new()
	_quad.size = Vector2(float(AtlasRef.FRAME_W), float(AtlasRef.FRAME_W))

	for child in get_children():
		child.queue_free()
	_batches.clear()

	var chunk_count: int = int(grid.chunks_x) * int(grid.chunks_y)
	for ci in chunk_count:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _quad
		mm.instance_count = 0

		var mmi := MultiMeshInstance2D.new()
		mmi.multimesh = mm
		mmi.material = _material
		mmi.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var cx: int = ci % int(grid.chunks_x)
		var cy: int = int(float(ci) / float(grid.chunks_x))
		mmi.position = Vector2(cx * grid.chunk_size * _cell_px, cy * grid.chunk_size * _cell_px)
		add_child(mmi)
		_batches.append(mmi)

	sync(0.0)


func sync(sim_time: float) -> void:
	if _store == null:
		return

	var chunk_count := _batches.size()
	var lists: Array = []
	lists.resize(chunk_count)
	for ci in chunk_count:
		lists[ci] = []

	for id in _store.count:
		if _store.alive[id] == 0:
			continue
		var ci: int = _grid.chunk_of(int(floor(_store.px[id])), int(floor(_store.py[id])))
		lists[ci].append(id)

	for ci in chunk_count:
		var mmi: MultiMeshInstance2D = _batches[ci]
		var mm: MultiMesh = mmi.multimesh
		var ids: Array = lists[ci]
		mm.instance_count = ids.size()
		if ids.is_empty():
			continue
		var origin := mmi.position
		for k in ids.size():
			var id: int = ids[k]
			var pos := Vector2(_store.px[id] * _cell_px, _store.py[id] * _cell_px) - origin
			var motion := sqrt(_store.vx[id] * _store.vx[id] + _store.vy[id] * _store.vy[id])
			var frame := _frame_for(int(_store.verb[id]), motion > 0.15, sim_time, id)
			# The silhouette is the body-size gene under the age scale: a child,
			# a small adult and a large old adult are different shapes made from
			# the same sprite, not three icons.
			var size_gene: float = _store.body_value(id, GenomeRef.F_SIZE)
			var silhouette: float = clampf((0.70 + 0.50 * size_gene) * _store.body_scale[id], 0.50, 1.35)
			mm.set_instance_transform_2d(k, Transform2D(0.0, Vector2(silhouette, silhouette), 0.0, pos))
			mm.set_instance_color(k, _tint_for(id))
			var hunger_urgency := clampf(1.0 - _store.food_level[id], 0.0, 1.0)
			# Carried material is drawn on the sprite, as the plan requires: the
			# shader turns (z, w) into a small load above the body. Food and sand
			# get different colours; the amount sets the blob size.
			var carry_code := 0.0
			var carried := 0.0
			if _store.carry_amount[id] > 0.001:
				carry_code = 1.0 if int(_store.carry_material[id]) == GridRef.FOOD else 2.0
				carried = clampf(_store.carry_amount[id], 0.0, 1.0)
			mm.set_instance_custom_data(k, Color(frame, hunger_urgency, carry_code, carried))


func _frame_for(verb: int, moving: bool, sim_time: float, id: int) -> float:
	match verb:
		StoreRef.Verb.EAT:
			return 3.0
		StoreRef.Verb.DRINK:
			return 4.0
		StoreRef.Verb.REST:
			return 5.0
		StoreRef.Verb.FLEE:
			return 6.0
		_:
			pass
	if moving:
		# Exhaustion slows the same two frame loop. The cadence is a state
		# transform, not an extra animation: a tired creature reads as tired
		# without an icon or a new sprite.
		var energy := clampf(_store.energy_level[id], 0.0, 1.0)
		var cadence := 2.0 + 4.0 * energy
		var phase := int(floor(sim_time * cadence + float(id) * 0.37)) % 2
		return 1.0 + float(phase)
	return 0.0


func _tint_for(id: int) -> Color:
	var health := clampf(_store.health[id], 0.0, 1.0)
	# Wet ground darkens the same sprite, so a creature crossing a damp shore
	# reads as wet without a second atlas or a floating status icon.
	var wet := 0.0
	var cx := int(floor(_store.px[id]))
	var cy := int(floor(_store.py[id]))
	if _grid.in_bounds(cx, cy):
		wet = clampf(float(_grid.wetness[_grid.index(cx, cy)]), 0.0, 1.0)
	var value := clampf(0.62 + 0.33 * health - 0.12 * wet, 0.18, 1.0)
	return Color.from_hsv(_store.hue[id], 0.55, value)
