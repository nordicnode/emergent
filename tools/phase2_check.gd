extends SceneTree

## Temporary focused check while the full suite is too slow to iterate on.
## Runs only the Phase 2 detector and history tests.

const ParamsRef := preload("res://sim/params.gd")
const SuiteRef := preload("res://sim/tests/sim_suite.gd")


func _initialize() -> void:
	var suite = SuiteRef.new()
	suite.set_params(ParamsRef.load_default())
	suite._section("phase 2 detectors and history")
	suite._test_detectors()
	suite._test_history()
	suite._section("reproduction gate")
	suite._test_reproduction()
	print("")
	print("phase 2 focused checks: %d checks, %d failures" % [suite._checks, suite._failures])
	quit(1 if suite._failures > 0 else 0)
