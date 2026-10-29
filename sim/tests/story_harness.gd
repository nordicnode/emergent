class_name Phase1StoryHarness
extends RefCounted

## Reusable disable-one-system runner for the Phase 1 exit stories. A story
## supplies a setup callback that returns a fresh Sim; this harness applies at
## most one named switch, optionally acts as the player each tick, and runs the
## real fixed tick. Nothing here reaches into creature state.

const SWITCHES := {
	"hardening": "hardening_enabled",
	"stress": "stress_weighting",
	"opinion": "opinion_enabled",
	"carry": "carry_enabled",
}


static func run(params, setup: Callable, steps: int, ablate: String = "", each_tick: Callable = Callable()) -> Dictionary:
	var sim = setup.call(params)
	if ablate != "":
		if not SWITCHES.has(ablate):
			push_error("unknown ablation '%s'" % ablate)
			return {"sim": sim, "ablation": ablate, "error": true}
		sim.set(String(SWITCHES[ablate]), false)
	for _s in steps:
		sim.step(sim.dt)
		if each_tick.is_valid():
			each_tick.call(sim)
	return {"sim": sim, "ablation": ablate, "error": false}


static func names() -> Array:
	return SWITCHES.keys()
