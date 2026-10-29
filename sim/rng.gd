class_name SimRng
extends RefCounted

## Seeded random source for the simulation.
## Every stochastic decision flows through here so a seed reproduces a world,
## and the generator state can be written to a save file.
## Engine RNG only: no scene, node or rendering types.

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 1) -> void:
	_rng.seed = seed_value


func randf() -> float:
	return _rng.randf()


func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


func chance(p: float) -> bool:
	return _rng.randf() < p


func gaussian(mean: float = 0.0, deviation: float = 1.0) -> float:
	return _rng.randfn(mean, deviation)


func get_state() -> int:
	return _rng.state


func set_state(state: int) -> void:
	_rng.state = state
