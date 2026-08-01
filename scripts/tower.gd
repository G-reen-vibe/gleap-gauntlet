class_name Tower
extends Node2D

## A rival tower. It is both the spawner and the evolutionary engine: it holds a
## population of crafted genomes, fields them one at a time as living gleaps, takes
## their scores back when they die, and breeds the next generation once every
## recipe in the population has been tried.

@export var team: int = Balance.TEAM_LEFT
@export var gleap_scene: PackedScene
@export var spawn_offset := Vector2(46.0, -26.0)
@export var rng_seed: int = 20260801

var population: Array[Genome] = []
var generation := 1
var energy := Balance.ENERGY_MAX
var spawn_timer := 0.0
var pending := 0                     # creatures still out on the course
var deployed := 0                    # lifetime spawn count
var arrivals := 0                    # creatures that touched the cake

var best_ever: Genome = null
var best_ever_fitness := -INF
var closest_ever := INF          # nearest any of this tower's creatures has come to the cake
var last_gen_best := -INF
var stale_generations := 0
var mutation_scale := 1.0

var _rng := RandomNumberGenerator.new()
var _queue: Array[int] = []
var _live: Array = []
var _arena: Node = null
var _next_id := 1


func _ready() -> void:
	_rng.seed = rng_seed + team * 7919
	_arena = get_tree().get_first_node_in_group("arena")
	for i in range(Balance.POP_SIZE):
		var g := Genome.random_new(_rng)
		g.id = _next_id
		_next_id += 1
		population.append(g)
	_fill_queue()
	z_index = 4
	set_process(true)


func _process(delta: float) -> void:
	queue_redraw()
	if _arena == null:
		_arena = get_tree().get_first_node_in_group("arena")
	if _arena and _arena.has_method("is_running") and not _arena.is_running():
		return

	_prune()
	energy = minf(energy + Balance.ENERGY_REGEN * delta, Balance.ENERGY_MAX)
	spawn_timer -= delta

	if spawn_timer > 0.0 or _live.size() >= Balance.MAX_ALIVE:
		return

	if _queue.is_empty():
		# Hold the line until every creature from this generation has reported,
		# otherwise their scores would land on genomes that no longer exist.
		if pending > 0:
			return
		_evolve()
		_fill_queue()

	var genome: Genome = population[_queue[0]]
	var cost := genome.cost()
	if energy < cost:
		return

	_queue.pop_front()
	energy -= cost
	spawn_timer = Balance.SPAWN_INTERVAL
	_spawn(genome)


# ==================================================================== spawning
func _spawn(genome: Genome) -> void:
	if gleap_scene == null:
		push_error("Tower %s has no gleap_scene assigned." % name)
		return
	var g: Gleap = gleap_scene.instantiate()
	g.configure(genome, team, self)
	var jitter := Balance.SPAWN_JITTER
	g.global_position = global_position \
		+ Vector2(spawn_offset.x * Balance.team_dir(team), spawn_offset.y) \
		+ Vector2(_rng.randf_range(-jitter, jitter), _rng.randf_range(-jitter, jitter))
	# A gentle toss out of the maw so the first hop is the brain's decision, not
	# gravity's, with a little wobble so a lineage cannot memorise one exact arc.
	g.velocity = Vector2(120.0 * Balance.team_dir(team) + _rng.randf_range(-jitter, jitter),
		-180.0 + _rng.randf_range(-jitter, jitter))
	get_parent().add_child(g)
	_live.append(g)
	pending += 1
	deployed += 1


func _prune() -> void:
	for i in range(_live.size() - 1, -1, -1):
		if not is_instance_valid(_live[i]):
			_live.remove_at(i)


## Called by a gleap when its run ends, however it ended.
func report_run(g: Gleap) -> void:
	pending = maxi(pending - 1, 0)
	if g.genome == null:
		return
	var score := g.fitness()
	g.genome.record(score)
	closest_ever = minf(closest_ever, g.best_dist)
	if g.reached:
		arrivals += 1
	if score > best_ever_fitness:
		best_ever_fitness = score
		best_ever = g.genome.clone()


func live_count() -> int:
	_prune()
	return _live.size()


func clear_creatures() -> void:
	for g in _live:
		if is_instance_valid(g):
			g.queue_free()
	_live.clear()
	pending = 0
	_queue.clear()
	_fill_queue()
	spawn_timer = 0.0
	energy = Balance.ENERGY_MAX


# ==================================================================== evolution
func _fill_queue() -> void:
	_queue.clear()
	for i in range(population.size()):
		# Elites carried over with their scores intact do not need re-running.
		for _r in range(Balance.EVALS_PER_GENOME - population[i].scores.size()):
			_queue.append(i)
	# Shuffle deterministically off this tower's own stream.
	for i in range(_queue.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := _queue[i]
		_queue[i] = _queue[j]
		_queue[j] = tmp


func _evolve() -> void:
	population.sort_custom(func(a: Genome, b: Genome) -> bool: return a.fitness() > b.fitness())

	var top := population[0].fitness()
	if top <= last_gen_best + 1.0:
		stale_generations += 1
	else:
		stale_generations = 0
	last_gen_best = top
	# Crank the mutation rate when the lineage stops improving, ease it back when
	# it starts climbing again.
	mutation_scale = clampf(1.0 + stale_generations * 0.35, 1.0, 2.6)

	var next: Array[Genome] = []
	for i in range(mini(Balance.ELITES, population.size())):
		var elite := population[i].clone()
		elite.id = population[i].id
		elite.lineage = population[i].lineage
		next.append(elite)

	while next.size() < Balance.POP_SIZE:
		var a := _tournament()
		var b := _tournament()
		var child := Genome.crossover(a, b, _rng)
		child.mutate(_rng, mutation_scale)
		child.id = _next_id
		_next_id += 1
		next.append(child)

	population = next
	generation += 1


func _tournament() -> Genome:
	var best: Genome = population[_rng.randi_range(0, population.size() - 1)]
	for _i in range(Balance.TOURNAMENT - 1):
		var c: Genome = population[_rng.randi_range(0, population.size() - 1)]
		if c.fitness() > best.fitness():
			best = c
	return best


func champion() -> Genome:
	var best: Genome = population[0]
	for g in population:
		if g.fitness() > best.fitness():
			best = g
	if best_ever and best_ever_fitness > best.fitness():
		return best_ever
	return best


# ------------------------------------------------------------- persistence (K/L)
func save_champion() -> String:
	var path := "user://champion_%s.json" % Balance.team_name(team).to_lower()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "save failed"
	f.store_string(JSON.stringify(champion().to_dict(), "\t"))
	f.close()
	return path


func load_champion() -> bool:
	var path := "user://champion_%s.json" % Balance.team_name(team).to_lower()
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var seed_genome := Genome.from_dict(parsed)
	# Reseed the whole population around the saved champion.
	population[0] = seed_genome
	for i in range(1, population.size()):
		var c := seed_genome.clone()
		c.mutate(_rng, 1.0)
		population[i] = c
	_fill_queue()
	return true


func stats() -> Dictionary:
	var evaluated := 0
	var best := -INF
	for g in population:
		if g.evaluated():
			evaluated += 1
		best = maxf(best, g.fitness())
	return {
		"team": team,
		"generation": generation,
		"best": best,
		"best_ever": best_ever_fitness,
		"closest": closest_ever,
		"energy": energy,
		"alive": live_count(),
		"deployed": deployed,
		"arrivals": arrivals,
		"evaluated": evaluated,
		"queued": _queue.size(),
		"pending": pending,
		"mutation": mutation_scale,
		"champion": champion(),
	}


# ====================================================================== drawing
func _draw() -> void:
	var dir := Balance.team_dir(team)
	var col := Balance.team_colour(team)
	var stone := Color(0.16, 0.18, 0.26)
	var stone_lit := Color(0.23, 0.26, 0.36)

	# --- body ---------------------------------------------------------------
	var w := 46.0
	var h := 164.0
	var shell := PackedVector2Array([
		Vector2(-w, 0), Vector2(w, 0),
		Vector2(w * 0.72, -h), Vector2(-w * 0.72, -h)])
	draw_colored_polygon(shell, stone)
	draw_polyline(PackedVector2Array([Vector2(-w, 0), Vector2(-w * 0.72, -h),
		Vector2(w * 0.72, -h), Vector2(w, 0)]), stone_lit, 2.0)

	# battlements
	for i in range(5):
		var bx := lerpf(-w * 0.72, w * 0.72, float(i) / 4.0)
		draw_rect(Rect2(bx - 6.0, -h - 14.0, 12.0, 16.0), stone_lit)

	# --- spawn maw ----------------------------------------------------------
	var maw := Vector2(dir * 24.0, -34.0)
	draw_circle(maw, 19.0, Color(0.06, 0.07, 0.11))
	var pulse := 0.55 + 0.45 * sin(float(Time.get_ticks_msec()) * 0.004)
	draw_arc(maw, 15.0, 0.0, TAU, 24, Color(col.r, col.g, col.b, 0.35 + 0.5 * pulse), 3.0, true)
	draw_circle(maw, 6.0 + 2.0 * pulse, Color(col.r, col.g, col.b, 0.75))

	# --- banner -------------------------------------------------------------
	var bx0 := -w * 0.5
	draw_rect(Rect2(bx0, -h + 18.0, w, 54.0), col.darkened(0.25))
	draw_rect(Rect2(bx0, -h + 18.0, w, 54.0), col, false, 2.0)

	# --- energy bar ---------------------------------------------------------
	var bar := Rect2(-w, -h - 40.0, w * 2.0, 10.0)
	draw_rect(bar, Color(0.08, 0.09, 0.14))
	var fill := bar
	fill.size.x = bar.size.x * clampf(energy / Balance.ENERGY_MAX, 0.0, 1.0)
	draw_rect(fill, col)
	draw_rect(bar, Color(0, 0, 0, 0.5), false, 1.0)

	# --- generation pips ----------------------------------------------------
	for i in range(mini(generation, 24)):
		var px := -w + 4.0 + float(i % 12) * 7.5
		var py := -h - 52.0 - float(i / 12) * 7.0
		draw_circle(Vector2(px, py), 2.4, Color(col.r, col.g, col.b, 0.8))
