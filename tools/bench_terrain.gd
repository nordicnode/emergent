extends SceneTree

const GridRef := preload("res://sim/grid.gd")
const TerrainRef := preload("res://render/terrain_view.gd")


func _initialize() -> void:
	var grid = GridRef.new(512, 384, 64, 8, {"sand": 4.0, "water": 1.0, "food": 1.0})
	for y in grid.height:
		for x in grid.width:
			grid.set_cell(x, y, GridRef.SAND, 0.8)
	for y in range(80, 120):
		for x in range(80, 140):
			grid.set_cell(x, y, GridRef.WATER, 0.9)
			grid.wetness[grid.index(x, y + 4)] = 0.7
			grid.hardness[grid.index(x, y + 6)] = 0.6
			grid.amount[grid.index(x, y + 8)] = 0.5
	var view = TerrainRef.new()
	root.add_child(view)
	var t0 := Time.get_ticks_usec()
	view.setup(grid)
	print("setup (%d chunks + repaint_all): %.2f ms" % [view._textures.size(), float(Time.get_ticks_usec() - t0) / 1000.0])
	var full := Rect2i(0, 0, 64, 64)
	for pass_i in 3:
		t0 = Time.get_ticks_usec()
		for k in 20:
			view._paint_chunk_rect(k % view._textures.size(), full)
		print("20 full chunk repaints: %.2f ms (%.3f ms/chunk)" % [
			float(Time.get_ticks_usec() - t0) / 1000.0,
			float(Time.get_ticks_usec() - t0) / 1000.0 / 20.0,
		])
	var one := Rect2i(10, 10, 1, 1)
	var cells := 4000
	t0 = Time.get_ticks_usec()
	for k in cells:
		view._paint_chunk_rect(0, one)
	print("%d single-cell repaints: %.2f ms (%.4f ms each)" % [
		cells, float(Time.get_ticks_usec() - t0) / 1000.0,
		float(Time.get_ticks_usec() - t0) / 1000.0 / float(cells),
	])
	quit(0)
