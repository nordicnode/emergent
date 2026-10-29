class_name SpatialHash
extends RefCounted

## Uniform-grid neighbour index. Creature queries go through here; no system
## scans all creatures. Bucket size is set near the maximum sensory radius.
## Rebuilt each tick in Phase 0 (cheap at this population; incremental buckets
## are a Phase 3 concern).
##
## The hash holds ids only. Positions are read from the creature store at query
## time, so the index never becomes a second copy of creature state.

var cell_size: float
var cols := 0
var rows := 0

var _buckets: Array = []
## Reused result buffer. A fresh array per query looked harmless at 20
## creatures, but the brain asks for neighbours every decision tick and the
## garbage showed up as 20-30 ms collector pauses against a 10 ms mean. The
## buffer is safe because no call site queries again while it still holds a
## result; that is a contract of this method, not an accident.
var _out: Array = []


func _init(world_width: float, world_height: float, size: float) -> void:
	cell_size = maxf(size, 1.0)
	cols = maxi(1, int(ceil(world_width / cell_size)))
	rows = maxi(1, int(ceil(world_height / cell_size)))
	_buckets.resize(cols * rows)
	for i in _buckets.size():
		_buckets[i] = []


func _bucket_index(x: float, y: float) -> int:
	var cx := clampi(int(floor(x / cell_size)), 0, cols - 1)
	var cy := clampi(int(floor(y / cell_size)), 0, rows - 1)
	return cy * cols + cx


func rebuild(store: CreatureStore) -> void:
	for i in _buckets.size():
		_buckets[i].clear()
	for id in store.count:
		if store.alive[id] == 0:
			continue
		var b: Array = _buckets[_bucket_index(store.px[id], store.py[id])]
		b.append(id)


## Results are valid until the next query on this hash.
func query_radius(store: CreatureStore, x: float, y: float, radius: float) -> Array:
	_out.clear()
	var out := _out
	var min_cx := clampi(int(floor((x - radius) / cell_size)), 0, cols - 1)
	var max_cx := clampi(int(floor((x + radius) / cell_size)), 0, cols - 1)
	var min_cy := clampi(int(floor((y - radius) / cell_size)), 0, rows - 1)
	var max_cy := clampi(int(floor((y + radius) / cell_size)), 0, rows - 1)
	var r2 := radius * radius
	for cy in range(min_cy, max_cy + 1):
		for cx in range(min_cx, max_cx + 1):
			for id in _buckets[cy * cols + cx]:
				var dx: float = store.px[id] - x
				var dy: float = store.py[id] - y
				if dx * dx + dy * dy <= r2:
					out.append(id)
	return out
