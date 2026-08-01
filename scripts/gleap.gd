class_name Gleap
extends CharacterBody2D

## A Starbound-style gleap: a squishy ball-monster that cannot walk at all. Every
## metre it travels comes from crouching, winding up a spring and firing itself in
## an arc — plus a wall grip and a landing bounce. All of that machinery is
## implemented here in full, but *none* of it self-triggers: the crouch, the aim,
## the release, the mid-air lean and the wall grab are driven only by the five
## output channels of this creature's neural network. Remove the brain and the
## gleap sits on the ground forever.

enum State { GROUND, AIR, CLING, DEAD }

const RAY_COUNT := 12
const RAY_LEN := 280.0
const TRAIL_MAX := 14

# --- identity, assigned by the tower before the node enters the tree ------------
var team := Balance.TEAM_LEFT
var genome: Genome
var tower: Node = null

# --- brain ---------------------------------------------------------------------
var brain: NeuralNet
var _inputs := PackedFloat32Array()
var _out := PackedFloat32Array()

# --- body ----------------------------------------------------------------------
var radius := Balance.BASE_RADIUS
var state := State.GROUND
var charging := false
var charge_t := 0.0
var charge_full := Balance.MAX_CHARGE
var cling_stamina := 1.0
var cling_normal := Vector2.ZERO
var _grab_cd := 0.0        # brief lockout after a wall leap, or it re-grabs instantly

# --- run bookkeeping -----------------------------------------------------------
var age := 0.0
var alive := true
var reached := false
var best_dist := INF
var start_dist := 1.0
var start_pos := Vector2.ZERO
var best_potential := 0.0
var stagnant := 0.0
var peak_y := 0.0
var fell := false
var _reported := false

# --- presentation --------------------------------------------------------------
var squash := 1.0          # >1 = stretched tall, <1 = flattened
var squash_vel := 0.0
var spin := 0.0
var spin_vel := 0.0
var blink_t := 0.0
var death_t := 0.0
var body_col := Color.WHITE
var _trail := PackedVector2Array()

var _tick := 0
var _was_on_floor := false
var _shape: CollisionShape2D


## Called by the tower immediately after instancing, before add_child().
func configure(g: Genome, t: int, owner_tower: Node) -> void:
	genome = g
	team = t
	tower = owner_tower


func _ready() -> void:
	if genome == null:
		# Standalone / editor run: give it a random body so the scene is playable alone.
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		genome = Genome.random_new(rng)

	brain = genome.build_brain()
	brain.reset_state()
	_inputs.resize(NeuralNet.IN)
	_out.resize(NeuralNet.OUT)

	radius = genome.radius()
	charge_full = genome.charge_seconds()
	cling_stamina = genome.cling_capacity()
	body_col = genome.colour(team)

	_shape = $CollisionShape2D
	var circle := _shape.shape as CircleShape2D
	circle.radius = radius

	start_pos = global_position
	start_dist = maxf(global_position.distance_to(Balance.CAKE_POS), 1.0)
	best_dist = start_dist
	peak_y = global_position.y
	blink_t = randf() * 4.0
	add_to_group("gleaps")


# ============================================================== simulation loop
func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		death_t += delta
		queue_redraw()
		if death_t > 0.4:
			queue_free()
		return

	age += delta
	_tick += 1
	if _tick % Balance.BRAIN_HZ_DIVISOR == 0:
		_think()

	_act(delta)

	var pre_velocity := velocity
	move_and_slide()
	_settle(delta, pre_velocity)


## Build the sensory vector and run one forward pass of the network.
func _think() -> void:
	var space := get_world_2d().direct_space_state
	var from := global_position
	for i in range(RAY_COUNT):
		var ang := TAU * float(i) / float(RAY_COUNT)
		var dir := Vector2.RIGHT.rotated(ang)
		var q := PhysicsRayQueryParameters2D.create(from, from + dir * RAY_LEN, 1)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		# 1.0 = surface right against the skin, 0.0 = open space.
		_inputs[i] = 0.0 if hit.is_empty() else 1.0 - (from.distance_to(hit.position) / RAY_LEN)

	var to_cake := Balance.CAKE_POS - global_position
	_inputs[12] = clampf(velocity.x / 600.0, -1.0, 1.0)
	_inputs[13] = clampf(velocity.y / 900.0, -1.0, 1.0)
	_inputs[14] = 1.0 if is_on_floor() else 0.0
	_inputs[15] = 1.0 if (is_on_wall() or state == State.CLING) else 0.0
	_inputs[16] = clampf(charge_t / charge_full, 0.0, 1.0) if charging else 0.0
	_inputs[17] = clampf(to_cake.x / 900.0, -1.0, 1.0)
	_inputs[18] = clampf(to_cake.y / 500.0, -1.0, 1.0)
	_inputs[19] = clampf(cling_stamina / genome.cling_capacity(), 0.0, 1.0)
	_inputs[20] = 1.0   # bias

	_out = brain.step(_inputs)


## Turn the five brain outputs into gleap locomotion.
func _act(delta: float) -> void:
	var aim := clampf(_out[NeuralNet.O_AIM], -1.0, 1.0)
	var hold := _out[NeuralNet.O_HOLD]
	var release := _out[NeuralNet.O_RELEASE]
	var lean := clampf(_out[NeuralNet.O_LEAN], -1.0, 1.0)
	var grip := _out[NeuralNet.O_CLING]

	var on_floor := is_on_floor()
	_grab_cd = maxf(_grab_cd - delta, 0.0)

	# ---- state resolution -----------------------------------------------------
	if state == State.CLING:
		if not is_on_wall() or cling_stamina <= 0.0 or grip < 0.35:
			_release_wall()
	if state != State.CLING:
		state = State.GROUND if on_floor else State.AIR
		if state == State.AIR and is_on_wall() and grip > 0.5 and cling_stamina > 0.05 \
				and _grab_cd <= 0.0:
			_grab_wall()

	# ---- stamina --------------------------------------------------------------
	if state == State.CLING:
		cling_stamina = maxf(cling_stamina - Balance.CLING_DRAIN * delta, 0.0)
	elif on_floor:
		cling_stamina = minf(cling_stamina + Balance.CLING_REGEN * delta, genome.cling_capacity())

	# ---- the spring: crouch, wind up, fire ------------------------------------
	var can_charge := state == State.GROUND or state == State.CLING
	if can_charge:
		if not charging and hold > 0.55:
			charging = true
			charge_t = 0.0
		if charging:
			charge_t += delta
			var maxed := charge_t >= charge_full
			if release > 0.5 or maxed:
				_launch(aim, clampf(charge_t / charge_full, 0.0, 1.0))
			elif hold < 0.35 and charge_t > 0.05:
				# Let go of the crouch without firing — the spring just unwinds.
				charging = false
	else:
		charging = false

	# ---- per-state motion -----------------------------------------------------
	var g := Balance.GRAVITY * genome.gravity_scale()
	match state:
		State.GROUND:
			var brake := Balance.GROUND_FRICTION * (1.9 if charging else 1.0)
			velocity.x = move_toward(velocity.x, 0.0, brake * delta)
			velocity.y += g * delta * 0.25   # keeps the body pinned to slopes
			spin_vel = velocity.x / maxf(radius, 1.0)
		State.CLING:
			velocity.x = -cling_normal.x * 70.0   # press into the wall to stay latched
			velocity.y = Balance.CLING_SLIDE * (1.0 - genome.gene(Genome.G_GRIP) * 0.7)
			spin_vel = move_toward(spin_vel, 0.0, 12.0 * delta)
		State.AIR:
			# Steering, not thrust: a gleap can nudge its arc but never add speed
			# beyond the cap it left the ground with.
			var authority := Balance.AIR_ACCEL * genome.gene(Genome.G_AIR_CONTROL)
			var nvx := velocity.x + lean * authority * delta
			if absf(nvx) > Balance.AIR_SPEED_CAP and absf(nvx) > absf(velocity.x):
				nvx = velocity.x
			velocity.x = nvx
			velocity.y += g * delta
		_:
			pass


func _launch(aim: float, ratio: float) -> void:
	charging = false
	charge_t = 0.0
	# Ease the power curve so a half-charge is meaningfully weaker than a full one.
	var power := lerpf(Balance.MIN_POWER, 1.0, ratio * ratio * (3.0 - 2.0 * ratio))
	var vy := genome.jump_velocity() * power
	var vx := aim * genome.hop_speed() * power

	if state == State.CLING:
		# Wall leap. Aiming away from the wall kicks off it hard; aiming back into
		# it converts almost all the spring into height, which is how a gleap
		# ladders its way up a face too tall to clear in one go.
		var away := signf(cling_normal.x)
		var out_frac := 0.16 + 0.84 * clampf(aim * away, 0.0, 1.0)
		vx = away * genome.hop_speed() * power * out_frac
		vy *= 1.0 - 0.22 * out_frac
		_grab_cd = 0.22
		_release_wall()

	velocity = Vector2(vx, -vy)
	state = State.AIR
	_was_on_floor = false
	squash = 1.0
	squash_vel = 5.0 + power * 7.0          # stretch out of the launch
	spin_vel = vx / maxf(radius, 1.0) * 0.55


func _grab_wall() -> void:
	state = State.CLING
	cling_normal = get_wall_normal()
	if cling_normal == Vector2.ZERO:
		cling_normal = Vector2.RIGHT * signf(-velocity.x if velocity.x != 0.0 else 1.0)
	velocity = Vector2.ZERO
	charging = false
	squash_vel = -3.0


func _release_wall() -> void:
	if state == State.CLING:
		state = State.AIR
	cling_normal = Vector2.ZERO


## After move_and_slide: landings, death checks, fitness and animation.
func _settle(delta: float, pre_velocity: Vector2) -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		_land(pre_velocity)
	_was_on_floor = on_floor

	# ---- fitness ---------------------------------------------------------------
	peak_y = minf(peak_y, global_position.y)
	best_dist = minf(best_dist, global_position.distance_to(Balance.CAKE_POS))
	var p := _potential()
	if p > best_potential + 1.0:
		best_potential = p
		stagnant = 0.0
	else:
		stagnant += delta

	# ---- lethal geometry -------------------------------------------------------
	if global_position.y > Balance.DEATH_Y:
		fell = true
		_perish()
		return
	if age >= Balance.LIFETIME or stagnant >= Balance.STAGNANT_LIMIT:
		_perish()
		return

	# ---- animation -------------------------------------------------------------
	var target_squash := 1.0
	if charging:
		var ratio := clampf(charge_t / charge_full, 0.0, 1.0)
		target_squash = lerpf(1.0, 0.55, ratio)          # deep crouch
	elif state == State.AIR:
		target_squash = clampf(1.0 + velocity.y * -0.00045, 0.72, 1.38)
	elif state == State.CLING:
		target_squash = 1.18
	squash_vel += (target_squash - squash) * 90.0 * delta
	squash_vel *= 0.80
	squash = clampf(squash + squash_vel * delta, 0.35, 1.8)

	spin += spin_vel * delta
	blink_t -= delta

	if _tick % 3 == 0:
		_trail.append(global_position)
		while _trail.size() > TRAIL_MAX:
			_trail.remove_at(0)

	queue_redraw()


func _land(pre_velocity: Vector2) -> void:
	var impact := pre_velocity.y
	squash_vel = -minf(impact * 0.012, 9.0)               # splat
	velocity.x = pre_velocity.x * Balance.LAND_KEEP
	var bounce := genome.gene(Genome.G_BOUNCE)
	if impact > 420.0 and bounce > 0.02:
		# A live gleap keeps a little of its fall as a hop, ball-style.
		velocity.y = -impact * bounce
		state = State.AIR
		_was_on_floor = false
	else:
		velocity.y = 0.0
		state = State.GROUND
	spin_vel = velocity.x / maxf(radius, 1.0) * 0.8


# ================================================================= life & death
func on_reached_cake() -> void:
	if reached or state == State.DEAD:
		return
	reached = true
	velocity = Vector2(0, -260)
	squash_vel = 9.0
	_finish()


func _perish() -> void:
	_finish()


## Killed from outside — the arena's out-of-bounds volume, or a match reset.
func kill(as_fall: bool = true) -> void:
	if state == State.DEAD:
		return
	fell = as_fall
	_finish()


func _finish() -> void:
	if _reported:
		return
	_reported = true
	alive = false
	state = State.DEAD
	death_t = 0.0
	velocity = Vector2.ZERO
	set_collision_layer_value(2, false)
	if _shape:
		_shape.set_deferred("disabled", true)
	if tower and tower.has_method("report_run"):
		tower.report_run(self)


## How far along the gauntlet this creature got. Blending "ground covered toward
## the centre" with "distance closed on the cake" matters: pure distance-to-cake
## has a dead zone where dropping off the gate wall into the trench *increases*
## it, and a lineage that only ever sees that would learn to sit on the wall.
func _potential() -> float:
	var travelled := (global_position.x - start_pos.x) * Balance.team_dir(team)
	var closed := start_dist - global_position.distance_to(Balance.CAKE_POS)
	return travelled * 0.5 + closed * 0.6


## Fitness for this run: progress along the course, a climb bonus, the jackpot
## for arriving, minus penalties for dawdling and for falling down a hole.
func fitness() -> float:
	var progress := best_potential
	var climb := maxf(0.0, (Balance.CAKE_POS.y + 600.0) - peak_y) * 0.05
	var score := progress + climb - age * Balance.TIME_PENALTY
	if reached:
		score += Balance.REACH_BONUS
	if fell:
		score -= Balance.PIT_PENALTY
	return score


# ======================================================================= drawing
func _draw() -> void:
	var fade := 1.0
	var scale_out := 1.0
	if state == State.DEAD:
		fade = clampf(1.0 - death_t / 0.4, 0.0, 1.0)
		scale_out = 1.0 + (1.0 - fade) * (1.6 if reached else -0.75)

	# --- motion trail -----------------------------------------------------------
	if _trail.size() > 2 and fade > 0.05:
		for i in range(1, _trail.size()):
			var a := to_local(_trail[i - 1])
			var b := to_local(_trail[i])
			var t := float(i) / float(_trail.size())
			draw_line(a, b, Color(body_col.r, body_col.g, body_col.b, 0.20 * t * fade), 1.0 + 2.0 * t)

	if fade <= 0.01:
		return

	var r := radius * scale_out
	var sy := squash
	var sx := 1.0 / squash
	var col := Color(body_col.r, body_col.g, body_col.b, fade)
	var dark := col.darkened(0.55)
	dark.a = fade

	# --- body -------------------------------------------------------------------
	draw_set_transform(Vector2(0, r * (1.0 - sy)), spin, Vector2(sx, sy))
	draw_circle(Vector2.ZERO, r, col)
	draw_arc(Vector2.ZERO, r * 0.99, 0.0, TAU, 26, dark, 2.0, true)
	draw_circle(Vector2(-r * 0.28, -r * 0.34), r * 0.30, Color(1, 1, 1, 0.28 * fade))
	# belly banding, so the spin reads while rolling
	draw_arc(Vector2.ZERO, r * 0.62, 0.35, 2.6, 14, Color(0, 0, 0, 0.16 * fade), 3.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# --- face (kept upright; only the eyes track) --------------------------------
	var centre := Vector2(0, r * (1.0 - sy) - r * 0.15 * sy)
	var eye_gap := r * 0.42
	var look := (Balance.CAKE_POS - global_position).normalized()
	var open := 1.0
	if blink_t < 0.0:
		open = 0.12
		if blink_t < -0.12:
			blink_t = randf_range(2.0, 6.0)
	if charging:
		open = lerpf(1.0, 0.45, clampf(charge_t / charge_full, 0.0, 1.0))

	for s in [-1.0, 1.0]:
		var e := centre + Vector2(eye_gap * s, 0)
		draw_circle(e, r * 0.26 * open + r * 0.05, Color(0.06, 0.07, 0.12, fade))
		if open > 0.4:
			draw_circle(e + look * r * 0.10, r * 0.10, Color(1, 1, 1, 0.92 * fade))

	# --- charge meter ------------------------------------------------------------
	if charging:
		var ratio := clampf(charge_t / charge_full, 0.0, 1.0)
		var ring := Color(1.0, 0.85, 0.35, (0.35 + 0.5 * ratio) * fade)
		draw_arc(centre, r + 7.0, -PI * 0.5, -PI * 0.5 + TAU * ratio, 22, ring, 3.0, true)

	# --- wall grip tell ----------------------------------------------------------
	if state == State.CLING:
		var anchor := centre - cling_normal * r
		draw_line(anchor, anchor - cling_normal * 6.0, Color(1, 1, 1, 0.55 * fade), 3.0)

	# --- team pip ----------------------------------------------------------------
	var pip := Balance.team_colour(team)
	pip.a = fade
	draw_circle(centre + Vector2(0, -r - 9.0), 2.6, pip)
