class_name Balance
extends RefCounted

## Central tuning table. Everything the simulation needs to agree on lives here so
## the level, the towers, the creatures and the brains cannot drift apart.

# ---------------------------------------------------------------- arena layout
const ARENA_LEFT := 0.0
const ARENA_RIGHT := 3600.0
const ARENA_TOP := -520.0
const ARENA_BOTTOM := 1080.0
const CENTRE_X := 1800.0

## Where the cake sits. Must match the Cake node position in main.tscn.
const CAKE_POS := Vector2(1800.0, 190.0)

## Anything that falls past this dies.
const DEATH_Y := 950.0

const TOWER_LEFT_POS := Vector2(170.0, 700.0)
const TOWER_RIGHT_POS := Vector2(3430.0, 700.0)

# ------------------------------------------------------------------- creatures
const GRAVITY := 1400.0
const BASE_RADIUS := 13.0

## Peak launch speeds at full charge for a baseline (gene value 1.0) gleap.
## v=1010 gives an apex of ~364px, which just clears the 300px gate wall.
const JUMP_V := 1010.0
const HOP_H := 500.0

const MAX_CHARGE := 0.75          # seconds of crouch for a full-power leap
const MIN_POWER := 0.34           # power multiplier at zero charge
const GROUND_FRICTION := 1250.0   # px/s^2 bleed when idle on the floor
const AIR_ACCEL := 320.0          # px/s^2 of steering authority (x air_control gene)
const AIR_SPEED_CAP := 380.0
const LAND_KEEP := 0.72           # fraction of horizontal speed kept on landing
const CLING_SLIDE := 70.0         # px/s downward creep while gripping a wall
const CLING_DRAIN := 0.85         # stamina per second while gripping
const CLING_REGEN := 0.55         # stamina per second while grounded

const LIFETIME := 26.0            # hard cap on one creature's run
const STAGNANT_LIMIT := 9.0       # give up if no progress for this long
const BRAIN_HZ_DIVISOR := 2       # think every N physics ticks

# --------------------------------------------------------------------- economy
const POP_SIZE := 12
const ENERGY_MAX := 100.0
const ENERGY_REGEN := 32.0        # per second
const SPAWN_INTERVAL := 0.85      # minimum seconds between spawns
const SPAWN_JITTER := 6.0         # px/px-per-sec of wobble so runs are not carbon copies
const MAX_ALIVE := 14             # per tower

# -------------------------------------------------------------------- learning
const ELITES := 3
const TOURNAMENT := 3
const MUTATE_RATE := 0.14
const MUTATE_SIGMA := 0.38
const BODY_MUTATE_RATE := 0.25
const BODY_MUTATE_SIGMA := 0.13
## The gauntlet is deterministic, so a genome only needs re-running if you want to
## average over the spawn jitter. 1 doubles generation throughput; raise it for a
## less noisy, slower search.
const EVALS_PER_GENOME := 1

const REACH_BONUS := 2500.0
const PIT_PENALTY := 180.0
const TIME_PENALTY := 2.0         # fitness lost per second alive

# --------------------------------------------------------------------- palette
const TEAM_LEFT := 0
const TEAM_RIGHT := 1

static func team_colour(team: int) -> Color:
	return Color(0.35, 0.85, 1.0) if team == TEAM_LEFT else Color(1.0, 0.47, 0.42)

static func team_name(team: int) -> String:
	return "AZURE" if team == TEAM_LEFT else "EMBER"

## Sign of travel toward the cake for a given team.
static func team_dir(team: int) -> float:
	return 1.0 if team == TEAM_LEFT else -1.0
