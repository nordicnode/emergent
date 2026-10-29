extends SceneTree

## Headless test runner:
##   godot --headless --path . --script res://tools/run_tests.gd

const ParamsRef := preload("res://sim/params.gd")
const SuiteRef := preload("res://sim/tests/sim_suite.gd")


func _initialize() -> void:
	var params = ParamsRef.load_default()
	var suite = SuiteRef.new()
	suite.set_params(params)
	var result: Array = suite.run_all()
	quit(1 if int(result[1]) > 0 else 0)
