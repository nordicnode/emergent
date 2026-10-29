class_name SimHarm
extends RefCounted

## Contested meals and injury, in one place.
##
## The food contest is the harm event: one hungry creature loses the bite it was
## heading for, and an aggressive, larger winner can turn that loss into an
## injury. This unit owns the dispute counter, the injury counter and damage,
## the opinion events and the log lines. It reads the simulation world through
## the owner reference and knows nothing about scenes or rendering.

const StoreRef := preload("res://sim/creature_store.gd")
const GenomeRef := preload("res://sim/genome.gd")

var food_taken_events := 0
var events := 0
var damage_total := 0.0


## A bite taken in front of a hungry creature that was heading into the same
## patch. Scarcity is what makes it a grievance: a full cell is housekeeping, a
## nearly empty one beside a starving neighbour is a betrayal. A per-pair
## cooldown keeps a long meal from minting an event every tick.
func contest_food(sim: Sim, eater: int, cell: int, amount_before: float) -> void:
	var abundance: float = clampf(amount_before / maxf(sim.grid.food_max, 0.001), 0.0, 1.0)
	if abundance >= sim.params.f("social", "abundance_threshold", 0.9):
		return
	var scarcity: float = 1.0 - abundance
	var gain: float = sim.params.f("social", "food_taken_gain", 0.22)
	var cooldown: float = sim.params.f("social", "food_taken_cooldown_days", 0.01)
	var radius: float = sim.params.f("social", "contact_radius_cells", 2.5) + 0.5
	for j in sim.neighbors.query_radius(sim.store, sim.store.px[eater], sim.store.py[eater], radius):
		if j == eater or j < 0 or j >= sim.store.count or sim.store.alive[j] == 0:
			continue
		# The same cell, not merely the same patch: two creatures grazing side by
		# side from different cells are sharing, not competing. Without this,
		# every crowded patch minted hundreds of grudges and rivalry stopped
		# meaning anything.
		if int(sim.store.aim_cell[j]) != cell:
			continue
		# A well-fed bystander has no grievance. Only a creature that was
		# actually hungry enough to need this meal can feel its loss.
		if sim.store.food_level[j] > 0.65:
			continue
		# And it must have been able to reach this cell. A creature across the
		# patch heading somewhere near it lost nothing it could have eaten; only
		# the neighbour that was about to take this bite was deprived.
		var dx: float = sim.store.px[j] - (float(sim.grid.cell_x(cell)) + 0.5)
		var dy: float = sim.store.py[j] - (float(sim.grid.cell_y(cell)) + 0.5)
		if dx * dx + dy * dy > 1.6 * 1.6:
			continue
		if sim.day() - sim.opinion.last_day(j, eater) < cooldown:
			continue
		var hunger: float = 1.0 - sim.store.food_level[j]
		var delta: float = -gain * scarcity * (0.25 + 0.75 * hunger)
		if delta >= -0.004:
			continue
		food_taken_events += 1
		sim.add_opinion(j, eater, delta, "disputed meals")
		# Losing the meal is the grievance; an aggressive winner can turn the
		# same contest into an injury. It is the same event read one step further,
		# not a fight action or a separate encounter.
		var injured := try_harm(sim, eater, j, scarcity)
		# The place view and the contested tint read the event where it happened;
		# the opinion above remains the only thing a creature remembers.
		sim.story.note_contest(sim, cell, eater, j, injured)


## A contested meal becomes an injury when the winner is aggressive, larger, and
## not fond of the loser, and the loser is already vulnerable. Damage is health,
## the victim's safety takes an immediate shock, and both sides remember it. The
## food-dispute cooldown already rate-limits this path, so a long meal cannot
## mint one injury per tick.
func try_harm(sim: Sim, attacker: int, victim: int, scarcity: float) -> bool:
	if not sim.social_enabled:
		return false
	if attacker < 0 or victim < 0 or attacker >= sim.store.count or victim >= sim.store.count:
		return false
	if sim.store.alive[attacker] == 0 or sim.store.alive[victim] == 0 or attacker == victim:
		return false
	var aggression: float = sim.store.body_value(attacker, GenomeRef.F_AGGRESSION)
	if aggression < sim.params.f("social", "harm_aggression_threshold", 0.60):
		return false
	var health_before: float = sim.store.health[victim]
	# Vulnerability is a low body or a hungry one. The dispute gate already
	# bounds the loser at 0.65 food; requiring near-starvation here would mean an
	# injury only ever lands once the victim is already dying, which natural
	# runs showed never happens (231 disputes, every victim at full health).
	var vulnerable: bool = health_before <= sim.params.f("social", "harm_vulnerable_health", 0.60) or sim.store.food_level[victim] <= sim.params.f("social", "harm_vulnerable_food", 0.55)
	if not vulnerable:
		return false
	var size_attacker: float = maxf(sim.store.body_value(attacker, GenomeRef.F_SIZE), 0.01)
	var size_victim: float = maxf(sim.store.body_value(victim, GenomeRef.F_SIZE), 0.01)
	var size_ratio: float = size_attacker / size_victim
	if size_ratio < sim.params.f("social", "harm_size_ratio", 0.95):
		return false
	# A creature does not injure someone it likes. The opponent's opinion is
	# not read: the attacker's own memory is what makes the contest personal.
	if sim.opinion.opinion(sim.store, attacker, victim, sim.day()) > 0.05:
		return false
	var damage: float = sim.params.f("social", "harm_damage", 0.08) * clampf(size_ratio, 0.8, 1.4) * (1.0 + 0.5 * (1.0 - health_before)) * (0.75 + 0.5 * clampf(scarcity, 0.0, 1.0))
	damage = minf(damage, health_before)
	if damage <= 0.0001:
		return false
	sim.store.health[victim] = maxf(0.0, health_before - damage)
	events += 1
	damage_total += damage
	if sim.safety_enabled:
		# The injury is a shock, not just another tick of proximity decay. The
		# negative opinion written below keeps the pressure on after the shock
		# fades, so the victim can choose to flee in the next decision.
		sim.safety.shock(sim, victim, sim.params.f("social", "harm_safety_shock", 0.35))
	sim.add_opinion(victim, attacker, -sim.params.f("social", "harm_opinion_gain", 0.45), "being harmed")
	sim.add_opinion(attacker, victim, -sim.params.f("social", "harm_attacker_opinion", 0.08), "harming a rival")
	var victim_opinion: float = sim.opinion.opinion(sim.store, victim, attacker, sim.day())
	sim.log.push(
		sim.time,
		"harm",
		"Creature %d harmed %d over a contested meal — %d%% health lost, safety %d%%, opinion %+.2f." % [
			attacker, victim, int(round(damage * 100.0)), int(round(sim.store.safety_level[victim] * 100.0)), victim_opinion
		],
		victim
	)
	if sim.store.health[victim] <= 0.0:
		sim.queue_death(victim, StoreRef.Death.HARM)
	return true
