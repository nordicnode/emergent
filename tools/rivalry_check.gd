extends SceneTree

const ParamsRef := preload("res://sim/params.gd")
const StoriesRef := preload("res://sim/tests/phase1_stories.gd")


func _initialize() -> void:
	var params = ParamsRef.load_default()
	var stories = StoriesRef.new()
	stories.set_params(params)
	stories._story_params = stories._small_world_params()
	stories._test_rivalry()
	var base: Dictionary = stories._rivalry_run()
	var sim = base["sim"]
	var pair: Array = stories._rival_pair(sim)
	print("pair=%s" % str(pair))
	if pair.size() == 2:
		print("evidence=%s" % str(sim.story.inspector_evidence(sim, int(pair[0]))))
		print("all=%s" % str(sim.opinion.top_opinions(sim.store, int(pair[0]), sim.day(), 8)))
	quit(0)
