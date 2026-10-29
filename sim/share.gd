class_name SimShare
extends RefCounted

## Carried-food sharing, in one place.
##
## A share rides the socialise verb, but it is its own event: a real material
## transfer, a per-giver cooldown, a counter and one log line. The simulation
## supplies the world this unit reads; nothing here knows about scenes or
## rendering.

const GridRef := preload("res://sim/grid.gd")

var events := 0
var _last_day := PackedFloat32Array()
var _birth := PackedFloat32Array()


func ensure(n: int) -> void:
	if _last_day.size() >= n:
		return
	var old := _last_day.size()
	_last_day.resize(n)
	_birth.resize(n)
	for k in range(old, n):
		_last_day[k] = -100.0
		_birth[k] = -1.0


## The day of this creature's last share. A reused slot starts blank: the
## previous occupant's clock must not follow the new body.
func last_day(sim: Sim, giver: int) -> float:
	ensure(sim.store.count)
	if _birth[giver] != sim.store.birth_time[giver]:
		_last_day[giver] = -100.0
		_birth[giver] = sim.store.birth_time[giver]
	return _last_day[giver]


## One carried meal transferred to a hungry partner during socialise. The giver
## must be in surplus and the load real; the recipient must be hungry and not
## hostile. Sharing is a physical transfer, so it has its own slower clock even
## though it rides the socialise verb: one exchange cannot empty a load.
func try_share(sim: Sim, giver: int, recipient: int) -> bool:
	if not sim.social_enabled or not sim.carry_enabled:
		return false
	if giver < 0 or recipient < 0 or giver >= sim.store.count or recipient >= sim.store.count:
		return false
	if sim.store.alive[giver] == 0 or sim.store.alive[recipient] == 0:
		return false
	if int(sim.store.carry_material[giver]) != GridRef.FOOD or sim.store.carry_amount[giver] <= 0.001:
		return false
	var amount: float = minf(sim.store.carry_amount[giver], sim.params.f("social", "share_amount", 0.15))
	if amount <= 0.001 or sim.store.food_level[giver] < sim.params.f("social", "share_surplus", 0.55):
		return false
	if sim.store.food_level[recipient] > sim.params.f("social", "share_hunger", 0.60):
		return false
	if sim.store.carry_nutrition[giver] <= 0.01:
		return false
	var now: float = sim.day()
	if now - last_day(sim, giver) < sim.params.f("social", "share_cooldown_days", 0.10):
		return false
	var opinion_giver: float = sim.opinion.opinion(sim.store, giver, recipient, now) if sim.opinion_enabled else 0.0
	var opinion_recipient: float = sim.opinion.opinion(sim.store, recipient, giver, now) if sim.opinion_enabled else 0.0
	var floor: float = sim.params.f("social", "share_min_opinion", -0.05)
	if opinion_giver < floor or opinion_recipient < floor:
		return false
	var hunger_before: float = sim.store.food_level[recipient]
	sim.store.carry_amount[giver] -= amount
	if sim.store.carry_amount[giver] <= 0.001:
		sim.clear_carry(giver)
	var relief: float = amount * sim.store.carry_nutrition[giver] * sim.params.f("metabolism", "hunger_relief_per_food", 1.4)
	sim.store.food_level[recipient] = minf(1.0, sim.store.food_level[recipient] + relief)
	_last_day[giver] = now
	events += 1
	# The recipient's gratitude is stronger when the meal was needed; the giver
	# also remembers the act, at a smaller weight. Both are ordinary opinion
	# events, so they decay and can be overwritten like any other memory.
	var credit: float = sim.params.f("social", "share_opinion_gain", 0.25)
	var gratitude: float = credit * (0.5 + 0.5 * (1.0 - hunger_before))
	sim.add_opinion(recipient, giver, gratitude, "shared food")
	sim.add_opinion(giver, recipient, credit * sim.params.f("social", "share_giver_credit", 0.5), "sharing food")
	var recipient_opinion: float = sim.opinion.opinion(sim.store, recipient, giver, now)
	sim.log.push(
		sim.time,
		"social",
		"Creature %d shared %.2f food with %d — recipient hunger %d%%, opinion %+.2f." % [
			giver, amount, recipient, int(round(hunger_before * 100.0)), recipient_opinion
		],
		giver
	)
	return true
