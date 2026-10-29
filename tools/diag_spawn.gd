extends SceneTree

## Spawn audit: how far is each founder from the nearest water and food at t=0?
##   godot --headless --path . --script res://tools/diag_spawn.gd -- --seed=202

const ParamsRef := preload("res://sim/params.gd")
const SimRef := preload("res://sim/sim.gd")
const GridRef := preload("res://sim/grid.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := int(_arg(args, "--seed=", "202"))
	var params = ParamsRef.load_default()
	var sim = SimRef.new(params, seed_value)
	sim.generate_world()
	sim.spawn_founders()
	var water: Array[int] = []
	var food: Array[int] = []
	for i in sim.grid.water_cell_snapshot():
		if int(sim.grid.material[i]) == GridRef.WATER:
			water.append(i)
	for i in sim.grid.food_cell_snapshot():
		if int(sim.grid.material[i]) == GridRef.FOOD:
			food.append(i)
	var dw: Array[float] = []
	var df: Array[float] = []
	var within_w := 0
	var within_f := 0
	for c in sim.store.count:
		if int(sim.store.alive[c]) == 0:
			continue
		var bw := 1e9
		for i in water:
			bw = minf(bw, Vector2(sim.store.px[c] - float(i % sim.grid.width), sim.store.py[c] - float(i / sim.grid.width)).length())
		var bf := 1e9
		for i in food:
			bf = minf(bf, Vector2(sim.store.px[c] - float(i % sim.grid.width), sim.store.py[c] - float(i / sim.grid.width)).length())
		dw.append(bw)
		df.append(bf)
		if bw <= 18.0:
			within_w += 1
		if bf <= 18.0:
			within_f += 1
	dw.sort()
	df.sort()
	print("seed %d founders %d | water within 18: %d, median %.0f, max %.0f | food within 18: %d, median %.0f, max %.0f" % [
		seed_value, dw.size(), within_w, dw[dw.size() / 2], dw[dw.size() - 1],
		within_f, df[df.size() / 2], df[df.size() - 1],
	])
	quit(0)


func _arg(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for arg in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback
