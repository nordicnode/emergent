# Emergent Creature Simulation — Development Plan

A 2D sprite simulation in which thousands of individually distinct creatures live, learn, compete, cooperate, and invent practices the developer never scripted — while the player does exactly three things: place sand, place water, and place food.

This plan turns that idea into a buildable game. It specifies the systems, the numbers to start tuning from, the order to build in, the tests that prove a behaviour is genuinely emergent, and the things to leave out permanently. Starting values in this document are tuning starting points to be measured and revised in the prototype, not proven constants.

## Executive summary

Build five simple systems that share one property language, and let everything interesting happen where they collide:

1. **A utility brain over 13 generic actions.** Move to, wander, seek, eat, drink, pick up, drop or pile, rest, flee, approach, avoid, mate, and socialise. No action is named shelter, hoard, fight a rival, or found a village.
2. **Homeostatic needs with response curves.** Hunger, thirst, rest, safety, health, social contact, comfort, curiosity, and reproduction. Steep curves when deprived, shallow curves when satisfied — hierarchy appears from the curves instead of being coded as a ladder.
3. **A parametric genome of about 25 clamped numbers.** Thresholds, rates, sensory range, personality axes, body trade-offs, and learning rates. One gene is read by several systems, so one mutation ripples without rewriting a brain.
4. **A 2D property grid for materials.** Every cell carries material plus wetness, temperature, hardness, density, cohesion, and nutrition. Hard sand is a state wet, compacted sand enters as it dries — not a recipe.
5. **Sparse memory with one learning rule.** Creatures remember a capped set of episodes and relationships, weighted by stress and recency. That single mechanism produces preference, hoarding after near-starvation, avoidance after an attack, rivalry, dominance, and imitation.

Around those five sit three supporting systems: stigmergy (piles, structures, and trails in the world outlive individual memory), a causal event log and inspector that make behaviour legible, and a tiered simulation budget that keeps the game running as population grows. How the whole set interacts — what each system writes that the others read, at what cadence, in what order, and with what effect on replayability — is traced in the systems-in-depth chapter after the interaction map.

**Recommended stack:** Godot 4, 2D-first, with the simulation written as plain data arrays decoupled from scene nodes and the renderer as a view over those arrays. Bevy in Rust is the alternative if a higher agent ceiling matters more than time to first playable.

**Honest scale target:** 100–300 full creatures is the first real milestone. 500–1,000 with staggered decisions is the standard tier to design for. 5,000 or more is achievable only as low-detail background agents with group-level behaviour. Rendering 10,000 simple sprites is a solved problem; deciding richly for 10,000 creatures every frame is not, and this plan never pretends otherwise.

## What this game is, and what it refuses to be

### The player contract

- The player places sand, water, and food — by brush, with amount and brush size, and nothing else in version 1.
- The player does not place creatures, order creatures, edit traits, build structures, unlock technologies, or complete quests.
- The player's skill is reading the world: noticing scarcity forming, seeing a practice spread, choosing where and when to perturb selection pressure, and deciding whether to intervene or watch.
- Every player intervention is therefore ecological, not directorial. Placing water in a dry basin does not command anything; it changes which genomes, memories, and practices succeed there.

That constraint is the game. Each new player power would give the player a way to bypass emergence by doing the creatures' work for them, so new powers need a stronger justification than "players might want it."

### The creature promise

Every creature is unique in four independent ways, and the inspector must be able to show all four:

- **Inherited:** its genome — thresholds, metabolism, senses, body, personality, and learning rates.
- **Embodied:** its current needs, injuries, age, location, and what it is carrying.
- **Experienced:** its episodic memories, learned action weights, and relationship history.
- **Situated:** the materials, neighbours, piles, and structures around it right now.

Two creatures with the same genome in different places with different histories should behave differently. Two creatures with different genomes in the same place with the same history should also behave differently. If either test fails, uniqueness is cosmetic.

### Non-goals for version 1

- No language, religion, technology tree, currency, jobs, or named professions.
- No predators as a separate scripted species, no quests, no win condition, no campaign.
- No direct creature control, trait editing, or "build shelter" button.
- No multiplayer, modding API, 3D view, or LLM-driven creature.
- No claim of thousands of fully rich creatures until a benchmark on target hardware proves it.

## The governing principle: simple systems, complex collisions

Complexity in this game comes from how, why, and when simple systems interact — never from a system that is itself complicated. A glider in Conway's Game of Life exists in no rule; flocking in Reynolds' boids exists in no boid. Shelter, hoarding, and rivalry must have the same status here: real, recognisable, and absent from the code as named behaviours.

### The five emergence tests

Apply all five before merging any feature. A feature that fails any test is not finished, however good it looks in a demo.

1. **Delete-the-name test.** Search the codebase for the behaviour's name. If a module, branch, or data flag implements "shelter", "hoarding", or "rivalry" directly, delete it. Does something like the behaviour still occur? If not, it was scripted.
2. **Two-systems-plus-timing test.** Name the two or three contributing systems and the timing, order, or context that makes them collide. If you cannot name them, you do not yet understand the feature — and are probably about to write a script.
3. **Disable-one-system test.** Turn off one contributing system in a debug build. The behaviour should change or disappear. If nothing changes, that system was decoration.
4. **Reader test.** For every new gene, material, or property, name the other systems that read it. If none do, cut it. Visual variety with no systemic consequence is the failure mode that made Spore's creature parts feel hollow: parts carried canned stats regardless of shape or position.
5. **Why test.** Click the creature in the inspector. Can you point to the need, memory, relationship, or material property that caused this action? If not, add legibility before adding behaviour.

### Timing is a mechanic, not an implementation detail

Because the brain scores actions, *when* a score is recomputed changes what a creature does:

- Hunger and danger scores recompute every decision tick, so a starving or threatened creature reacts fast.
- Social scores recompute every few seconds, so friendships and feuds evolve slowly and do not flicker.
- Material affordances recompute when a creature enters a new neighbourhood, so it does not instantly re-plan for every cell it crosses.
- A fleeing creature finishes fleeing before hunger wins again. That lag — hysteresis — reads to the player as character, and it costs no code beyond update cadence.

Design reviews should ask about cadence with the same seriousness as about content: what updates, how often, in what order, and what is allowed to interrupt what.

### Order is a mechanic

Sequences matter as much as states. Wet sand piled, then compacted, then dried becomes hard. The same three events in a different order produce mud or a loose dune. Food found after near-starvation teaches more than food found routinely. Food taken from a starving neighbour damages a relationship; the same act beside an abundant pile is neutral. None of these need special cases — they need systems that record state, history, and context honestly, and a brain that reads all three.

## Core loop and session shape

### The moment-to-moment loop

1. The player surveys the world — population, food stock, water, structures, and highlighted events.
2. The player places sand, water, or food somewhere, for a reason they formed by watching.
3. The simulation responds over minutes, not seconds: creatures discover, compete, learn, copy, build up piles and structures, form and lose relationships, reproduce, and die.
4. The player zooms in to follow individuals, opens the inspector to ask why, and reads the log to confirm or revise their theory of what is happening.
5. A new scarcity, discovery, feud, or migration forms — and the player perturbs again, or deliberately does not.

There is no turn, round, or objective screen. A session ends when the player stops, and a world persists across sessions through save and load.

### The long arc the player should be able to witness

- **Founding:** a small, diverse founder population explores, eats, and mostly wanders. Individual differences are visible but little has accumulated.
- **Settlement:** stigmergic piles and favoured resting places appear. Some locations become busy because creatures return to them, and they become busier because creatures return.
- **Specialisation of place:** one area becomes associated with food storage, another with shelter, another with conflict — because of material and history, not zoning.
- **Culture:** a practice discovered by one creature is observed, copied imperfectly, and repeated until it is a local norm that newcomers and children absorb.
- **Pressure and change:** the player moves water, adds food in a new place, or stops intervening. Populations shift, a culture adapts or dies, lineages spread or vanish, and migration follows memory and trails.

If a test world never leaves the founding stage, the accumulation systems — memory consolidation, artefact persistence, imitation — are too weak. If it reaches culture in the first minutes, they are too strong and discovery means nothing.

### Failure states are simulation outcomes, not game-over screens

Extinction, famine collapse, and runaway population growth are all possible and all informative. The game does not end; the world records what happened, and the player can keep watching the empty world, reseed founders as an explicit world setting, or load an earlier save. Guardrails in the balancing section reduce accidental total collapse without forbidding it.

## World design

### Representation

- **Material grid:** 512 × 384 cells as the starting size. A cell is 8–16 pixels at 1× zoom, tuned so a creature sprite is roughly two cells tall. Treat size as a Phase 3 scaling variable, not a fixed promise.
- **Creature position:** continuous floating-point coordinates over the grid. A creature interacts with the cell it stands in and reachable neighbouring cells.
- **Chunks:** the grid is divided into 64 × 64 cell chunks for material updates and rendering. Only dirty, active chunks simulate or repaint.
- **No separate item entities for piles.** A pile is a cell, or a small cluster of cells, with a high amount of a material. Carrying is a small material amount held by a creature. Dropping adds it to a cell. Inventory is material accounting, not a new system.

### What the player places, precisely

| Input | Placement effect | What it does not do |
|---|---|---|
| Sand | Adds sand amount to cells in the brush | Does not create shelter directly; loose, wet, muddy, or hard states depend on what happens next |
| Water | Adds water to cells; flows, soaks, and evaporates under material rules | Does not irrigate, bless, or target creatures |
| Food | Adds food amount with starting nutrition and freshness | Does not feed any creature until a creature finds, reaches, and eats it |

Placement amount matters. A little water dampens sand; a lot creates a pool that flows and floods. A little food feeds whoever is nearest; a lot creates competition, storage behaviour, rotting stock, and a place worth defending. Brushes should show amount clearly so the player learns dosage by watching outcomes.

### Starting world

Generate a deliberately plain starting world: mostly open ground, some existing sand variation, no pre-built shelter, no pre-placed culture, and no tutorial structures that teach a "correct" solution. Seed a founder population with wide genome variation so early differences come from the creatures, not from a landscaped puzzle. Provide several saved seed worlds for testing and first play, each differing in water distribution and sand placement so players learn systems, not a map.

### Seasons and time — optional, late, and systemic only

Do not add seasons in version 1. If added later, a season may only change global material parameters — temperature, evaporation rate, food regrowth rate — and must never trigger creature behaviour directly. A dry season is interesting precisely because thirst, wetness, hardening, migration, and competition all respond to the same parameter change at different rates.

## Material system: discovery without a recipe table

### Cell data model

Each cell stores a material identifier and a set of scalar properties. Store these as structure-of-arrays data, one array per property, for cache-friendly sweeps.

| Field | Meaning | Read by |
|---|---|---|
| Material | Air, sand, water, food, debris, or a derived state | Flow, rendering, affordances |
| Amount | How much material the cell holds | Piles, carrying, placement |
| Wetness, 0–1 | Water absorbed or present | Hardening, comfort, cold risk, rotting |
| Temperature | Local heat, diffused between neighbours | Evaporation, phase change, comfort, rotting |
| Hardness, 0–1 | Resistance to digging and deformation | Shelter affordance, support, movement cost |
| Cohesion, 0–1 | How well the material holds together | Structure stability, pile shape |
| Density | Weight relative to neighbours | Liquid swapping, sinking, carrying cost |
| Nutrition | Food value remaining | Hunger affordance, learning outcomes |
| Age | Time since the cell last changed materially | Rotting, drying, erosion, decay |

Derived states such as mud, hard sand, and vapour are states a cell enters when its properties cross thresholds. They are not player-placed materials and they are not entries in a crafting table.

### Interaction rules — one function per property

Write general functions, each serving every material that carries the relevant property:

- **Flow.** A liquid cell tries to move down; if blocked, it tries sideways. When moving down into a lighter liquid, compare densities and swap. Gas does the same inverted: up first, then sideways.
- **Wetness transfer.** A wet neighbour raises a cell's wetness in proportion to contact and time. Wetness drains downward and evaporates in proportion to temperature and exposure.
- **Compaction.** Weight above a cell, creatures standing or resting on it, and repeated piling raise its compaction. Compaction alone does nothing dramatic — which is the point.
- **Hardening.** Hardness rises as a function of wetness history, compaction, and drying. Sand that was wet, became compacted, and then dries gains hardness and cohesion. Sand that dries loose stays loose. Sand that stays wet stays mud.
- **Temperature and phase.** Temperature diffuses between neighbours. Water hot enough becomes vapour, which rises and can cool back into water elsewhere. No fire system is required for version 1; the phase machinery exists so temperature is a real property other systems can later use.
- **Rotting.** Food nutrition falls with age, temperature, and wetness. Past a threshold, food gains a harmful property. Creatures do not know this in advance; they learn it through the learning rule when eating it makes health worse.
- **Support and shelter.** A cell's hardness and cohesion decide whether it supports weight, blocks exposure, and resists digging. Shelter is computed from arrangement: a creature positioned so that hard cells reduce its exposure gains safety and comfort. No cell is tagged "shelter".

### Worked example: hard sand, step by step

1. The player places water beside sand, or rain-equivalent placement wets a sandy area. Sand wetness rises.
2. A creature with a high safety or comfort drive piles material in a dry, sheltered spot — the generic drop or pile action, chosen because that location already scores well.
3. The pile happens to contain wet sand. Creatures standing and resting on it compact it.
4. Time passes. The exposed surface dries while compacted.
5. Hardness and cohesion rise. The pile now blocks more exposure than loose sand does.
6. The safety affordance of resting there rises. The originating creature returns; its learned weight for piling and resting there rises.
7. Neighbours observe a visibly more comfortable creature, or simply encounter a better resting place, and copy the pile action nearby.
8. The player sees a shelter district. No step contains the word shelter in creature code.

Change any condition and the outcome changes honestly: pile dry sand and get a dune; pile wet sand in a perpetually wet hollow and get mud; pile and never rest there and compaction may never happen.

### Affordances: how materials talk to the brain

Cells and piles advertise what they offer, in the pattern The Sims uses for objects: a water cell advertises thirst relief, a food pile advertises hunger relief scaled by amount and nutrition, a hard, dry, enclosed position advertises safety and comfort. The brain multiplies the advertisement by need, personality, memory, and distance. Consequences:

- A new material becomes usable without touching creature code, because creatures respond to properties and advertisements, not material names.
- The same pile advertises differently to different creatures. To a hungry creature it is food; to a creature that was attacked there, it is a place to avoid; to a creature carrying food, it is a place to add to.
- Advertisements must be computed from properties at query time, never stored as hand-authored per-material behaviour.

### Adding a material later — the approved process

1. Give the new material property values: density, cohesion, how it takes and loses wetness, how temperature affects it, nutrition if any.
2. Check which existing functions now apply to it automatically.
3. Check which affordances its properties generate.
4. Add a sprite and tint.
5. Do not add creature code. If creature code seems necessary, the property model is missing a general property — add the property, not a special case.

One or two explicitly authored pairwise interactions may eventually prove necessary. If one is added, document it in the code and in this plan as an authored interaction, not as an emergent discovery. Honesty about that boundary keeps the rest of the claim credible.

### Material performance rules

- Simulate only dirty chunks; a still, dry, unoccupied region costs nothing per tick.
- Update material chunks in a checkerboard pattern if threading is added, so two threads never write the same cell in the same pass.
- Keep the version 1 material set tiny: sand, water, food, plus the derived states mud, hard sand, and vapour. Five states, three player inputs, unlimited arrangements.

## Creatures: needs, wants, and quirks

### Needs model

Each need has a current value, a setpoint, and a decay or growth rate modified by genome, body, activity, and environment. Deficit is the distance from setpoint. A response curve converts deficit into urgency: nearly flat when satisfied, steep when critical. Utility is driven by urgency, not by raw deficit, which is what lets a mildly hungry creature socialise while a starving one cannot think about anything except food — without a coded priority ladder.

| Need | Rises or falls when | Generic satisfiers | Curve character |
|---|---|---|---|
| Hunger | Decays with metabolism and activity | Eat | Steep near empty |
| Thirst | Decays faster when hot, dry, or active | Drink | Steep near empty |
| Energy | Falls with activity, recovers at rest | Rest | Steep near exhaustion |
| Safety | Falls with nearby threats, exposure, and remembered danger | Flee, avoid, rest in a protected position | Fastest interrupt of all |
| Health | Falls with starvation, dehydration, harm, and bad food | Eat, drink, rest — slowly, indirectly | Slow, and a modifier on everything else |
| Social | Falls with isolation from positively regarded creatures | Approach, socialise | Rises in importance when other needs are met |
| Comfort | Falls when wet, cold, exposed, or on poor ground | Move to or create a better position, rest | Medium, strongly place-dependent |
| Curiosity | Falls slowly over time, faster in familiar places | Enter unvisited cells, handle new materials | The engine of discovery; never fully steep |
| Reproduction | Available only when adult and basic needs are met | Mate | Gated by hunger, thirst, energy, and safety |

Add a need only if you can name its generic satisfier, its curve, and the systems that modify it. Every need is a permanent tax on decision cost, tuning, and player comprehension.

### Wants are needs with a history

A want is a need plus a specific remembered satisfier plus a personality tilt. One creature wants *that* shaded food pile because it ate there safely twice. Another wants any food at all because urgency has drowned out memory. Wants are therefore computed, not assigned, and the inspector can decompose any want into its three parts.

### Personality axes

Five axes, each 0–1, inherited and fixed for life in version 1. Personality changes behaviour only by weighting scores, never by unlocking or forbidding actions.

- **Boldness** — discounts danger and distance; raises flee thresholds.
- **Sociality** — weights social need, approach, sharing, and group proximity.
- **Curiosity** — weights novelty, unvisited places, and unfamiliar materials.
- **Aggression** — weights contest behaviour when opinion is negative and needs compete.
- **Conscientiousness** — weights the generic store or pile action when resources are abundant and future-oriented scores compete with idling. It raises a score; it never triggers hoarding by itself.

Extreme personalities should be viable but costly. A maximally bold creature finds food first and gets hurt most. A maximally curious creature discovers most and rests least. If an extreme is purely advantageous, the trade-off structure is broken and selection will collapse the population onto it.

## Genome: uniqueness that cannot break the creature

### Encoding rules

- The genome is a fixed vector of about 25 floating-point loci, decoded through clamps into viable ranges.
- Genes encode parameters of general systems, never behaviours, brain topologies, or action lists.
- Each gene should be read by two or more systems where practical, so mutation ripples. Limit that ripple: a gene that affects everything makes every mutation catastrophic.
- Inherited values and learned values live in separate stores. Learning never writes to the genome, and children never inherit a parent's learned weights. Culture reaches children through observation and shared places, not through inheritance.

### Starting loci

| Gene family | Example loci | Systems affected |
|---|---|---|
| Need thresholds | Hunger, thirst, and rest setpoints | Needs, utility, ranging behaviour |
| Metabolism | Metabolic rate, stomach capacity, water loss | Needs, environment fit, body trade-offs |
| Senses | Sensory radius, sensory noise | Perception, discovery order, who gets copied |
| Memory | Memory capacity, memory decay rate | Learning, social persistence, place fidelity |
| Personality | The five axes above | Utility weights, social, learning |
| Curve shape | Steepness per major need, novelty weight, social weight | Brain — identical needs, different choices |
| Body | Size, speed, strength, carrying capacity, temperature tolerance | Movement, material work, contests, mating, hunger |
| Learning | Learning rate, stress sensitivity, imitation fidelity | Memory consolidation and cultural spread |

### Trade-offs are mandatory

Bigger means stronger and able to carry more — and hungrier. Faster means better at reaching food and fleeing — and quicker to tire or to need food. A larger sensory radius means earlier discovery — paid for in body cost or metabolism. Encode trade-offs as a body-cost budget at decode time: the sum of body-cost genes is capped, so a mutation that pushes one trait up pushes effective capacity elsewhere down rather than producing a creature that is best at everything.

### Appearance genes are the one safe place for pure decoration

Colour hue, pattern type, pattern density, and size rendering derive from dedicated appearance genes plus body size. A pattern generated procedurally — spots, stripes, or plain, selected by gene — varies appearance without extra textures. Appearance genes may also become socially relevant if creatures preferentially approach similar or dissimilar patterns, but only through the generic opinion and approach scores. Never let appearance silently carry gameplay stats; Spore's lesson is that decoration pretending to be system is worse than honest decoration.

### Life cycle

- **Child:** smaller, weaker, higher imitation fidelity during an early window, protected only by whatever kin and neighbours actually do — there is no invulnerability flag.
- **Adult:** full body values, reproduction gate available, imitation fidelity at its inherited level.
- **Old:** gradual decline in speed, strength, and sensory acuity through the same body parameters, not a separate old-age behaviour set. A healthy old creature remains eligible for the reproduction gate until its health or needs fall below it, so adult and old cohorts can overlap.
- **Death:** from health reaching zero, with cause recorded from the proximate system — starvation, dehydration, harm, exposure, or age-related health decline. Cause of death is a first-class log and lineage field, because population stories are mostly death stories.

## The brain: utility AI over generic actions

### Why utility, and why not the alternatives

- **Finite state machines** are cheap per creature and collapse under their own transitions: professional state machines reach hundreds of states and become increasingly difficult to debug, and every new interaction is a new hand-drawn edge.
- **Behaviour trees** organise execution well but lock decision-making into conditional nodes; a tree per trick is precisely the shelter script and hoard script this design forbids. Small trees may still execute a chosen action, such as moving to a target. They never choose the goal.
- **GOAP and planners** can chain actions in unscripted ways, but planning is search per creature per replan. At hundreds of creatures it consumes the whole budget. Reserve it for nobody in version 1.
- **Deep reinforcement learning** reintroduces scripting through reward shaping, trains unstably, and costs far more than a solo developer can afford per creature. A small weight update on top of utility scores captures the useful part.
- **NEAT-style evolved networks** are for evolution across generations, not live brains: direct encoding limits networks to thousands of connections, and evolving thousands of live brains is a research project.
- **LLM agents** are disqualifying at scale: the Smallville generative-agents experiment ran 25 agents for two simulated days at a cost of thousands of dollars in token credits, with outputs that drift from world logic. An LLM may, much later and offline, narrate a selected creature's recorded history. It never drives a tick.

Utility AI is the remaining option that is cheap, inspectable, and genuinely context-sensitive: score every generic action from considerations passed through response curves, then choose stochastically from the top few. Scorers can be added without restructuring the brain, and the resulting decisions can be good in situations the developer never foresaw — which is the definition of what this game needs.

### The action vocabulary — 13 verbs

| Action | What it does, generically | Typical satisfiers |
|---|---|---|
| Move to | Travel toward a remembered or perceived target cell | Any need, via its target |
| Wander | Move toward a low-familiarity direction | Curiosity, fallback |
| Seek | Move toward the best current advertisement of a type | Hunger, thirst, comfort, safety |
| Eat | Consume food at the current position or from a pile | Hunger, health |
| Drink | Consume water at the current position | Thirst, health |
| Pick up | Take material from a cell into carrying | Store, carry, contest |
| Drop or pile | Add carried material to a cell | Storage, construction, abandoning a load |
| Rest | Stay, recover energy, compact the ground, observe | Energy, health, comfort |
| Flee | Move away from a threat source, fast | Safety |
| Approach | Move toward a specific creature | Social, mating, contest |
| Avoid | Keep distance from a specific creature, place, or material | Safety, social memory |
| Mate | Attempt reproduction with a willing, compatible partner | Reproduction |
| Socialise | Generic close interaction producing a social event for both parties | Social, opinion formation |

Socialise is the thirteenth row because approach and socialise do different work — one closes distance, the other produces the event that memory records. Keep the vocabulary at this size. Every proposed fourteenth action must prove it cannot be expressed as a sequence or scoring variation of these.

### Scoring, in words

For each candidate action and target, compute a score from considerations: need urgency after its curve, personality weight, memory modifier for that target or actor, advertised value of the target, minus distance cost, danger cost, and effort cost. Multiply multiplicative considerations; add or subtract costs. Clamp to a common range so scores are comparable and inspectable.

Then sample, do not maximise. Choose from the top three to five scores with a softmax whose temperature rises when the creature is distressed: a comfortable creature is consistent, a desperate creature is erratic. This single rule produces both reliability the player can learn and mistakes the player will remember.

### Interrupts, commitment, and hysteresis

- Flee and avoid can interrupt any action when safety urgency crosses a high threshold.
- Every other action carries a small commitment bonus while in progress, so creatures finish eating, carrying, and resting instead of dithering between near-equal scores each tick.
- A target stays cached until reached, invalidated, or interrupted. Re-deciding is the expensive operation; moving is cheap. Protect the decision budget accordingly.

## Perception: creatures act on what they know, not on the truth

A creature perceives only what falls inside its sensory radius, degraded by its sensory noise, plus what it remembers. The simulation must maintain that distinction rigorously: decisions read the creature's knowledge, never the global world state. Cheating perception is an invisible script — a creature that walks unerringly to food it has never seen is being puppeteered.

- **Spatial hash.** A uniform grid with cell size near the maximum sensory radius serves all neighbour, material, and social queries. No system ever scans all creatures.
- **Scent and gradient fields.** Shared flow fields toward water and toward food scent, recomputed per region about once per second, give cheap long-range hints without per-creature pathfinding. A field is a hint with noise, not a route; creatures still take wrong turns.
- **Place memory.** Creatures remember visited places with the resources and dangers encountered there, decaying over time. Returning to a remembered place is a decision made from memory and must sometimes be wrong because the world changed — a dried pool a creature still travels to is a story, not a bug.
- **Reserve true pathfinding.** Straight steering with grid collision handles most movement. Reserve A* for the few creatures that must route precisely around a new obstacle, and cap how many can request it per tick.

## Memory and lifetime learning

### Episodic memory record

Each creature keeps a ring buffer of roughly 32 records. A record stores time, place, actors involved, action taken, context (needs at the time, materials present, nearby creatures), outcome as need changes, and stress at encoding. Retrieval scores past records by similarity to the current context; the best matches bias current action weights.

Decay applies per record, multiplied over time. High-stress records decay more slowly. Forgetting is load-bearing: it bounds memory cost, lets feuds cool, lets stale place knowledge expire, and forces cultures to be maintained by practice rather than remembered forever by one long-lived creature.

### The one learning rule

After an action, and again a few ticks later for delayed effects, compare need levels before and after against what the current weight predicted:

> Change in weight = learning rate × stress at encoding × (actual need improvement − expected improvement)

Three properties do all the work. Prediction error means routine success teaches little and surprising rescue teaches a lot. Stress weighting means episodes at near-critical need consolidate strongly without anyone coding "trauma". The delayed second evaluation means slow effects — resting somewhere safe, eating food that later harms health — can still teach.

### Worked example: hoarding, with no hoard rule

1. A creature nearly starves far from food. Hunger is near critical, so stress is high.
2. It finds a pile, eats, and survives. The episode — place, the carrying and eating actions in its recent sequence, the recovery — consolidates strongly because stress was high.
3. The learned weight for carrying food and adding it to a pile, in contexts of food abundance, rises: in the remembered episode, having food secured preceded survival.
4. Weeks later, beside abundant food and with hunger low, the generic pile action still scores above idling because of that learned weight, reinforced by any inherited conscientiousness.
5. The creature stockpiles. It looks like foresight. It is weighted memory plus timing: abundance after scarcity.

Run the same rule backwards and it produces the opposite personality from the same code. A creature attacked while carrying food learns a negative weight for carrying in the open, and thereafter drops its load when threatened. Both creatures are behaving "in character", and neither character was written.

### Imitation without language or teaching

- **Observation.** When a creature is within sensory range of another performing an action that visibly improves its state — eating, resting comfortably, storing — the observer gains a weak copy of that action's weight in that context, scaled by its imitation fidelity gene.
- **Context travels with the copy.** Copying must carry action plus context, not just destination. A creature that copies "pile food" without the home context piles food anywhere — a plausible origin for middens and scattered caches, not a bug to patch.
- **Fidelity stays below perfect.** Cap copied fidelity below 1.0 and keep curiosity alive. Perfect copying creates a monoculture that cannot adapt when the player moves the water.
- **Youth window.** Imitation fidelity is temporarily higher early in life. Children start near parents, so local practice reaches the next generation through proximity alone.

## Social system: events, not relationships

### Opinion is a sum of remembered events

Each creature stores opinions only about creatures it has interacted with or is kin to: a sparse map of at most about 30 entries holding signed valence, last-seen time, kinship, and event count. Opinions are asymmetric — one creature can value another far more than it is valued back, as in RimWorld's opinion system, where personal opinions are not shared and remembered thoughts stack with magnitudes and decay.

Events are generic and their valence is computed from need impact at the time:

| Event | Valence depends on |
|---|---|
| Shared food | Recipient's hunger and the giver's surplus at that moment |
| Food taken | Whether food was abundant, and how hungry the loser was |
| Harm done | Damage, and whether the victim was already vulnerable |
| Help by proximity | Danger averted while the other was near |
| Socialised | Both creatures' social need and existing opinion |
| Mated | Compatibility, opinion, and reproductive state |
| Witnessed success | No direct valence; feeds imitation instead |

Timing is the meaning. Taking the last food from a starving creature is a betrayal; taking from an abundant pile is housekeeping. Any system that assigns fixed valence to an act regardless of context will produce feuds that feel random and kindness that feels free.

### Behaviour reads opinion at encounter time

There is no "if rival, then fight" branch. At an encounter, approach and socialise scores rise with positive opinion and sociality; avoid and flee scores rise with negative opinion discounted by boldness; sharing rises with opinion, surplus, and reciprocity memory; contest behaviour rises with negative opinion, competing need, and aggression. A bold, aggressive creature with a grievance tends to fight. A timid one with the same grievance tends to flee and avoid. Same memory, different creature, different story.

### Dominance is remembered outcomes

After a contest over a resource, winner and loser both record the outcome. Next time, the loser's avoid score and the winner's approach score carry that history. A stable hierarchy is a pattern across many memories, and it can reverse when bodies change — a grown child, an aged former dominant — because nothing stores a rank that would need a script to update.

### Family is a starting condition for memory

Children begin with lineage knowledge: parents and siblings receive a kinship bonus to opinion and sharing, and a kinship penalty to mating. Family is not a separate system with its own behaviours; it is an initial condition fed into opinion, imitation proximity, and reproduction gating, and then left for events to overwrite.

### Labels are for the player only

The interface labels a pair friends above a high positive threshold, rivals below a negative threshold with at least three events, mates after mating with positive opinion, and kin by lineage distance. The brain never reads these labels. Labels update as memory decays and new events arrive, so the player can watch a rivalry cool into indifference when the creatures stop meeting — and that cooling is itself a story worth surfacing.

### Cooperation without an altruism script

Sharing scores highly when surplus, positive opinion, sociality, and reciprocity coincide. Repeated sharing raises opinion, which raises sharing: a feedback loop, not a cooperation module. Defection breaks the same loop through the same memory. Protect the loop's fragility — if sharing is ever made unconditionally good, cooperation becomes the only strategy and carries no information about the creatures.

## Reproduction and evolution

### The reproduction gate is generic

The mate action scores highly only when both creatures are past maturity, adequately fed, watered, rested, and safe, near each other, compatible, not close kin, and not negatively disposed toward each other. Healthy old creatures remain eligible, so adult and old cohorts can overlap. There is no breeding season script. If seasons or scarcity cycles exist, breeding pulses fall out of food availability on their own.

### Inheritance procedure

1. For each locus, select one parent's value, or average both with noise — pick one scheme in the prototype and keep it consistent so results are interpretable.
2. Mutate each locus with probability around 1–3%, adding Gaussian noise of roughly 5% of the locus range.
3. With probability around 0.1% per locus, apply a larger jump — the rare defect or advantage.
4. Decode through clamps and the body-cost budget. Allow births that look unfit for the current world. Selection, not the birth check, is the judge; pre-judging fitness means designing the species yourself.
5. Record lineage: parents, birth time and place, mutation count from each parent, and a founder-line identifier.

### Selection is the world

There is no fitness function anywhere in the code. Creatures that eat, avoid danger, and reproduce leave more copies of their parameters; creatures that do not, do not. The finite resources are food, water, protected positions, and mates — and the player controls the placement of the first three. That is the entire evolutionary game, and it mirrors the artificial-life lesson of Tierra and Avida: complexity arose from competition for a finite resource, not from a designer ranking organisms.

### Drift, speciation-lite, and diversity protection

Keep a lineage identifier and a simple genetic-distance measure. Mating probability falls with genetic distance, which preserves recognisably different populations without implementing full NEAT speciation. Monitor diversity directly: if the population's genome variance collapses toward a single point, the world has stopped evolving and become a monoculture — treat that as a balancing failure, and fix it through trade-offs and environmental variety, never by forcibly re-randomising living creatures.

## Stigmergy and culture

Stigmergy is coordination through the environment: termites deposit material, the deposit attracts more deposits, and pillars and chambers emerge with no plan and no leader. This game has three stigmergic channels, and together they are why culture can outlive individuals:

- **Piles and structures.** A food pile or a hardening sand structure is visible to every creature that passes, long after its maker has forgotten it or died.
- **Trails and worn places.** Repeated travel and resting change cells — compaction, clearing, accumulated debris — so frequented routes and places advertise themselves.
- **Shared local landscape.** Children inherit no learned weights, but they are born into their parents' piles, structures, and routes, and absorb the practice those artefacts make easy.

Define a **practice** operationally, for detection and display only: the same action, in the same kind of context, performed by at least a threshold number of distinct creatures in one region within a time window. The simulation never stores "this region's practice is X". The detector watches behaviour, names the pattern for the player, and tracks its spread and death on the map overlay. When the founder of a practice dies and the practice persists, the game has produced culture by any honest definition it needs — preserve that fragility rather than protecting practices artificially.

A culture fails in instructive ways, and all of them should be possible: the discoverer dies before being observed; copiers copy the action without its context and the practice degrades; the player moves the water and the practice becomes a liability its holders must unlearn; a rival region's different practice out-competes it where the two meet.

## Emergence collision catalogue

Each entry follows the same discipline: the behaviour the player sees, the systems that collide, the timing or order that matters, the evidence the player can inspect, and the tuning knob if the behaviour is too weak or too strong. If a future feature cannot be written in this format, it does not ship.

### Hard-sand shelter

- **Systems:** pile action × wetness, compaction, and drying × safety and comfort affordances.
- **Timing:** wet first, compacted second, dried third. Any other order fails honestly.
- **Evidence:** cell history in the inspector — wetness at pile time, hardness now; creatures resting preferentially in protected positions.
- **Knobs:** drying rate, compaction per resting creature, safety value of exposure reduction.

### Hoarding and food caching

- **Systems:** store or pile action × stress-weighted episodic memory × conscientiousness weighting.
- **Timing:** scarcity first, abundance second. Hoarding before any scarcity is just a high base store weight and should be rare.
- **Evidence:** the creature's near-starvation memory, its learned store weight, piles growing while its hunger is low.
- **Knobs:** stress weighting, memory decay for high-stress records, base store score.

### Rivalry and feuds

- **Systems:** competition for the same resource × negatively valenced event memory × aggression or avoidance at re-encounter.
- **Timing:** repeated encounters in the same place. A single theft makes a grudge; repetition makes a rival.
- **Evidence:** the opinion panel — event list, valence, and count for the pair.
- **Knobs:** valence scaling by victim need, opinion decay rate, encounter frequency via resource distribution.

### Territory without borders

- **Systems:** return-to-remembered-place × growing stigmergic piles × avoidance of negatively regarded others' places.
- **Timing:** a positive feedback loop over days — the pile grows, visitors avoid it, the owner returns more, the pile grows.
- **Evidence:** the territory map tint, which is drawn from pile clusters and visit frequency, never from a claimed-border data structure.
- **Knobs:** place-memory decay, pile erosion rate, avoidance weight for contested places.

### Tool and material use

- **Systems:** pick up and carry × the carried material's properties modifying the carrier × threat or need context.
- **Timing:** carrying a hard chunk is a cost until the moment it reduces harm; only then does its learned weight rise and copying begin.
- **Evidence:** carried-item sprite, the safety outcome in the carrier's memory, observers' copied weights.
- **Knobs:** carry cost by density and body strength, defensive value of hardness, drop probability under stress.

A hard chunk that reduces harm is a shield in every way that matters, and a heavy food lump carried home is a pack. Neither needs a tool category, a tool gene, or an equip slot.

### Villages and local culture

- **Systems:** imitation × stigmergy × the youth imitation window.
- **Timing:** discover, succeed visibly, be observed, be copied, be repeated — in that order, over days.
- **Evidence:** the practice detector and spread overlay; lineage and place histories showing persistence past the founder's death.
- **Knobs:** imitation fidelity cap, artefact decay rates, youth window length.

### Migration and exodus

- **Systems:** regional food depletion × place memory of a distant resource × copying of route and destination.
- **Timing:** depletion first, individual departures second, group movement only once copying and trails align. A migration that starts instantly and unanimously is scripted, whatever the code says.
- **Evidence:** departure order in the log; trail formation; the old region's piles abandoned and eroding.
- **Knobs:** food regrowth, place-memory range and decay, curiosity weight under local scarcity.

### Division of labour — expect a weak form, promise nothing

Creatures with different bodies, thresholds, and histories will settle into different activity mixes: far-seeing creatures find food first, strong creatures accumulate piles, social creatures cluster. That is specialisation of behaviour, and it is worth surfacing in statistics. Do not promise roles, jobs, or coordinated labour — nothing in the system assigns, requests, or rewards a role, and coordinated labour would need communication this design deliberately omits.

### Middens, graves, and other honest accidents

Expect refuse heaps where copied piling lost its context, favoured resting places that become communal, and contested piles that function as arenas. Log and highlight these when detectors notice them, but do not name them in creature code, do not reward them, and do not add systems to make them more likely. Their value is precisely that nobody designed them.

## Systems interaction map

Read each row as: this system writes something the next systems read. A proposed change that touches one cell of this table must be checked against every reader of that cell.

| System | Writes | Read by |
|---|---|---|
| Player placement | Material amounts | Materials, perception, needs |
| Materials | Cell properties and affordances | Brain, needs, learning, rendering |
| Needs | Urgency after curves | Brain, stress, reproduction gate |
| Genome | Thresholds, rates, weights, body | Needs, brain, memory, movement, appearance |
| Perception | Known targets, neighbours, places | Brain, social, learning |
| Brain | Chosen action and target | Movement, materials, social, memory |
| Action execution | World edits: compacted ground, moved material, reduced nutrition, a creature relocated | Materials, perception, needs, memory — every verb is also a world-edit, which is why behaviour accumulates instead of just happening |
| Memory | Learned weights, place and episode records | Brain, inspector, log |
| Social memory | Opinion and reciprocity | Brain at encounters, labels, lineage view |
| Stigmergy | Piles, structures, trails | Perception, brain, culture detector |
| Evolution | Next generation's genome distribution | Everything, one generation later |
| Legibility | The player's next placement | Placement — the log, inspector, practice detector, and territory tint close the outermost loop: player watches, forms a theory, places, and revises the theory |

Evolution is the slowest and most powerful loop in the game: a change that feels small in one creature's lifetime can dominate once selection amplifies it across generations — which is why balance testing must run for simulated weeks, not minutes. Legibility is the outermost loop, and the only one that runs through a human.

## Systems in depth: how the collisions actually work

The sections above specify each system on its own: the material grid, the needs, the genome, the brain, memory, social memory, stigmergy, evolution. This chapter specifies what happens *between* them — what each system writes that the others read, how fast each loop runs, what order events have to arrive in, and why the same few parts produce a different world every run. The collision catalogue earlier lists the behaviours to expect; this chapter traces the mechanism underneath them, so a behaviour can be debugged as a collision rather than admired as a mystery.

Nothing in this chapter adds a system. If a behaviour described here seems to need one, the chapter has failed its own test, set out at its end.

### The locked inventory, in one breath

- **Player:** 3 inputs only — sand, water, food, placed by brush and amount.
- **Creatures:** 13 generic verbs — move to, wander, seek, eat, drink, pick up, drop or pile, rest, flee, approach, avoid, mate, socialise.
- **Inside each creature:** 9 needs with response curves (hunger, thirst, energy, safety, health, social, comfort, curiosity, reproduction), 5 personality axes (boldness, sociality, curiosity, aggression, conscientiousness), about 25 clamped genome numbers, and 1 learning rule.
- **World:** 1 property language — every cell carries material, amount, wetness, temperature, hardness, cohesion, density, nutrition, and age.

That is the entire premise. There is no shelter verb, no hoard verb, no fight verb, no village verb, and no tech tree. Everything else in this plan has to be a collision between items on this list. The inventory is locked because each addition is not one more feature — it is a multiplier on every interaction the new item can have with everything already here, and a new way for a designer to shortcut a collision by scripting it.

### Why a small set explodes

A decision is not 13 choices. It is 13 verbs × every reachable target in sensory range × the current urgency of 9 needs after their curves × 5 personality weights × remembered places, piles, and creatures × the properties of the ground underfoot. Even a short behaviour — five decisions in sequence — already runs into millions of distinct paths, and that count ignores order, which the timing section below shows is itself meaningful.

Two multiplications make runs unrepeatable in practice:

- **Pairs.** With 500 creatures there are 124,750 possible pairs, each holding its own asymmetric, decaying social memory. No designer enumerates those relationships; no two runs populate them the same way.
- **World state.** A 512 × 384 grid is 196,608 cells, each carrying its own wetness, hardness, nutrition, and age, all changing under creature traffic. The same founders, placed in the same world, diverge as soon as one stochastic choice moves one creature onto different ground.

Replayability, on this design, is not content added later. It is what remains when the state space is left unconstrained — which is why so many of the failure modes below are ways of accidentally constraining it.

### What each system writes, and who reads it

The interaction map above is the summary. This is the same graph in prose, with the consequences that only appear when a write is followed through its readers.

**Placement writes material amounts — nothing else.** But amount is dosage. A little water dampens sand; a lot makes a pool that flows and floods. A little food feeds whoever is nearest; a lot creates competition, rot, storage, and a place worth contesting. Placement also writes *timing*: water placed in a hot, exposed spot behaves differently from water placed in a shaded hollow, because evaporation, drying, and hardening all run on clocks. The player never writes a creature's state directly, yet controls the initial conditions of every downstream system.

**Materials write properties and affordances.** A cell never says "I am shelter." It says hardness 0.8, cohesion 0.7, dry, enclosed on two sides — and the brain reads that bundle as safety and comfort. A food pile says nutrition 40, amount 12, and the brain reads hunger relief. Because affordances are computed from properties at query time, a material state nobody planned — a half-dried, half-compacted pile at a particular angle — is usable by creatures the moment it exists, with no creature code written for it.

**Needs write urgency.** Each need's curve is flat when satisfied and steep when critical, and urgency is all the brain ever sees. There is no coded priority ladder: a mildly hungry creature socialises because hunger's urgency is low, and a starving one thinks of nothing else because it is not. Safety interrupts everything not because a script says "safety first" but because its curve rises fastest — interrupt behaviour is a curve shape, and can be tuned as one.

**Genome writes the starting shape of everything else.** One locus is read by several systems, so one mutation ripples across them. A larger sensory radius means earlier discovery, which means that creature is the one neighbours observe, which means its practices are the ones that spread — a sensing gene becomes a cultural gene one step removed. A faster metabolism means wider ranging and sooner starvation. Body size trades against hunger through the decode-time cost budget, so no gene is a pure upgrade; if one were, selection would collapse the population onto it and evolution, the slowest loop, would stop.

**Perception writes knowledge, not truth.** A creature knows only what falls inside its sensory radius, degraded by its sensory noise, plus what it remembers — and memory can be stale. So a creature travels to a pool that dried up yesterday, acting correctly on wrong information. Another walks past food while fleeing, because fleeing was decided first and decisions carry commitment. That gap between knowledge and truth is where most individual stories come from. A creature with perfect global knowledge would be a puppet: always right, never interesting, and indistinguishable from the simulation optimising itself.

**The brain writes a choice.** For each verb and target the score is need urgency after its curve × personality weight × memory modifier × advertised value, minus distance, danger, and effort. The brain then samples from the top few scores instead of maximising, with the sampling temperature rising under distress. A comfortable creature is therefore predictable — the player can learn its habits — and a desperate creature makes mistakes: takes the exposed route, eats the doubtful food, contests a stronger rival. Both properties are load-bearing. Predictability is what lets the player form theories; mistakes are what turn theories into tragedies and surprises.

**Action writes the world back.** This is the write that makes behaviour accumulate. Moving compacts the ground a little. Resting compacts it more. Dropping adds material to a cell; picking up removes it; eating reduces its nutrition. Every verb is also a world-edit, so a creature is never merely responding to the world — it is continuously, incidentally rewriting the world the next creature will perceive. Remove this write and creatures would act forever in a world that never bore their marks: no piles, no trails, no hardened resting places, no stigmergy, and nothing for culture to be carried by.

**Memory writes weights and stories.** Each creature keeps about 32 episodic records — time, place, actors, action, needs at the time, materials present, outcome as need changes, and stress at encoding — and retrieves them by similarity to the present context. The one learning rule does all the teaching:

> Weight change = learning rate × stress at encoding × (actual need improvement − expected improvement)

Routine success teaches almost nothing, because the prediction error is near zero. A surprising rescue teaches a lot. And the delayed second evaluation — the same outcome re-judged a few ticks later — is what lets slow causes teach at all: resting somewhere safe only proves itself over time, and food that harms health does so after the eating is over. Without delayed evaluation, creatures could only ever learn from immediate payoffs, and both shelter preference and food avoidance would be unlearnable.

**Social memory writes opinion.** The store is sparse, asymmetric, and capped at about 30 others: only creatures actually interacted with, each valued independently of how they value back. Crucially, valence comes from need impact at the time, not from the act. Sharing food with a full creature is a small event; sharing with a starving one is a large one. Taking the last food from a starving creature is a betrayal; taking from an abundant pile is nothing. At the next encounter that opinion merely tilts the approach, avoid, share, and contest scores — there is no "if rival, fight" branch anywhere. A bold, aggressive creature with a grievance tends to contest; a timid creature with the identical grievance tends to avoid. Same memory, different creature, different story.

Dominance is the same trick stretched over time. Repeated contest outcomes accumulate in memory until they read as a hierarchy — and because no rank is stored anywhere, the hierarchy reverses on its own when bodies change: a grown child, an aged former dominant. A stored rank would need a script to update it. A remembered pattern updates itself.

**Stigmergy writes the world as memory.** Piles, hardening structures, and worn routes outlive the creature that made them. A child inherits no learned weights — that separation is absolute — but it is born into its parents' piles and routes, and absorbs the practice those artefacts make easy, simply because the easy action near a pile is the pile action. That is culture with no language, no teaching system, and no culture module. Artefacts decay, so a culture must be maintained by practice or it erodes — which is exactly why moving the water can kill a village without anyone being told to leave: the practice's context is gone, the artefacts stop being refreshed, and the norm dies of disuse rather than decree.

**Evolution writes the next generation's starting point.** The mate verb scores highly only when a creature is adult, fed, watered, rested, safe, and near a compatible non-kin creature it does not hate. Children recombine parental loci with small mutations, decoded through clamps and the body budget. There is no fitness function: creatures that eat, avoid danger, and reproduce leave more copies, and that is all. The player, by placing food and water, is literally choosing selection pressures — placement is evolution's environment, written in advance. This loop is the slowest and the most powerful, because a change that is marginal in one lifetime can dominate after selection amplifies it for generations.

**Legibility writes the player's next placement.** The log, the "why did it do that?" inspector, the practice detector, and the territory tint are not decoration on top of the simulation; they are the final write in the graph. Player watches → forms a theory → places sand, water, or food → the world responds → the player revises the theory. The player is the outermost system in the interaction map. Break legibility and the whole graph still runs — but it reads as randomness, no matter how real the emergence underneath it is. That is why legibility work is scheduled as a simulation phase, not as polish.

### Timing, cadence, and order are systems in their own right

Most designs that call themselves emergent cheat here: when a behaviour is missing, they add content. In this design cadence does that work instead. Each loop runs at its own rate, and the differences between rates are behaviour.

| Loop | Cadence | What the cadence produces |
|---|---|---|
| Hunger and danger scoring | Every decision tick | Fast reaction; a threatened creature is never caught mid-thought |
| Social scoring | Every few seconds | Feuds and friendships evolve slowly and do not flicker between encounters |
| Material affordances | On entering a new neighbourhood | No re-planning for every cell crossed; places, not cells, are the unit of intention |
| Learning outcome | At action end, then again a few ticks later | Slow causes — safe rest, harmful food — can teach |
| Cultural transmission | One full sequence, over days | Discover → succeed visibly → be observed → be copied imperfectly → be repeated → become a norm |
| Evolution | Generational | Nothing learned is inherited; only the genome moves forward, and only through survival |

Three cadence effects deserve naming because they read as character and cost almost nothing:

- **Commitment.** A fleeing creature finishes fleeing before hunger wins again. That lag — a creature still running from a danger it has already escaped — reads as temperament, and it is only an interrupt threshold plus a commitment bonus.
- **Delayed learning.** Because the second evaluation happens later, two creatures can perform the same action and learn opposite lessons from it, depending on what the world did next.
- **The skippable culture sequence.** Every step in discover → succeed → be observed → copied → repeated → norm is necessary, and any step can fail. A discoverer who dies before being observed takes the innovation with them — unless a pile or structure survives them. That single exception is why stigmergy matters more than any individual genius: artefacts are the only channel through which a dead creature can still teach.

Order flips outcomes with identical ingredients. The same three events, rearranged, are different materials and different creatures:

| Sequence | Outcome |
|---|---|
| Wet → compacted → dried | Hard sand |
| Compacted → wet → never dried | Mud |
| Dry → piled | A loose dune |
| Starvation → food found → later abundance | A hoarder: the high-stress episode consolidated, so the pile action keeps scoring in abundance |
| Abundance → starvation → abundance | A different creature from the row above — the scarcity memory formed against a lifetime of plenty, not as its first lesson |

The design consequence is a rule, not an observation: if you want a new behaviour, do not add a verb. Change the order, the cadence, or the context in which two existing systems meet. A verb added to force a behaviour is visible forever in the vocabulary; a cadence change that lets a behaviour appear is invisible in the code and repeatable across situations nobody foresaw.

### Traced collisions: the mechanism, not just the claim

The collision catalogue gives each expected behaviour its systems, timing, evidence, and knobs. The traces below walk the same behaviours step by step through the writes and reads, and — the part the catalogue cannot show — what breaks when one piece is removed. A trace that survives a removal intact was never depending on that piece, and the piece was decoration.

**Shelter district.** Safety need high → the pile verb chosen for an already-sheltered spot → the pile is wet sand → resting on it compacts it → time dries it → hardness and cohesion rise → the safety affordance of resting there rises → the learning rule raises the weight for resting and piling there → neighbours observe a visibly comfortable creature and copy nearby. Remove any one piece and it falls apart honestly: no drying, mud; no resting, no compaction; no safety affordance for hard cells, no reason to return; no observation, one creature's shelter — never a district.

**Hoarder village.** Near-starvation at high stress → a pile found and eaten from → survival, so the episode consolidates strongly → later abundance arrives, but the learned pile weight persists → inherited conscientiousness tilts the same verb further → the piles themselves persist as stigmergy → children are born near piles, inside the practice → the youth imitation window copies it. The village is not planned by anyone. It is a trauma, remembered by individuals, copied by neighbours, and then inherited environmentally by creatures who never starved. Remove the stress weighting and the first episode teaches no more than lunch did; remove artefact persistence and each generation starts from bare ground.

**Feud and territory.** Two creatures, one food pile → food taken at a moment of high victim hunger, so the event's valence is strongly negative → repeated encounters at the same pile repeat the lesson → at re-encounter, opinion tilts one toward contest and the other toward avoidance → both hold place memory of the contested spot → the pile there grows, because it is worth returning to and worth defending → other creatures, reading the same signals, avoid the spot. Territory is the tint drawn over pile clusters and visit frequency. There is no border data structure to cheat with — if the tint cannot be drawn from behaviour, there is no territory, whatever the map looks like.

**Tool use.** Pick up → carrying costs scale with the material's density and the carrier's strength → a contest happens while a hard chunk is carried → the chunk's hardness reduces the harm taken → that safety improvement, caught by the learning rule, raises the carry weight in threat contexts → observers copy carry-in-threat. A shield is a property bundle in a hand, not a tool type; the same trace with a heavy food lump carried home is a pack, not an inventory system. Remove the property-to-carrier effect and carrying is pure cost, so nothing is ever carried except food in transit — which is the correct negative control for the trace.

**Migration.** Regional food depletes → a creature with place memory of a distant water or food source scores seek above local wandering, helped by curiosity under local scarcity → it departs alone → its route compacts into a trail → other creatures copy the route and the destination, imperfectly → group movement appears only once trails and copying align. If everyone leaves instantly and unanimously, that is a script, however it is coded: real migration here is staggered, partial, and leaves stragglers whose memories pointed elsewhere.

**Honest accidents.** Copied piling without its context makes middens. A favoured resting place becomes communal without anyone founding anything. A contested pile becomes an arena. These are not catalogue entries to engineer toward: do not name them in code, do not reward them, and do not add systems to make them more likely. Their value is precisely that nobody designed them — they are the control group proving the designed traces are not the only thing the collisions can produce.

### Divergence: what makes runs differ, and what kills it

Endless replayability is divergence that survives contact with the balancing process. Seven sources produce it:

- **Founder genetics.** A wide founder genome spread means the first discoveries are made by different kinds of creature in different runs.
- **Player placement history.** Where and when sand, water, and food were placed is an input no two players repeat.
- **Founder effects.** Who happens to survive the first famine decides which genomes, memories, and practices the rest of the run is built from — an accident of timing with generational consequences.
- **Path dependence.** A culture or territory that locks in early changes what later creatures can learn, copy, and contest.
- **Stochastic choice.** Softmax sampling means near-equal scores resolve differently, and early coin-flips are amplified by every loop above.
- **Forgetting.** Decaying memory re-opens settled questions: stale places are revisited, cooled feuds can restart, and old practices must be re-earned.
- **Death erasing innovations.** Knowledge held only in one creature's memory dies with it, so progress is genuinely losable.

Each source has a corresponding way to kill it, and every one of these has appeared in real designs as an innocent-looking convenience:

| Killer | What it does to the run |
|---|---|
| Perfect copying (imitation fidelity at 1.0) | One practice wins everywhere; a monoculture that cannot adapt when the water moves |
| Artefacts that never decay | The first discovery becomes permanent; later runs differ only in who found it first |
| Genes without trade-offs | One optimal build; selection converges and then has nothing left to do |
| Memory that never forgets | Feuds are eternal, every place is permanently known, no question ever re-opens |
| Food that regrows instantly | Scarcity vanishes — and with it any reason to compete, hoard, cooperate, or migrate; only wandering, eating, and sleeping remain, forever |

Treat any proposed convenience against this table before implementing it. Divergence is easy to destroy accidentally and impossible to restore by adding content afterwards.

### The tuning knobs: tune the collision, never add an exception

Nine knobs, in plain terms, cover most of the ways the collisions can run too weak or too strong. They are also entered in the parameter register in Appendix B, so a change to any of them is recorded with the soak metric that motivated it.

| Knob | Raised | Lowered |
|---|---|---|
| Drying rate | Hard sand forms sooner; shelter practices appear earlier | Wet ground stays mud; piling teaches nothing |
| Compaction per rest | Resting places harden and become worth returning to | Structures never firm up, however often they are used |
| Stress weighting in the learning rule | Scarcity and danger leave deep, lasting lessons | Trauma teaches no more than routine; hoarding and avoidance weaken |
| High-stress memory retention | Grudges and lessons from crises persist across a lifetime | Crises are forgotten; every famine is the creature's first |
| Imitation fidelity cap | Practices spread faster and more uniformly | Discoveries stay private and die with their discoverers |
| Artefact erosion | The world forgets faster; cultures must be actively maintained | First discoveries become permanent (see the divergence killers) |
| Place-memory decay | Known places expire sooner; exploration re-opens | The map is permanently solved; migration loses its reason |
| Food regrowth | Scarcity softens; population stabilises at a higher level | Scarcity deepens; at the extreme, famine outlasts every adaptation |
| Softmax temperature when distressed | Desperate creatures act more erratically; more mistakes, more stories | Desperation looks like calm optimisation; distress becomes invisible |

The rule governing all nine is the one the research behind this plan kept returning to: when emergence goes degenerate, tune the interacting systems — never add a scripted exception for the degenerate case. An exception fixes the symptom in the one situation that prompted it and silently breaks the same collision everywhere else. A knob change moves the whole behaviour family, which is what was actually wrong.

### The gate for every new idea

The five emergence tests in the governing-principle section are the merge gate. Applied to a new idea, a proposed behaviour, or a suspiciously convenient result, they reduce to four questions to answer in order:

1. Can the behaviour be named without naming a module? If its name is a file, a branch, or a flag, it is a script.
2. Can the two or three contributing systems be named, plus the timing or order that makes them collide? If not, the mechanism is not understood yet.
3. Does disabling one of those systems change or remove the behaviour in a debug build? If not, that system was decoration and the real cause is elsewhere.
4. Clicking the creature, can the need, memory, relationship, or material property that caused the action be pointed to in the inspector? If not, the legibility is missing before the behaviour is.

If any step fails, it is not emergent yet — it is a script waiting to be noticed. That is not a reason to discard the idea; it is the instruction for what to build instead: the missing system interaction, the missing cadence, or the missing inspector evidence.

## 2D art direction

### Sprites serve legibility first

Creatures are small 2D sprites, simple enough to render by the thousand and distinct enough to follow individually at close zoom. The art budget goes on readability of state, not detail:

- Silhouette varies with body size gene; pattern and tint vary with appearance genes.
- Carried material is drawn on the sprite. A carrying creature must be identifiable at a glance.
- Hunger desaturates; exhaustion slows the animation; wetness darkens. State is shown by transformation of the same sprite, not by icons floating over every creature.
- Selected creatures, and only selected creatures, get a ring, name, and need display.
- Terrain shows material state honestly: wet sand is darker than dry sand, hard sand is visibly denser and lighter than mud, piles grow with amount. If the player cannot see wet, dry, hard, piled, and contested, they cannot see timing — and timing is the game.

### Animation is action, rendered

Animation states derive from the current generic action: walk, eat, drink, carry, pile, rest, flee, socialise. There is no shelter-building animation, because there is no shelter-building action — a creature piling wet sand animates as piling, and becomes a builder only in the player's understanding. That restraint is what keeps the visual language honest, and it caps the animation set at about eight short loops regardless of how complex behaviour becomes.

## Rendering at scale

Rendering is the smallest of the three budgets if — and only if — the fatal pattern is avoided: never one scene node or game object per creature.

- **One atlas.** Pack every creature frame, pattern layer, terrain glyph, and pile stage into one or two atlases. Batching breaks on texture and blend-mode switches, so creatures use one material and one blend mode; selection rings and highlights live in a second batch.
- **Instancing for creatures.** In Godot, one MultiMesh per world chunk, with per-instance transform plus custom data carrying atlas frame, tint, and flip; a shader advances animation from that data. A MultiMesh cannot cull individual instances, which is exactly why the batch is per chunk: culling works at chunk granularity.
- **Chunk textures for terrain.** Each chunk renders to a cached texture and repaints only when its cells change. A full world then costs one quad per visible chunk instead of a sprite per cell, and player painting marks a few chunks dirty instead of rebuilding a scene.
- **Zoom defines the view, honestly.** Near zoom shows individuals and stories. Mid zoom shows individuals without per-creature detail. Far zoom swaps individuals for density and territory tints — the player is reading populations there, not creatures, and the interface should say so by what it shows.
- **Mind overdraw, not draw calls.** Overlapping translucent sprites cost fill rate. Keep water in the chunk texture rather than as per-cell translucent sprites, cap particles, and avoid full-screen translucent overlays.

Rendering benchmarks from engines — tens of thousands of batched sprites — are render-only figures. They prove the graphics processing unit (GPU) is not the bottleneck for this art style. They say nothing about simulation capacity and must never be quoted as creature counts.

## Simulation architecture

### Layers

- **Simulation layer:** plain arrays and structs, no scene nodes, no rendering types. Entities are integer identifiers; position, needs, genome, memory handles, and state are stored as structure-of-arrays columns.
- **Render layer:** a view that reads simulation arrays each frame and writes instance buffers and dirty chunk textures. It contains no behaviour and makes no decisions.
- **Interface layer:** inspector, log, overlays, and placement tools. It reads recorded events and state; it never reaches into creature internals to change behaviour.

### Tick pipeline, in fixed order

1. Advance world time by a fixed simulation step; rendering frame rate never changes simulation speed.
2. Update dirty material chunks: flow, wetness, drying, hardening, rotting.
3. Recompute shared gradient fields for any region whose materials changed materially.
4. Decay needs for all creatures; update stress.
5. Run decisions for one bucket of creatures (see staggering below).
6. Execute movement and actions for all active creatures; collect social, material, and reproduction events into an ordered queue.
7. Apply queued events: memory writes, opinion changes, births, deaths, pile changes.
8. Run learning updates for creatures whose actions completed or whose delayed outcomes fell due.
9. Run detectors: first-time patterns, practice spread, population and diversity statistics, highlight candidates.
10. Emit log entries and update interface data.

Events go through the queue rather than mutating shared state mid-step. That keeps ordering deterministic for a given seed, makes the causal log trustworthy, and keeps later parallelisation possible: needs decay, material diffusion, and transform updates parallelise trivially, while event application stays single-threaded and ordered.

### Determinism, seeds, and save format

- All randomness flows from a seeded generator. Same seed, same placement script, same version should reproduce the same world — the foundation of every balance and emergence test in this plan.
- Saves store the full simulation state: world time, grid arrays, every creature's genome, needs, memory and opinion stores, learned weights, lineage, event log tail, and the random-generator state. Version the format from the first save; genome or grid changes need a migration or an explicit incompatibility.
- Learned weights and memories are save data, not derived data. Losing them on load would silently delete every creature's character while keeping its body — the worst possible save bug, and one a load test must explicitly check for.

## Performance budgets and scaling tiers

### Three budgets, kept separate

| Budget | Cost driver | Scaling lever |
|---|---|---|
| Rendering | Visible instances and chunk repaints | Atlas, instancing, chunk culling, zoom swap |
| Movement and needs | Creatures × simple arithmetic per tick | Structure-of-arrays sweeps, parallel jobs |
| Decision | Creatures × actions × considerations | Staggering, level of detail, cached targets |

The reference point for staggering is a shipped survivors-style game holding 5,000–6,000 flocking enemies on about one core by updating distant enemies at roughly 3.75 Hz and near enemies at 15 Hz on a 30 Hz simulation. Those enemies were boids — three steering rules, no needs, memory, or social reasoning. Treat that as an upper reference for cheap agents and an explicit warning about rich ones, not as a target for this brain.

### Tiers

| Tier | Population | Decision rate | Behaviour |
|---|---|---|---|
| Full | About 100–300 | 10–20 Hz | Full utility, memory, social, and material interaction; full animation |
| Standard | About 500–1,000 total | 2–5 Hz, staggered by stable buckets | Full utility; social limited to neighbours; cached paths; reduced animation rate |
| Background | 1,000–5,000+ total | 0.2–1 Hz life update | Needs, movement toward remembered goals, aggregate births and deaths; no per-creature social or episodic updates; rendered as dots or not at all |

Assign decision buckets by a stable hash of creature identifier so a creature's cadence never jitters. Significance — near the camera, selected, socially active, or involved in a highlighted event — promotes a creature to a higher tier temporarily.

### Governor and caps

- If a simulation step exceeds its time budget, increase staggering automatically and show a plain "simulation throttled" indicator. Frame rate must never become the invisible population control.
- Prefer in-world caps: births gated by surplus, piles eroding, memories decaying. A hard population cap, if one proves necessary, must be visible in world settings and logged when it bites — never a silent deletion.
- Profile on a mid-range laptop, not the development machine, from Phase 3 onward. Every performance figure in a progress report names its hardware, population, tier mix, and whether creatures were deciding or merely moving.

## Legibility: the interface is part of the simulation

Emergence the player cannot read is indistinguishable from randomness. Legibility gets its own phase in the roadmap and its own systems here — it is not narration added at the end.

### The "why did it do that?" inspector

Clicking a creature shows, in plain language:

- Its top three action scores with their components: need and curve, personality weight, memory modifier, advertised value, distance and danger costs.
- Its last five memories, one line each.
- Its genome translated into words — "bold, far-seeing, fast metabolism, learns quickly from stress" — generated from thresholded gene values, never hand-written per creature.
- Its opinion list with the events behind each entry.
- Its life summary: age, parents, offspring, current place attachments, and major events.

This is the single highest-value interface feature in the game. If a behaviour cannot be explained through this panel, either the behaviour is scripted or the panel is incomplete — both are bugs.

### Causal event log

Every notable event becomes a sentence generated from the same records memory uses, so the log cannot lie about causes:

- "Creature 88 piled wet sand at the north pool. It dried overnight and is now hard. Creature 88 rests there. Creatures 91 and 93 have copied the pile."
- "Creature 412 took food from Creature 207 while 207 was starving. Opinion −18. Third negative event between them: rivalry."

Log lines carry links: click a creature name to select it, click a place to move the camera. The log has world, region, and per-creature views sharing one underlying event store.

### Highlights without narration

Detectors notice first-time patterns — first hardened structure, first stockpile above a size threshold, first rivalry crossing its label threshold, first practice reaching ten creatures — and respond by flashing the location, briefly following the creature, and writing the causal log entry. Do not show a story card that explains the event as if it were authored. Show the causes and let the player name it. Players trust stories they assemble themselves, and they are right to distrust stories a game announces.

### History and lineage views

- Per creature: birth, parents, mates, offspring, major events, cause of death.
- Per lineage: founder, population over time, geographic spread, genome drift.
- Per place: what accumulated there, who built or stored it, what contests happened there.
- Per practice: where it is performed, by how many, whether it survived its founder.

Dwarf Fortress's Legends mode is the model: a persistent, browsable history is not a luxury feature in a simulation game — for many players it is the product.

### Onboarding without a tutorial script

The first session teaches by highlighting, not by instructing: the game points the camera at the first creature to eat, the first pile, the first structure, and offers the inspector. Placement hints, if any, are phrased as questions — "this basin is dry" — never as objectives. The moment the game sets a goal, it has started scripting the player's story as well as the creatures'.

## Balancing and collapse testing

### Carrying capacity is the master dial

Food placed by the player plus any slow world regrowth sets the population the world can support. Births require surplus, so births should fall before starvation begins, not after. If regrowth is used, make it logistic — proportional to uneaten stock — so a grazed-down world recovers slowly and an untouched one saturates, rather than growing without bound.

Scarcity must be real but graded. A world with permanently abundant food produces no competition, no hoarding, no cooperation worth the name, and no migration. A world with permanent famine produces one short story, repeatedly. The interesting band is oscillation: plenty that teaches storing, shortage that tests it, recovery that rewards whoever adapted.

### The no-input soak test

Before any phase is declared complete, run at least ten seeds with no player input for thirty simulated days each and record:

- Population over time — it should oscillate or stabilise, never die out on every seed and never grow without bound.
- Cause-of-death distribution — a single cause above roughly 80% signals a broken system, not a hard world.
- Genome variance over time — collapse to a point signals a trade-off failure.
- Practice formation — at least one detectable practice in most seeds by Phase 4.
- Decision and step times at peak population.

A seed that does collapse is data: read its log, find the first irreversible step, and tune the system that allowed it. Do not rescue it with an exception.

### Degenerate strategies are tuning signals

If every creature piles food in one spot, if nobody ever socialises, if fleeing always beats eating — the scores are mis-weighted. The fix, per the emergence design literature this plan follows, is to tune the interacting systems, never to add a scripted exception for the degenerate case. Keep a written tuning register: every parameter, its current value, why it changed, and which soak metric moved. Untracked tuning is how simulation games drift into unexplainable states nobody can reproduce.

### Deliberate disaster tests

Run scripted *placement* scenarios — placement being the only script the game allows itself:

- **Drought:** no water placement for ten days in a world built around one pool that is then left to evaporate. Watch for migration, conflict at the last water, and learned avoidance of the dry region.
- **Feast then famine:** heavy food placement for three days, then none for ten. Watch for storing during the feast, and whether storers survive the famine at higher rates.
- **Flood the shelter:** water placed onto an established hardened-sand area. Watch whether structures soften, whether residents relocate, and whether the practice re-forms elsewhere.

## Technology choice

### Decision

| Criterion | Godot 4 (recommended) | Bevy (Rust) |
|---|---|---|
| Time to first playable | Fast; strong 2D editor and tooling | Slower; code-first, no visual editor workflow |
| 2D rendering at this scale | Sufficient with atlas and MultiMesh discipline | Excellent; batched sprites and parallel culling natively |
| Simulation ceiling | Good if hot loops move to C# or GDExtension when profiling demands | Higher; entity-component-system (ECS) and parallelism are native |
| Solo-developer risk | Writing the sim as nodes — avoidable by rule | Rust learning curve if not already fluent |
| Cost | Free and open source | Free and open source |

Choose Godot if shipping a playable 100-creature game in months outranks a higher eventual ceiling. Choose Bevy if the thousands-creature target outranks iteration speed and Rust is already comfortable. Do not choose a 3D engine used in 2D, and do not build the shipped game in Python — Python is a fine tool for offline tuning analysis of exported soak data.

Whichever engine is chosen, the decoupling rule is non-negotiable: simulation as data, renderer as view, interface as reader. That rule, not the engine, is what keeps the scaling path open — including the escape hatch of rewriting one hot system in a faster language without touching the rest.

### Project structure

- `sim/` — world grid, materials, creatures, genome, needs, brain, memory, social, events. No engine scene or rendering types.
- `sim/tests/` — unit, property, soak, and benchmark suites, runnable headless.
- `render/` — atlas loading, chunk textures, instanced creature view, zoom tiers.
- `ui/` — inspector, log views, overlays, lineage and history views, placement tools.
- `data/` — parameter register, seed worlds, sprite sources.
- `tools/` — soak runner, log analyser, tuning comparison reports.

Keep the parameter register as data, loaded at start, so tuning never requires recompiling and soak tests can sweep values automatically.

## Phased roadmap

Durations are planning estimates for a solo developer and will slip; exit criteria, not dates, gate each phase. A phase that misses its exit criterion is not finished, however much code it produced.

### Phase 0 — Toy world (about 1–2 weeks)

**Build:** the grid with three static materials, 20 creatures, needs decay, the utility chooser with eat, drink, rest, wander, and seek, and a batched single-atlas sprite renderer. No genome, memory, social, or material simulation.

**Exit criteria:** creatures eat, drink, rest, and wander without instantly dying, freezing, or all stacking on one cell; the toy is worth watching for ten minutes. If it is not, fix movement and scoring here — no later system rescues a dull toy.

**Leave out:** everything else, without exception.

### Phase 1 — Interaction core at 100 creatures (about 4–6 weeks)

**Build:** material simulation (flow, wetness, drying, compaction, hardening, rotting); the full 13-action vocabulary; the parametric genome and reproduction; episodic memory with the stress-weighted learning rule; imitation; the sparse opinion system; the event log and the why-inspector, in first working form.

**Exit criteria:** in seeded test worlds, shelter-like, storing-like, and rivalry-like stories occur with no code naming them, and for each one the log and inspector can show the causal chain end to end. The disable-one-system harness exists and is used on each story: turning off hardening kills the shelter story, turning off stress weighting weakens storing, turning off opinion memory dissolves rivalries.

**Leave out:** culture labels and spread overlays, dominance as an interface feature, seasons, predators, tool categories.

### Phase 2 — Legibility and balance (about 3–4 weeks)

**Build:** highlights and first-time-pattern detectors; lineage, history, and place views; the full visual state language; carrying-capacity and scarcity tuning; the ten-seed, thirty-day soak suite; disaster scenarios.

**Exit criteria:** a new player, unaided, can follow one creature's story for five minutes and correctly explain why it did two things it did; population oscillates rather than collapsing or exploding across the soak suite; cause-of-death and diversity metrics sit in their healthy bands.

**Leave out:** new simulation systems entirely. This phase is tuning and interface. The urge to add a system here is the emergence-illusion trap — behaviour that looks thin in Phase 2 almost always needs stronger accumulation or better surfacing, not a new mechanism.

### Phase 3 — Scale (about 4–8 weeks)

**Build:** structure-of-arrays refactor where profiling points; spatial hash everywhere; decision staggering and tier promotion; chunked instanced rendering with zoom tiers; shared gradient fields; the throttling governor; caps with visible causes. Move only the proven hot loops to C# or GDExtension if Godot was chosen.

**Exit criteria:** 500–1,000 standard-tier creatures at interactive rates and a stable 60 frames per second render on a mid-range laptop, with 5,000 background agents running at life-update rates, measured and reported with hardware and tier mix stated.

**Leave out:** GPU-resident brains, multiplayer, modding support. If the exit criterion cannot be met, cut decision cost — fewer considerations, cheaper sensing — before cutting population, and record the trade in the tuning register.

### Phase 4 — Culture and polish (only if Phases 1–3 hold)

**Build:** stigmergy tuning (artefact decay and erosion rates); the youth imitation window in final form; the practice detector, spread overlay, and territory tint; practice persistence statistics; save-format hardening and migration tests.

**Exit criteria:** at least one practice, in seeded worlds, spreads across a region and persists after its founder's death, visible on the overlay and traceable in the log; moving the water in a disaster test forces that practice to adapt, move, or die.

**Leave out:** any new player power. Culture is the reward for the constraint, and a new power at this point would devalue it.

### Phase 5 — Release hardening (time-boxed, scope-frozen)

**Build:** performance passes on minimum-spec hardware, save compatibility tests, accessibility for the interface (scalable text, colour-independent state cues alongside tint changes), localisation-ready strings for log templates, and a settings screen that exposes world guardrails honestly.

**Exit criteria:** no known save corruption, no silent population cap, soak suite green on release seeds, and a first-time player reaching the Phase 2 legibility standard without developer help.

## Prior art: what to steal, what to refuse

| Work | Steal this | Refuse this |
|---|---|---|
| Conway's Game of Life | Proof that a handful of local rules can generate unbounded pattern | A world with no identity, agency, or persistence of individuals |
| Reynolds' boids | Three local steering rules as the movement layer under the brain | Boids as the brain — flocking alone produces no individual stories |
| Tierra and Avida | Selection from competition for a finite, visible resource | Abstract resources nobody can watch; here the resource is food, water, and protected positions |
| Polyworld | The closest ancestor: watched ecology, foraging, mating, evolved behaviour | A full neural network per creature at this population target |
| Creatures | Genome to body and drives to learning; defects and unpredictability from interacting parts | Full biochemistry per creature — it ran in tens, not thousands — and its opacity about why a creature acted |
| Dwarf Fortress | Personality, stress, relationships, and a browsable history — Legends is a product, not a bonus | Single-threaded per-creature pathfinding and fluids with no level of detail; its long-running slowdown is the warning this plan's tiers answer |
| RimWorld | Asymmetric opinion, traits, mood, and inspectable relationships | The injected storyteller; here the player's placement is the only external pressure |
| WorldBox | Culture, family, and group identity as spreading, diverging, transmissible patterns in a 2D god-game | Race-archetype creatures instead of individual genomes, and a large palette of direct god powers |
| The Sims | Utility scoring, object advertisements, personality and distance weighting, stochastic choice among top scores | Thousands of hand-written social rules, and households too small for ecology or evolution |
| Spore | Procedural variety from parameters | The central warning: visual variety whose parts carry canned stats regardless of form is decoration pretending to be system |
| No Man's Sky | Procedural content at large scale | Variety without coupling — systems existing side by side without interaction produce scenery, not behaviour |
| Noita | The falling-sand material engine: property interactions, chunks, dirty regions, sleeping static material | Nothing about its creatures — they are enemies, not learners; add memory-bearing creatures that read and write the material world |

The pattern across all twelve is the same: the works that produced lasting stories coupled systems together, and the works that disappointed generated variety in systems that never touched each other.

## Testing and verification

Emergence claims are falsifiable or they are marketing. Four test families carry the burden:

- **Unit and property tests.** Material functions (wet sand under compaction and drying hardens; loose dry sand does not), genome decoding (no input produces an out-of-range trait), scoring (a starving creature's eat score exceeds its socialise score under controlled inputs), memory (decay, eviction, and stress weighting behave as specified).
- **Emergence harness tests.** Seeded scenarios run headless: the feast-then-famine scenario must produce higher storing in previously starved populations than in never-starved controls, at a rate stated before the run — not "we saw a creature pile food once". Each catalogue behaviour gets a scenario, a metric, and a threshold.
- **Soak and balance tests.** The ten-seed suite from the balancing section, run on every tuning change and every phase exit, with results archived beside the parameter register.
- **Performance benchmarks.** Fixed scenarios at each tier and population, on named hardware, reporting step time split by budget — render, movement and needs, decision — so a regression names its own cause.

Playtesting has one job the automated tests cannot do: the legibility check. Watch a new player silently for five minutes, then ask them to tell you a story about one creature and explain two of its decisions. Score the explanation against the log. Every mismatch is either an interface gap or a behaviour that is not actually being caused by what the log claims — investigate both possibilities, in that order.

## Risks and mitigations

| Risk | Early signal | Mitigation |
|---|---|---|
| Emergence is real but invisible | Playtesters describe creatures as random | Inspector, log, highlights, visual state language — Phase 2 exists for this |
| Emergence is fake and nobody notices | A behaviour survives its systems being disabled | Delete-the-name and disable-one-system tests on every feature |
| Aimless drift, nothing accumulates | No practices in soak runs; artefacts vanish | Slow artefact decay, strengthen stress consolidation, add real scarcity gradients |
| Population collapse or explosion | Soak curves go monotonic | Surplus-gated births, logistic regrowth, visible guardrail settings |
| Performance death spiral | Step time grows with population; players compensate with more food | Tiers, staggering, governor, honest caps |
| Monoculture genomes | Variance metric collapses | Restore trade-offs; add environmental variety across the map |
| Scope creep into a second game | Feature list grows a language, economy, or tech tree | Non-goals list; every addition must pass the five emergence tests |
| Save corruption of learned state | Creatures keep bodies but lose character after load | Learned state is first-class save data with explicit load tests |

## Open decisions

These belong to the developer and should be settled at the phase shown, not before they are needed:

- Engine confirmation — Godot or Bevy — before Phase 0 ends.
- World size and cell scale, settled by Phase 3 profiling rather than by preference.
- Final art style within the sprite and pattern system, before Phase 2's visual language is built.
- Whether food regrowth exists at all, or the world runs purely on player placement — a Phase 2 balancing decision with large consequences for idle watching.
- Naming, including the game's title and how much individual creatures are named by the game versus by the player.
- Licence and release route, before any public build.
- The single first use case to optimise for — quiet observation, story hunting, or long-running unattended worlds — since it sets defaults for speed controls, highlights, and save behaviour.

## Appendix A: Pseudocode sketches

These sketches fix shape and order, not language or final constants.

### Utility decision

```text
for each action in ACTIONS:
  for each reachable target for action:
    score = 1.0
    for each consideration of action:
      score *= curve(consideration.value, consideration.shape)
    score *= personality_weight(action, creature)
    score *= memory_modifier(action, target, creature)
    score -= distance_cost(target) + danger_cost(target)
    score += commitment_bonus if action == creature.current_action
    record(action, target, score, components)   # the inspector reads this
choose by softmax over the top 4 scores, temperature rising with distress
```

### Learning update

```text
on action_complete(creature, action, context):
  actual = need_improvement(creature.needs_before, creature.needs_now)
  expected = creature.learned[action, context_key].expectation
  error = actual - expected
  creature.learned[action, context_key].weight +=
      creature.learning_rate * context.stress * error
  store episode in ring buffer with stress and outcome

on delayed_outcome_due(creature, episode):
  repeat the update against current needs, with reduced rate
```

### Material step, per dirty chunk

```text
for each cell in chunk:
  flow(cell)              # down, then sideways; density decides swaps
  transfer_wetness(cell)  # neighbours, drain, evaporate
  diffuse_temperature(cell)
  update_hardness(cell)   # from wetness history, compaction, drying
  update_rot(cell)        # nutrition falls; harmful past threshold
  if any property changed beyond epsilon: mark chunk dirty for render
sleep chunks with no changes and no occupants
```

### Birth

```text
child_genome = []
for each locus:
  value = pick(parent_a[locus], parent_b[locus])   # or average + noise; pick one scheme
  if random() < 0.02: value += gaussian(0, 0.05 * locus_range)
  if random() < 0.001: value += gaussian(0, 0.25 * locus_range)
  child_genome.append(clamp(value, locus_range))
decode_with_body_budget(child_genome)
record lineage(parents, place, time, mutation_count)
```

## Appendix B: Starting parameter register

Record every change to this table, with the soak metric that motivated it.

| Parameter | Starting value | Notes |
|---|---|---|
| World grid | 512 × 384 cells | Revisit in Phase 3 |
| Chunk size | 64 × 64 cells | Materials and rendering |
| Actions | 13 generic verbs | Adding a verb needs the five tests |
| Decision rate, full tier | 10–20 Hz | Movement every frame |
| Decision rate, standard tier | 2–5 Hz | Stable buckets by creature identifier |
| Life update, background tier | 0.2–1 Hz | No episodic or social updates |
| Episodic memory capacity | 32 records | Ring buffer, stress-weighted retention |
| Opinion map capacity | 30 creatures | Evict lowest weight × recency |
| Genome size | About 25 loci | All clamped at decode |
| Mutation rate | 1–3% per locus | Plus 0.1% large-jump probability |
| Mutation size | About 5% of locus range | Gaussian |
| Soak standard | 10 seeds × 30 simulated days | No player input |
| Drying rate | Tune in Phase 1 | Governs hard-sand timing; see systems-in-depth knobs |
| Compaction per rest | Tune in Phase 1 | Resting is the main compaction source |
| Stress weighting | Tune in Phase 1 | Strength of crisis lessons in the learning rule |
| High-stress memory decay | Slower than baseline decay | Exact ratio set by soak storing and feud metrics |
| Imitation fidelity cap | Below 1.0 | Perfect copying is a divergence killer |
| Artefact erosion rate | Tune in Phase 4 | Piles and trails decay; culture must be maintained |
| Place-memory decay | Tune in Phase 1 | Expiry of remembered resource and danger places |
| Food regrowth | Phase 2 decision | Logistic if present at all; never instant |
| Softmax temperature, distressed | Above comfortable temperature | Rises with distress; governs mistake rate |

## Appendix C: Glossary

- **Affordance / advertisement:** what a cell, pile, or position offers a need, computed from its properties at query time.
- **Bucket:** a stable subset of creatures whose decisions run on a given frame, used for staggering.
- **Dirty chunk:** a world chunk whose cells changed and which therefore needs material updates or a repaint.
- **Emergence test:** any of the five checks in the governing-principle section, used as a merge gate.
- **Founder effect:** the outsized influence of which creatures happen to survive an early bottleneck on the genomes, memories, and practices of everything after it.
- **Genome / locus:** the inherited parameter vector; one locus is one inherited number.
- **Level of detail (LOD) tier:** a simulation fidelity band — full, standard, or background — assigned by distance and significance.
- **Opinion:** one creature's signed, decaying sum of remembered events about another creature.
- **Path dependence:** a state in which early outcomes — a locked-in practice, territory, or lineage — constrain what later creatures can learn, copy, and contest.
- **Practice:** a repeated action-in-context pattern across creatures in a region, detected for display; never stored as creature knowledge.
- **Response curve:** the function converting a need deficit into urgency.
- **Stigmergy:** coordination through traces left in the environment — piles, structures, trails.
- **Stress weighting:** consolidation of a memory in proportion to how close any need was to critical when it formed.
- **Utility AI:** decision-making by scoring candidate actions from weighted considerations and choosing among the best.

## Sources

Key claims in this plan are grounded in the research report that preceded it. Sources below are listed with the status recorded there: "verified live" means read in full during research on 2026-10-27; "index" means established from search-result material.

- Game Developer — Are Behavior Trees a Thing of the Past? (verified live) https://www.gamedeveloper.com/programming/are-behavior-trees-a-thing-of-the-past-
- GMTK / Mark Brown — The Genius AI Behind The Sims (verified live) https://gmtk.substack.com/p/the-genius-ai-behind-the-sims
- Noita falling-sand interview, via 80 Level (verified live) https://dfx.lv/w/noita-a-game-based-on-falling-sand-simulation-80lvl_1283/
- KinematicSoup — How We Synced 5,000 Enemies (verified live) https://www.kinematicsoup.com/blog/multiplayer-survivors-5000-enemies/
- Wikipedia — Utility system (index) https://en.wikipedia.org/wiki/Utility_system
- Wikipedia — Noita (index) https://en.wikipedia.org/wiki/Noita_(video_game)
- Wikipedia — Artificial life (index) https://en.wikipedia.org/wiki/Artificial_life
- RimWorld Wiki — About RimWorld (index) https://rimworldwiki.com/index.php?title=About_RimWorld&printable=yes
- RimWorld Wiki — Opinion (index) https://mail.rimworldwiki.com/wiki/Opinion
- Godot documentation — MultiMeshInstance2D (index) https://docs.godotengine.org/en/4.0/classes/class_multimesh.html
- Bevy 0.6 release notes (index) https://bevy.org/news/bevy-0-6/
- Generative Agents / Smallville cost summary (index) https://5gantennas.org/how-to-build-generative-ai-agents-with-joon-sung-park/
- Episodic social learning in multi-agent reinforcement learning (index) https://arxiv.org/pdf/2412.20271
- Cultural accumulation in reinforcement learning (index) https://www.emergentmind.com/papers/2406.00392
- Stigmergy (index) https://pmc.ncbi.nlm.nih.gov/articles/PMC9768137/
- Spore design critique, Game Developer (index) https://www.gamedeveloper.com/design/spore-my-view-of-the-elephant
- Dwarf Fortress simulation engine essay (index) https://dev.to/wlz/why-dwarf-fortress-bet-on-a-hand-rolled-simulation-engine-the-ascii-world-machine-behind-20-years-2nip
- Emergent gameplay design overview (index) https://falcon.so/resources/game-design/emergent-gameplay
- WorldBox culture and meta-systems analysis (index) https://medium.com/@prabhan1/playing-god-without-a-conscience-meter-worldbox-as-an-ethics-laboratory-93889ffe7a10

Benchmark figures from engine and vendor sources are render-only or simple-update figures and are used in this plan only as scaling references, never as simulation guarantees. No public benchmark matches this exact brain at 1,000 creatures; the tier figures in this plan are design targets to be measured in Phases 1 and 3, and the plan's exit criteria treat them that way.
