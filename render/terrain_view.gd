extends Node2D

## Terrain as cached chunk textures: one quad per chunk instead of a sprite per
## cell. A chunk repaints only when its cells change, and at most a few chunks
## repaint per frame so a busy pond cannot stall rendering.
##
## Terrain shows material state honestly: wet sand is darker than dry, mud is
## darker still, hard sand is pale and speckled, food browns and purples as it
## rots with its nutrition and toxicity. If the player cannot see wet, dry,
## hard, piled and contested, they cannot see timing - and timing is the game.

const GridRef := preload("res://sim/grid.gd")
## A full chunk used to cost ~5 ms, so eight of them stalled a frame. The dirty
## rectangle makes most repaints a handful of pixels, and the time budget keeps
## a burst of full chunks from ever owning the frame.
const MAX_REPAINTS_PER_FRAME := 8
const MAX_REPAINT_MS := 2.5

var _grid = null
var _story = null
var _cell_px := 8
var _textures: Array = []
var _sprites: Array = []
var _images: Array = []
var _buffers: Array = []
var _grain_tiles: Array = []


func setup(grid, story = null) -> void:
	_grid = grid
	_story = story
	_cell_px = grid.cell_px
	for child in get_children():
		child.queue_free()
	_textures.clear()
	_sprites.clear()
	_images.clear()
	_buffers.clear()
	_grain_tiles.clear()

	var cw: int = int(grid.chunk_size)
	for cy in grid.chunks_y:
		for cx in grid.chunks_x:
			var blank := Image.create(cw, cw, false, Image.FORMAT_RGBA8)
			var tex := ImageTexture.create_from_image(blank)
			var sprite := Sprite2D.new()
			sprite.texture = tex
			sprite.centered = false
			sprite.position = Vector2(cx * cw * _cell_px, cy * cw * _cell_px)
			sprite.scale = Vector2(_cell_px, _cell_px)
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			add_child(sprite)
			_textures.append(tex)
			_sprites.append(sprite)
			_images.append(blank)
			var buf := PackedByteArray()
			buf.resize(cw * cw * 4)
			_buffers.append(buf)
			# Grain is decorative and never changes. Hashing 4,096 cells on every
			# repaint was a measurable part of the old 10 ms chunk cost.
			var tile := PackedFloat32Array()
			tile.resize(cw * cw)
			var base_x: int = int(cx) * cw
			var base_y: int = int(cy) * cw
			for ly in cw:
				for lx in cw:
					tile[ly * cw + lx] = _grain(base_x + lx, base_y + ly)
			_grain_tiles.append(tile)

	repaint_all()
	_grid.take_dirty(100000)
	_grid.clear_dirty_rects()


func refresh() -> void:
	if _grid == null:
		return
	# Take one chunk at a time: if the budget runs out, the remaining chunks stay
	# queued with their rectangles intact instead of being silently dropped.
	var start := Time.get_ticks_usec()
	for _k in MAX_REPAINTS_PER_FRAME:
		var dirty: PackedInt32Array = _grid.take_dirty(1)
		if dirty.is_empty():
			return
		var ci: int = dirty[0]
		_paint_chunk_rect(ci, _grid.take_dirty_rect(ci))
		if float(Time.get_ticks_usec() - start) / 1000.0 >= MAX_REPAINT_MS:
			return


func repaint_all() -> void:
	var full := Rect2i(0, 0, int(_grid.chunk_size), int(_grid.chunk_size))
	for ci in _textures.size():
		_paint_chunk_rect(ci, full)


## Per-pixel colour is written straight into a per-chunk byte buffer. The first
## version built several Color objects per pixel and cost ~10 ms for one 64x64
## chunk; even the direct rewrite was ~5 ms. With a dirty rectangle the common
## repaint touches only the cells that changed.
func _paint_chunk_rect(ci: int, rect: Rect2i) -> void:
	var cw: int = int(_grid.chunk_size)
	var width: int = int(_grid.width)
	var height: int = int(_grid.height)
	var cx: int = ci % int(_grid.chunks_x)
	var cy: int = int(float(ci) / float(_grid.chunks_x))
	var base_x: int = cx * cw
	var base_y: int = cy * cw
	var x0 := clampi(rect.position.x, 0, cw - 1)
	var y0 := clampi(rect.position.y, 0, cw - 1)
	var x1 := clampi(rect.position.x + rect.size.x, 1, cw)
	var y1 := clampi(rect.position.y + rect.size.y, 1, cw)
	var grain_tile: PackedFloat32Array = _grain_tiles[ci]
	var buf: PackedByteArray = _buffers[ci]
	var mud := float(_grid.mud_wetness)
	var hard_threshold := float(_grid.hard_sand_threshold)
	for ly in range(y0, y1):
		var y: int = base_y + ly
		for lx in range(x0, x1):
			var x: int = base_x + lx
			var r := 0.10
			var g := 0.11
			var b := 0.095
			var hard := 0.0
			var contest_heat := 0.0
			if x < width and y < height:
				var i: int = y * width + x
				var mat: int = int(_grid.material[i])
				if mat == GridRef.SAND:
					var amt := float(_grid.amount[i])
					var w := clampf(float(_grid.wetness[i]), 0.0, 1.0)
					hard = clampf(float(_grid.hardness[i]), 0.0, 1.0)
					r = 0.75 + (0.36 - 0.75) * w
					g = 0.69 + (0.29 - 0.69) * w
					b = 0.51 + (0.19 - 0.51) * w
					var h := hard * 0.9
					r += (0.67 - r) * h
					g += (0.65 - g) * h
					b += (0.57 - b) * h
					if w > mud and hard < hard_threshold:
						r += (0.31 - r) * 0.35
						g += (0.27 - g) * 0.35
						b += (0.16 - b) * 0.35
					# Amount is the pile's visible mass. A loose dusting and a
					# creature-made heap share a material but not a silhouette.
					var dark := 1.0 - clampf(0.34 - amt * 0.12, 0.0, 0.34)
					r *= dark
					g *= dark
					b *= dark
				elif mat == GridRef.WATER:
					var t := clampf(float(_grid.amount[i]), 0.0, 1.0)
					r = 0.055 + (0.17 - 0.055) * t
					g = 0.16 + (0.42 - 0.16) * t
					b = 0.30 + (0.63 - 0.30) * t
				elif mat == GridRef.FOOD:
					var n := clampf(float(_grid.nutrition[i]), 0.0, 1.0)
					r = 0.27 + (0.44 - 0.27) * n
					g = 0.20 + (0.66 - 0.20) * n
					b = 0.10 + (0.24 - 0.10) * n
					var tox := float(_grid.toxicity[i])
					# A full food cell is a cache; a grazed trace is a living shred.
					# Brightness carries that amount so a stockpile is visible as a
					# cluster, not inferred from a number in the HUD.
					var food_amount := clampf(float(_grid.amount[i]), 0.0, 1.0)
					var pile := 0.62 + 0.38 * food_amount
					r *= pile
					g *= pile
					b *= pile
					if tox > 0.01:
						var u := clampf(tox, 0.0, 1.0) * 0.85
						r += (0.35 - r) * u
						g += (0.22 - g) * u
						b += (0.38 - b) * u
				if _story != null:
					contest_heat = _story.contest_heat(i)
			# A contested place is a property of the event history, not a cell
			# tag: the red fades as the last dispute recedes. It sits on top of
			# whatever material is there, so a contested cache and a contested
			# pond read the same way.
			if contest_heat > 0.01:
				r += (0.70 - r) * contest_heat
				g += (0.16 - g) * contest_heat
				b += (0.12 - b) * contest_heat
			var grain := grain_tile[ly * cw + lx] * (1.0 + hard * 1.2)
			var o := (ly * cw + lx) * 4
			buf[o] = int(clampf(r + grain * 0.03, 0.0, 1.0) * 255.0)
			buf[o + 1] = int(clampf(g + grain * 0.03, 0.0, 1.0) * 255.0)
			buf[o + 2] = int(clampf(b + grain * 0.03, 0.0, 1.0) * 255.0)
			buf[o + 3] = 255
	# set_data updates the existing image instead of allocating a new 16 KB one
	# for every repaint.
	var image: Image = _images[ci]
	image.set_data(cw, cw, false, Image.FORMAT_RGBA8, buf)
	_textures[ci].update(image)


## Deterministic per-cell grain so flat sand still reads as ground, without
## storing a per-cell decorative value.
func _grain(x: int, y: int) -> float:
	var h := (x * 374761393 + y * 668265263) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	return float(h % 1000) / 500.0 - 1.0
