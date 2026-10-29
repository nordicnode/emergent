class_name SimGrid
extends RefCounted

## The material grid. Structure-of-arrays, no scene or rendering types.
##
## Every cell carries a material, an amount, and the property language the rest
## of the simulation reads: wetness, compaction, hardness, cohesion, nutrition,
## toxicity and age. Derived states (mud, hard sand) are computed from those
## properties, never stored as their own material and never a recipe.
##
## Phase 1 still holds one material per cell. Water placed on porous material is
## absorbed as wetness; water arriving at a saturated, soft cell floods it. Hard
## sand resists flooding while it is hard, which is what makes the softening
## step of the flood test possible.

const AIR := 0
const SAND := 1
const WATER := 2
const FOOD := 3

const MATERIAL_NAMES := ["air", "sand", "water", "food"]

## Derived states. Computed from properties at query time.
const STATE_AIR := 0
const STATE_SAND_DRY := 1
const STATE_SAND_WET := 2
const STATE_MUD := 3
const STATE_HARD_SAND := 4
const STATE_WATER := 5
const STATE_FOOD := 6
const STATE_FOOD_ROTTEN := 7

const STATE_NAMES := ["air", "dry sand", "wet sand", "mud", "hard sand", "water", "food", "rotting food"]

## Density, read by flow when two liquids meet. Sand never flows in this slice;
## it is moved by creature verbs, so its number is here for later materials.
const DENSITY := [0.1, 2.2, 1.0, 1.1]

var width: int
var height: int
var chunk_size: int
var cell_px: int
var chunks_x: int
var chunks_y: int

var material := PackedByteArray()
var amount := PackedFloat32Array()
var nutrition := PackedFloat32Array()

## Absorbed water, 0..1. Free water is a WATER cell; wetness is water held in
## porous material (sand, food).
var wetness := PackedFloat32Array()
## Recent high-water mark of wetness. This is the "wetness history" hardening reads.
var wet_history := PackedFloat32Array()
var compaction := PackedFloat32Array()
var hardness := PackedFloat32Array()
var cohesion := PackedFloat32Array()
var toxicity := PackedFloat32Array()
var age := PackedFloat32Array()

var sand_max := 4.0
var water_max := 1.0
var food_max := 1.0
## Food never disappears completely: an eaten cell keeps this much living trace,
## which is what lets a grazed patch regrow. Set from the parameter register.
var food_min_amount := 0.02

## Thresholds live in the parameter register and are copied in at start.
var mud_wetness := 0.55
var hard_sand_threshold := 0.45
var food_rot_threshold := 0.40
var convert_max_hardness := 0.35

var _dirty := PackedByteArray()
var _dirty_list := PackedInt32Array()
## Per-chunk dirty rectangle, four ints per chunk: x0, y0, x1, y1 in local
## chunk cells, or -1 when clean. A repaint of one changed cell used to cost a
## whole 64x64 chunk; the rectangle lets the renderer touch only what moved.
var _dirty_rects := PackedInt32Array()

var _tick := 0

## Material work queue. Chunk-level activity was too coarse: one wet cell forced
## a 4,096-cell repaint of the simulation. A cell sits in this queue while
## something about it is still changing; a dry, still cell is not in it at all.
##
## FIFO with a head index and a per-cell flag: waking a cell twice costs nothing,
## a cell can re-queue itself when its pass finishes, and a pass can take a
## bounded batch and leave the rest for the next material tick.
var _queue := PackedInt32Array()
var _queued := PackedByteArray()
var _head := 0

## Water cells, maintained incrementally so flow runs every material tick
## without scanning the grid. Swap-remove plus a position index keeps it O(1).
var _water_cells := PackedInt32Array()
var _water_pos := PackedInt32Array()

## Food cells, same incremental pattern as water. Rot visits food, not every
## cell in every chunk that happens to contain a patch.
var _food_cells := PackedInt32Array()
var _food_pos := PackedInt32Array()

## Material tick at which a cell last entered the property queue or was last
## processed. A cell gets the elapsed time it actually waited, so a fixed batch
## budget makes material time coarser, never slower or faster.
var prop_tick := PackedInt32Array()

## Per-cell tick stamp: a liquid cell moves at most once per tick, including
## across chunk boundaries.
var stamp := PackedInt32Array()


func _init(w: int, h: int, cs: int, px: int = 8, capacity: Dictionary = {}) -> void:
	width = maxi(w, 1)
	height = maxi(h, 1)
	chunk_size = maxi(cs, 1)
	cell_px = maxi(px, 1)
	chunks_x = int(ceil(float(width) / float(chunk_size)))
	chunks_y = int(ceil(float(height) / float(chunk_size)))
	var n := width * height
	material.resize(n)
	amount.resize(n)
	nutrition.resize(n)
	wetness.resize(n)
	wet_history.resize(n)
	compaction.resize(n)
	hardness.resize(n)
	cohesion.resize(n)
	toxicity.resize(n)
	age.resize(n)
	stamp.resize(n)
	stamp.fill(-1)
	_dirty.resize(chunks_x * chunks_y)
	_dirty_rects.resize(chunks_x * chunks_y * 4)
	_dirty_rects.fill(-1)
	_queued.resize(n)
	_water_pos.resize(n)
	_water_pos.fill(-1)
	_food_pos.resize(n)
	_food_pos.fill(-1)
	prop_tick.resize(n)
	sand_max = float(capacity.get("sand", 4.0))
	water_max = float(capacity.get("water", 1.0))
	food_max = float(capacity.get("food", 1.0))


func index(x: int, y: int) -> int:
	return y * width + x


func cell_x(i: int) -> int:
	return i % width


func cell_y(i: int) -> int:
	return int(float(i) / float(width))


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func chunk_of(x: int, y: int) -> int:
	var cx := clampi(int(float(x) / float(chunk_size)), 0, chunks_x - 1)
	var cy := clampi(int(float(y) / float(chunk_size)), 0, chunks_y - 1)
	return cy * chunks_x + cx


# --- material properties -------------------------------------------------

func absorb_capacity(mat: int) -> float:
	match mat:
		SAND:
			return 1.0
		FOOD:
			return 0.7
		_:
			return 0.0


func is_porous(mat: int) -> bool:
	return mat == SAND or mat == FOOD


func density_of(mat: int) -> float:
	if mat >= 0 and mat < DENSITY.size():
		return float(DENSITY[mat])
	return 10.0


# --- derived states ------------------------------------------------------

func state_of(i: int) -> int:
	var m := int(material[i])
	match m:
		AIR:
			return STATE_AIR
		WATER:
			return STATE_WATER
		FOOD:
			return STATE_FOOD_ROTTEN if nutrition[i] < food_rot_threshold else STATE_FOOD
		SAND:
			if hardness[i] >= hard_sand_threshold:
				return STATE_HARD_SAND
			if wetness[i] >= mud_wetness:
				return STATE_MUD
			if wetness[i] > 0.15:
				return STATE_SAND_WET
			return STATE_SAND_DRY
	return STATE_AIR


func state_name(i: int) -> String:
	return STATE_NAMES[state_of(i)]


## What standing or resting on this cell offers a creature's comfort, read from
## properties at query time. Hard, dry, compacted ground scores highest; water
## and air score zero and mud barely above it. No cell is tagged "shelter": a cell that
## dried hard after being piled and rested on simply scores well here.
func comfort_quality(i: int) -> float:
	if i < 0 or i >= material.size():
		return 0.0
	var m := int(material[i])
	if m == WATER or m == AIR:
		return 0.0
	var value := 0.10 + 0.55 * hardness[i] + 0.20 * compaction[i] + 0.15 * (1.0 - wetness[i])
	return clampf(value, 0.0, 1.0)


## How much the arrangement around this cell cuts a creature's exposure, read
## from properties at query time. Hardness and cohesion underfoot help a little;
## hard cells on its sides help far more, which is the difference between a lone
## hardened patch and a sheltered corner. No cell is tagged "shelter"; the score
## is the same arrangement rule for a pond pan, a dune and a pile a creature made.
func protection_quality(i: int) -> float:
	if i < 0 or i >= material.size():
		return 0.0
	var m := int(material[i])
	if m == WATER or m == AIR:
		return 0.0
	var hard := 0
	var around := 0
	var cx := cell_x(i)
	var cy := cell_y(i)
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			var tx := cx + ox
			var ty := cy + oy
			if not in_bounds(tx, ty):
				continue
			around += 1
			var j := index(tx, ty)
			var jm := int(material[j])
			if jm == AIR or jm == WATER:
				continue
			if hardness[j] >= hard_sand_threshold * 0.8:
				hard += 1
	var wall := 0.0 if around == 0 else float(hard) / float(around)
	return clampf(0.25 * hardness[i] + 0.15 * cohesion[i] + 0.60 * wall, 0.0, 1.0)


## One scan for reports and the soak harness. Not used per tick.
func counts() -> Dictionary:
	var c := {"water": 0, "wet": 0, "mud": 0, "hard": 0, "food": 0, "rotten_food": 0}
	for i in material.size():
		var m := int(material[i])
		if m == WATER:
			c["water"] = int(c["water"]) + 1
		elif m == FOOD:
			c["food"] = int(c["food"]) + 1
			if nutrition[i] < food_rot_threshold:
				c["rotten_food"] = int(c["rotten_food"]) + 1
		elif m == SAND:
			if wetness[i] > 0.05:
				c["wet"] = int(c["wet"]) + 1
			var s := state_of(i)
			if s == STATE_HARD_SAND:
				c["hard"] = int(c["hard"]) + 1
			elif s == STATE_MUD:
				c["mud"] = int(c["mud"]) + 1
	return c


# --- active cells --------------------------------------------------------

func begin_tick(t: int) -> void:
	_tick = t


func wake_cell(i: int) -> void:
	if i < 0 or i >= _queued.size():
		return
	if _queued[i] == 0:
		_queued[i] = 1
		_queue.append(i)
		# A cell that was asleep did not accumulate material time, so its clock
		# starts when it joins the queue.
		prop_tick[i] = _tick


func wake_cell_xy(x: int, y: int) -> void:
	if in_bounds(x, y):
		wake_cell(index(x, y))


## Hands up to max_count queued cells to the material pass, oldest first. The
## rest stay queued with their flags set, so a busy world degrades into slower
## material time instead of a longer frame. Order is deterministic.
func take_material_batch(max_count: int) -> PackedInt32Array:
	var end := mini(_queue.size(), _head + maxi(max_count, 0))
	if end <= _head:
		return PackedInt32Array()
	var out := _queue.slice(_head, end)
	for k in range(_head, end):
		_queued[_queue[k]] = 0
	_head = end
	if _head > 2048 and _head * 2 >= _queue.size():
		_queue = _queue.slice(_head)
		_head = 0
	return out


func active_cell_count() -> int:
	return _queue.size() - _head


func clear_activity() -> void:
	for k in range(_head, _queue.size()):
		_queued[_queue[k]] = 0
	_queue = PackedInt32Array()
	_head = 0


func track_water(i: int) -> void:
	if i < 0 or i >= _water_pos.size() or _water_pos[i] >= 0:
		return
	_water_pos[i] = _water_cells.size()
	_water_cells.append(i)


func untrack_water(i: int) -> void:
	if i < 0 or i >= _water_pos.size():
		return
	var p := _water_pos[i]
	if p < 0:
		return
	var last := _water_cells.size() - 1
	var moved := _water_cells[last]
	_water_cells[p] = moved
	_water_pos[moved] = p
	_water_cells.resize(last)
	_water_pos[i] = -1


## Snapshot taken before flow, because moving water edits the live list.
func water_cell_snapshot() -> PackedInt32Array:
	return _water_cells.duplicate()


func water_cell_count() -> int:
	return _water_cells.size()


func is_water_tracked(i: int) -> bool:
	return i >= 0 and i < _water_pos.size() and _water_pos[i] >= 0


## Wake every cell that holds water or wet material, once at world start.
func activate_dynamic() -> void:
	for i in material.size():
		if material[i] == WATER:
			track_water(i)
		elif material[i] == FOOD:
			track_food(i)
		if material[i] == WATER or wetness[i] > 0.01:
			wake_cell(i)


func track_food(i: int) -> void:
	if i < 0 or i >= _food_pos.size() or _food_pos[i] >= 0:
		return
	_food_pos[i] = _food_cells.size()
	_food_cells.append(i)


func untrack_food(i: int) -> void:
	if i < 0 or i >= _food_pos.size():
		return
	var p := _food_pos[i]
	if p < 0:
		return
	var last := _food_cells.size() - 1
	var moved := _food_cells[last]
	_food_cells[p] = moved
	_food_pos[moved] = p
	_food_cells.resize(last)
	_food_pos[i] = -1


func food_cell_count() -> int:
	return _food_cells.size()


## Rotating food does not create or destroy food cells, so a plain snapshot is
## enough; it exists so the loop cannot be surprised by array reuse.
func food_cell_snapshot() -> PackedInt32Array:
	return _food_cells.duplicate()


# --- dirty chunks (rendering) -------------------------------------------

## Whole-chunk invalidation, for changes that have no single cell.
func mark_chunk_dirty(ci: int) -> void:
	if ci < 0 or ci >= _dirty.size():
		return
	var b := ci * 4
	_dirty_rects[b] = 0
	_dirty_rects[b + 1] = 0
	_dirty_rects[b + 2] = chunk_size - 1
	_dirty_rects[b + 3] = chunk_size - 1
	if _dirty[ci] == 0:
		_dirty[ci] = 1
		_dirty_list.append(ci)


func touch_cell(x: int, y: int) -> void:
	if not in_bounds(x, y):
		return
	mark_chunk_dirty(chunk_of(x, y))


## A visible material change: grow this chunk's dirty rectangle by this cell.
## Wake the cell separately when the change also needs simulation.
func mark_dirty_cell(x: int, y: int) -> void:
	if not in_bounds(x, y):
		return
	var ci := chunk_of(x, y)
	var lx := x % chunk_size
	var ly := y % chunk_size
	var b := ci * 4
	if _dirty_rects[b] < 0:
		_dirty_rects[b] = lx
		_dirty_rects[b + 1] = ly
		_dirty_rects[b + 2] = lx
		_dirty_rects[b + 3] = ly
	else:
		# PackedInt32Array has no min/max in place; four comparisons are still
		# cheaper than the old full-chunk repaint this replaces.
		if lx < _dirty_rects[b]:
			_dirty_rects[b] = lx
		if ly < _dirty_rects[b + 1]:
			_dirty_rects[b + 1] = ly
		if lx > _dirty_rects[b + 2]:
			_dirty_rects[b + 2] = lx
		if ly > _dirty_rects[b + 3]:
			_dirty_rects[b + 3] = ly
	if _dirty[ci] == 0:
		_dirty[ci] = 1
		_dirty_list.append(ci)


func mark_all_dirty() -> void:
	_dirty.fill(1)
	_dirty_list.clear()
	var full := chunk_size - 1
	for c in _dirty.size():
		_dirty_list.append(c)
		var b := c * 4
		_dirty_rects[b] = 0
		_dirty_rects[b + 1] = 0
		_dirty_rects[b + 2] = full
		_dirty_rects[b + 3] = full


## Hands at most max_count dirty chunks to the renderer. Repaint work is capped
## per frame; the rest stay queued, so a busy world degrades smoothly instead
## of stalling a frame.
## Hands back and clears one chunk's changed rectangle. Call it immediately
## before painting that chunk.
func take_dirty_rect(ci: int) -> Rect2i:
	var b := ci * 4
	var x0 := _dirty_rects[b]
	if x0 < 0:
		return Rect2i(0, 0, chunk_size, chunk_size)
	var y0 := _dirty_rects[b + 1]
	var rect := Rect2i(x0, y0, _dirty_rects[b + 2] - x0 + 1, _dirty_rects[b + 3] - y0 + 1)
	_dirty_rects[b] = -1
	_dirty_rects[b + 1] = -1
	_dirty_rects[b + 2] = -1
	_dirty_rects[b + 3] = -1
	return rect


## The renderer repainted everything; forget the rectangles as well as the flags.
func clear_dirty_rects() -> void:
	_dirty_rects.fill(-1)


func take_dirty(max_count: int = 8) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _dirty_list.is_empty():
		return out
	var keep := PackedInt32Array()
	var taken := 0
	for c in _dirty_list:
		if _dirty[c] == 1:
			if taken < max_count:
				_dirty[c] = 0
				out.append(c)
				taken += 1
			else:
				keep.append(c)
	_dirty_list = keep
	return out


# --- reading and writing cells ------------------------------------------

func max_for(mat: int) -> float:
	match mat:
		SAND:
			return sand_max
		WATER:
			return water_max
		FOOD:
			return food_max
		_:
			return 0.0


func material_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return AIR
	return int(material[index(x, y)])


func amount_at(x: int, y: int) -> float:
	if not in_bounds(x, y):
		return 0.0
	return amount[index(x, y)]


func nutrition_at(x: int, y: int) -> float:
	if not in_bounds(x, y):
		return 0.0
	return nutrition[index(x, y)]


func wetness_at(x: int, y: int) -> float:
	if not in_bounds(x, y):
		return 0.0
	return wetness[index(x, y)]


func hardness_at(x: int, y: int) -> float:
	if not in_bounds(x, y):
		return 0.0
	return hardness[index(x, y)]


func set_cell(x: int, y: int, mat: int, amt: float, nutr: float = 1.0) -> void:
	if not in_bounds(x, y):
		return
	var i := index(x, y)
	material[i] = mat
	amount[i] = clampf(amt, 0.0, max_for(mat))
	nutrition[i] = nutr if mat == FOOD else 0.0
	wetness[i] = 0.0
	wet_history[i] = 0.0
	compaction[i] = 0.0
	hardness[i] = 0.0
	cohesion[i] = 0.0
	toxicity[i] = 0.0
	age[i] = 0.0
	if mat == WATER:
		track_water(i)
	else:
		untrack_water(i)
	if mat == FOOD:
		track_food(i)
	else:
		untrack_food(i)
	mark_dirty_cell(x, y)
	wake_cell(i)


func add_material(x: int, y: int, mat: int, amt: float) -> void:
	if not in_bounds(x, y) or amt <= 0.0:
		return
	var i := index(x, y)
	match mat:
		WATER:
			_add_water(i, amt)
		SAND:
			_add_sand(i, amt)
		FOOD:
			_add_food(i, amt)
		_:
			return
	if int(material[i]) == WATER:
		track_water(i)
	else:
		untrack_water(i)
	if int(material[i]) == FOOD:
		track_food(i)
	else:
		untrack_food(i)
	mark_dirty_cell(x, y)
	wake_cell(i)


## Water onto porous material is absorbed as wetness (dosage: a little dampens).
## Once the material is saturated and soft enough, the excess floods the cell
## (a lot becomes a pool). Hard sand refuses the flood while it is hard.
func _add_water(i: int, amt: float) -> void:
	var m := int(material[i])
	if m == WATER:
		amount[i] = minf(water_max, amount[i] + amt)
		return
	if m == AIR:
		material[i] = WATER
		amount[i] = minf(water_max, amt)
		wetness[i] = 0.0
		return
	var cap := absorb_capacity(m)
	var space := maxf(0.0, cap - wetness[i])
	var absorbed := minf(space, amt)
	if absorbed > 0.0:
		wetness[i] += absorbed
		wet_history[i] = maxf(wet_history[i], wetness[i])
		amt -= absorbed
	if amt > 0.001 and hardness[i] < convert_max_hardness:
		material[i] = WATER
		amount[i] = minf(water_max, amt)
		wetness[i] = 0.0
		compaction[i] = 0.0
		hardness[i] = 0.0
		cohesion[i] = 0.0
		toxicity[i] = 0.0


## Sand dropped into water arrives wet. That single line is how a player can
## start the hardening chain deliberately: pile sand into a pool.
func _add_sand(i: int, amt: float) -> void:
	var m := int(material[i])
	if m == SAND:
		amount[i] = minf(sand_max, amount[i] + amt)
		return
	material[i] = SAND
	amount[i] = minf(sand_max, amt)
	wetness[i] = 1.0 if m == WATER else 0.0
	wet_history[i] = wetness[i]
	compaction[i] = 0.0
	hardness[i] = 0.0
	cohesion[i] = 0.0
	nutrition[i] = 0.0
	toxicity[i] = 0.0
	age[i] = 0.0


func _add_food(i: int, amt: float) -> void:
	var m := int(material[i])
	if m == FOOD:
		var total := amount[i] + amt
		if total > 0.0001:
			nutrition[i] = (nutrition[i] * amount[i] + 1.0 * amt) / total
		amount[i] = minf(food_max, total)
		return
	var inherited_wet := 0.0
	if m == WATER:
		inherited_wet = 0.8
	elif m == SAND:
		inherited_wet = wetness[i]
	material[i] = FOOD
	amount[i] = minf(food_max, amt)
	nutrition[i] = 1.0
	toxicity[i] = 0.0
	wetness[i] = inherited_wet
	wet_history[i] = inherited_wet
	compaction[i] = 0.0
	hardness[i] = 0.0
	cohesion[i] = 0.0
	age[i] = 0.0


## Removes up to max_amount from a cell and returns how much was taken.
## The caller reads nutrition before consuming when the material is food.
## Removes up to max_amount of a solid material for a creature to carry. Food
## keeps its living trace, exactly as eating does, so carrying cannot strip a
## patch below the amount that lets it regrow. Returns the material and the
## properties it had in the cell; an empty dictionary means nothing was taken.
func extract(x: int, y: int, max_amount: float) -> Dictionary:
	if not in_bounds(x, y) or max_amount <= 0.0:
		return {}
	var i := index(x, y)
	var m := int(material[i])
	if m != SAND and m != FOOD:
		return {}
	var floor := 0.0
	if m == FOOD:
		floor = minf(food_min_amount, food_max)
	var available := amount[i] - floor
	var taken := minf(available, max_amount)
	if taken <= 0.0001:
		return {}
	var sample := {
		"material": m,
		"amount": taken,
		"wetness": wetness[i],
		"nutrition": nutrition[i],
		"toxicity": toxicity[i],
	}
	amount[i] -= taken
	if amount[i] <= floor + 0.0001:
		amount[i] = floor
		if floor <= 0.0:
			material[i] = AIR
			nutrition[i] = 0.0
			wetness[i] = 0.0
			wet_history[i] = 0.0
			compaction[i] = 0.0
			hardness[i] = 0.0
			cohesion[i] = 0.0
			toxicity[i] = 0.0
			age[i] = 0.0
			untrack_water(i)
			untrack_food(i)
	mark_dirty_cell(x, y)
	wake_cell(i)
	return sample


## Puts carried material into a cell. Sand may be added to sand, dropped into
## open air, or used to fill water; food may be added to food or dropped on open
## ground. A solid of another material is refused, so a creature cannot bury a
## food patch under a load of sand. Returns the amount actually deposited.
func deposit(x: int, y: int, mat: int, amt: float, wetness_value: float = 0.0, nutrition_value: float = 0.0, toxicity_value: float = 0.0) -> float:
	if not in_bounds(x, y) or amt <= 0.0:
		return 0.0
	if mat != SAND and mat != FOOD:
		return 0.0
	var i := index(x, y)
	var m := int(material[i])
	var deposited := 0.0
	if mat == SAND:
		if m == FOOD:
			return 0.0
		if m == SAND:
			var room := maxf(0.0, sand_max - amount[i])
			deposited = minf(room, amt)
			if deposited <= 0.0:
				return 0.0
			var total := amount[i] + deposited
			wetness[i] = (wetness[i] * amount[i] + wetness_value * deposited) / total
			# Wetness history is the memory hardening reads. Depositing wet sand
			# onto loose dry sand raises the mix above the wet-history floor just
			# as a fresh pile does; without this, a pile a creature made could
			# never harden even though it arrived wet.
			wet_history[i] = maxf(wet_history[i], wetness[i])
			amount[i] = total
		else:
			deposited = minf(amt, sand_max)
			material[i] = SAND
			amount[i] = deposited
			wetness[i] = clampf(wetness_value, 0.0, 1.0)
			wet_history[i] = wetness[i]
			compaction[i] = 0.0
			hardness[i] = 0.0
			cohesion[i] = 0.0
			nutrition[i] = 0.0
			toxicity[i] = 0.0
			age[i] = 0.0
			untrack_water(i)
			untrack_food(i)
		if m == WATER:
			# Filling a pool with sand arrives wet, which is the input the
			# hardening chain needs. The material system, not a recipe, decides
			# what happens next.
			wetness[i] = maxf(wetness[i], 0.8)
			wet_history[i] = maxf(wet_history[i], wetness[i])
		mark_dirty_cell(x, y)
		wake_cell(i)
		return deposited

	if m != AIR and m != FOOD:
		return 0.0
	if m == FOOD:
		var room := maxf(0.0, food_max - amount[i])
		deposited = minf(room, amt)
		if deposited <= 0.0:
			return 0.0
		var total := amount[i] + deposited
		nutrition[i] = (nutrition[i] * amount[i] + nutrition_value * deposited) / total
		toxicity[i] = (toxicity[i] * amount[i] + toxicity_value * deposited) / total
		wetness[i] = (wetness[i] * amount[i] + wetness_value * deposited) / total
		amount[i] = total
		wet_history[i] = maxf(wet_history[i], wetness[i])
	else:
		deposited = minf(amt, food_max)
		material[i] = FOOD
		amount[i] = deposited
		nutrition[i] = clampf(nutrition_value, 0.0, 1.0)
		toxicity[i] = clampf(toxicity_value, 0.0, 1.0)
		wetness[i] = clampf(wetness_value, 0.0, 1.0)
		wet_history[i] = wetness[i]
		compaction[i] = 0.0
		hardness[i] = 0.0
		cohesion[i] = 0.0
		age[i] = 0.0
		untrack_water(i)
		track_food(i)
	mark_dirty_cell(x, y)
	wake_cell(i)
	return deposited


func consume(x: int, y: int, max_amount: float) -> float:
	if not in_bounds(x, y) or max_amount <= 0.0:
		return 0.0
	var i := index(x, y)
	# Food leaves a living trace that is not edible: roots and seed stock. A
	# creature cannot farm that last 0.02 forever, but the cell survives to
	# regrow and the food map does not shrink to nothing.
	var floor := 0.0
	if int(material[i]) == FOOD:
		floor = minf(food_min_amount, food_max)
	var available := amount[i] - floor
	if available <= 0.0:
		return 0.0
	var taken := minf(available, max_amount)
	amount[i] -= taken
	if amount[i] <= floor + 0.0001:
		amount[i] = floor
		if floor <= 0.0:
			material[i] = AIR
			nutrition[i] = 0.0
			wetness[i] = 0.0
			wet_history[i] = 0.0
			compaction[i] = 0.0
			hardness[i] = 0.0
			cohesion[i] = 0.0
			toxicity[i] = 0.0
			age[i] = 0.0
			untrack_water(i)
			untrack_food(i)
	mark_dirty_cell(x, y)
	wake_cell(i)
	return taken
