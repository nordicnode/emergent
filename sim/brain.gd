class_name SimBrain
extends RefCounted

## Utility chooser over generic verbs. No verb is named after a behaviour;
## nothing here knows what a shelter, a cache, a friend or a feud is. Opinion is
## read as one more consideration on approach, socialise and avoid, and as a
## discount on a contested meal, so the same memory produces a bold creature's
## contest and a timid one's retreat.
##
## Pick up and pile are the generic store verbs. Pick up is offered when the
## creature has a surplus to move or ground poor enough to improve; pile is
## offered while carrying and values a cell by what the load would do there
## (food away from a patch is a cache; wet sand on dry ground starts the
## hardening chain). Comfort is read from cell properties at query time, so a
## cell that dried hard after being piled and rested on becomes a comfortable
## place without any cell being tagged as one.
##
## Every candidate score is recorded with its components so the inspector can
## answer "why did it do that?" from the same numbers the choice was made from.

const GridRef := preload("res://sim/grid.gd")
const StoreRef := preload("res://sim/creature_store.gd")
const NeedsRef := preload("res://sim/needs.gd")
const GenomeRef := preload("res://sim/genome.gd")
const MemoryRef := preload("res://sim/memory.gd")


class Decision:
	var verb: int = 0
	var aim_x: float = 0.0
	var aim_y: float = 0.0
	var aim_cell: int = -1
	var aim_creature: int = -1
	var scores: Array = []
	var label: String = ""
	## Recorded so the learning rule knows what was pressing and what state the
	## action was chosen in. Sampling temperature uses survival distress only;
	## the recorded stress includes comfort because a rest can be driven by
	## comfort even when no survival need is pressing.
	var stress: float = 0.0
	var context: int = 0


## Curves, setpoints, boldness and curiosity all come from the creature's own
## body, so two creatures with identical needs can still choose differently.
## The reproduction arguments are the gate's verdict and the partner search
## result; the brain only turns them into candidate scores.
static func decide(
	store: CreatureStore,
	i: int,
	grid: SimGrid,
	params: SimParams,
	rng: SimRng,
	sensory_radius: float,
	mate_ready: bool = false,
	partner_id: int = -1,
	partner_dist: float = 0.0,
	memory: SimMemory = null,
	day: float = 0.0,
	opinion: SimOpinion = null,
	neighbors = null,
	social_ready: bool = true,
	carry_enabled: bool = true,
	safety_enabled: bool = true
) -> Decision:
	var d := Decision.new()
	var x: float = store.px[i]
	var y: float = store.py[i]

	# Urgency reads the raw level; setpoints only decide how far a creature tops
	# itself up. Normalising by setpoint here would quietly flatten every
	# urgency as the setpoint rose, which is a behaviour change disguised as a
	# gene, not a trade-off.
	var hunger_u := NeedsRef.urgency(1.0 - store.food_level[i], store.body_value(i, GenomeRef.F_HUNGER_EXP))
	var thirst_u := NeedsRef.urgency(1.0 - store.water_level[i], store.body_value(i, GenomeRef.F_THIRST_EXP))
	var energy_u := NeedsRef.urgency(1.0 - store.energy_level[i], store.body_value(i, GenomeRef.F_ENERGY_EXP))
	var social_u := NeedsRef.urgency(1.0 - store.social_level[i], params.f("needs", "social_curve_exp", 1.8))
	var comfort_u := NeedsRef.urgency(1.0 - store.comfort_level[i], params.f("needs", "comfort_curve_exp", 1.6))
	# Safety reads a curve shape of its own, so two creatures with the same fright
	# can differ in how urgently they act on it. Like social and comfort it is
	# outside the sampling temperature: it decides whether to run, not how
	# erratically every other choice is made. The ablation switch zeroes it here
	# as well as in the world, so a disabled safety need cannot leak into another
	# system's context or stress.
	var safety_u := 0.0
	if safety_enabled:
		safety_u = NeedsRef.urgency(1.0 - store.safety_level[i], store.body_value(i, GenomeRef.F_SAFETY_EXP))
	# Social and comfort needs are deliberately outside distress: their urgency
	# changes what a creature wants to do, not how erratically it chooses. Only
	# survival needs raise the sampling temperature.
	var distress := maxf(hunger_u, maxf(thirst_u, energy_u))
	# Context is the need that dominates right now, however mildly. A threshold
	# high enough to mean "really hungry" would file ordinary meals under
	# content, and a lesson learned while content would never apply to the
	# hunger that drove the meal. Content is only for a creature with nothing
	# pressing at all.
	var context_floor := params.f("memory", "context_content_threshold", 0.05)
	var context := MemoryRef.CONTEXT_CONTENT
	var pressing := maxf(distress, maxf(comfort_u, safety_u))
	if pressing >= context_floor:
		context = 0
		# Acute fear is its own context: a meal eaten while running from a rival
		# and a meal eaten while hungry are different lessons, and the flee verb
		# learns in the first one. The check is the same comparison the other
		# contexts use, not a priority ladder.
		if safety_u > hunger_u and safety_u > thirst_u and safety_u > energy_u and safety_u > comfort_u:
			context = MemoryRef.CONTEXT_AFRAID
		elif thirst_u > hunger_u and thirst_u >= energy_u and thirst_u >= comfort_u:
			context = 1
		elif energy_u > hunger_u and energy_u > thirst_u and energy_u >= comfort_u:
			context = 2
		elif comfort_u > hunger_u and comfort_u > thirst_u and comfort_u > energy_u:
			context = MemoryRef.CONTEXT_UNCOMFORTABLE
	d.context = context
	d.stress = maxf(distress, maxf(comfort_u, safety_u))
	var curiosity := store.body_value(i, GenomeRef.F_CURIOSITY)
	var boldness := store.body_value(i, GenomeRef.F_BOLDNESS)
	var sociality := store.body_value(i, GenomeRef.F_SOCIALITY)
	var aggression := store.body_value(i, GenomeRef.F_AGGRESSION)
	var conscientiousness := store.body_value(i, GenomeRef.F_CONSCIENTIOUSNESS)
	var cons_factor := 0.2 + 1.6 * conscientiousness
	var carry_capacity := maxf(GenomeRef.carry_capacity(store, i), 0.01)
	var carry_mass := store.carry_amount[i] * grid.density_of(int(store.carry_material[i]))
	var load_fraction := clampf(carry_mass / carry_capacity, 0.0, 1.0)
	# Boldness discounts distance: a bold creature crosses more ground for the
	# same advertised value. It pays in exposure, which Phase 2 adds.
	var dist_scale := params.f("brain", "distance_cost_scale", 0.5) * (1.25 - 0.55 * boldness)
	var own_cell: int = grid.index(int(floor(x)), int(floor(y)))
	var current_quality := grid.comfort_quality(own_cell)
	var current_protection := grid.protection_quality(own_cell)
	var greed_threshold := params.f("carry", "surplus_threshold", 0.55)
	# Pick-up is a surplus activity. A creature near water zero has to spend its
	# next movement and commitment on thirst, not on another handful of sand; the
	# gate is a need threshold, not a ban on carrying, so a mildly thirsty creature
	# can still finish a useful load. Pile is deliberately not gated: a parched
	# carrier must be able to shed the load and its speed penalty on the way to
	# water. The same verb serves a cache, a structure and an emergency drop.
	var pickup_ready := thirst_u < params.f("carry", "thirst_suppress", 0.60)

	# Social perception. One bounded neighbour query finds everyone this
	# creature could approach, socialise with, or prefer to keep away from. The
	# best and worst remembered creatures are tracked separately because a
	# crowd can hold both a friend and a rival.
	var social_reach := params.f("social", "contact_radius_cells", 2.5)
	var social_weight := params.f("social", "socialise_weight", 0.9)
	var share_weight := params.f("social", "share_weight", 1.6)
	var share_surplus := params.f("social", "share_surplus", 0.55)
	var share_hunger := params.f("social", "share_hunger", 0.60)
	var share_min_opinion := params.f("social", "share_min_opinion", -0.05)
	var share_amount := params.f("social", "share_amount", 0.15)
	# A share is a socialise exchange with food in it, not a separate verb. It
	# is only worth offering when the load is real, the giver is not hungry, and
	# the partner is. Carrying disabled removes the material but not the door.
	var share_ready := social_ready and carry_enabled and int(store.carry_material[i]) == GridRef.FOOD and store.carry_amount[i] >= share_amount and store.food_level[i] >= share_surplus
	var notice := minf(sensory_radius, params.f("social", "notice_radius_cells", 12.0))
	var near: Array = []
	var in_contact := -1
	var in_contact_val := -2.0
	var in_contact_dist := 1.0e9
	var seen_positive := -1
	var seen_positive_val := -2.0
	var seen_positive_dist := 0.0
	var seen_negative := -1
	var seen_negative_val := 0.0
	var seen_negative_dist := 0.0
	# Best hungry partner for a food share. Chosen by need and opinion, not by
	# an action name: the same socialise verb carries the meal.
	var share_target := -1
	var share_score := -1.0
	# A threat is not a species or a flag: it is a creature this one has come to
	# dislike, weighted by how close it is and how much bigger it is. Opinion is
	# the memory; body size is the observable danger. Strangers are not threats.
	var threat_reach := params.f("safety", "notice_radius_cells", 12.0)
	var threat_threshold := params.f("safety", "threat_opinion_threshold", 0.0)
	var threat_id := -1
	var threat_value := 0.0
	var threat_dist := 0.0
	var threat_strength := 0.0
	if opinion != null and neighbors != null:
		near = neighbors.query_radius(store, x, y, notice)
		for j in near:
			if j == i or j < 0 or j >= store.count or store.alive[j] == 0:
				continue
			if mate_ready and j == partner_id:
				continue
			var value := opinion.opinion(store, i, j, day)
			var dx := store.px[j] - x
			var dy := store.py[j] - y
			var dist := sqrt(dx * dx + dy * dy)
			# Ties go to the nearest creature, so repeated meetings concentrate on
			# neighbours and a friendship can actually accumulate instead of being
			# spread one point at a time across a shifting crowd.
			if dist <= social_reach and (value > in_contact_val + 0.001 or (absf(value - in_contact_val) <= 0.001 and dist < in_contact_dist)):
				in_contact = j
				in_contact_val = value
				in_contact_dist = dist
			if value > seen_positive_val:
				seen_positive = j
				seen_positive_val = value
				seen_positive_dist = dist
			if value < seen_negative_val:
				seen_negative = j
				seen_negative_val = value
				seen_negative_dist = dist
			if share_ready and dist <= social_reach and store.food_level[j] <= share_hunger and value >= share_min_opinion:
				var need := 1.0 - store.food_level[j]
				var pull := need * (0.5 + 0.5 * maxf(value, 0.0)) / (1.0 + dist * 0.1)
				if pull > share_score:
					share_score = pull
					share_target = j
			if safety_enabled and value < threat_threshold and dist < threat_reach:
				var size_me := maxf(store.body_value(i, GenomeRef.F_SIZE), 0.01)
				var size_factor := clampf(store.body_value(j, GenomeRef.F_SIZE) / size_me, 0.6, 1.6)
				var proximity := 1.0 - clampf(dist / maxf(threat_reach, 0.5), 0.0, 1.0)
				var strength := (-value) * size_factor * (0.25 + 0.75 * proximity)
				if strength > threat_strength:
					threat_strength = strength
					threat_id = j
					threat_value = value
					threat_dist = dist

	var candidates: Array = []

	# Wander. A baseline disposition to be somewhere else, strongest when no
	# need is pressing. Never zero, so a creature with nothing to do still lives.
	var wander_base := params.f("brain", "wander_base", 0.10)
	var wander_bonus := params.f("brain", "wander_content_bonus", 0.30)
	candidates.append({
		"label": "wander",
		"verb": StoreRef.Verb.WANDER,
		"score": (wander_base + wander_bonus * (1.0 - distress)) * (0.70 + 0.60 * curiosity),
		"aim_cell": -1,
		"parts": {"contentment": 1.0 - distress, "curiosity": curiosity},
	})

	# Eat: only available when food is already within reach. Approaching food is
	# the generic seek verb, not a special case.
	var food_reach := _best_adjacent(grid, x, y, GridRef.FOOD)
	if int(food_reach[0]) >= 0:
		var food_quality: float = food_reach[1]
		var eat_score := params.f("brain", "eat_base", 0.08) + 0.95 * hunger_u * food_quality
		# A meal with a disliked creature at the same patch is a contest. An
		# aggressive creature takes the contested bite more readily; a calm one
		# is slightly put off by the company. Sharing is not coded here; this is
		# only how strongly the eater wants the disputed cell.
		if opinion != null:
			for j in near:
				if j == i or j < 0 or j >= store.count or store.alive[j] == 0:
					continue
				if store.food_level[j] > 0.7:
					continue
				var dx := store.px[j] - x
				var dy := store.py[j] - y
				if sqrt(dx * dx + dy * dy) > social_reach:
					continue
				if opinion.opinion(store, i, j, day) >= -0.05:
					continue
				eat_score *= 1.0 + params.f("social", "contest_aggression_bonus", 0.35) * aggression
				break
		candidates.append({
			"label": "eat",
			"verb": StoreRef.Verb.EAT,
			"score": eat_score,
			"aim_cell": int(food_reach[0]),
			"parts": {"hunger_urgency": hunger_u, "food_quality": food_quality},
		})

	# A carried meal is at hand even when no food cell is. This is the same eat
	# verb consuming the load, not a separate behaviour: a starving carrier
	# eats rather than standing beside its own food.
	if int(store.carry_material[i]) == GridRef.FOOD and store.carry_amount[i] > 0.001 and hunger_u > 0.05:
		var carried_quality := clampf(store.carry_amount[i] * store.carry_nutrition[i], 0.0, 1.0)
		candidates.append({
			"label": "eat_carried",
			"verb": StoreRef.Verb.EAT,
			"score": params.f("brain", "eat_base", 0.08) + 0.95 * hunger_u * carried_quality,
			"aim_cell": -1,
			"parts": {"hunger_urgency": hunger_u, "carried_amount": store.carry_amount[i], "nutrition": store.carry_nutrition[i]},
		})

	var water_reach := _best_adjacent(grid, x, y, GridRef.WATER)
	if int(water_reach[0]) >= 0:
		var water_quality: float = water_reach[1]
		var drink_score := params.f("brain", "drink_base", 0.08) + 0.95 * thirst_u * water_quality
		candidates.append({
			"label": "drink",
			"verb": StoreRef.Verb.DRINK,
			"score": drink_score,
			"aim_cell": int(water_reach[0]),
			"parts": {"thirst_urgency": thirst_u, "water_quality": water_quality},
		})

	if carry_enabled and pickup_ready:
		var carry_mat := int(store.carry_material[i])
		var carrying := store.carry_amount[i] > 0.001
		var avoid_cell := -1
		if store.pile_cell[i] >= 0 and day - store.pile_day[i] < params.f("carry", "repick_cooldown_days", 0.02):
			avoid_cell = store.pile_cell[i]
		# A creature can keep filling a load of the material already in its hands
		# until the load is full; that is what gives the pick-up action enough
		# commitment to reach a useful amount instead of one tick's handful.
		var can_take_food := (not carrying or carry_mat == GridRef.FOOD) and (not carrying or load_fraction < 0.98)
		var can_take_sand := (not carrying or carry_mat == GridRef.SAND) and (not carrying or load_fraction < 0.98)
		# Food is picked up only out of surplus. A hungry creature eats where it
		# stands; one that is full can carry a meal to somewhere it prefers. The
		# conscientiousness gene weights the store action, never food choice.
		if can_take_food:
			var surplus := clampf(store.food_level[i] - greed_threshold, 0.0, 1.0)
			if surplus > 0.0:
				var food_pick := _best_pickup(grid, x, y, GridRef.FOOD, avoid_cell)
				if int(food_pick[0]) >= 0:
					var pile_abundance: float = clampf(float(food_pick[2]) / maxf(grid.food_max, 0.001), 0.0, 1.0)
					candidates.append({
						"label": "pickup_food",
						"verb": StoreRef.Verb.PICKUP,
						"score": params.f("carry", "pickup_base", 0.03) + params.f("carry", "pickup_food_weight", 0.30) * cons_factor * surplus * pile_abundance,
						"aim_cell": int(food_pick[0]),
						"parts": {"surplus": surplus, "conscientiousness": conscientiousness, "source_amount": float(food_pick[2]), "load_fraction": load_fraction},
					})
		# Sand is picked up when the ground here is poor for comfort. Wet sand is
		# easier to handle (cohesion), which is how the wet half of the hardening
		# chain enters a creature's load without the creature knowing chemistry.
		if can_take_sand and comfort_u > 0.2 and current_quality < 0.45:
			var sand_pick := _best_pickup(grid, x, y, GridRef.SAND, avoid_cell)
			if int(sand_pick[0]) >= 0:
				var wet_bonus: float = 0.5 + params.f("carry", "wet_pickup_bonus", 0.5) * float(sand_pick[3])
				candidates.append({
					"label": "pickup_sand",
					"verb": StoreRef.Verb.PICKUP,
					"score": params.f("carry", "pickup_base", 0.03) + params.f("carry", "pickup_sand_weight", 0.40) * comfort_u * cons_factor * wet_bonus * (1.0 - 0.5 * current_quality),
					"aim_cell": int(sand_pick[0]),
					"parts": {"comfort_urgency": comfort_u, "conscientiousness": conscientiousness, "source_wetness": float(sand_pick[3]), "ground_quality": current_quality, "load_fraction": load_fraction},
				})

	# Pile. Food is worth carrying away from a patch to a place with none, which
	# is the physical origin of a cache; sand is worth piling where the ground is
	# poor and the cell is dry enough to go through the hardening chain. Neither
	# score asks what a cache or a shelter is.
	if carry_enabled and store.carry_amount[i] > 0.001:
		var carried_mat := int(store.carry_material[i])
		var deposit_cell := _best_deposit(grid, x, y, carried_mat)
		# A handful is not worth a trip: pile value grows with how much of the
		# load is filled, so a creature finishes picking before it dumps the load.
		var load_factor := 0.2 + 0.8 * load_fraction
		if deposit_cell >= 0:
			if carried_mat == GridRef.FOOD:
				var cache_value: float = 1.0 - _local_food_abundance(grid, deposit_cell, 2)
				candidates.append({
					"label": "pile_food",
					"verb": StoreRef.Verb.PILE,
					"score": params.f("carry", "pickup_base", 0.03) + params.f("carry", "food_cache_weight", 0.32) * cons_factor * clampf(cache_value, 0.0, 1.0) * (0.5 + 0.5 * (1.0 - hunger_u)) * load_factor,
					"aim_cell": deposit_cell,
					"parts": {"carried_amount": store.carry_amount[i], "cache_value": clampf(cache_value, 0.0, 1.0), "conscientiousness": conscientiousness},
				})
			else:
				# Water is wet regardless of its stored wetness field. Filling a pond
				# is possible, but it is not a comfortable building site.
				var site_wetness: float = 1.0 if int(grid.material[deposit_cell]) == GridRef.WATER else float(grid.wetness[deposit_cell])
				var site_dryness: float = 1.0 - site_wetness
				var room: float = clampf(1.0 - float(grid.amount[deposit_cell]) / maxf(grid.sand_max, 0.001), 0.0, 1.0)
				var softness: float = 1.0 - float(grid.hardness[deposit_cell])
				# Piling onto a hard or full cell improves nothing. The store score
				# reads the cell's capacity to take material, not a construction plan.
				candidates.append({
					"label": "pile_sand",
					"verb": StoreRef.Verb.PILE,
					"score": params.f("carry", "pickup_base", 0.03) + params.f("carry", "sand_pile_weight", 0.32) * cons_factor * (0.25 + 0.75 * comfort_u) * (0.35 + 0.65 * site_dryness) * (0.25 + 0.75 * room) * softness * load_factor,
					"aim_cell": deposit_cell,
					"parts": {"comfort_urgency": comfort_u, "site_dryness": site_dryness, "room": room, "softness": softness, "conscientiousness": conscientiousness},
				})

	# Seek comfort: when the ground underfoot is poor and a better cell is close,
	# moving there is the generic seek verb aimed by a property, not a place tag.
	var comfort_threshold := params.f("comfort", "seek_threshold", 0.30)
	var quality_threshold := params.f("comfort", "quality_threshold", 0.55)
	var scan_radius := params.f("comfort", "seek_radius_cells", 10.0)
	var scan_cooldown := params.f("comfort", "scan_cooldown_days", 0.005)
	var target_cell := int(store.comfort_cell[i])
	var target_quality := -1.0
	if target_cell >= 0 and target_cell < grid.material.size():
		target_quality = grid.comfort_quality(target_cell)
		var tdx := float(grid.cell_x(target_cell)) + 0.5 - x
		var tdy := float(grid.cell_y(target_cell)) + 0.5 - y
		if target_quality <= current_quality + 0.02 or sqrt(tdx * tdx + tdy * tdy) > scan_radius:
			target_cell = -1
			store.comfort_cell[i] = -1
	if comfort_u > comfort_threshold and current_quality < quality_threshold and target_cell < 0 and day - store.comfort_scan_time[i] >= scan_cooldown:
		store.comfort_scan_time[i] = day
		var comfort_target := _find_comfort(grid, x, y, scan_radius, current_quality)
		target_cell = int(comfort_target.get("cell", -1))
		store.comfort_cell[i] = target_cell
		if target_cell >= 0:
			target_quality = float(comfort_target["quality"])
	if target_cell >= 0 and target_quality > current_quality + 0.02:
		var dxc := float(grid.cell_x(target_cell)) + 0.5 - x
		var dyc := float(grid.cell_y(target_cell)) + 0.5 - y
		var dist_c := sqrt(dxc * dxc + dyc * dyc)
		var gain: float = target_quality - current_quality
		var norm_c := clampf(dist_c / maxf(scan_radius, 1.0), 0.0, 1.0)
		candidates.append({
			"label": "seek_comfort",
			"verb": StoreRef.Verb.SEEK,
			"score": params.f("comfort", "seek_weight", 0.75) * comfort_u * clampf(gain, 0.0, 1.0) * (1.0 - dist_scale * norm_c),
			"aim_cell": target_cell,
			"aim_x": float(grid.cell_x(target_cell)) + 0.5,
			"aim_y": float(grid.cell_y(target_cell)) + 0.5,
			"parts": {"comfort_urgency": comfort_u, "ground_gain": gain, "distance_penalty": dist_scale * norm_c},
		})

	# Remember: seek comfort aims at a cell, and the execution path treats a
	# claimed cell as a resource to reach. It is a property, not a material.

	# Socialise: company within reach. The score rises with the creature's own
	# sociality and with how much it already values the other one, so a lonely
	# creature will sit beside a stranger and a well-connected one seeks a
	# friend. It is not offered while the social cooldown runs, which is what
	# stops a crowd from filling every opinion to the cap in one minute.
	if opinion != null and social_ready and in_contact >= 0 and social_u > 0.05 and in_contact_val > -0.25:
		var affinity := clampf(0.85 + 0.5 * maxf(in_contact_val, 0.0), 0.7, 1.35)
		candidates.append({
			"label": "socialise",
			"verb": StoreRef.Verb.SOCIALISE,
			"score": social_weight * social_u * (0.55 + 0.45 * sociality) * affinity,
			"aim_cell": -1,
			"aim_creature": in_contact,
			"parts": {
				"social_urgency": social_u,
				"sociality": sociality,
				"opinion": in_contact_val,
				"distance": in_contact_dist,
			},
		})

	# Share. The generic socialise verb, aimed at a hungry partner, with a meal
	# from the load as the event. The score is the plan's coincidence: the giver
	# must be in surplus, the partner hungry, and the relationship not hostile.
	if share_target >= 0:
		var share_opinion: float = opinion.opinion(store, i, share_target, day)
		var surplus := clampf(store.food_level[i] - share_surplus, 0.0, 1.0)
		var recipient_hunger := 1.0 - store.food_level[share_target]
		var share_dist := Vector2(store.px[share_target] - x, store.py[share_target] - y).length()
		var affinity := clampf(0.7 + 0.6 * maxf(share_opinion, 0.0), 0.7, 1.3)
		candidates.append({
			"label": "share",
			"verb": StoreRef.Verb.SOCIALISE,
			"score": share_weight * (0.35 + 0.65 * recipient_hunger) * (0.35 + 0.65 * surplus) * (0.55 + 0.45 * sociality) * affinity,
			"aim_cell": -1,
			"aim_creature": share_target,
			"aim_x": store.px[share_target],
			"aim_y": store.py[share_target],
			"parts": {
				"recipient_hunger": recipient_hunger,
				"giver_surplus": surplus,
				"opinion": share_opinion,
				"distance": share_dist,
			},
		})

	# Seek: the same verb serves every need. The target is whichever advertised
	# resource best answers the most urgent need within sensory range. A
	# resource already within reach is not a seek target: distance is zero, so
	# the available verb is eat or drink. Seeking it too would make a creature
	# dither in front of its own meal.
	var seek_weight := params.f("brain", "seek_weight", 0.9)
	var perceived_food := {"cell": -1}
	if hunger_u > 0.05 and int(food_reach[0]) < 0:
		perceived_food = _find_perceived(grid, x, y, GridRef.FOOD, sensory_radius)
	var food_lead := int(perceived_food["cell"]) >= 0
	if int(perceived_food["cell"]) >= 0:
		var norm_dist := clampf(float(perceived_food["dist"]) / maxf(sensory_radius, 1.0), 0.0, 1.0)
		candidates.append({
			"label": "seek_food",
			"verb": StoreRef.Verb.SEEK,
			"score": seek_weight * hunger_u * float(perceived_food["value"]) * (1.0 - dist_scale * norm_dist),
			"aim_cell": int(perceived_food["cell"]),
			"aim_x": float(perceived_food["x"]),
			"aim_y": float(perceived_food["y"]),
			"parts": {
				"hunger_urgency": hunger_u,
				"advertised_value": float(perceived_food["value"]),
				"distance_penalty": dist_scale * norm_dist,
			},
		})

	var perceived_water := {"cell": -1}
	if thirst_u > 0.05 and int(water_reach[0]) < 0:
		perceived_water = _find_perceived(grid, x, y, GridRef.WATER, sensory_radius)
	var water_lead := int(perceived_water["cell"]) >= 0
	if int(perceived_water["cell"]) >= 0:
		var norm_dist_w := clampf(float(perceived_water["dist"]) / maxf(sensory_radius, 1.0), 0.0, 1.0)
		candidates.append({
			"label": "seek_water",
			"verb": StoreRef.Verb.SEEK,
			"score": seek_weight * thirst_u * float(perceived_water["value"]) * (1.0 - dist_scale * norm_dist_w),
			"aim_cell": int(perceived_water["cell"]),
			"aim_x": float(perceived_water["x"]),
			"aim_y": float(perceived_water["y"]),
			"parts": {
				"thirst_urgency": thirst_u,
				"advertised_value": float(perceived_water["value"]),
				"distance_penalty": dist_scale * norm_dist_w,
			},
		})

	# Move to. Recall is the plan's thirteenth verb: travel to a chosen place
	# rather than toward the best current advertisement. When nothing of the
	# needed kind is in sight, a remembered place is the only target a creature
	# has. Confidence decays with the age of the memory, so a dried pond is walked
	# to a few times and then given up; the decision to stop trusting a place is
	# forgetting, not a new rule. The label still names the lead (recall_food),
	# while the verb is the generic action; seek stays reserved for a resource the
	# creature can currently perceive.
	var recall_threshold := params.f("memory", "recall_need_threshold", 0.15)
	var place_decay := params.f("memory", "place_decay_days", 2.0)
	# A remembered place is judged against the memory's own reach, not against
	# what the eyes can resolve. Normalising by the sensory radius made every
	# remembered meal past the edge of sight maximally distant, so a place seven
	# cells away and one forty cells away cost the same and recall lost to idle
	# wandering. The reference is longer than any sense radius per locus, so the
	# discount now actually falls off with distance.
	var recall_distance := maxf(params.f("memory", "recall_distance_cells", 24.0), 1.0)
	if memory != null and hunger_u > recall_threshold and int(food_reach[0]) < 0 and int(perceived_food["cell"]) < 0:
		var remembered := memory.recall(i, GridRef.FOOD, x, y, day, place_decay, grid.width)
		if not remembered.is_empty():
			food_lead = true
			var norm_dist_m := clampf(float(remembered["dist"]) / recall_distance, 0.0, 1.0)
			candidates.append({
				"label": "recall_food",
				"verb": StoreRef.Verb.MOVE_TO,
				"score": seek_weight * hunger_u * float(remembered["confidence"]) * (1.0 - dist_scale * norm_dist_m),
				"aim_cell": int(remembered["cell"]),
				"aim_x": float(int(remembered["cell"]) % grid.width) + 0.5,
				"aim_y": float(int(remembered["cell"]) / grid.width) + 0.5,
				"parts": {
					"hunger_urgency": hunger_u,
					"memory_confidence": float(remembered["confidence"]),
					"memory_age_days": float(remembered["age_days"]),
					"distance_penalty": dist_scale * norm_dist_m,
				},
			})

	if memory != null and thirst_u > recall_threshold and int(water_reach[0]) < 0 and int(perceived_water["cell"]) < 0:
		var remembered_w := memory.recall(i, GridRef.WATER, x, y, day, place_decay, grid.width)
		if not remembered_w.is_empty():
			water_lead = true
			var norm_dist_mw := clampf(float(remembered_w["dist"]) / recall_distance, 0.0, 1.0)
			candidates.append({
				"label": "recall_water",
				"verb": StoreRef.Verb.MOVE_TO,
				"score": seek_weight * thirst_u * float(remembered_w["confidence"]) * (1.0 - dist_scale * norm_dist_mw),
				"aim_cell": int(remembered_w["cell"]),
				"aim_x": float(int(remembered_w["cell"]) % grid.width) + 0.5,
				"aim_y": float(int(remembered_w["cell"]) / grid.width) + 0.5,
				"parts": {
					"thirst_urgency": thirst_u,
					"memory_confidence": float(remembered_w["confidence"]),
					"memory_age_days": float(remembered_w["age_days"]),
					"distance_penalty": dist_scale * norm_dist_mw,
				},
			})

	# Search. A creature with nothing of the needed kind in sight or in memory
	# picks a direction and commits to a long leg. Without this, a thirsty
	# creature beside a food patch tops up, wanders three cells, tops up again,
	# and dies within twenty cells of a pond it never sensed. The heading turns
	# gradually instead of re-rolling, so successive legs cover ground.
	# Food and water are not the same emergency. Water is scarce in area and a
	# missed pond is fatal, so a thirsty creature searches early; food regrows
	# and is usually already close, so a hungry one eats before it wanders.
	var food_threshold := params.f("brain", "search_food_threshold", 0.35)
	var water_threshold := params.f("brain", "search_water_threshold", 0.15)
	if memory == null:
		food_lead = int(perceived_food["cell"]) >= 0
		water_lead = int(perceived_water["cell"]) >= 0
	var food_search_weight := params.f("brain", "search_food_score_weight", 0.7)
	var water_search_weight := params.f("brain", "search_water_score_weight", 1.1)
	var search_dist := params.f("brain", "search_distance_cells", 48.0)
	var search_turn := params.f("brain", "search_turn_radians", 0.35)
	if hunger_u > food_threshold and int(food_reach[0]) < 0 and not food_lead:
		var search_aim := _search_target(grid, x, y, store.heading[i], rng, search_dist, search_turn)
		candidates.append({
			"label": "search_food",
			"verb": StoreRef.Verb.WANDER,
			"score": food_search_weight * hunger_u,
			"aim_cell": -1,
			"aim_x": search_aim.x,
			"aim_y": search_aim.y,
			"parts": {"hunger_urgency": hunger_u, "search_distance": Vector2(x, y).distance_to(search_aim)},
		})
	if thirst_u > water_threshold and int(water_reach[0]) < 0 and not water_lead:
		var search_aim_w := _search_target(grid, x, y, store.heading[i], rng, search_dist, search_turn)
		candidates.append({
			"label": "search_water",
			"verb": StoreRef.Verb.WANDER,
			"score": water_search_weight * thirst_u,
			"aim_cell": -1,
			"aim_x": search_aim_w.x,
			"aim_y": search_aim_w.y,
			"parts": {"thirst_urgency": thirst_u, "search_distance": Vector2(x, y).distance_to(search_aim_w)},
		})

	# Close the distance to company. A known friend is worth crossing ground
	# for at mild loneliness; a stranger only when the need is stronger, which
	# is how first encounters still happen in a sparse world.
	var approach_threshold := params.f("social", "approach_threshold", 0.25)
	var stranger_threshold := params.f("social", "stranger_threshold", 0.55)
	if opinion != null and social_u > approach_threshold and seen_positive >= 0 and seen_positive_dist > social_reach:
		var known := seen_positive_val > 0.02
		# A stranger is an unknown creature (opinion near zero), not the least
		# disliked creature in sight. Without the second condition a lonely
		# creature alone with a rival walked toward it as if they had just met.
		var stranger := absf(seen_positive_val) <= 0.05
		if known or (stranger and social_u > stranger_threshold):
			var norm := clampf(seen_positive_dist / maxf(notice, 1.0), 0.0, 1.0)
			var affinity := 0.45
			if known:
				affinity = 0.45 + 0.55 * maxf(seen_positive_val, 0.0)
			candidates.append({
				"label": "approach_social",
				"verb": StoreRef.Verb.APPROACH,
				"score": social_weight * social_u * affinity * (1.0 - dist_scale * norm),
				"aim_cell": -1,
				"aim_creature": seen_positive,
				"aim_x": store.px[seen_positive],
				"aim_y": store.py[seen_positive],
				"parts": {
					"social_urgency": social_u,
					"opinion": seen_positive_val,
					"distance_penalty": dist_scale * norm,
				},
			})

	# Avoid. Negative memory raises the value of keeping distance, discounted by
	# boldness: the same grievance moves a bold creature to the contested food
	# and a timid one away from it. No branch reads a relationship label.
	var avoid_threshold := params.f("social", "avoid_threshold", -0.25)
	var avoid_weight := params.f("social", "avoid_weight", 1.25)
	var avoid_radius := params.f("social", "avoid_radius_cells", 6.0)
	if opinion != null and seen_negative >= 0 and seen_negative_val < avoid_threshold and seen_negative_dist < avoid_radius:
		var closeness := 1.0 - clampf(seen_negative_dist / maxf(avoid_radius, 0.5), 0.0, 1.0)
		candidates.append({
			"label": "avoid",
			"verb": StoreRef.Verb.AVOID,
			"score": avoid_weight * (-seen_negative_val) * (1.0 - 0.6 * boldness) * (0.35 + 0.65 * closeness),
			"aim_cell": -1,
			"aim_creature": seen_negative,
			"parts": {
				"opinion": seen_negative_val,
				"boldness": boldness,
				"closeness": closeness,
			},
		})

	# Flee. The same negative opinion that makes a creature avoid also makes it
	# run when safety is low; boldness only discounts the retreat. The target is a
	# point away from the threat, not a shelter the brain knows about. Flee is
	# offered only inside its notice radius, so a cooled feud stops pulling a
	# creature across the map.
	var flee_candidate: Dictionary = {}
	var flee_reach := minf(params.f("safety", "flee_notice_cells", 9.0), threat_reach)
	var flee_need := params.f("safety", "flee_need_threshold", 0.15)
	if safety_enabled and safety_u > flee_need and threat_id >= 0 and threat_dist < flee_reach:
		var away := Vector2(x - store.px[threat_id], y - store.py[threat_id])
		if away.length_squared() < 0.0001:
			away = Vector2(1.0, 0.0)
		away = away.normalized()
		var flee_distance := params.f("safety", "flee_distance_cells", 8.0)
		var retreat := Vector2(
			clampf(x + away.x * flee_distance, 1.0, float(grid.width - 2)),
			clampf(y + away.y * flee_distance, 1.0, float(grid.height - 2))
		)
		flee_candidate = {
			"label": "flee",
			"verb": StoreRef.Verb.FLEE,
			"score": params.f("safety", "flee_weight", 3.0) * safety_u * threat_strength * (1.0 - 0.6 * boldness),
			"aim_cell": -1,
			"aim_creature": threat_id,
			"aim_x": retreat.x,
			"aim_y": retreat.y,
			"parts": {
				"safety_urgency": safety_u,
				"opinion": threat_value,
				"threat_distance": threat_dist,
				"boldness": boldness,
			},
		}
		candidates.append(flee_candidate)

	# Rest. Suppressed in proportion to hunger and thirst because resting
	# satisfies neither: a starving creature with full energy does not lie down,
	# and a creature at water zero that chooses a nap is choosing to die. Half
	# suppression was not enough: at critical thirst, rest still beat a known
	# pond thirty cells away, so the sickest creature in the world kept lying
	# down. Near-critical suppression is what removes that; the 0.8 leaves a
	# creature with a mild thirst able to nap, because energy still has to
	# recover for breeding. Energy has no death clock; food and water do.
	# Rest serves energy and comfort, but only where the ground can actually
	# restore comfort. A hard, dry resting place therefore scores above a muddy
	# one without any "shelter" branch: the quality is a property of the cell.
	var comfort_rest := comfort_u * current_quality * params.f("comfort", "rest_weight", 0.8)
	# Safety is restored by rest only where the arrangement cuts exposure. A
	# frightened creature on open ground cannot rest its fear away; one in a
	# hardened corner can. This is the same property read as comfort, weighted by
	# a different need, so the shelter chain serves both without a second system.
	var safety_rest := safety_u * current_protection * params.f("safety", "rest_weight", 0.8)
	var rest_score := params.f("brain", "rest_weight", 0.9) * maxf(energy_u, maxf(comfort_rest, safety_rest)) * (1.0 - 0.8 * maxf(hunger_u, thirst_u))
	candidates.append({
		"label": "rest",
		"verb": StoreRef.Verb.REST,
		"score": rest_score,
		"aim_cell": -1,
		"parts": {"energy_urgency": energy_u, "comfort_urgency": comfort_u, "safety_urgency": safety_u, "ground_quality": current_quality, "protection": current_protection},
	})

	# Reproduction. The gate has already decided whether this creature may breed;
	# the brain only chooses between closing the distance and taking the mate.
	# Nothing here knows what a species is, and the same scores serve every
	# creature in the world.
	if mate_ready and partner_id >= 0:
		var repro_weight := params.f("brain", "repro_weight", 0.85)
		var reach := params.f("movement", "arrive_radius", 1.2) + 0.35
		if partner_dist <= reach:
			candidates.append({
				"label": "mate",
				"verb": StoreRef.Verb.MATE,
				"score": repro_weight,
				"aim_cell": -1,
				"aim_creature": partner_id,
				"parts": {"partner": float(partner_id), "distance": partner_dist},
			})
		else:
			var norm_partner := clampf(partner_dist / maxf(sensory_radius, 1.0), 0.0, 1.0)
			candidates.append({
				"label": "approach_mate",
				"verb": StoreRef.Verb.APPROACH,
				"score": repro_weight * (1.0 - dist_scale * norm_partner),
				"aim_cell": -1,
				"aim_creature": partner_id,
				"aim_x": store.px[partner_id],
				"aim_y": store.py[partner_id],
				"parts": {"partner": float(partner_id), "distance": partner_dist},
			})

	# Learning biases the scores. The multiplier is bounded (0.4 .. 1.6) and
	# cannot create a candidate, so a lesson changes how tempting an available
	# action is, never what is physically possible.
	if memory != null:
		for c in candidates:
			var lesson := memory.learned(i, int(c["verb"]), context)
			c["parts"]["learned"] = lesson
			if absf(lesson) > 0.001:
				c["score"] = float(c["score"]) * clampf(1.0 + lesson, 0.4, 1.6)

	# Commitment bonus while an action is in progress: creatures finish eating,
	# carrying and resting instead of dithering between near-equal scores.
	if store.commitment[i] > 0.0:
		var current_verb := int(store.verb[i])
		var bonus := params.f("brain", "commitment_bonus", 0.12)
		for c in candidates:
			if int(c["verb"]) == current_verb:
				c["score"] = float(c["score"]) + bonus

	# Safety interrupts. Once fear crosses the interrupt threshold, no amount of
	# hunger or habit keeps the creature in place; this is the plan's one
	# priority-like rule, and it belongs to the safety curve rather than to a
	# ladder of needs. Below the threshold the same flee candidate competes on
	# its score like everything else.
	var interrupt_threshold := params.f("safety", "interrupt_threshold", 0.7)
	var chosen: Dictionary
	if safety_enabled and safety_u >= interrupt_threshold and not flee_candidate.is_empty():
		chosen = flee_candidate
	else:
		chosen = _pick(candidates, rng, params, distress)
	d.label = String(chosen.get("label", ""))
	d.verb = int(chosen["verb"])
	d.aim_x = x
	d.aim_y = y
	d.aim_cell = int(chosen.get("aim_cell", -1))
	if chosen.has("aim_x"):
		d.aim_x = float(chosen["aim_x"])
		d.aim_y = float(chosen["aim_y"])
	d.aim_creature = int(chosen.get("aim_creature", -1))

	if d.verb == StoreRef.Verb.WANDER and d.label == "wander":
		var target := _wander_target(grid, x, y, rng, params, curiosity)
		d.aim_x = target.x
		d.aim_y = target.y
		d.aim_cell = -1

	d.scores = candidates
	return d


static func _pick(candidates: Array, rng: SimRng, params: SimParams, distress: float) -> Dictionary:
	var viable: Array = []
	for c in candidates:
		if float(c["score"]) > 0.0001:
			viable.append(c)
	if viable.is_empty():
		return {"verb": StoreRef.Verb.WANDER, "score": 0.0, "aim_cell": -1}
	viable.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	var k := mini(params.i("brain", "softmax_top_k", 4), viable.size())
	var top: Array = viable.slice(0, k)
	var temperature := params.f("brain", "temperature_base", 0.10) + params.f("brain", "temperature_distress", 0.35) * distress
	temperature = maxf(temperature, 0.01)
	var best := float(top[0]["score"])
	var weights: Array = []
	var total := 0.0
	for c in top:
		var w := exp((float(c["score"]) - best) / temperature)
		weights.append(w)
		total += w
	var roll := rng.randf() * total
	for idx in top.size():
		roll -= float(weights[idx])
		if roll <= 0.0:
			return top[idx]
	return top[0]


## Best cell of a material within immediate reach (3x3 around the creature).
## Returns [cell_index, quality]; cell is -1 when nothing is reachable.
static func _best_adjacent(grid: SimGrid, x: float, y: float, mat: int, include_center: bool = true) -> Array:
	var cx := int(floor(x))
	var cy := int(floor(y))
	var best_cell := -1
	var best_value := 0.0
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if not include_center and ox == 0 and oy == 0:
				continue
			var tx := cx + ox
			var ty := cy + oy
			if not grid.in_bounds(tx, ty):
				continue
			var idx := grid.index(tx, ty)
			if int(grid.material[idx]) != mat:
				continue
			if mat == GridRef.FOOD and grid.amount[idx] <= grid.food_min_amount:
				continue
			var value: float = float(grid.amount[idx])
			if mat == GridRef.FOOD:
				value *= float(grid.nutrition[idx])
			if value > best_value:
				best_value = value
				best_cell = idx
	return [best_cell, best_value]


## Best nearby cell to take material from. Returns [cell, material, amount,
## wetness]; cell is -1 when nothing is reachable. The centre cell is excluded:
## picking up what lies underfoot and piling it back is a no-op, and the store
## verb should move material through the world.
static func _best_pickup(grid: SimGrid, x: float, y: float, mat: int, avoid_cell: int = -1) -> Array:
	var cx := int(floor(x))
	var cy := int(floor(y))
	var best := [-1, mat, 0.0, 0.0]
	var best_value := 0.0
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			var tx := cx + ox
			var ty := cy + oy
			if not grid.in_bounds(tx, ty):
				continue
			var idx := grid.index(tx, ty)
			if idx == avoid_cell:
				continue
			if int(grid.material[idx]) != mat:
				continue
			if mat == GridRef.SAND and grid.hardness[idx] >= grid.convert_max_hardness:
				continue
			var available: float = float(grid.amount[idx])
			if mat == GridRef.FOOD:
				available = maxf(0.0, available - grid.food_min_amount)
			if available <= 0.001:
				continue
			var value := available
			if mat == GridRef.FOOD:
				value *= float(grid.nutrition[idx])
			else:
				value *= 0.5 + 0.5 * float(grid.wetness[idx])
			if value > best_value:
				best_value = value
				best = [idx, mat, available, float(grid.wetness[idx])]
	return best


## Best cell to put a load into: the current cell first, then the adjacent ring.
## Sand may fill water; food may join food or open ground; neither may bury a
## different solid. Returns -1 when the load has nowhere to go here.
static func _best_deposit(grid: SimGrid, x: float, y: float, mat: int) -> int:
	var cx := int(floor(x))
	var cy := int(floor(y))
	if grid.in_bounds(cx, cy):
		var here := grid.index(cx, cy)
		if _can_deposit(grid, here, mat):
			return here
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			var tx := cx + ox
			var ty := cy + oy
			if not grid.in_bounds(tx, ty):
				continue
			var idx := grid.index(tx, ty)
			if _can_deposit(grid, idx, mat):
				return idx
	return -1


static func _can_deposit(grid: SimGrid, idx: int, mat: int) -> bool:
	var m := int(grid.material[idx])
	if m == GridRef.AIR:
		return true
	if m == mat:
		return grid.amount[idx] < grid.max_for(mat) - 0.001
	if mat == GridRef.SAND and m == GridRef.WATER:
		return true
	return false


## Food mass in a small square around a cell. A load carried away from a patch
## is worth more as a cache than one dropped on top of the patch it came from.
static func _local_food_abundance(grid: SimGrid, cell: int, radius: int) -> float:
	var cx := grid.cell_x(cell)
	var cy := grid.cell_y(cell)
	var total := 0.0
	var cells := 0
	for oy in range(-radius, radius + 1):
		for ox in range(-radius, radius + 1):
			var tx := cx + ox
			var ty := cy + oy
			if not grid.in_bounds(tx, ty):
				continue
			var idx := grid.index(tx, ty)
			if int(grid.material[idx]) == GridRef.FOOD:
				total += float(grid.amount[idx])
			cells += 1
	return clampf(total / maxf(float(cells) * grid.food_max, 0.001), 0.0, 1.0)


## Best nearby cell by comfort quality, coarsely sampled because places, not
## cells, are the unit of intention. Returns {cell, x, y, quality, dist} or an
## empty dictionary when nothing beats the ground underfoot.
static func _find_comfort(grid: SimGrid, x: float, y: float, radius: float, current_quality: float) -> Dictionary:
	var best := {}
	var best_score := current_quality + 0.02
	var cx := int(floor(x))
	var cy := int(floor(y))
	var limit := int(ceil(radius))
	for oy in range(-limit, limit + 1, 2):
		for ox in range(-limit, limit + 1, 2):
			var d2 := float(ox * ox + oy * oy)
			if d2 > radius * radius or d2 < 1.0:
				continue
			var tx := cx + ox
			var ty := cy + oy
			if not grid.in_bounds(tx, ty):
				continue
			var idx := grid.index(tx, ty)
			# A position needs solid ground under it. Air has no material amount
			# for the seek execution to arrive on, and water is not comfortable.
			var m := int(grid.material[idx])
			if m == GridRef.AIR or m == GridRef.WATER:
				continue
			var quality := grid.comfort_quality(idx)
			var dist := sqrt(d2)
			var score := quality - dist * 0.01
			if score > best_score:
				best_score = score
				best = {"cell": idx, "x": float(tx) + 0.5, "y": float(ty) + 0.5, "quality": quality, "dist": dist}
	return best


## Best advertised resource within sensory range. Sampling gets coarser with
## distance: places, not cells, are the unit of intention. Perception is
## approximate by design, and a Phase 1 genome locus will add noise on top.
## Three fixed bands keep the cost near 300 cell reads instead of 1,369.
static func _find_perceived(grid: SimGrid, x: float, y: float, mat: int, radius: float) -> Dictionary:
	var best := {"cell": -1, "value": 0.0, "dist": 0.0, "x": 0.0, "y": 0.0, "score": 0.0}
	var cx := int(floor(x))
	var cy := int(floor(y))
	best = _scan_band(grid, cx, cy, mat, 0.0, minf(4.0, radius), 1, best)
	best = _scan_band(grid, cx, cy, mat, 4.0, minf(10.0, radius), 2, best)
	best = _scan_band(grid, cx, cy, mat, 10.0, radius, 3, best)
	return best


static func _scan_band(grid: SimGrid, cx: int, cy: int, mat: int, inner: float, outer: float, step: int, best: Dictionary) -> Dictionary:
	if outer <= inner + 0.001:
		return best
	var limit := int(ceil(outer))
	var start := int(ceil(float(-limit) / float(step))) * step
	var inner2 := inner * inner
	var outer2 := outer * outer
	for oy in range(start, limit + 1, step):
		for ox in range(start, limit + 1, step):
			var d2 := float(ox * ox + oy * oy)
			if d2 < inner2 or d2 > outer2:
				continue
			var tx := cx + ox
			var ty := cy + oy
			if not grid.in_bounds(tx, ty):
				continue
			var idx := grid.index(tx, ty)
			if int(grid.material[idx]) != mat:
				continue
			if mat == GridRef.FOOD and grid.amount[idx] <= grid.food_min_amount:
				continue
			var value: float = float(grid.amount[idx])
			if mat == GridRef.FOOD:
				value *= float(grid.nutrition[idx])
			if value <= 0.0:
				continue
			var d := sqrt(d2)
			# Advertised value discounted by distance: near food beats a bigger
			# pile on the horizon, but not overwhelmingly.
			var score := value / (1.0 + d * 0.15)
			if score > float(best["score"]):
				best = {
					"cell": idx,
					"value": value,
					"dist": d,
					"x": float(tx) + 0.5,
					"y": float(ty) + 0.5,
					"score": score,
				}
	return best


## A long leg in a gradually turning direction. The heading itself is updated by
## the simulation only when the search is chosen, so unchosen proposals never
## steer the next one.
static func _search_target(grid: SimGrid, x: float, y: float, heading: float, rng: SimRng, dist: float, turn: float) -> Vector2:
	var angle := heading + rng.randf_range(-turn, turn)
	return Vector2(
		clampf(x + cos(angle) * dist, 1.0, float(grid.width - 2)),
		clampf(y + sin(angle) * dist, 1.0, float(grid.height - 2))
	)


## Somewhere else to be, biased away from water so wandering creatures do not
## spend their lives standing in ponds. Water remains walkable.
static func _wander_target(grid: SimGrid, x: float, y: float, rng: SimRng, params: SimParams, curiosity: float = 0.5) -> Vector2:
	var min_d := params.f("movement", "wander_min_cells", 6.0) * (0.7 + 0.6 * curiosity)
	var max_d := params.f("movement", "wander_max_cells", 18.0) * (0.7 + 0.6 * curiosity)
	var tx := x
	var ty := y
	for attempt in 4:
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(min_d, max_d)
		tx = clampf(x + cos(angle) * dist, 1.0, float(grid.width - 2))
		ty = clampf(y + sin(angle) * dist, 1.0, float(grid.height - 2))
		if grid.material_at(int(floor(tx)), int(floor(ty))) != GridRef.WATER:
			break
	return Vector2(tx, ty)
