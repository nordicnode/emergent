# Tuning register — Phase 0, Phase 1 materials, genome, memory, search, regrowth, social, carrying, safety, move-to, sharing, harm, and Phase 2 legibility and balance

The live values live in [data/parameters.json](../data/parameters.json), which is
loaded at startup. This file records **why** each value is what it is and which
measured metric moved when it changed. Editing values in the JSON does not need
a recompile and is picked up by both the game and the headless runners.

Protocol for every change:

1. Change the JSON (or the named scoring rule).
2. Run `godot --headless --path . --script res://tools/run_tests.gd`.
3. Run `godot --headless --path . --script res://tools/phase0_soak.gd`.
4. Add a row below with the metric that motivated the change and the metric
   after it. Never change two unrelated knobs in one row.

## Decisions

| Date | Decision | Rationale |
|---|---|---|
| 2026-10-27 | Engine: Godot 4.7, GL compatibility, 2D | Plan's recommended engine; simulation kept as plain data arrays with the renderer as a view, so the engine choice does not lock the simulation layer |
| 2026-10-27 | One material per cell in Phase 0 | Plan scopes material simulation out of Phase 0; replacing is an explicit simplification, to be deleted with the property model in Phase 1 |
| 2026-10-27 | All creatures decide at 15 Hz | Plan's full tier is 10–20 Hz; staggering is scheduled for Phase 3 |
| 2026-10-27 | No food regrowth in Phase 0 | The plan leaves regrowth as a Phase 2 decision; the toy is seeded with enough food to watch without input |
| 2026-10-27 | Food regrows in Phase 1, but water does not | Food is grazed to the floor and would otherwise shrink the map permanently; water replenishment is a separate supply decision and remains open |
| 2026-10-27 | Seeded food near the founding site | Without it the founders walk a mostly empty map for ten minutes; this is a starting-world choice, not a behaviour rule |
| 2026-10-27 | 15 loci, every locus read by a live system | The 14 body and need loci plus imitation fidelity; the plan's ~25 loci include social genes whose systems are still absent, and those would mutate without consequence |
| 2026-10-27 | Size, speed, sense and stomach share a body budget below their maximums | Without a budget, mutation can make a creature best at everything and collapse the trade-off structure selection needs |
| 2026-10-27 | Each locus is taken from one parent, not averaged | Averaging blends lineages toward one mean and makes a mutation's effect hard to attribute |
| 2026-10-27 | Reproduction gate lives in the simulation, not the brain | Any verb could otherwise bypass kinship, compatibility or readiness; the brain only scores approach and mate |
| 2026-10-27 | Need setpoints stop eating, drink and rest; urgency still reads the raw level | Normalising urgency by setpoint flattened every hunger and thirst drive; the control run died faster than the baseline, so the setpoint is a stopping rule only |
| 2026-10-27 | Rot 0.35 → 0.10/day, toxicity threshold 0.40 → 0.30, toxicity 0.30 → 0.12/day, damage 0.06 → 0.02/s | 2-day control: every food cell rotted, 17 creatures died of poison, and the world became inedible before the population could use it |
| 2026-10-28 | 18 loci: sociality, aggression and conscientiousness | Every locus has a live reader; conscientiousness weights the store verbs without unlocking them, so the store behaviour still has to win on its own utility |
| 2026-10-28 | Comfort is a fifth need, computed from cell properties | The plan's shelter story needs a reason to build and a reason to rest there; a cell tag would replace that reason with a special case. Comfort never damages health |
| 2026-10-28 | Pick up and pile are one material-transfer system for sand and food | A cache, a pile and a structure are the same verb applied to a cell; separate item or building systems would each need their own rules before the emergence tests can read them |
| 2026-10-28 | Keep the carrying slice with an explicit water-poor cost | 3-day A/B: 27.0 alive with carrying against 29.3 without; seed 303 falls 24 → 15 with 8 dehydration deaths against 3, and hard cells are lower on every carry seed. The verbs stay; the next work is the critical-thirst suppression and the missing pile compaction, not removal |
| 2026-10-28 | Suppress pick-up and pile at thirst urgency 0.60 | Seed 303: 15 → 17 alive, dehydration 8 → 5, loads 1,066 → 748, but still 7 below the 24 control. Keep the gate; the next test is to allow a critical-thirst carrier to drop its load while still suppressing pick-up |
| 2026-10-28 | Keep pile available at critical thirst (drop-at-thirst) | Seed 303: 17 → 20 alive, dehydration 5 → 2, loads 748 → 790, still 4 below the 24 control. The drop recovers three more; keep it and target the comfort/rest draw next |
| 2026-10-28 | Full drop-at-thirst A/B: 32.7 vs 29.3 mean alive | Seed 101 56 vs 42 (a boom with 37 births and one death), 202 flat 22/22, 303 20 vs 24; 18 deaths vs 19 and 3,849 loads moved. Overall positive, but the gain is one seed's boom and the water-poor seed still loses four. Keep the rule; test 101 stability and 303's comfort/rest next |
| 2026-10-28 | Ten-day seed 101: the 56 is an overshoot; both arms extinct | Carry reaches a sampled 73 and is 0 by the 8.75-day sample; control reaches 42 and is 0 by 6.25. Food and water remain and old age is the largest cause, so the next fix is overlapping generations, not another carrying knob. The three-day +3.4 mean is a boom phase, not a stable gain |
| 2026-10-28 | Old age is not a reproductive cutoff; it did not prevent extinction | The gate now excludes only children; a unit test passes for a healthy old parent. Ten-day seed 101: births unchanged at 56/24, both arms extinct, and the no-carry curve repeated exactly. No second breeding cohort formed because the old cohort was already below the scarcity gate. Keep the gate as a stage-correctness fix; the next fix is resource stability or a longer, spread-out breeding window |
| 2026-10-28 | Longer, jittered breeding cooldown: boom removed, bust remains | 0.90 d + ±0.20 d: seed 101 births 56 → 22, sampled peak 73 → 32, deaths 76 → 42, but still extinct at 7.5 d with 29 of 42 deaths old age and food/water standing. Spacing births alone is not enough; test an intermediate 0.6–0.7-day interval or a longer reproductive lifespan |
| 2026-10-28 | Breeding-interval sweep ends negative at 0.65 d | 0.65 ± 0.05 d: births 38, sampled peak 46, deaths 58, zero at the 8.75-day sample, 35 of 58 deaths old age. With 0.4, 0.65 and 0.9 all extinct, cooldown is not the missing replacement mechanism. Stop interval tuning; test a longer reproductive lifespan or resource stability |
| 2026-10-28 | Safety is a need; protection is arrangement, not a shelter tag | Safety was the only plan need with no state at all. A predator species or a danger flag would have scripted the fear; hardness underfoot and around a cell is a property other systems already read, and a cover score gives the shelter chain a second need |
| 2026-10-28 | Flee is the twelfth verb, offered only for remembered enemies | A threat is the creature's own negative opinion, not a species or a global danger flag. This makes fear a consequence of real disputes and lets it cool as opinion decays. Flee is the urgent form of the same read as avoid, with an interrupt that belongs to the safety curve |
| 2026-10-28 | Any negative opinion is a threat, graded by strength | A −0.25 floor meant a one-day soak's four food disputes produced no fear at all: the need and the flee verb existed but could never fire in ordinary play. Grading from 0.0 lets a mild grievance erode safety a little and a real feud erode it fast, without lowering the avoid threshold |
| 2026-10-28 | 19 loci: safety curve exponent | The new need has its own inherited steepness, read by the flee score and by rest on protected ground; every locus still has a live reader |
| 2026-10-28 | Move to is its own verb; recall travel no longer counts as seek | The plan's vocabulary has thirteen actions and the code had twelve. Travel to a remembered cell was already implemented but reported as seek, hiding it in the action mix and blurring seek's meaning (a currently perceived advertisement). The split changes no score, commitment or movement; labels stay recall_food/recall_water so the memory metric is unchanged |
| 2026-10-28 | Sharing rides socialise; harm rides the food contest | The plan's two missing social events need no fourteenth verb: a share is a socialise exchange with a meal in it, and an injury is the food contest read one step further. Both write through the existing opinion, log, metrics and safety paths. Sharing needs a surplus carrier and a hungry partner; harm needs an aggressive, larger winner and a vulnerable loser, so neither is unconditional |
| 2026-10-28 | One home per event: `share.gd`, `harm.gd`, `safety.gd`, `tick.gd` | The event counters, cooldowns and log writes had accumulated as loose `Sim` fields. `sim/sim.gd` fell 1,995 → 1,686 lines; share, harm, safety/flee and the tick pipeline now each read alone, with no score, RNG or tuned value changed. The same 2-day seed-202 run reproduces 32 alive, 3 shares and 6 harms; mean step 30.49–32.41 ms across reruns on this host |
| 2026-10-28 | Phase 2 legibility: observers only | First-time detectors, lineage population samples, place contest records and the contested terrain tint all read records written by the simulation; none is read by a creature and none changes a score. The opinion chain cap is five (not three) so a positive exchange between rivals cannot push an earlier dispute out of the inspector; the rivalry evidence check now counts three disputes inside the five-event chain. Focused checks: 33 before the history/contest additions, 357 total suite with the Phase 2 cases included |
| 2026-10-28 | Drought and flood are placement scenarios, not exceptions | Drought 256×192, one pond, no water placed, 10 days: 177 → 0 water cells, population 14 → 0, 20 deaths (9 starvation, 6 dehydration, 4 combined), 34 food disputes and 10,521 flee decisions. Flood 64×64, established 5×5 hard structure: hardness 0.99 → 0.70, resting residents 2 → 1, all 4 residents alive, mean movement 5.1 cells. Both run through the real fixed tick; the only scripts are starting conditions and the player's water placement |
| 2026-10-28 | Feast/famine run: storing did not buy survival | Heavy food for three days, none for seven: 209 food loads piled and 90 caches used, but 0/6 storers and 0/12 non-storers survived; 19 starvation deaths. The scenario needs a longer famine, a larger cache threshold, or a cheaper store route before it can test the plan's survival hypothesis; report it as a failed balance signal, not evidence for storing |
| 2026-10-28 | Phase 2 carrying pass is bundled, not isolated | Breeding 0.65 → 1.50 d with ±0.25 jitter, maturity 0.25 → 0.50 d, old age 6 → 8 d with 0.45/day decline, water search 0.10 urgency / 64-cell legs, 6 ponds and a 20-cell mate search. These interact and were changed as one carrying-capacity pass, so no single row claims a clean attribution. First measurement, 3 seeds × 3 days: peak 29–30, end 21–26, 10–14 births, 6–9 deaths, diversity 0.399–0.404; seed 101 was 30 at day 1 and 24 at day 3, so the old boom is gone. A 10-day follow-up then showed seed 101 extinct at day 7 with 18 starvation deaths and mean food already 0.14 at day 3. Regrowth 0.05 had fallen below consumption; it is now 0.12 and the same three seeds are rerunning. The full 10 × 30-day soak remains the gate |
| 2026-10-29 | Phase 3 decision staggering, first slice: `brain.decision_every_ticks` (shipped = 1) | Creatures split into stable buckets by slot id; one bucket decides per tick, movement and execution still run every tick. A creature re-decides at most (every − 1) ticks late, flee interrupt included (0.13 s at every = 3, 15 Hz). No tier promotion, throttling governor or rendering change yet — those are the rest of Phase 3. Measured on this VM (2 cores, Godot 4.7.2 headless), seed 101, 0.25 days: unstaggered step 14.10 ms / decide 9.11 ms, staggered every = 3 step 7.99 ms / decide 3.07 ms, identical outcome (29 alive, 9 births, 0 deaths; diversity 0.403 vs 0.401). 3-day staggered seed 101: 39 alive, 20 births, 1 death, diversity 0.397, step 10.07 ms / decide 4.51 ms — inside the restored 3-day band (38 alive on the unstaggered restored build). A fresh Godot clone needs `godot --headless --editor --import` once before headless scripts load, or the run idles with no class cache; that import also surfaced a real type-inference error in the first staggering draft (bucket variable), fixed by typing it explicitly |

## Parameters in use

| Section | Parameter | Value | Read by |
|---|---|---|---|
| world | width × height | 512 × 384 | grid, perception, renderer |
| world | chunk_size / cell_px | 64 / 8 | material chunks, terrain, creatures |
| sim | tick_hz / day_seconds | 15 / 480 | pipeline, needs decay, HUD clock |
| needs | hunger decay | 0.50 / day | hunger need, seek/mate readiness later |
| needs | hunger active multiplier | 1.35 | hunger need during movement |
| needs | hunger curve exponent | 2.2 | utility urgency |
| needs | thirst decay | 0.70 / day | thirst need |
| needs | thirst active multiplier | 1.40 | thirst need during movement |
| needs | thirst curve exponent | 2.6 | utility urgency |
| needs | energy decay | 1.30 / day | energy need |
| needs | energy movement multiplier | 0.80 | energy need during movement |
| needs | energy curve exponent | 1.8 | utility urgency |
| needs | rest recovery | 5.0 / day | energy need while resting |
| needs | social decay / curve exponent | 0.9 / day / 1.8 | social need, urgency |
| needs | comfort decay / wet / water | 0.55 / 1.2 / 2.0 per day | comfort need |
| needs | comfort rest recovery / curve | 2.2 / day / 1.6 | rest, comfort urgency |
| needs | starve / dehydration damage | 0.7 / 0.9 per day | health |
| needs | health regen | 0.4 / day above 0.45 | health |
| metabolism | eat / drink rate | 0.6 / 0.9 amount per second | eat, drink |
| metabolism | hunger relief per food | 1.4 | eat |
| metabolism | thirst relief per water | 1.2 | drink |
| movement | speed | 2.5 cells/s | wander, seek |
| movement | separation radius / strength | 1.6 cells / 1.2 | movement steering |
| movement | arrive radius | 1.2 cells | seek, wander |
| movement | wander distance | 6–18 cells | wander target |
| perception | sensory radius | 18 cells | resource search, future social |
| brain | softmax top k | 4 | choice |
| brain | temperature base / distress | 0.10 / 0.35 | choice |
| brain | commitment bonus | 0.12 | choice hysteresis |
| brain | wander base / content bonus | 0.10 / 0.30 | wander score |
| brain | eat / drink base | 0.30 / 0.30 | eat, drink score |
| brain | seek weight | 0.90 | seek score |
| brain | rest weight | 0.90 | rest score, × (1 − 0.8 × max(hunger, thirst)) |
| brain | distance cost scale | 0.50 | seek score |
| comfort | seek threshold / radius / weight | 0.30 / 10 cells / 0.75 | seek comfort |
| comfort | quality threshold / rest weight | 0.55 / 0.80 | rest, comfort scan |
| comfort | scan cooldown | 0.005 day | comfort target cache |
| carry | capacity base / per size | 1.4 + 2.6 × size | pick up, load speed cost |
| carry | pickup / deposit rate | 0.9 / 2.0 amount per second | pick up, pile |
| carry | pickup base / food / sand weights | 0.03 / 0.30 / 0.40 | pickup scores |
| carry | surplus threshold | 0.55 | pickup_food |
| carry | thirst suppress | 0.60 | pick-up gate; pile stays as a drop |
| carry | wet pickup bonus | 0.50 | pickup_sand |
| carry | food / sand pile weight | 0.32 / 0.32 | pile scores |
| carry | load speed penalty | 0.40 | movement |
| carry | cache lesson / repick cooldown | 1.0 / 0.02 day | delayed store learning, pile hysteresis |
| social | contact / notice radius | 2.5 / 12 cells | socialise, approach, avoid |
| social | socialise weight / cooldown | 1.2 / 20 s | socialise |
| social | avoid threshold / weight / radius | −0.25 / 1.25 / 4.5 cells | avoid |
| social | socialise relief / gain | 0.45 / 0.14 | social need, opinion |
| social | contest abundance / gain / cooldown | 0.6 / 0.18 / 0.05 day | food disputes |
| social | share weight / surplus / hunger | 1.6 / 0.55 / 0.60 | share candidate |
| social | share amount / cooldown / opinion gain | 0.15 / 0.10 day / 0.25 | transfer, event log |
| social | share min opinion / giver credit | −0.05 / 0.5× | share gate, giver memory |
| social | harm aggression / vulnerability | 0.60 / 0.60 health or 0.55 food | injury gate |
| social | harm size ratio / damage / safety shock | 0.95 / 0.08 / 0.35 | injury, safety need |
| social | harm victim / attacker opinion | −0.45 / −0.08 | opinion memory |
| social | mate gain / kin bonus | +0.12 / +0.30 | opinion |
| social | friend / rival thresholds | +0.30 / −0.20 | labels only |
| social | opinion half-life / cap | 3 days / 16 entries | opinion store |
| safety | threat / exposure decay | 10.0 / 0.15 per day | safety need |
| safety | passive / rest recovery | 0.30 / 1.8 per day × protection | safety need, rest |
| safety | notice radius / opinion floor | 12 cells / 0.0 | threat scan |
| safety | flee need / weight / notice | 0.15 / 3.0 / 9 cells | flee candidate |
| safety | flee distance / exit / speed | 8 / 9 cells / 1.4× | flee execution |
| safety | flee interrupt | 0.70 urgency | choice |
| safety | log below / minimum gap | 0.35 / 0.05 day | flee log throttle |
| commit | wander / seek / eat / drink / rest | 1.2 / 2.0 / 2.0 / 1.5 / 3.0 s | commitment |
| commit | approach / mate / flee | 2.0 / 0.8 / 1.2 s | commitment |
| genome | loci / body budget | 19 / 0.72 | decode, inheritance |
| genome | imitation locus | 0–1 fidelity | observed place learning |
| genome | sociality / aggression / conscientiousness | loci 15–17 | social need, contests, store verbs |
| genome | safety curve exponent | locus 18, 1.6–3.2 | safety urgency, flee, rest |
| genome | mutation rate / size | 0.02 / 0.05 of range | offspring |
| genome | jump rate / size | 0.001 / 0.25 of range | offspring |
| repro | gate food / water / energy / health | 0.55 / 0.55 / 0.55 / 0.70 | reproduction gate |
| repro | cooldown / jitter | 1.50 / 0.25 days | reproduction gate, birth spacing |
| repro | search radius / contact radius | 20 / 2.5 cells | approach, mate |
| repro | minimum genetic distance | 0.04 | mate compatibility |
| repro | energy cost / child start need | 0.30 / 0.85 | birth cost, newborn |
| life | maturity / old age | 0.50 / 8.0 days | life stage, body scale |
| life | old-age decline | 0.45 health/day | old age |
| brain | repro weight | 0.85 | approach, mate score |
| brain | search_food_threshold / weight | 0.35 / 0.70 | food search candidate |
| brain | search_water_threshold / weight | 0.10 / 1.10 | water search candidate |
| brain | search_distance_cells | 64 | search leg length |
| brain | search_turn_radians | 0.35 | search heading turn |
| commit | wander_seconds | 1.2 s minimum | a leg is held for distance / speed, capped at 24 s |
| memory | place slots / episode slots | 8 / 32 | place store, episode ring |
| memory | place_decay_days | 2.0 | recall confidence |
| memory | recall_need_threshold | 0.15 | recall candidate |
| memory | recall_distance_cells | 24.0 | recall distance discount |
| memory | context_content_threshold | 0.05 | learning context |
| memory | learning_rate | 0.25 | weight update |
| memory | delayed_check_seconds | 1.0 | delayed evaluation |
| memory | health_lesson_scale / threshold | 100.0 / 0.0002 | delayed health fallback |
| memory | toxin_gain_per_food / clear / damage | 4.0 / 3.0/day / 1.2 health/day | poison load |
| materials | food_regrow_per_day | 0.12 | food cells, material pass |
| materials | water_regrow_per_day | 0.15 amount/cell/day at half full | standing water, flow pass |
| materials | food_min_amount | 0.02 | living trace left by consume |
| detectors | scan interval / stockpile cells | 0.05 day / 6 | first-time scans, stockpile cluster |
| detectors | stockpile amount / radius | 0.75 / 3 cells | stockpile cluster |
| detectors | highlight seconds | 12.0 | first-time flash lifetime |
| imitation | teach radius / copy fraction | 9 cells / 0.5 | observed place learning |
| imitation | youth / old multiplier | 1.4 / 0.8 | observed place learning |
| imitation | teach cooldown / min copy | 1.0 s / 0.02 | observed place learning |
| spawn | founders | 20 | world start |
| spawn | need range | 0.65–1.0 | founder variation |
| world_gen | dunes / ponds / food patches | 70 / 6 / 20 | starting world |
| world_gen | nearby food patches | 6 | starting world |
| render | initial zoom / min / max | 2.0 / 0.4 / 4.0 | camera |

## Change log

### 2026-10-27 — Baseline parameter register

Starting values taken from Appendix B of the plan where it specifies a value
(tick rate, memory capacities, mutation rates as placeholders), and chosen for
Phase 0 where it says “tune in Phase 1”. Baseline measurements before any
change:

- 20 creatures: 12.86 ms/step; 200 creatures: 128.19 ms/step.
- 3 seeds × 10 sim-minutes: population 20/20 in all seeds, 0 deaths.
- Action mix: wander 60–62%, rest 31–32%, seek 4–8%, eat 0–1%, drink 1%.
- Eat verb absent in two of three seeds.

### 2026-10-27 — Banded perception ([sim/brain.gd](../sim/brain.gd))

The first implementation iterated a 37 × 37 square for each resource query and
skipped lattice points inside it — 1,369 iterations per query.

- Rule: scan three bands (1-cell lattice within 4 cells, 2-cell within 10,
  3-cell beyond), ~300 reads per query.
- Motivation: step cost.
- Effect: 12.86 ms → 3.0 ms per step at 20 creatures; 128.19 ms → 24.3 ms at 200.

### 2026-10-27 — Resource already in reach is not a seek target ([sim/brain.gd](../sim/brain.gd))

- Rule: when food or water is within the 3 × 3 reach, omit the seek candidate
  for that material.
- Motivation: a starving creature standing on food chose eat in only 164/300
  samples because seek scored almost as high with distance near zero.
- Effect: 275/300 samples choose eat. No special case was added; the verb that
  applies at distance zero is the verb that consumes.

### 2026-10-27 — `brain.eat_base` 0.08 → 0.30, `brain.drink_base` 0.08 → 0.30

- Motivation: creatures reached food and wandered away without eating; eat was
  0–1% of ticks. Eating at a food cell should be worthwhile once hunger urgency
  passes a low bar, while a sated creature should still prefer to move on.
- Effect: eat 1–3% of ticks, drink 0–1%; diet is maintenance-level, as expected
  from a need that decays 0.5/day and a 1.4-relief food cell.
- Checked: a fully satisfied creature standing on food still scores wander
  above eat (test asserts this), so the floor did not create compulsive eating.

### 2026-10-27 — `world_gen.food_patches` 12 → 20, added `world_gen.nearby_food_patches` = 4

- Motivation: with 12 patches over 196,608 cells, food was almost never inside
  an 18-cell sensory radius, so seek fired at 2–8% and often found nothing.
- Effect: seek 2–5% of ticks, eat 1–3%, and every seed now exercises all five
  verbs. The nearby patches are a starting-world choice and are documented as
  such; player placement remains the real food source.

### 2026-10-27 — Bug fixes, not tuning

- Perception compared a distance-discounted score against the previous cell's raw
  value, so a far high-value cell permanently beat a nearer equal one. Fixed with
  an explicit `score` field.
- `0x9E3779B97F4A7C15` cannot be represented as a signed 64-bit literal in
  GDScript; replaced with a 32-bit constant in the state hash.
- Selection ring did not follow a moving creature because the cursor cached on
  “no change”; a selected creature now redraws every frame.

## Baseline after changes

Reference machine: Linux, Intel i5-9400 @ 2.90 GHz, NVIDIA GTX 1660 SUPER,
Godot 4.7.2, GL compatibility renderer.

Test suite: **55 checks, 0 failures.**

Soak (10 seeds × 1.25 simulated days, no input):

| Metric | Result |
|---|---|
| Population | 20 in every seed, no deaths |
| Action mix | wander 63–65%, rest 29–32%, seek 2–5%, eat 1–3%, drink 0–1% |
| Final mean needs | food 0.39–0.79, water 0.21–0.56, energy 0.64–0.84 |
| Mean step time | 3.6–5.4 ms across seeds |
| Peak step time | 9.9–44.5 ms across seeds, one outlier seed |
| 20-creature benchmark | 2.86 ms/step |
| 200-creature benchmark | 23.59 ms/step |

Open issue: the 44.5 ms peak in seed 404 is not explained. The mean for that
seed was 4.34 ms. Phase 3 profiling should identify whether it is allocation,
GC, or host scheduling before scale work begins.

## Phase 1 — material simulation

Scope of this slice: flow, wetness transfer, drying, compaction, hardening and
softening, rotting, and the wet-sand hardening chain. The rest of Phase 1 (the
13-verb vocabulary, genome, reproduction, memory, learning, imitation, opinions)
is not in this slice.

### Decisions

| Date | Decision | Rationale |
|---|---|---|
| 2026-10-27 | Materials run at 5 Hz flow / 2.5 Hz property cadence, not every 15 Hz tick | Flow at 15 Hz looks like teleporting, and the pass cost at 15 Hz was 97 ms/step. Elapsed time is scaled by the ticks a pass skipped, so rates are unchanged |
| 2026-10-27 | One work queue of changing cells, batched at 4,000 cells per pass | Cell-level activity replaced chunk-level activity (one wet cell used to cost a 4,096-cell pass). FIFO plus a head index keeps order deterministic; the batch bounds the worst case |
| 2026-10-27 | Held water below field capacity does not drain | Without a field capacity every drop walked to the bottom of the map leaving a trail of 0.8%-wet cells; the queue grew to 15,000 cells and cost 97 ms/step |
| 2026-10-27 | Ponds start on a hard-sand pan | Loose sand under a pond soaked it dry in minutes (the whole world's ponds were gone in 5 sim-minutes, and creatures died of thirst). Hard sand refuses water through its face, and flooding it still softens it |
| 2026-10-27 | Rot runs every property pass | It was gated on a slow tick modulo, which fought the split cadence. Food is 252 cells in a starting world, so the cost is ~0.2 ms |
| 2026-10-27 | Flow rejects pond interior cells before the precise move checks | 76% of the water cells in a settled pond cannot move, but each paid up to five `_can_enter` calls (0.6 µs) and a `_move_water` (1.1 µs) to prove it. The reject is conservative: any non-water neighbour falls through to the exact checks |
| 2026-10-27 | Drying and hardening retuned together | Slower drying (1.6 → 0.4 wetness/day) made the hardening chain take longer than the two-day test window |

### Material parameters

| Parameter | Value | Read by |
|---|---|---|
| material_tick_hz | 5.0 | `sim/tick.gd` material cadence |
| material_batch_cells | 400 | `sim/materials.gd` property pass |
| wetness_field_capacity | 0.50 | held water vs gravity water |
| wetness_drain_per_sec | 0.04 | drainage above field capacity |
| wetness_evaporate_per_day | 0.40 | surface drying |
| water_evaporate_per_day | 0.05 | pond loss |
| water_absorb_per_sec | 0.01 | infiltration into porous cells |
| wetness_dry_epsilon / wetness_move_epsilon | 0.001 / 0.0005 | snapping dry, ignoring noise transfers |
| wet_history_decay_per_day | 0.12 | hardening memory |
| hardening_per_day | 4.0 | hardening rate |
| softening_per_day | 0.8 | flood softening |
| hardening_compaction_min / hardening_wet_history_min | 0.25 / 0.35 | hardening thresholds |
| creature_compaction_per_sec | 0.20 | resting creature compaction (rest is 1.0×, walking 0.35×) |
| weight_compaction_per_sec / weight_compaction_cap | 0.02 / 0.20 | burial compaction, capped below the threshold |
| rot_per_day / rot_wetness_mult / rot_temperature_mult | 0.35 / 1.5 / 0.6 | rot |
| rot_toxicity_threshold / rot_toxicity_per_day | 0.40 / 0.30 | toxic food |
| eat_toxicity_damage_per_sec | 0.06 | health cost of eating rot |
| mud_wetness / hard_sand_threshold | 0.55 / 0.45 | derived states |
| convert_max_hardness | 0.35 | hard sand refuses floods and flow |

### Change log

#### 2026-10-27 — Active cells, not active chunks

- Rule: the material pass walks a FIFO queue of cells that are still changing.
  A dry, still cell is not in the queue. A cell re-queues itself while wetness,
  water or hardening is still moving.
- Motivation: with chunk activity, the first pond woke whole chunks and the
  queue reached 15,833 cells; the pass cost **96.9 ms/step** at 20 creatures
  (material-only 101.6 ms/step).
- Effect: after the queue, field capacity and the split cadence, **5.3–8.0
  ms/step** over 1.7 simulated days at 20 creatures, 2,300–2,700 queued cells.

#### 2026-10-27 — Field capacity 0.5

- Rule: wetness above field capacity drains down; wetness below it is held and
  only evaporates.
- Motivation: diagnosing the queue showed a front of cells at exactly 0.008
  wetness, one cell deeper every pass — a single drop walked to the bottom of
  the map. Queue 11,533 pending after 40 s, still climbing ~30 cells/pass.
- Effect: queue 11,533 → 2,263 after 40 s and flat afterwards; ponds stop
  leaking into an effectively bottomless sand bed.

#### 2026-10-27 — Infiltration 0.30 → 0.01 /s, water evaporation 0.20 → 0.05 /day

- Motivation: at 0.30/s the whole world's ponds were gone by 5 simulated
  minutes; at 0.01/s they survived, but still lost 30% in half a day until the
  pan was added.
- Effect with the pan: 498 → 455 water cells over 1.74 simulated days (-8.6%),
  while shorelines stay damp.

#### 2026-10-27 — Hard-sand pond pans (`sim/sim.gd`)

- Rule: sand touching pond water starts at hardness 0.9 and cohesion 0.9. Flow
  and drainage refuse porous cells at or above `convert_max_hardness`, and the
  world generator leaves the pan dry so the pond does not soften its own shell.
- Motivation: a pond in loose sand drained away in minutes and the founders died
  of thirst around day 1.7.
- Effect: ponds survive the two-day check; the pan is visible as hard sand and
  a brush of water poured onto it pools instead of vanishing, then softens it.

#### 2026-10-27 — Drying 1.6 → 0.4 wetness/day, hardening 2.0 → 4.0/day, creature compaction 0.12 → 0.20/s

- Motivation: at the slower drying rate the direct chain reached 0.33 hardness
  in two days (threshold 0.45) and the creature-resting chain only 0.04, because
  a resting creature managed ~0.4 compaction in the test window.
- Effect (two simulated days, same tests): direct chain 0.33 → **0.70**, resting
  chain 0.04 → **0.76**, both above the hard-sand threshold.

#### 2026-10-27 — Per-cell material clock, batch 4,000 → 400

- Rule: every queued cell stores the material tick at which it last entered the
  queue or was processed. A pass still takes a fixed batch, but each cell is
  advanced by the time **it** waited, so the budget changes smoothness and
  never rates. Previously a smaller batch would have slowed drying and
  hardening; now it only makes the integration step coarser.
- Motivation: the property pass was the worst step in the game. Over 9,000
  steps of seed 404, material time had p99 **13.2 ms** and max **18.2 ms**; the
  wall p99 was 18.1 ms and the worst step 24.1 ms. The pass was processing the
  whole ~2,200-cell queue in one tick and colliding with the decision pass.
- Effect: material p99 **6.2 ms**, wall p99 **11.0 ms**, worst step **19.6 ms**,
  mean 6.15 ms, no step over 20 ms in that run. The suite's seed peaks fell
  from 26–82 ms to 19–21 ms. Total material work per simulated second is lower
  than before (fewer redundant cell visits).

#### 2026-10-27 — Rot visits food cells, not food chunks

- Rule: the grid maintains a food-cell list exactly like the water list; rot
  iterates it.
- Motivation: 250 food cells in ~30 chunks cost a **120,000-cell scan every
  material tick**, 5 times a second. This was the 8–10 ms floor hidden inside
  material time and the reason some material steps were far more expensive than
  the batch alone.
- Effect: rot visits 250 cells instead of 120,000; material p99 fell another
  ~2 ms, and the scan no longer grows with the number of patches.

#### 2026-10-27 — Step timing split and a real mean

- Rule: `Sim.step` records material, needs, decision and execution time, and
  the sim exposes `mean_step_ms` beside `last_step_ms`/`max_step_ms`.
- Motivation: the soak and suite labelled the **last** step's time as "avg".
  Spikes were being reported with no way to tell which phase paid for them.
- Effect: the numbers above are attributable. The remaining steps over one
  60 fps frame are decision-time variance (p99 5.1 ms, max 12.5 ms) plus the
  bounded material pass, not an unbounded material scan.

#### 2026-10-27 — Epsilons: dry 0.01 → 0.001, move 0.004 → 0.0005

- Motivation: drained films of 0.008 were snapped to zero before they could
  accumulate, so no wet ground formed next to water; and the slow infiltration
  (0.001 per 0.5 s) was below the move floor and never happened at all.
- Effect: "water soaks into dry sand below it" and "wetness drains downward"
  pass again; the field-capacity rule keeps the queue bounded without the
  aggressive epsilon.

#### 2026-10-27 — Flow rejects pond interior before the precise move checks

- Rule: a water cell whose every destination — down, both down-diagonals and
  both sides — already holds water at or above its own level, within the 0.02
  leveling epsilon, returns before `_can_enter`/`_move_water`. The test only
  rejects when all of those are water at that level; any other material, or any
  lower water level, sends the cell down the full path unchanged. Water never
  moves up, so the cell above is not a candidate.
- Motivation: flow walked every water cell at 5 Hz, and a settled pond is mostly
  interior. Measured on seed 202 after 1,200 steps (662 water cells): the flow
  pass cost **5.3 ms**, 8 µs per cell, and **51 of 3,000 material passes** in a
  1.25-day run exceeded 8 ms. `_can_enter` measures 0.6 µs per call and
  `_move_water` 1.1 µs, so proving "nothing moves" was most of the material step.
- Effect: the same world and cell count costs **2.54 ms** per flow pass (3.8 µs
  per cell); 504 of 662 cells take the reject. Material passes over 8 ms fell
  **51 → 4** of ~4,100, material mean is 2.8–3.2 ms with p99 4.4–5.0 ms, and step
  p99 over seeds 101/202/303 (9,000 steps each) fell 12.6/13.5/10.3 →
  **9.7/10.5/8.7 ms**.

#### 2026-10-27 — The residual peaks are host scheduling, not material work

- Rule: none. This entry exists so the numbers above are not overclaimed.
- Method: the same seed re-run to the same step, and the counters that describe
  the work (water cells, queued cells, batch size, moves) compared against the
  slow run. On seed 303 step 6467 a material pass measured **63.9 ms**; that
  exact step re-ran at **3.8 ms** with water 420, moves 21 and 400 processed
  cells — the same work. Seed 101 step 8435 measured material 17.9 ms and
  re-ran at 4.0 ms with water 600, moves 0, active 2,433. A 3.6× spread was also
  seen between two passes with identical counters (659 vs 657 cells scanned) in
  the same run.
- Conclusion: the 37–110 ms peaks were real material work — the whole property
  queue in one tick, the 120,000-cell rot scan, and a flow pass that ran the
  precise checks on every water cell — with host noise on top. Those three costs
  are now removed, and the 20–60 ms peaks that remain no longer reproduce as
  work. Untouched over-frame steps are decision bursts (one step of 20 creatures
  reached 22 ms of decision time); staggering decisions is Phase 3.

#### 2026-10-27 — Genome: 14 loci, body budget, pick-one inheritance

- Rule: 14 loci, all read by a live system — size, speed, sense, metabolism,
  three setpoints, stomach, three curve exponents, boldness, curiosity, hue.
  Size/speed/sense/stomach are normalised against their ranges and share a
  **0.72** budget; over budget they are scaled back together. Metabolism is
  multiplied by body cost, so a bigger body is hungrier.
- Inheritance: each locus is taken from one parent, then mutated at 2% (5% of
  range) or at 0.1% for a 25% jump. Mutation count, parents, generation and
  founder line are stored on the child; the child's body is decoded once at
  birth and never mutated afterwards.
- Motivation: the plan requires inherited trade-offs rather than a best-at-
  everything birth. Decoding through a budget is the mechanism; no fitness
  function or birth check exists anywhere.
- Effect: an all-max cost genome decodes to 0.72 cost, with size scaled below
  its locus maximum (asserted). All 14 loci fit in 56 bytes per creature;
  distance between two random founders is typically ~0.3, well above the 0.04
  mate-compatibility floor.

#### 2026-10-27 — Reproduction gate, approach/mate verbs, life cycle

- Rule: a creature may breed when it is adult, off cooldown, healthy, fed,
  watered and rested (gate 0.55/0.55/0.55/0.70). Both partners are re-checked at
  contact; parent/child and siblings are refused, and pairs closer than 0.04
  genetic distance are refused. The brain scores **approach** toward a willing
  partner in sensory range and **mate** in contact; neither can bypass the gate.
- Life cycle: children (below 0.25 days) run at 0.62–1.0 body scale, adults at
  1.0, the old (past 4 days) decline through the same scale and lose 1.2
  health/day until age kills them. Causes of death now include old age.
- Effect, seed 101 over 3 days: 20 founders → peak 31 → 15 alive, **11 births**,
  max generation **2**, 16 deaths, 600 water cells. Without reproduction on the
  same seed and window the population reaches 10 at day 2 and has fewer adults
  at every sample, so births are adding members, not causing the decline.
- Decision cost: the mate search re-read gate thresholds per candidate per tick
  and cost up to 36 ms of decide at 31 creatures; thresholds are now read once
  per tick and the genetic-distance loop uses cached inverse spans.

#### 2026-10-27 — Setpoints stop intake, urgency reads the raw level

- Rule: `_do_eat`/`_do_drink`/`_do_rest` stop at the creature's own setpoint;
  hunger, thirst and energy urgency are computed from the raw level, as before.
- Motivation: the first cut normalised urgency by the setpoint. With a 0.575
  hunger setpoint a creature at 0.26 food read a deficit of 0.55 instead of 0.74,
  so every drive in the world was flattened — a behaviour change disguised as a
  gene. The gene must change how much a creature eats, not rescale the brain.
- Effect: the 2-day gate-on control on seed 101 went from **11 to 16** alive with
  the same seed, and the founders again survive the 1.25-day window without
  deaths.

#### 2026-10-27 — Place memory and the one learning rule

- Rule: eating and drinking record the cell (material, standing value, day) in
  an 8-slot place store. When a need is above 0.15 and nothing of that material
  is in sight, the brain scores `recall_food` / `recall_water` from the best
  remembered cell, with confidence halving every 2 days and a distance penalty.
  Finding a remembered cell empty forgets it.
- Rule: after eat, drink or rest ends, `weight += 0.25 × stress × (improvement
  − weight)` is applied to that (verb, context) pair. Context is the dominant
  need at the time (hungry/thirsty/tired), however mild; content is only for a
  creature with no distress above 0.05. Stress is the distress at the same
  moment. The weight multiplies the candidate score, bounded to 0.4–1.6, so a
  lesson biases an available action and never creates one. Seek, wander,
  approach and mate record episodes but do not update weights: mean need drifts
  down over them, so learning from that would punish looking for food.
- Rule: eating arms a second evaluation 1 s later, once per bout. Toxicity now
  leaves a body load (gain 4× toxicity per food eaten, cleared at 3/day, dealing
  1.2 health/day per unit). The re-check turns a toxin gain into a negative EAT
  weight in that context, capped at −0.6; a health fallback catches other slow
  harm. This is the plan's delayed evaluation, and it is how rotten food becomes
  something a creature avoids rather than merely survives.
- Motivation for the context fix: the first cut treated 0.25 distress as the
  hungry floor, so most top-up meals were filed under content and the EAT lesson
  never applied to the hunger that drove them. The threshold is now 0.05.
- Motivation for the toxin load: a poisoned bite costs ~0.002 health, which
  health regen (0.4/day) hid within a second, so the delayed health check never
  fired in normal play. The load is the body's state, not a peek at the grid:
  it is what makes one bad meal matter.
- Episodes: 32 per creature (verb, context, stress, need before/after, cell,
  day). A full ring evicts by stress-weighted recency, so a 0.9-stress record
  decays at a third of a calm one. Memory is reset when an id is reused; no
  learning is inherited.

#### 2026-10-27 — Search when nothing is in sight

- Rule: when hunger or thirst urgency is above 0.30 and that resource is
  neither in reach, perceived, nor remembered, the brain adds `search_food` or
  `search_water` with the **wander** verb and a target 36 cells away along the
  creature's stored heading, turned by up to 0.5 rad. The heading is updated
  only when a search is chosen. Score is 0.9 × urgency.
- Rule: a wander leg is held until the target is reached: commitment is
  `distance / speed`, with `commit.wander_seconds` now a 1.2 s minimum and a 24 s
  cap. Previously the 1.2 s commitment expired after about three cells and the
  brain re-rolled the destination, so a "6–18 cell" wander was in practice a
  3-cell jitter. This is the actual discovery bug, not the 18-cell sense radius.
- Diagnosis, seed 202 at 3 days: of 14 deaths, **13 had never drunk**. They sat
  on food patches with 5–8 food places in memory, **zero** water places, and
  water 21–88 cells away. They were not starving beside food; they were
  thirsting beside it because they never left it. This is why search targets
  both needs, not food alone.

#### 2026-10-27 — Rot slowed: all food became toxic on day 2

- Rule: `rot_per_day` 0.35 → **0.10**, toxicity threshold 0.40 → **0.30**,
  toxicity rate 0.30 → **0.12**/day, eating damage 0.06 → **0.02**/s.
- Motivation: the first 2-day soak with reproduction ended with **278 of 278**
  food cells rotten and **17 poisoned deaths**, because creatures do not yet
  avoid toxic food (the learning rule is the next slice) and no food regrows.
  The poisoning wave was driven by the food supply, not the birth rate:
  reproduction adds mouths, but only rot can turn every remaining meal toxic.
- Effect: at day 2 the world still holds 289–296 edible food cells and has 0–1
  poison deaths; rot still becomes toxic, but after about five days of wet food
  rather than two. The rot test now runs five simulated days at the real rate.

#### 2026-10-27 — Food regrowth, observational places, search rebalance

- Rule: food regrows **in place** at `food_regrow_per_day` 0.15, visiting only
  the maintained food-cell list. New mass has full nutrition and no toxin, so
  the blend dilutes rot and toxin in proportion to the mass added. Growth never
  creates food on bare ground, and a full cell gains nothing and keeps rotting.
- Rule: `consume` leaves a `food_min_amount` 0.02 **living trace** on food. The
  trace is not edible. Motivation: a grazed cell used to become air, so the food
  map shrank with every meal and regrowth had nowhere to happen — three days of
  grazing could erase a patch entirely.
- Rule: imitation of places. A creature that eats or drinks teaches everyone
  within `teach_radius_cells` 9, at most once per `teach_cooldown_seconds` 1. A
  copy is `value × copy_fraction 0.5 × fidelity × age × distance falloff`, so
  it is always weaker than firsthand knowledge and never overwrites a better
  record. Children copy at 1.4×, old creatures at 0.8×. Fidelity is the 15th
  genome locus, 0–1.
- Rule: food and water search split. Food searches from 0.35 urgency at score
  weight 0.70; water from 0.15 at 1.10. Search legs lengthened 36 → 48 cells and
  the turn narrowed 0.5 → 0.35 rad. Rest is suppressed by
  `1 − 0.8 × max(hunger, thirst)`, up from a flat half: at water zero, rest
  (0.40) beat a known pond 29 cells away (0.29), so a creature that had drunk 16
  times napped to death beside water it remembered.

### Materials measurements

Test suite: **187 checks, 0 failures** at the time of writing. These material
measurements were taken at 159 checks (55 before the material slice, 97 before
the flow work, 101 before the genome slice, 134 before memory).

- Suite material test (small pond, 96 water cells, 60 steps): **0.8 ms** per
  material step.
- 20 creatures, full tier: **4.3 ms/step**; 200 creatures: **25.4 ms/step**
  (the 200-creature figure is dominated by deciding every creature, not
  materials).
- Ten-seed soak, 1.25 simulated days each, no input: **20 alive in every seed,
  0 deaths**, mean step **5.09–6.22 ms** (was 5.71–7.33 before the flow reject),
  worst step 16.6–27.0 ms with one 58 ms host stall (was 23.9–77.4).
- Needs after the run: food 0.47–0.77, water 0.19–0.54, energy 0.62–0.82;
  action mix wander 62–65%, rest 29–32%, seek 2–5%, eat 1–3%, drink 0–1%.
- Materials in that soak: water 414–722 cells, damp 1,561–1,867, mud 167–225,
  hard 205–336, food 240–387, rotten 0–22. Damp food rots faster, so rotten
  cells now appear inside 1.25 days; toxicity is still beyond that window and
  the tests force it.
- Flow study (seed 202, 662 water cells, same world before and after): flow pass
  5.3 → **2.54 ms**, 8.0 → **3.8 µs per cell**; 504 of 662 cells take the reject;
  material passes over 8 ms 51 → **4** of ~4,100. Three-seed step distribution:
  p99 12.6/13.5/10.3 → **9.7/10.5/8.7 ms**, material p99 **4.4–5.0 ms**.
- Spike attribution: slow passes re-run to the same step with identical counters
  (water cells, queued cells, batch, moves) come back 3.8–4.2 ms after measuring
  13.5, 17.9 and 63.9 ms. Two passes in one run with 659 and 657 cells scanned
  differed by 3.6×. The residual peaks are host scheduling.
- Water bookkeeping: the incrementally maintained water list matches a full grid
  scan after flow, placement and drinking (asserted).
- Material batch: a 64-cell budget processes exactly 64 cells and leaves the
  rest queued; nothing is dropped (asserted).
- Disable-one-system sanity check on the material slice: with absorption,
  evaporation, rot, compaction and hardening set to zero, 1.74 days killed 5 of
  20 founders; with them on, 3 died. The material systems are not the cause of
  founder attrition, which is a Phase 2 balance question because reproduction is
  not in this slice.

### Genome and reproduction measurements

- 3-day soak, 3 seeds (101, 202, 303), no input, before memory: population
  peaks 28–31 around day 1, then settles at **12–15**; **8–13 births** per
  seed; max generation **1–2**; 51 deaths total across the three seeds, almost all
  starvation-and-dehydration rather than poison (0 poison deaths).
- Gate-on versus gate-off on seed 101 at 2 days: **16 versus 10** alive. The
  births add members, and the decline that both runs share is the discovery and
  supply problem, not reproduction.
- Population cost: 20 creatures **5.1 ms/step**, 100 founders **20.3 ms**,
  200 founders **38.4 ms** (founders breed during the warm-up, so the 100- and
  200-creature runs finish at 149 and 298 alive). The 20-creature benchmark in
  the suite is 5.0 ms.
- Decision cost is the population scaling term: ~10–15 ms at 30 creatures. The
  mate search was re-reading gate thresholds per candidate per tick and costing
  up to 36 ms of decide at 31 creatures; thresholds are now read once per tick
  and genetic distance uses cached inverse spans.
- Soak peaks of 44–51 ms on a 31-creature world are one worst step, and the
  phase study at that population found a mean of 8.85 ms, p99 13.6 ms and a
  22.7 ms maximum when no other process was running. Treat the peak column as
  host-sensitive, as in the material spike study.

### Memory and learning measurements

- A/B on the pre-search code, same 3-day, 3-seed soak (101, 202, 303), memory
  on vs off: **16 / 15 / 13 alive with memory (mean 14.7)** against **15 / 12 /
  14 without (mean 13.7)**; 45 vs 51 deaths; births 11/9/9 vs 11/8/13; max
  generation 1/2/1 vs 2/1/1. One seed ends one lower with memory on. Place
  memory is a modest net help, not a population fix.
- Recall is used: 681 / 3,815 / 1,665 decisions chose a remembered cell; mean
  places held at the end 7.5 / 7.9 / 6.2; every survivor holds at least one
  learned weight.
- Population curves with memory: [22,29,30,30,25,17,16,16],
  [20,28,28,28,25,18,17,16], [20,29,29,29,25,16,13,13]. The overshoot to 28–31
  and the day-2 trough are unchanged; the difference is one to three creatures
  at the end.
- Cost: **6.07–6.95 ms** mean step with memory against **6.25–6.65 ms** without;
  a recall scan of 8 slots for each hungry or thirsty creature with nothing in
  sight, one learning update per qualifying verb change and a 32-slot eviction
  scan on recording cost ~0.2 ms at 13–32 creatures. Peak columns for this run
  were 19–33 ms, unusually low for the host, so treat absolute milliseconds as
  run-specific and the on/off delta as the signal.
- Learning configuration matters more than memory here. A first cut filed most
  meals under "content" (0.25 distress floor), and a second taught negative
  weights to seek/wander because mean needs always drift down over those verbs.
  Both produced 18–19 alive on some seeds and 13 on others: the population's own
  dynamics amplify a small change in which action gets encouraged. The final
  rule learns only directly need-changing verbs (eat, drink, rest) and uses the
  dominant need as context.
- Unit coverage: place confidence halving and refresh, material specificity,
  bounded store with weakest-record eviction, forgetting, eating records the
  cell, a hungry creature with nothing in sight aims at a remembered cell while
  a fed one does not, update convergence, 4× stress weighting, a real poisoned
  meal leaving a toxin load and teaching EAT a negative weight, and blank memory
  on id reuse.

### Search measurements (pre-regrowth)

- 3-day soak, 3 seeds, search on: **26 / 15 / 19 alive** (mean 20.0), 12 / 8 / 9
  births, max generation 3, **29 deaths**, 1 starved, 15 dehydrated, 13
  starvation-and-dehydration. Same code with search off (leg persistence kept):
  19 / 9 / 10 (mean **12.7**), 52 deaths. The pre-fix code was 16 / 15 / 13
  (mean 14.7), 45 deaths. The search candidate is the active ingredient: holding
  long wander legs **without** a search direction is worse than the old short
  legs, because a blind long walk leaves the food patch without finding water.
- Seed 101 population curve with search: [22,30,32,29,26,26,23,1] over 5 days.
  The first 4 days hold 26–32; the collapse is the old-age cliff, not discovery.
  5-day comparison: **search 0 alive / 32 deaths / 17 old age**, no-search 2
  alive / 30 deaths / 16 old age, with 12 births in both. Search raises the
  plateau and does not change the long-run extinction while food is finite.
- Death diagnosis (seed 202, 3 days, pre-search code): 13 of 14 deaths had never
  drunk. Typical record: 5–8 food places, 0 water places, nearest water 21–88
  cells, path 800–2,100 cells. They were orbiting food, not crossing ground.
  Search brings seed 202's dehydration deaths to 6, against 11 with search off
  and 9 on the pre-search code.
- Cost: mean step **7.2–8.2 ms** with search (26 creatures at the high end)
  against **5.8–7.1 ms** with search off (9–19 alive). Search is one target
  calculation per decision, not a new per-cell pass; most of the increase is the
  larger population it supports. Peaks 26–106 ms on a loaded host.
- Unit coverage: search only without sight or memory, seek instead when visible,
  recall instead when remembered, a 48-cell aim, search score above idle wander,
  and a 20-cell leg committed for 11.1 s against the 1.2 s floor.

### Regrowth, imitation and rebalance measurements

- Five-day soak, seed 101, before/after regrowth: **0 → 17 alive**. Births 11,
  max generation 2, 14 deaths (5 starved, 2 dehydrated, 3 combined, 4 old age),
  and 16 of the 17 survivors old. Population curve
  [20,30,30,28,23,21,21,20]. Food 297 and water 599 at day 5, against 297/600 at
  day 3: a stable standing crop, not a draining larder. Rot 0.
- 3-day, 3-seed rebalance A/B, same code except the four knobs: before
  **27 / 33 / 14 alive** (mean 24.7), 5 / 9 / 15 deaths, 1 / 7 / 6 dehydration;
  after **22 / 33 / 19** (mean 24.7), 8 / 10 / 10 deaths, 2 / 3 / 9
  dehydration; births 43 → 42. **The aggregate is a wash**: the water-poor seed
  gains 5 creatures and seed 202 loses 4 thirst deaths, while seed 101 gives up
  5 to hunger. The knobs are kept because they remove the nap-at-zero behaviour
  and improve the two worst seeds, not because they raise the mean.
- Seed 303 diagnosis (the seed that still fails): it starts with 420 water cells,
  not 600–660 like the others. At day 3 it holds 309 water and 554 wet cells;
  mean water 0.08; 9 of 10 deaths are thirst. Death records show `search_water`
  chosen at score 1.10 with food 0.00, energy 0.00, **zero water places**, and
  the nearest water 60–170 cells away: they were walking, not dithering, in a
  world whose ponds had been drunk dry. Water replenishment is the next supply
  decision.
- Imitation coverage: child and adult observers 2 cells from a drinker learn one
  place; the teacher does not; zero fidelity and 9+ cells learn nothing; a
  second lesson within 1 s is skipped; a child's copy is stronger than an
  adult's, and both are weaker than firsthand knowledge.
- Cost: 3-day soaks run **7.7–8.8 ms** mean at 19–33 alive (7.2–8.2 at 15–32
  before regrowth). Peaks 25–99 ms on a loaded host. Regrowth and rot each walk
  the food-cell list per material pass; imitation is one neighbour query per
  meal, not a per-tick scan.
- Suite: **187 checks, 0 failures**.

### Social measurements

Three tuning passes on the same 3 seeds x 3 days. The first pass let any hungry
creature heading into the same **patch** record a food dispute; it produced
**2,687 disputes and 281 rival bonds** on seed 101 alone, and every relationship
turned negative. Rivalry stopped carrying information.

| Pass | Dispute rule | Seed | Alive | Disputes | Rival bonds | Friend bonds | Avoid decisions |
|---|---|---|---|---|---|---|---|
| 1 | same patch within 3 cells | 101 | 27 | 2,687 | 281 | 0 | — |
| 1 | same patch within 3 cells | 202 | 30 | 2,496 | 288 | 2 | — |
| 2 | same cell, gain 0.22, cooldown 0.01 d | 101 | 29 | 540 | 42 | 15 | — |
| 2 | same cell, gain 0.22, cooldown 0.01 d | 202 | 31 | 822 | 112 | 2 | 18,346 |
| 3 | same cell, adjacent to it, loser hungry, cell < 60% full, cooldown 0.05 d | 101 | 27 | 556 | 50 | 12 | 3,226 |
| 3 | same rule | 202 | 34 | 1,068 | 137 | 8 | 14,297 |
| 3 | same rule | 303 | 18 | 81 | 5 | 9 | 1,189 |

What changed and why:

- **Dispute = the same cell, not the same patch.** Two creatures grazing side by
  side from different cells are sharing; only the neighbour that was about to
  take *this* bite lost anything. With the patch rule, a crowded food patch
  minted a hundred grudges an hour.
- **The loser must be hungry and able to reach the cell.** A well-fed bystander
  has no grievance, and a creature across the patch heading somewhere near it
  lost nothing it could have eaten.
- **The cell must be under 60% full.** The plan's rule is that context is the
  meaning: taking the last food from a hungry creature is a betrayal, taking
  from a full pile is housekeeping. At 90% almost every meal qualified.
- **A per-pair cooldown of 0.05 day** stops a long meal from recording an event
  every few seconds. Before it, one pair could accumulate a rivalry in a single
  bout.
- **Avoidance is local and weak.** It was offered below -0.15 opinion within 6
  cells at weight 1.5; by seed 202 that produced 18,346 avoid decisions and a
  mean food level of 0.23. It is now below -0.25, within 4.5 cells, at weight
  1.25 with a 0.6 boldness discount, and one second long. A strong hatred still
  moves a creature; a mild dislike no longer does.
- **Socialising prefers the nearest tie.** With every stranger at opinion 0, the
  first creature in the neighbour buffer won each tie and friendships were
  spread one point at a time across a shifting crowd. Ties now go to the nearest
  neighbour, so repeated meetings accumulate.
- **Socialise gain 0.10 → 0.14.** Two meetings now cross the +0.30 friend
  threshold; three are still needed for the label, which is the point.
- **The opinion read path is allocation-free**, and the spatial hash returns a
  reused buffer. Mean step fell only 10.34 → 10.24 ms; the 60–117 ms outliers
  persisted and also appear with social off (102 ms on seed 202), so they are
  not opinion-store cost. The buffer is kept because it is strictly cheaper.

### Social A/B, same seed and settings except `--no-social`

| Seed | Social | Alive | Births | Deaths | Mean step | Opinion entries | Rival bonds |
|---|---|---|---|---|---|---|---|
| 101 | on | 27 | 9 | 2 | 10.09 ms | 116 | 50 |
| 101 | off | 27 | 10 | 3 | 8.30 ms | — | — |
| 202 | on | 34 | 21 | 7 | 10.94 ms | 172 | 137 |
| 202 | off | 22 | 13 | 11 | 7.92 ms | — | — |
| 303 | on | 18 | 9 | 11 | 8.62 ms | 37 | 5 |
| 303 | off | 22 | 9 | 7 | 8.21 ms | — | — |

Mean alive 26.3 with social against 23.7 without; births 39 against 32; deaths
20 against 21. The direction is positive but not a rescue: one seed gains 12,
one is flat and one loses 4. Seed 303's loss is the same water ceiling recorded
above — mean water 0.10, six dehydration deaths — and the social build spends
some movement on avoidance instead of the next search leg. The social need never
kills; only the walking does.

Suite: **209 checks, 0 failures**. Benchmark 6.14 ms at 20 creatures, 59.52 ms
at 200. A 1-day spike probe on seed 101 recorded two steps over 20 ms (peak
24.5 ms) with social on, against four (peak 22.5 ms) before the shared buffer.
The 3-day soak peaks were 24.1 ms on 101, 90.0 ms on 202 and 97.2 ms on 303;
the two large ones are the same collector/host outliers seen with social off.

### Carrying, piling and comfort

The first pass exposed a treadmill rather than a store behaviour. Pick up moved
one tick's worth of sand into the load, pile immediately scored higher than
filling the load, and the cell just piled was picked up again: seed 101 recorded
**1,812 loads picked and 1,807 piled in one day**, almost all of them a single
handful, with 4 creatures still carrying at the end.

| Build | Seed | Picked | Piled | Still carrying |
|---|---|---|---|---|
| One-tick handfuls, pile wins immediately | 101 | 1,812 | 1,807 | 4 |
| Pile value scales with load fraction; pick-up can keep filling | 101 | 252 | 234 | 14 |
| Final build, 1 day | 101 | 180 | 162 | 15 |
| Final build, 1 day | 202 | 107 | 85 | 20 |
| Final build, 1 day | 303 | 272 | 246 | 19 |

The second rule is not a store script: it values a trip by what arrives at the
other end. A creature that has taken one handful has little to gain by dumping
it, so it keeps filling; the score reaches its maximum only when the load is
full. A short repick cooldown on the cell just piled prevents the immediate
grab-back without forbidding a later return.

The final 1-day, three-seed run ends at **29.7 mean alive** (range 29–31), no
deaths, and **10.64 ms** mean step. Loads are 559 picked and 493 piled across
the three seeds; 15–20 creatures are still carrying at the end of each day.
Pick-up and pile together are 1% of decisions, so the behaviour is rare enough
to be a choice rather than a new default. The one-day A/B is below; the clean
three-day A/B follows it.

| Seed | Carry | Alive | Births | Loads picked | Opinions | Mean step |
|---|---|---|---|---|---|---|
| 101 | on | 31 | 11 | 180 | 1 | 11.64 ms |
| 101 | off | 32 | 12 | 0 | 2 | 11.22 ms |
| 202 | on | 29 | 9 | 107 | 0 | 10.27 ms |
| 202 | off | 29 | 9 | 0 | 2 | 10.22 ms |
| 303 | on | 29 | 9 | 272 | 2 | 10.00 ms |
| 303 | off | 29 | 9 | 0 | 3 | 9.36 ms |

Mean alive **29.7** with carrying against **30.0** without; no deaths in either
arm. The only per-seed difference is seed 101 (31 against 32), one birth. The
A/B is not a controlled trajectory comparison: store choices consume the shared
RNG stream, and pick-up leaves an air hole that changes the next comfort
choice, so the two runs diverge from the first store decision. The social trace
diverges too: seed 101 records 42 food disputes with carrying against 12
without, and one labelled opinion against two. That is a different trajectory,
not proof that carrying is antisocial; the number of social exchanges is 56
against 66.

#### Three-day A/B (pre-overlap build)

The clean three-day A/B on the pre-overlap drop-at-thirst build uses the same
three seeds, with the control arm run as `--no-carry`. The runs shared the host,
so their step times are not compared; the simulation itself is fixed-step and
deterministic.

| Seed | Carry | Alive | Births | Deaths | Comfort | Loads picked | Loads piled | Hard cells |
|---|---|---|---|---|---|---|---|---|
| 101 | on | 56 | 37 | 1 | 0.51 | 2,605 | 2,556 | 403 |
| 101 | off | 42 | 24 | 2 | 0.54 | 0 | 0 | 466 |
| 202 | on | 22 | 9 | 7 | 0.08 | 454 | 438 | 385 |
| 202 | off | 22 | 11 | 9 | 0.17 | 0 | 0 | 440 |
| 303 | on | 20 | 10 | 10 | 0.05 | 790 | 760 | 322 |
| 303 | off | 24 | 12 | 8 | 0.05 | 0 | 0 | 378 |

Mean **32.7 alive with carrying against 29.3 without**; 18 deaths against 19,
and 3,849 loads picked / 3,754 piled against none. Mean comfort across the
three seeds is 0.21 with carrying against 0.25 without. Seed 101 gains fourteen
(56 against 42), 202 is flat (22 against 22), and 303 loses four (20 against
24). The 101 boom has 37 births and one death, with food 351 and water 598 still
standing at day 3; it has not met a ceiling in this window. The 303 arm records
two dehydration deaths against three and a mean water level of 0.24 on both
sides; its water cells are 308 against 309, so the ponds are equally dry. It
still dies more overall (10 against 8), and its comfort is as low as the
control's.

The harder result is the material one: despite moving 3,849 loads, the carry arm
ends with **fewer hard cells** on every seed (403 / 385 / 322 against 466 / 440 /
378). The piles are being made but not compacted into hard ground; the control's
extra resting compacts more. The suite proves the chain is reachable when a
creature rests on its own wet pile, but the soaks show it is not yet common
enough to pay for the carrying. That is a behaviour to inspect, not a number to
raise blindly.

The overall +3.4 is one seed's boom, not a uniform gain: 202 is flat and 303 is
still negative. The ten-day follow-up below answers the 101 stability question:
it does not settle, it goes extinct. The 303 residual cost remains open. The
seed-303 gate history is below.

#### Ten-day seed 101 follow-up (pre-overlap build)

Both arms were extended with `--days=10 --seed=101`, the control adding
`--no-carry`. This is the pre-overlap drop-at-thirst build used by the
three-day A/B; no code changed during that run. The populations were sampled
every 1.25 days.

| Sim day (sample) | 0 | 1.25 | 2.5 | 3.75 | 5.0 | 6.25 | 7.5 | 8.75 |
|---|---|---|---|---|---|---|---|---|
| Carry | 20 | 34 | 48 | 73 | 41 | 8 | 3 | 0 |
| No carry | 20 | 35 | 42 | 42 | 9 | 0 | 0 | 0 |

| Arm | Sampled peak | Day 10 | Births | Deaths | Old age | Starved | Dehydrated | Starved + dehydrated | Loads picked | Hard cells | Food / water |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Carry | 73 | 0 | 56 | 76 | 36 | 12 | 13 | 15 | 7,199 | 518 | 378 / 417 |
| No carry | 42 | 0 | 24 | 44 | 31 | 5 | 2 | 6 | 0 | 509 | 297 / 423 |

Both populations are extinct. The 56 at day 3 was the front of a boom, not a
stable ceiling: carrying reaches a sampled **73** and is **0 by the 8.75-day
sample**, while the control reaches **42** and is **0 by 6.25 days**. The crash
is primarily demographic, not a simple resource wall. Food (378 / 297, of which
254 / 263 is rotten) and water (417 / 423) are still standing, old age is the
largest death cause (36 of 76 with carrying, 31 of 44 without), and no child
or adult remains. The cohort ages out and there is no second generation to
replace it.

Carrying does not rescue that trajectory; it makes the boom larger and later:
56 births against 24, 76 deaths against 44, a sampled peak 31 higher. The extra
bodies consume more food and water, and 7,199 loads picked / 7,117 piled over
ten days do not produce a breeding generation. Hard cells end at 518 against
509, a negligible difference once both populations are gone. The three-day
positive mean is therefore a phase of the boom, not evidence of a persistent
carrying gain. The next experiment is an overlapping-generations rule, not
another carrying knob.

#### Overlapping generations attempt

Rule: the reproduction gate now excludes only children. A creature past
maturity may breed while its food, water, energy and health pass the gate, so
adult and old cohorts can overlap. A unit test covers a healthy old parent
producing a child; the old-age death test still covers the terminal decline.

Ten-day seed 101 on this build:

| Arm | Births | Deaths | Old age | Starved | Dehydrated | Starved + dehydrated | Sampled peak | Zero at | Population curve |
|---|---|---|---|---|---|---|---|---|---|
| Carry | 56 | 76 | 37 | 17 | 6 | 16 | 73 | 7.5-day sample | [20,34,48,73,40,8,0,0] |
| No carry | 24 | 44 | 31 | 5 | 2 | 6 | 42 | 6.25-day sample | [20,35,42,42,9,0,0,0] |

The rule added **no births**: 56 with carrying and 24 without, exactly the
pre-overlap counts. The control's whole population curve is identical. The
carrying curve is one sample shorter (40 against 41 at day 5, and 0 against 3
at day 7.5), but it has the same 76 deaths and the same final extinction. A
second breeding cohort never formed. The unchanged birth count indicates the
old cohort was not passing the food, water and health gate during the crash, so
the new eligibility was not exercised at population scale; the unit test proves
the gate permits old breeding, while the soak shows scarcity closes it first.

The result is negative for the extinction question: making another stage
fertile does not help a population that has already overshot its food and
water. The next fix is resource stability or a longer, more spread-out
breeding window, not another stage label.

#### Breeding-interval sweep

Rule: each birth leaves a base cooldown with independent jitter for each parent
(`repro.cooldown_days`, `repro.cooldown_jitter_days`). The flat 0.40-day
cooldown let a cohort return together; the sweep tested **0.65 ± 0.05** and
**0.90 ± 0.20** days. Each draw stays inside its stated window.

Ten-day seed 101, carrying arm only (the no-carry arm was not rerun for these
builds; the question was whether spacing births prevents the carrying arm's
boom-bust):

| Build | Births | Deaths | Old age | Starved | Dehydrated | Combined | Sampled peak | Zero at | Population curve |
|---|---|---|---|---|---|---|---|---|---|
| Pre-overlap, 0.4 d flat | 56 | 76 | 36 | 12 | 13 | 15 | 73 | 8.75 | [20,34,48,73,41,8,3,0] |
| Old fertility, 0.4 d flat | 56 | 76 | 37 | 17 | 6 | 16 | 73 | 7.5 | [20,34,48,73,40,8,0,0] |
| 0.65 d + 0.05 jitter | 38 | 58 | 35 | 4 | 13 | 6 | 46 | 8.75 | [20,29,35,46,44,15,1,0] |
| 0.90 d + 0.20 jitter | 22 | 42 | 29 | 5 | 5 | 3 | 32 | 7.5 | [20,30,31,32,31,7,0,0] |

The midpoint is not a rescue. At 0.65 days births are **38**, the sampled peak
is **46**, and deaths are **58**; the population lasts to the 8.75-day sample
but still reaches zero. Old age is 35 of the 58 deaths, no child or adult
remains, and food (399, of which 261 is rotten) and water (419) are still
standing. The three intervals produce three shapes — a boom at 0.4, a medium
rise at 0.65, and a low plateau at 0.9 — and all three extinguish. Changing the
interval changes the boom, not whether an aged cohort is replaced. The next
test is a longer reproductive lifespan or resource stability, not another
cooldown value.

The 0.65 and 0.90 runs had mean steps of 33.40 and 24.07 ms under a busy host,
so neither is compared with the earlier step times.

#### Critical-thirst gate (seed 303)

Rule: `carry.thirst_suppress = 0.60`. While thirst urgency is at or above the
threshold, pick-up is not offered; pile remains available as an emergency drop,
so a carrier can shed its load and speed penalty while heading for water. The
gate is a need threshold, not a ban: a mildly thirsty creature can finish a
useful trip. Two suite checks cover the suppressed pick-up and the still
available pile.

| Arm | Alive | Births | Deaths | Dehydration | Comfort | Loads picked | Loads piled | Hard cells |
|---|---|---|---|---|---|---|---|---|
| Carry, before gate | 15 | 10 | 15 | 8 | 0.08 | 1,066 | 1,027 | 293 |
| Carry, suppress both (previous) | 17 | 10 | 13 | 5 | 0.04 | 748 | 709 | 310 |
| Carry, drop-at-thirst (current) | 20 | 10 | 10 | 2 | 0.05 | 790 | 760 | 322 |
| No carry (control) | 24 | 12 | 8 | 3 | 0.05 | 0 | 0 | 378 |

Suppressing both recovered **two creatures** and cut dehydration from **8 to 5**.
Allowing the pile as an emergency drop recovers **five**: 15 → 20 alive,
dehydration 8 → 2, loads 1,066 → 790, hard cells 293 → 322. The drop-at-thirst
arm now has *less* dehydration than the 24 control, but it is still **4 below**
the control, with 10 deaths against 8 and 8 loads still carried. The residual
cost is not water alone: the arm still spends commitment on store and comfort
and ends with fewer hard cells (322 against 378). Drop-at-thirst is the current
rule and stays; the next knob is the comfort/rest draw or the 0.60 threshold,
not another water gate.

Suite: **260 checks, 1 failure** — all functional checks pass, but the
20-creature performance gate measured **27.77 ms** against its 10 ms limit, and
the 200-creature pass measured 296.30 ms against 69.88 ms on the previous clean
run. The host was still contended (the same build's seed 101 step was ~33 ms),
so this is a timing failure, not a code regression. The previous clean suite on
the old build was 259 checks, 0 failures at 6.73 / 69.88 ms.

Open issues from this slice:

- **No soak has produced a readable cache or shelter story yet.** The loads move
  and the hardened cells appear, but the log does not yet say “creature 88 piled
  wet sand here, rested on it, and the cell is now hard.” That belongs to the
  why-inspector, not to a new behaviour rule.
- **Carrying is not selective about water.** Sand can be piled into a pond and
  will fill it; the score now treats water as wet so it is unattractive, but the
  action remains possible. Water cannot be carried at all because there is no
  container material.
- **Store learning is one delayed credit, not a model of planning.** Eating from
  a cache credits the pile and pick-up weights with the meal's gain, using the
  context and stress recorded at piling time. A creature cannot yet anticipate a
  future cache; it can only learn that the last one worked.
- **Comfort has no gene.** Its decay and recovery are parameters, not inherited
  loci, so selection cannot yet act on a creature's tolerance for poor ground.
- **The water-poor seed still pays for carrying.** On the pre-overlap
  drop-at-thirst A/B, seed 303 is 20 against 24, with 10 deaths against 8;
  dehydration is now 2 against 3, so water is no longer the deficit. It ends
  with 8 loads still
  carried and 322 hard cells against 378. The next knob is the comfort/rest draw
  or the 0.60 threshold; the water gate has done its job.
- **Seed 101's 56 was an overshoot, and old fertility did not rescue it.** The
  pre-overlap ten-day follow-up reaches a sampled 73 with carrying against 42
  without, and both arms are extinct (0 by the 8.75-day and 6.25-day samples)
  with food and water still standing. The old-fertility rerun adds **no births**
  (56 with carrying, 24 without), so it did not create a second breeding cohort.
- **The overlap experiment failed for a resource reason.** The unchanged birth
  count indicates the old cohort was not passing the food, water and health
  gate during the crash; the new gate permits old breeding only while those
  needs pass.
- **The breeding-interval sweep is negative.** The 0.4, 0.65 and 0.90-day
  cooldowns produce boom/medium/low shapes (peaks 73/46/32) and all end at zero
  (8.75/8.75/7.5 days). At 0.65, 35 of 58 deaths are old age and food and water
  still stand. Changing the interval alone does not replace the aged cohort;
  test a longer reproductive lifespan or resource stability next.

### 2026-10-28 — Safety need, protection affordance and the flee verb

**Rule.** Safety is a need with its own inherited curve (locus 18, 1.6–3.2).
Each tick it walks the creature's own opinion store (at most sixteen entries):
every negative opinion within 12 cells is a threat whose strength is
`−opinion × size_other / size_self × (0.25 + 0.75 × proximity)`. The strongest
threat applies `10/day × strength` of loss, and exposure adds
`0.15/day × (1 − protection)`. With no threat it recovers 0.30/day; rest adds
`1.8/day × protection`. Protection is `0.25 × hardness + 0.15 × cohesion +
0.60 × share_of_hard_neighbours`, read from the cell at query time. It is an
arrangement, not a tag: a pond pan, a dune and a creature's pile all use the
same rule.

Flee is the twelfth verb. It is offered when safety urgency passes 0.15 and a
remembered enemy is inside 9 cells; its score is `3.0 × urgency × threat
strength × (1 − 0.6 × boldness)`. The target is 8 cells directly away, movement
is 1.4×, and the bout ends at 9 cells. At urgency ≥ 0.70 flee bypasses sampling
and interrupts whatever else was chosen, while a threat is in reach. That
interrupt is the plan's one priority-like rule and belongs to the safety curve,
not to a ladder of needs.

**Why the threat floor is 0.0, not −0.25.** The first build reused avoid's
−0.25 threshold. One day on seed 202 produced 4 food disputes, 0 opinions with
three events and 0 flee bouts; the need could only fire in a test that
manufactured a −0.70 opinion. Grading from any negative opinion lets a mild
grievance erode safety slowly and a real feud erode it fast. Avoid still
requires −0.25, so the mild response is unchanged.

**Evidence.**

- Protection: a lone hard cell 0.36, a hard ring 0.96, open sand 0.00, water
  0.00.
- 200 ticks beside a −0.70 opinion: safety 1.00 → 0.82; the same pair as
  strangers stays at 1.00.
- 3000 ticks from 0.40: open ground 0.46, resting in a hardened 3 × 3 1.00.
- Safety 0.20 beside a disliked neighbour at 1.5 cells: flee 59/60, aim away
  from the threat 59/60.
- Safety 0.45: flee score 0.45 timid vs 0.18 bold.
- Hungry on food with safety 0.03: the eat candidate exists, the chosen verb is
  flee, and the context is afraid.
- 30 real ticks: 30 flee decisions, distance 1.50 → 6.98 cells, one throttled
  `safety` log line.
- A retreat from safety 0.10 to 0.60 teaches +0.125 flee weight in the afraid
  context; the episode records its safety outcome.
- With safety disabled: no flee candidate, no flee decisions, safety 0.15
  unchanged over 30 steps.
- A newborn starts at safety 1.00 while both parents are at 0.10.

**Same-seed A/B, 2 simulated days, seed 202:**

| Metric | safety on | safety off |
|---|---|---|
| Alive / births / deaths | 24 / 10 / 6 | 24 / 10 / 6 |
| Mean safety | 0.57 | 1.00 |
| Flee bouts / decisions | 1,839 / 2,586 | 0 / 0 |
| Avoid decisions | 181 | 1,635 |
| Rival / friend bonds | 6 / 2 | 13 / 2 |
| Food disputes / opinions | 116 / 24 | 161 / 33 |
| Hard cells | 377 | 372 |
| Mean / peak step | 40.03 / 223.95 ms | 39.89 / 179.67 ms |

Flee substitutes for much of the avoidance and the surviving population is
identical. The social graph is thinner (rival bonds 13 → 6), which is the next
thing to read in play; it should be tuned through the flee need threshold or
threat scaling, not with a new verb.

**Cost.** The need walks at most sixteen remembered relationships and a 3 × 3
protection scan; it adds no spatial query. A 200-creature probe measured 209.4
ms/step with safety against 204.5 without on this host, inside the noise. The
host is about 2.7× slower than the reference machine (16.8 ms at 20 creatures
with safety off), so the suite's 10 ms gate fails here for environment reasons;
the functional checks pass.

**Not in this slice.** No attack, damage, sharing or help event: a threat is
only a remembered negative opinion, so a stranger is never feared. Danger is
not stored per place. Flee has no pathfinding and can run into water or the map
edge. The safety locus changes the genome draw, so seeds differ from the
pre-safety build and `--no-safety` is the controlled comparison.

### 2026-10-28 — Move to is the thirteenth verb

**Rule.** `MOVE_TO` is appended to the verb table. The brain gives it to the
recall candidates only: a remembered meal or pond is a chosen place, not a
currently perceived resource. `seek` remains the verb for an advertisement in
sight. The labels stay `recall_food` and `recall_water` because they name the
lead, and `recall_actions` counts those labels, so the memory metric is
unchanged. Move-to shares `_do_seek`, the 2.0 s commitment and the walk frames.

**What changes.** The action mix and the inspector now separate travel from
seeking; `seek` in a soak means a resource was visible at decision time. Episodes
record `move_to` instead of `seek`. Neither teaches a weight: the mean need
drifts down while travelling, and the eat or drink that follows carries the
credit. Nothing in scoring, commitment, movement or the RNG changed, so no
balance claim is made and no A/B is needed.

**Evidence.** A hungry creature with only a remembered cell offers
`recall_food` with the move-to verb; 45 real ticks choose move-to and close the
distance. A visible meal offers `seek_food` with seek. The verb table has 13
unique names. These are asserted in the suite.

### 2026-10-28 — Sharing and harm: two social events that move a real quantity

**Rule.** A share is an extra `socialise` candidate. The giver must carry at
least 0.15 food and sit above its own surplus line (0.55 food); the partner must
be at or below 0.60 food, and neither side's opinion may be below −0.05. The
score rises with recipient hunger, giver surplus, sociality and affinity. On
execution the load falls by 0.15, the recipient's food rises by 0.15 × carried
nutrition × 1.4, the recipient's gratitude is 0.25 × (0.5 + 0.5 × hunger), and
the giver records half that. A per-giver 0.10-day cooldown is the slower clock
inside the 20 s socialise cooldown.

Harm is the existing `_contest_food` path read once more. After the grievance is
recorded, the eater injures a loser when it is aggressive above 0.60, at least
0.95× the loser's size, does not like the loser (opinion ≤ 0.05), and the loser
is vulnerable (health ≤0.60 or food ≤0.55). Damage is 0.08 × size ratio ×
(1 + 0.5 × missing health) × (0.75 + 0.5 × scarcity). The victim loses health,
takes a 0.35 safety shock, records −0.45, and the attacker records −0.08. A
lethal injury is queued with cause `harm`. The per-pair dispute cooldown
(0.05 day) rate-limits the whole event.

**Why the vulnerability floor is 0.55 food, not 0.30.** A two-day diagnostic on
the old gate saw 231 disputes: 154 winners were too calm, and all 77 aggressive
winners then failed vulnerability. Victim food at the dispute averaged 0.52
(range 0.25–0.65) and victim health was 1.00 in every case, so a 0.30 food or
0.60 health floor made harm unreachable in ordinary play. A hungry contestant is
already the dispute's vulnerable party; 0.55 is its median food level and still
leaves aggression, size and a negative relationship as gates. With that one
value changed the same seed produces 6 harms.

**Evidence.**

- Focused tests: one share transfers 0.15 food, raises both opinions, writes one
  `social` line and counts once; a second exchange inside the cooldown does not
  share again.
- One contested meal injures, shocks safety 0.40 → 0.05, makes the attacker the
  victim's remembered threat, and the victim then chooses flee and gains more
  than 0.5 cells over 20 ticks. The harm line names the damage, safety and
  opinion.
- The injury is capped by the loser's health; a 0.02-health victim dies and the
  death is counted as `harm`, not starvation. With safety off the injury and
  memory still occur but the shock and flight do not; with social off neither
  event occurs.
- Same-seed 2-day soak (202): 209 food disputes, **3 shares, 6 harms**, 0 harm
  deaths, 32 alive. The event log held **134 of 256 slots: 3 share lines and 6
  harm lines**, one per event, not one per tick, so the two new events do not
  crowd deaths, births or rival transitions out of the ring. Mean step 30.67 ms
  on this host, against 32.70 ms on the same seed before the vulnerability
  change; both are host-bound, so no speed claim is made.

**Not in this slice.** No help-by-proximity or witnessed-success event, no fight
verb, no shield or weapon, no dominance, and no culture detector. Harm is only
the contested-meal outcome; a creature cannot attack outside a meal. Sharing is
rare (3 in 2 days), so a session may show cooperation only after a successful
food load meets a hungry neighbour.

### 2026-10-29 — Restoring the documented baseline, and a recall distance that does not saturate

The working tree reached this session mid-experiment: the previous run lost its
connection after editing `data/parameters.json` and `sim/sim.gd` at 01:59, two
hours after the register was written. Four changes were live but unregistered:
energy decay / movement / rest recovery 1.30 / 0.80 / 5.0 → 0.90 / 0.50 / 7.0,
`brain.commitment_bonus` 0.12 → 0.40, `repro.cooldown_days` 1.50 → 2.50, and
larger, fuller pond ellipses (rx 5–10, ry 4–8, fill 0.70–1.00 → rx 6–11,
ry 5–9, fill 0.85–1.00) with six near-founder food patches instead of four.
The suite on that build reported **357 checks, 12 failures**: the 20-creature
performance gate under six parallel soaks, the move-to distance check, and ten
of the twenty-four Phase 1 exit-criteria story checks (all five shelter and all
five rivalry checks).

**Move-to: the distance discount saturated.** The recall candidate divided the
memory's distance by the creature's *sensory radius*, then clamped to 1.0. For a
child, whose sense radius is only a few cells, every remembered place beyond
sight was therefore maximally distant, so a meal 7 cells away and one 40 cells away scored the same
and recall sat at roughly the same score as idle wandering. One sampled wander
leg — held for 6–9 s by the wander commitment — was enough to walk the creature
away from its only lead. The fixture closed 3.16 cells at commitment 0.12, 0.31
at 0.20 and 0.96 at 0.40, against a check that requires 2.0.

Fixed by a new `memory.recall_distance_cells` (24.0): the discount now falls off
against the memory's own reach, not the eye's. The same fixture ends **3.85 cells
from the target at commitment 0.12** (3.36 closed) and 4.60 at 0.40 (2.61
closed), so the check passes on both and no longer depends on a large commitment
bonus. The bonus itself returns to 0.12 because 0.4 is not
“small” beside base scores of 0.1–0.5: it makes a held wander leg nearly
unbreakable, and the 0.4 arm reached the move-to target only when the recall fix
was also present.

**Shelter: cheap rest removed the compaction the chain needs.** With the
0.90 / 0.50 / 7.0 energy values the shelter fixture's builder never tires: it
piles **87** loads of sand in two days, the wet load is diluted and the pocket
fills with food caches (sand cannot be deposited on a food cell), and the
result is max wet history **0.21**, max hardness **0.00**, shelter events **0**.
With the register's 1.30 / 0.80 / 5.0 the same fixture produces hard sand
(hardness **1.00**, wet history **0.92**) and **one** shelter event. The energy
values were restored: a fatigue cycle is what makes resting on a pile a real
choice, and the shelter story is the plan's Phase 1 exit criterion. The previous
session's claim that the energy fix “keeps two of three seeds alive” did not
reproduce under measurement (see the soak below).

**Breeding interval is not the collapse lever.** Ten simulated days, three
seeds, no player input, on the in-flight build, one `--param=` arm each:

| Seed | Cooldown | Peak (day) | Alive at day 10 | Births | Deaths | Diversity |
|---|---|---|---|---|---|---|
| 101 | 1.50 | 62 (4.0) | 6 | 51 | 65 | 0.270 |
| 101 | 2.50 | 45 (3.5) | 5 | 31 | 46 | 0.357 |
| 202 | 1.50 | 40 (3.0) | 3 | 27 | 44 | 0.421 |
| 202 | 2.50 | 32 (2.0) | 0 | 15 | 35 | 0.000 |
| 303 | 1.50 | 31 (1.5) | 0 by day 7 | 14 | 34 | 0.000 |
| 303 | 2.50 | 31 (1.5) | 0 by day 6 | 12 | 32 | 0.000 |

The longer interval halves the boom (births 51 → 31, peak 62 → 45) and still
collapses, on every seed. This matches the earlier interval sweep: spacing
births changes the shape of the overshoot, not whether the cohort is replaced.
The value returns to the documented 1.50 rather than being changed on evidence
that does not separate the arms on outcome.

**The restored build, three days, three seeds.** Energy and cooldown restored,
commitment 0.12, recall distance 24, otherwise the in-flight world:

| Seed | Alive | Peak | Births | Deaths | Diversity | Verb changes / creature-minute |
|---|---|---|---|---|---|---|
| 101 | 38 | 38 | 19 | 1 | 0.404 | 478 |
| 202 | 30 | 31 | 11 | 1 | 0.394 | 466 |
| 303 | 28 | 29 | 10 | 2 | 0.398 | 489 |

All three are alive and in the documented diversity band, but seed 101 is above
the register's day-3 band (21–26), and this build also carries the enlarged
ponds (standing water 1,011–1,212 cells against 309–659 in the earlier runs) and
six near-founder food patches. Which of the two moves the population — the water
supply or the recall distance — is not separated here; the new `--param=` flag
makes that A/B one run per arm. The suite on the restored build is **357 checks,
1 failure**, and the failure is the 20-creature gate at 10.03 ms against its
10.0 ms limit while three soaks shared the host; the earlier clean suite measured
8.47 ms on the same machine.

**Instruments added, not behaviour.** `tools/phase2_soak.gd` accepts
`--param=section.key=value` (repeatable) so an A/B pair can share one parameter
file, and `Sim.verb_changes` counts verb swaps; the soak reports them per
creature-minute. The count is how hysteresis is now measured: **466–489 swaps
per creature-minute** on the restored build means a creature changes verb about
every other tick. Commitment at 0.12 does not stop that, and 0.4 only reduced it
by about 40% in the fixture. This is the next legibility question, and it is a
decision-cadence change rather than a knob (see Open issues).

### 2026-10-29 — A world water cycle, and a rivalry fixture that stops depending on the draw

**The water budget had no inflow, so the 30-day gate was arithmetically
unreachable.** No rule returned water to the world: ponds evaporated at
`water_evaporate_per_day` 0.05, seeped into their banks as wetness, and were
drunk at ~0.65 amount per creature-day, and nothing replenished them. Seed 303
fell from 420 water cells to 309 in three days (9.3%/day) and seed 202's
dehydration deaths were the largest single cause. A ten-seed, thirty-day
no-input soak can therefore only end in extinction, whatever the creatures do,
so the plan's soak gate could not be met by tuning creature parameters at all.

Added `materials.water_regrow_per_day` (0.15) as a logistic seepage into cells
that are already water: gain = rate × (a/cap) × (1 − a/cap), so a pond refills
the holes drinking left in it, while a pond drunk down to a puddle recovers only
a trickle. That shape is deliberate: it is the plan's "logistic, proportional to
uneaten stock" rule, and it keeps the drought scenario honest because a small,
heavily used pond still cannot be sustained (a 177-cell pond with 14 creatures
needs ~0.27 to balance, so it drains). Zero restores the old finite world.

Measured on three seeds × twelve days, same tick, no player input:

| Seed | Water cells at day 0 | No water cycle | With the cycle |
|---|---|---|---|
| 101 | 1,186 | 0.41 mean creature water at day 4, falling | 1,014 cells held at day 8 |
| 202 | 1,212 | dehydration the largest cause | 1,208 cells held at day 10 |
| 303 | 1,024 | 420 → 309 in 3 days before this build | 1,022–1,024 held through day 8 |

The ponds now hold. The population still collapses, and the cause is not water
(see the entry below): the water cycle removes one fatal arithmetic limit, it
does not make the ecology sustainable on its own.

**The rivalry story was a knife-edge, and any material change re-rolled it.**
The Phase 1 exit-criteria fixture put four hungry creatures on one food cell
refilled to 0.40 whenever it fell below 0.05, in an 8 × 8 world with a spring.
With the water cycle in place the same fixture produced **0 rival labels**: the
opening burst of disputes spread across six pairs, each pair reaching three or
five events at a per-event valence of −0.045 instead of −0.055, and the label
needs three events below −0.20. The mechanism was intact — the run had 20
disputes and opinions in the right direction — but the fixture had no margin, so
it was testing which pair happened to meet most, not whether repeated negative
events make a rival.

Fixed by making the meal meagre instead of generous: the cell started at 0.40
and was refilled to 0.40 on any dip below 0.05, which ended the disputes after
a tenth of a day. It now holds 0.30 and is refilled only when it is empty
(< 0.02), so the cell is usually depleted and the contests keep coming. The
assertion is unchanged. The label now appears at **every** regrowth value tested
(0, 0.05, 0.15, 0.30, 0.60), so the check no longer moves when a material knob
does: one rival label, 19 disputes, one flight from the rival.

**Where the population actually goes: not supply, not distance.** With the
water cycle in place the three seeds still declined (101: peak 44 at day 5.5,
26 at day 7, 13 at day 8; 202: one creature at day 12; 303: extinct at day 8),
so the next question was which resource runs out. A census every half day —
population by stage, the gate term each living creature fails, food mass,
edible cells, mean nutrition, and the distance from each creature to the nearest
food and water cell by a breadth-first sweep — says none of them:

| Signal, seed 303 | day 0.5 | day 4.5 | day 6 |
|---|---|---|---|
| population | 29 | 9 | 6 |
| food mass standing (cells) | 304 (371) | 350 (374) | 354 (374) |
| mean food nutrition | 0.95 | 0.66 | 0.58 |
| nearest food cell, mean / max | 14 / 56 cells | — | — |
| mean creature food / energy | 0.56 / 0.36 | 0.25 / 0.24 | 0.29 / 0.21 |

The larder is not short: mass and edible-cell count rise while the population
falls, and the creatures are within a few cells of food. Nutrition does fall
(0.07/day, rot) which doubles the mass a creature must find for the same meal,
and that is a real multiplier — but a doubling of distance cost cannot explain
starvation at five cells. Two coupled failures explain it instead:

1. **Rest is structurally short, so energy sits below its own breeding gate.**
   Energy decays at 1.8/day while moving and recovers at 5.0/day while resting,
   so a creature must rest ~47% of its day to hold its level; the rest score is
   multiplied by `1 − 0.8 × max(hunger, thirst)`, which is the intended fatigue
   cycle, and 25% of decisions are rest. Measured mean energy is **0.19–0.36**
   against `repro.gate_energy` **0.55**, and the gate census found **0–2
   creatures ready to breed out of 29** for days at a time. No second cohort
   forms, so the founder cohort ages out — the same conclusion the earlier
   interval sweep reached, now with the failing term named.
2. **Fear dominates the decision budget.** At day 6 on seed 303 the action mix
   was wander 30%, rest 25%, seek 23%, eat 7%, move-to 6%, flee 3%, with
   **25,888 flee bouts and 21,061 flee starts against 133 food disputes** — about
   195 retreats per dispute. Any negative opinion is a threat, so a dense home
   range of mild grievances makes everyone afraid of everyone, and a fleeing
   creature neither eats nor rests. Escape, not scarcity, is what empties the
   day.

Two experiments were run against this reading.

- **Slower rot (0.05/day) and faster regrowth (0.25/day) each help one seed and
  not the outcome.** Rot 0.05, seed 303: 3 alive at day 6 against 7 on the
  baseline. Regrowth 0.25, seed 303: **14 alive at day 6** against 7, and 17 at
day 5.5, but seed 101 still fell from 39 at day 3 to 14 at day 6. Both change
the shape of the overshoot; neither stops the replacement failure, which is what
a food knob should be expected to do once supply is demonstrably not binding.
- **Regrowth that also refreshed spoiled tissue was rejected.** Letting a
  full cell gain nutrition at the growth rate (instead of only eating diluting
  rot) makes the standing patch settle at an equilibrium nutrition instead of
  decaying. It flattens the rot->toxicity path entirely — the suite's
  "food that rots past the threshold becomes toxic" check fails, because at
  `food_regrow_per_day` 0.12 no wetness produces an equilibrium below the 0.40
  threshold — and seed 303 still crashed (9 alive at day 5, nutrition 0.63).
  Reverted: a balance fix that removes a designed outcome and does not move the
  gate is not a fix.

### Open issues

- **Verbs dither far faster than a player can read.** 466–489 verb changes per
  creature-minute (one every ~1.9 ticks at 15 Hz) on the restored build. The
  commitment bonus is additive and small against score gaps of a few hundredths
  while softmax temperature is 0.10–0.45, so sampling flips the verb even while
  an action is “in progress”. The plan's wording is that commitment applies
  *while in progress*; the honest fix is decision cadence — decide every N ticks
  with safety and critical-need interrupts — not a larger bonus, which the
  0.4 experiment showed makes one long wander leg unbreakable instead. Phase 3
  territory, but it gates the Phase 2 legibility criterion.
- **The world's water supply doubled without a record.** Pond ellipses are now
  rx 6–11 × ry 5–9 at 0.85–1.00 fill (was rx 5–10 × ry 4–8 at 0.70–1.00), so the
  same seeds hold 1,011–1,212 water cells where earlier runs held 309–659, and
  the near-founder food patches went from four to six. The values are recorded
  here for the first time; the long soak must decide whether they stay. The
  register's parameter table now lists nearby food patches as 6.
- The worst typical step is now ~20–32 ms with social on, most of it the
  decision pass growing with the population (10–11 ms at 30 creatures) landing
  on a material pass. Staggering decisions is Phase 3 work; the material pass is
  bounded at ~5 ms p99. The 90–97 ms soak outliers also occur with social off
  (102 ms on seed 202), and a 1-day probe peaks at 24.5 ms, so they are host/GC
  noise, not a system budget.
- Opinion is capped at sixteen relationships per creature and never forgets an
  entry, only decays it; a creature that has met many others evicts the weakest
  record, which can discard a mild friend while keeping a strong rival.
  Helped-by-proximity, witnessed-success and dominance events are not
  implemented, so the social graph is built from socialising, food disputes,
  sharing, harm and mating only.
- Sharing is rare: 3 shares in a 2-day run with 100 food loads picked. A giver
  must still hold food above 0.55 and meet a hungry partner inside 2.5 cells
  during a 20 s social cooldown. If a first session should show cooperation
  sooner, widen `share_hunger` or the contact radius; do not make the transfer
  unconditional.
- Rivalry is still lopsided on seed 202: **16 directed rival bonds against 2
  friend bonds** after two days (41 opinion entries). The disputes are real
  (same cell, hungry loser, depleted cell), but a player may read a crowded
  patch as a den of rivals rather than a place with two or three feuds. Raising
  the rival threshold or lengthening the cooldown further is the next knob if
  that reads badly.
- Avoidance can pull a creature off a search leg, and that cost is visible on
  the water-poor seed: social on ends at 18 alive, social off at 22. The social
  need itself is harmless; the movement it causes is not free.
- Social decisions consume the shared RNG stream, so an on/off A/B diverges from
  the first social choice. The three-seed mean and the same-seed A/B are the
  honest comparisons; per-seed numbers against the pre-social build are not.
- Population on seed 101 booms and then ages out: the pre-overlap ten-day A/B
  reaches a sampled 73 with carrying and 42 without, and both reach zero (by
  the 8.75-day and 6.25-day samples). The old-fertility rerun adds no births and
  still reaches zero (7.5 and 6.25 days); the 0.65-day spacing run peaks at 46
  and still reaches zero at 8.75, while the 0.90-day run peaks at 32 and reaches
  zero at 7.5. **The ceiling is demographic, not food**: old age is the largest
  single cause and food and water are still standing, so the cohort has no
  second generation left. The interval sweep is exhausted; the next test is a
  longer reproductive lifespan, with resource stability the other lever.
- Water does not regrow, and that is now the binding constraint on the
  water-poor seed: seed 303 loses 420 → 309 water cells in three days and 9 of
  10 deaths to thirst. Search cannot find water that has been drunk dry.
- Search is blind and correlated, not intelligent: it can miss a pond between
  legs, and a creature with no water memory can spend its reserve before
  crossing one. Even with 48-cell legs the 3-day mean is unchanged by the
  rebalance; the gain is behavioural (no nap at water zero), not demographic.
- Learned weights never fade, and recall is per creature; imitation copies
  places, not actions, so a practice cannot yet spread as a sequence. Lessons
  from one poisoned meal persist for life, which is intended but untested
  beyond a five-day window.
- Imitation is one neighbour query each time a creature eats or drinks, capped
  at one lesson per second per teacher; at 33 creatures it is not measurable
  above the decision-pass noise.
- A child is not drawn smaller; the body scale affects speed, sense and strength
  but the renderer has one sprite size.
- Step peaks of 20–60 ms still appear on a loaded host with identical work
  counters, which is scheduling rather than simulation cost. The soak's peak
  column is a single worst step, so it reports that noise; p99.9 is the stable
  figure.
- The property batch is deterministic but makes material time slower when more
  than 400 cells are changing at once; no starting world reaches that today
  (2,000–2,600 queued cells, 400 processed per pass).
- Flow cost scales with the number of water cells (~3.8 µs each, ~2.5 ms for a
  660-cell pond). A flood holding several thousand water cells would cost tens
  of ms; there is no flow budget yet.
- Pond pans are a world-generation fact, not a general impermeable material.
  When Phase 4 adds clay or bedrock, the pan should be expressed with it.
- Safety is social memory plus injury: fear still comes from the creature's own
  negative opinion, and harm adds a one-off shock to that same memory. There is
  no attack action, no weapon or shield, and danger is not stored per place; a
  stranger is never a threat until it has wronged someone. Dominance and
  help-by-proximity are still absent.
- Fear is slow and build-dependent. One day on the pre-share seed 202 had no
  flee at all; two days had 1,839 bouts then and **3,934** after sharing/harm
  changed the trajectory, with mean safety 0.55. If a first session should show
  a retreat sooner, the knob is threat scaling or the flee need threshold, not
  a new verb.
- Flee and avoid overlap. The 2-day A/B cut avoidance from 1,635 to 181
  decisions and rival bonds from 13 to 6 while the population stayed at 24.
  Read the social graph in play before changing either threshold.
- The safety locus changes the genome draw, so pre-safety seed numbers are not
  per-seed comparable; use `--no-safety` on the same build.
