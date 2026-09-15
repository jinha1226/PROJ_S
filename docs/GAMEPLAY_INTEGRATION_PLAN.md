# PROJ_S — Gameplay & Mobile Top-View Integration Plan

> Status: working design document  
> Priority: **gameplay integration first**. Code quality/refactoring and visual polish come later.

## 1. Product direction

PROJ_S should become a mobile-friendly top-view dungeon crawler that combines:

- the run-to-run discovery and build variety of a traditional roguelike,
- dungeon crawling where positioning, terrain, resources and encounters matter,
- the existing body, elemental, ability, personality, relationship and world simulation,
- readable decisions on a small screen without exposing raw simulation values during normal play.

The simulation engine is not the final gameplay. The next phase is to make its systems **interact in ways the player can intentionally exploit, discover and combine**.

The target experience is:

> **Simple input → understandable intent → rich simulated consequence → new tactical choice.**

The player should not need to understand every internal number. Detailed values remain available through inspection screens for players who want them.

---

## 2. Current design problem

The project already contains many potentially interesting systems, but their existence alone does not create roguelike depth.

The main risk is **parallel systems**:

- body simulation exists,
- elemental simulation exists,
- abilities exist,
- equipment exists,
- terrain exists,
- personality/relationships exist,

but if each system mostly produces its own isolated modifiers, the player experiences complexity rather than combinations.

The core development task is therefore not adding more systems. It is creating a **shared interaction grammar** between the systems already implemented.

---

## 3. Core gameplay loop

The dungeon loop should converge toward:

1. **Observe**
   - enemies
   - terrain
   - hazards
   - body/condition cues
   - nearby objects
   - party/NPC state

2. **Form intent**
   - approach
   - disengage
   - control space
   - exploit environment
   - use ability/item
   - protect/reposition
   - recover

3. **Act**
   - movement
   - weapon action
   - ability
   - item
   - environmental interaction
   - party command

4. **Simulation resolves consequences**
   - damage/body effects
   - elemental/material interaction
   - terrain changes
   - statuses
   - enemy/NPC response
   - secondary events

5. **World state changes visibly**

6. Player receives a new tactical problem.

The important unit of fun is not the individual skill button. It is the **state transition created by the action**.

---

## 4. Interaction grammar

Before adding a large number of skills/items, define reusable states that multiple systems can create and consume.

Candidate shared states:

### Body / actor

- bleeding
- burning
- wet
- chilled
- overheated
- poisoned
- exhausted
- staggered
- immobilized
- impaired limb/function
- panic/fear
- unconscious/downed

### Environment / material

- wet
- burning
- frozen
- electrified
- slippery
- obscured
- toxic
- broken
- conductive
- flammable

### Tactical

- exposed
- guarded
- threatened
- flanked
- pinned
- separated
- concealed
- controlled zone

The exact list should remain small initially.

The goal is:

**one state can be created by several sources and consumed by several other mechanics.**

Example:

```
water spell
    ↓
WET
 ├─ lightning → conductivity / chain effect
 ├─ cold → freeze
 ├─ fire → steam / extinguish
 ├─ movement → slippery surface
 └─ body simulation → temperature interaction
```

This is much more valuable than five unrelated skills with five bespoke effects.

---

## 5. Build-combination design

The long-term run variety should come from combinations across several axes.

### A. Body

Species/body properties and current physical condition change what is viable.

### B. Equipment

Weapons, armor, accessories and consumables should change **how the player interacts with the simulation**, not only numerical stats.

Prefer:

- applies a state,
- consumes a state,
- converts one effect into another,
- changes range/shape/timing,
- creates terrain interaction,
- alters risk/reward.

Avoid relying primarily on:

- +5% damage
- +3 defense
- +10% elemental damage

### C. Abilities / powers

Abilities should be verbs in the interaction grammar.

Examples:

- ignite
- freeze
- pull
- push
- rupture
- conduct
- absorb
- spread
- convert
- anchor
- mark

### D. Skills / mastery

Mastery can specialize a verb or weapon behavior rather than simply increasing output.

### E. Dungeon findings

A run needs discoveries that can redirect the build after it begins.

The ideal question during a run is:

> “Given what I found, what can I build from this?”

rather than:

> “Did the item with the larger number drop?”

---

## 6. Emergent-combination prototype

Do not immediately build dozens of abilities.

First create a small vertical slice where interactions are undeniable.

Suggested prototype ingredients:

- 3–4 damage/effect families,
- 5–8 shared states,
- 3 weapon archetypes,
- 6–10 abilities/powers,
- several terrain/material types,
- several items that modify interactions,
- enemies with meaningfully different vulnerabilities/behaviors.

Acceptance criterion:

**The same encounter should admit several materially different solutions depending on the player's current combination.**

For example:

- direct weapon kill,
- wet + electricity,
- fire + combustible terrain,
- freeze + positional control,
- body impairment + disengagement,
- terrain manipulation + ranged attack.

If the prototype cannot produce this, adding content should stop until the interaction grammar improves.

---

## 7. Dungeon crawling requirements

The game should not become only a combat simulator.

Dungeon exploration needs persistent decisions between encounters.

Required pressures:

- unexplored space,
- visibility/information,
- routes and chokepoints,
- resource expenditure,
- recovery opportunity,
- environmental hazards,
- loot temptation,
- retreat/advance decision,
- enemy positioning or patrol/contact,
- occasional NPC/social consequences.

Exploration should create combat context.

Examples:

- entering from a favorable direction,
- discovering water before meeting a fire-based enemy,
- spending a consumable to cross a hazard,
- choosing a dangerous shortcut,
- retreating into terrain previously altered by the player.

This is where DCSS-like dungeon crawling and the simulation engine should meet.

---

## 8. Information hierarchy for mobile

Default target remains **portrait top-view**. Landscape can be supported later if the information density demands it, but should not be used to avoid solving the portrait UI.

### Always visible

Only information needed for the next decision:

- dungeon field,
- player position,
- visible threats,
- immediately relevant terrain/hazards,
- HP / critical resource,
- critical status,
- current actionable controls,
- approximately three lines of recent meaningful events.

### Contextual / temporary

Shown only when relevant:

- target selection,
- ability range,
- projected affected tiles,
- interaction prompt,
- pickup prompt,
- immediate status change,
- enemy intent.

### Detail screens

Raw or detailed simulation belongs here:

- exact body values,
- body-part condition,
- elemental values,
- resistance calculations,
- personality facets,
- relationship details,
- skill/mastery details,
- equipment statistics,
- complete event history.

Principle:

> **Show consequences by default; show calculations on demand.**

---

## 9. Three-line event surface

A single log line is insufficient because one action can trigger several simulation consequences.

Use a compact ~3-line surface over or adjacent to the field.

The three lines should not simply be the last three raw events. They should be a **presentation summary**.

Example:

```
칼날이 고블린의 왼팔을 깊게 베었다.
출혈 · 팔 기능 저하
고블린이 뒤로 물러나며 방어 자세를 취한다.
```

Another:

```
번개가 젖은 바닥을 타고 퍼졌다.
오크와 얕은 물이 감전됨
오크의 행동이 끊겼다.
```

Priority:

1. player action/result,
2. important simulation consequence,
3. reaction/new tactical state.

Full event history remains accessible from the record screen.

---

## 10. Intent presentation

Intent is valuable only if it changes player decisions.

Do not expose AI internals as verbose text.

Good:

- 공격 준비
- 후퇴
- 엄호
- 접근
- 도주
- 시전 준비

Better when spatially represented:

- target marker,
- directional cue,
- threatened cells,
- expected destination,
- small icon above actor.

Detailed reason can be inspected:

```
후퇴
- 심한 출혈
- 공포 증가
- 아군과 분리됨
```

The player should normally understand **what is likely to happen**, while inspection explains **why**.

---

## 11. Top-view portrait layout

Target hierarchy:

```
┌──────────────────────┐
│ compact status rail  │
├──────────────────────┤
│                      │
│                      │
│     DUNGEON FIELD    │
│                      │
│   intent/status FX   │
│                      │
├──────────────────────┤
│ meaningful events    │
│ up to ~3 lines       │
├──────────────────────┤
│ party / hero strip   │
├──────────────────────┤
│ contextual actions   │
└──────────────────────┘
```

The field must remain the dominant visual area.

Avoid permanent UI panels for information that is not required every turn.

---

## 12. Action UI

The bottom action region should be contextual rather than a permanent wall of buttons.

Normal exploration:

- contextual interact/pickup,
- ability access,
- wait/rest where appropriate,
- auto-explore,
- inventory/detail access.

Combat:

- frequently usable actions,
- currently equipped/available abilities,
- targeting feedback,
- tactical command where relevant.

A tap should generally mean one obvious thing.

Long press or detail panels can expose advanced information.

---

## 13. Visual feedback from simulation

Simulation consequences need field feedback before more numerical UI is added.

Examples:

- blood mark / bleeding cue,
- fire,
- water/wet surface,
- frost/frozen tile,
- poison/toxic cloud,
- stunned/staggered actor cue,
- damaged limb/body warning,
- fear/panic indicator,
- elemental propagation.

A simulation state that affects decisions but cannot be noticed on the field is effectively hidden complexity.

---

## 14. Development priority

### P0 — Gameplay readability

1. Keep top-view as the primary presentation.
2. Make dungeon field visually dominant.
3. Keep meaningful event surface at ~3 lines.
4. Reduce persistent HUD clutter.
5. Make enemy/NPC intent readable spatially.
6. Make critical simulation consequences visible on the field.

### P1 — System integration

1. Define shared interaction states.
2. Map existing body simulation into those states.
3. Map existing elemental simulation into those states.
4. Map existing powers/abilities into producers/consumers of states.
5. Connect weapons/items to the same grammar.
6. Add preview/presentation for important interactions.

### P2 — Roguelike combination prototype

1. Small item pool.
2. Small ability/power pool.
3. Several weapon identities.
4. Enemy archetypes that demand different solutions.
5. Terrain/material interactions.
6. Run rewards that redirect builds.
7. Test whether repeated runs produce genuinely different tactical solutions.

### P3 — Dungeon crawling

1. Encounter distribution.
2. Exploration pressure.
3. Resource attrition.
4. Risk/reward branches.
5. Environmental opportunities.
6. Enemy placement/patrol/awareness.
7. Retreat and recovery decisions.
8. Floor progression.

### Later

- large content expansion,
- visual polish,
- broad refactoring,
- architecture cleanup that is not blocking gameplay,
- micro-optimization,
- final balance.

---

## 15. What not to do yet

Do **not** prioritize:

- rewriting large working systems,
- adding dozens of isolated abilities,
- large item catalogs,
- elaborate stat screens,
- visual polish without gameplay purpose,
- exposing every simulation value,
- adding more simulation subsystems simply because they are interesting technically.

The project already has enough underlying complexity to begin proving the game.

---

## 16. Validation questions

Every new gameplay feature should answer at least one of these:

1. Does this create a new decision?
2. Does this interact with another system?
3. Can the player understand the consequence?
4. Can the player deliberately exploit it?
5. Can it produce a different solution in another run?
6. Does it improve dungeon exploration or combat?
7. Is the important information readable on a phone?

If the answer to all of them is no, the feature is probably simulation complexity rather than gameplay.

---

## 17. Immediate implementation sequence

The recommended next implementation sequence is:

```
Current simulation
      ↓
Shared state grammar
      ↓
Field visualization
      ↓
Intent + consequence presentation
      ↓
3-line meaningful event summarizer
      ↓
Small interaction-heavy item/ability set
      ↓
Multi-solution encounter prototype
      ↓
Run reward/build variation
      ↓
Dungeon crawling pressure
      ↓
Content expansion
```

The key milestone is not “more systems implemented.”

It is:

> **A player can look at a dungeon situation on a phone, understand the important state, choose a simple action, and discover a useful interaction between several underlying simulations.**
