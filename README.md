# Gleap Gauntlet

A Battle-Cats-shaped tower duel where nobody is driving. Two rival towers stand at
opposite ends of an obstacle course, endlessly crafting and fielding **gleaps** —
the ball-shaped hopping monsters from Starbound — and every one of them is piloted
by its own small recurrent neural network. The towers breed better brains and
better bodies as the match runs. First gleap to touch the cake on the central mesa
wins for its tower.

Godot **4.7**, GDScript only, no binary assets — every creature, tower, cake and
rock is drawn in code.

```
godot --path .          # run it
godot --editor --path . # open it
```

---

## What is actually simulated

### The gleap

A gleap cannot walk. It has no run speed, no step-up, no ground control at all.
Every metre it covers comes from the same four-part cycle Starbound's gleaps use:

1. **Crouch** — the body squashes and a spring winds up (up to `MAX_CHARGE`).
2. **Launch** — the spring fires it along a ballistic arc; the body stretches.
3. **Flight** — gravity owns it. A small steering authority (the `air_control`
   gene) lets it nudge the arc, but it can never add speed beyond what it left
   the ground with.
4. **Land** — it splats, keeps `LAND_KEEP` of its horizontal momentum, and if it
   hit hard and its `bounce` gene is high it keeps hopping ball-style.

Plus a wall grip: a gleap that touches a wall can latch on, slide slowly, burn
stamina, and fire a wall-leap away from it. That is the only reliable way early
generations get over the 300px gate wall.

**None of that self-triggers.** `scripts/gleap.gd` implements the whole state
machine, but the crouch, the aim, the release, the mid-air lean and the wall grab
are *only* set from the five output channels of the creature's network. Delete the
brain and a gleap sits in the spawn maw's shadow forever.

### The brain

`scripts/neural_net.gd` — a 21 → 16 → 5 Elman network (the hidden layer feeds back
into itself, which is what lets a gleap hold a crouch across frames and remember
which way it was going while airborne). It ticks every other physics frame.

**Inputs (21)**

| # | Sense |
|---|---|
| 0–11 | 12 raycast whiskers in a full circle, 280px, `1.0` = surface against the skin |
| 12–13 | own velocity, normalised |
| 14–15 | on floor / touching wall |
| 16 | current charge, 0–1 |
| 17–18 | offset to the cake, x and y |
| 19 | remaining wall-grip stamina |
| 20 | bias |

**Outputs (5)**

| # | Action |
|---|---|
| `O_AIM` | horizontal aim of the next leap, −1..1 |
| `O_HOLD` | begin / keep the crouch |
| `O_RELEASE` | fire now |
| `O_LEAN` | mid-air steering |
| `O_CLING` | grab the wall being touched |

### The crafting

`scripts/genome.gd`. A creature is a **body recipe** plus a **weight chromosome**,
and both evolve together. The seven body genes are:

`size`, `power`, `charge_rate`, `air_control`, `bounce`, `grip`, `hue`

They set the collision radius, launch speed, how fast the spring winds, steering
authority, landing bounciness, wall stamina, and the shade of the creature — and
they set the **spawn cost**, so a monstrous high-power gleap means the tower can
field fewer of them. That is the Battle Cats economy: energy trickles in, each
unit is bought, the queue keeps rolling.

### The learning

`scripts/tower.gd`. Each tower runs its own genetic algorithm over a population of
12 genomes:

- every genome is fielded `EVALS_PER_GENOME` times per generation, in shuffled order;
- a run scores `distance closed on the cake + climb bonus + 2500 for arriving
  − 2/second − 180 for falling down a hole`;
- once all of them have reported, the top 3 survive untouched and the rest are
  bred by 3-way tournament selection, uniform crossover on the weights and blend
  crossover on the body, then mutated;
- if the best score stops improving, mutation strength ramps up to 2.6× to shake
  the lineage off a plateau, and eases back once it starts climbing again.

The two towers evolve **independently and in parallel** — they are two separate
populations racing each other, with different RNG seeds.

Expect nothing for the first minute. Generation 1 is 24 random brains and most of
them fall in the first hole. Somewhere around generation 3–6 you start seeing
deliberate charged leaps, then wall grabs on the gate, then a lineage that runs
the staircase cleanly.

---

## The gauntlet

Symmetric about the centre, 3600px wide, drawn from `scenes/main.tscn`:

```
tower ─ ramp ─ [HOLE] ─ run-up ─ ██ 300px GATE WALL ██ ─ trench under a low ceiling
        ─ floating staircase over [HOLE 2] ─ plateau ─ [CHASM] ─ 🎂 mushroom mesa
```

- **Hole 1** and **Hole 2** drop straight past the death plane at `y=950`.
- The **gate wall** is 300px — right at the theoretical ceiling of a full-charge
  leap, so most lineages solve it with the wall grip first and only later evolve
  the body power to clear it outright.
- The **overhang** forces a flat trajectory out of the gate; you cannot just
  moon-shot the whole middle section.
- The staircase floats *over* hole 2, so a missed step is fatal.
- The mesa is mushroom-shaped: the final leap from the plateau has to clear an
  overhanging lip, not just gain height.

---

## Controls

| Key | |
|---|---|
| `R` | next match — populations and everything they have learned carry over |
| `Shift+R` | full restart, brains wiped |
| `C` | camera: chase the leader / overview / free |
| `WASD`/arrows, `Q`/`E` | pan and zoom in free camera |
| `F` | simulation speed ×1 → ×2 → ×4 |
| `P` or `Space` | pause |
| `K` / `L` | save / load each tower's champion to `user://champion_*.json` |
| `Esc` | quit |

The HUD shows both populations live: generation, best and all-time fitness, spawn
queue, energy, mutation pressure and the current champion's body recipe. The
minimap at the bottom is built from the level's own collision polygons, so it
tracks any edit to the course automatically.

---

## Files

```
project.godot            4.7, GL-compatibility renderer, physics layers
icon.svg
scenes/main.tscn         the whole arena: terrain, towers, cake, camera, HUD
scenes/gleap.tscn        one creature: CharacterBody2D + circle shape
scripts/balance.gd       every tuning number the sim agrees on
scripts/neural_net.gd    21-16-5 Elman network
scripts/genome.gd        body recipe + weight chromosome, crossover, mutation
scripts/gleap.gd         gleap physics, senses, drawing — driven only by the net
scripts/tower.gd         spawner, energy economy, genetic algorithm, tower art
scripts/arena.gd         match rules, hotkeys, score, headless telemetry
scripts/cake.gd          the goal trigger
scripts/camera_director.gd
scripts/hud.gd           readouts + minimap
scripts/backdrop.gd      scenery
tools/build_level.py     regenerates scenes/main.tscn (see below)
```

### Editing the course

`scenes/main.tscn` is a normal, hand-editable scene — open it in Godot and drag
things. If you would rather retune the layout numerically, edit the `LEFT` shape
list in `tools/build_level.py` and run:

```
python3 tools/build_level.py
```

It re-emits the whole scene, mirrored about the centre so the race stays fair.
Two things must stay in step if you move the goal: `Cake.position` in the scene
and `Balance.CAKE_POS`.

### Headless training

With no window, the arena prints the HUD numbers every 10 simulated seconds:

```
godot --headless --path . --quit-after 60000
[t= 240.0s] AZURE gen7 best 1512 closest 118 alive 6 fielded 251 cake 0 | EMBER ...
```

`closest` is the nearest any of that tower's creatures has ever come to the cake,
in pixels — the most honest single measure of whether a population is learning.
# gleap-gauntlet
