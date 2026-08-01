extends Camera2D

## Three viewing modes: chase whoever is winning, look at the whole gauntlet, or
## fly around by hand. C cycles, arrows/WASD pan in free mode, Q/E zoom.

enum Mode { LEADER, OVERVIEW, FREE }

const MODE_NAMES := ["CHASE LEADER", "OVERVIEW", "FREE CAM"]

var mode: int = Mode.OVERVIEW
var _target := Vector2(Balance.CENTRE_X, 380.0)
var _target_zoom := 0.4
var _free_pos := Vector2(Balance.CENTRE_X, 380.0)
var _leader: Node2D = null
var _leader_hold := 0.0


func _ready() -> void:
	limit_left = int(Balance.ARENA_LEFT) - 400
	limit_right = int(Balance.ARENA_RIGHT) + 400
	limit_top = int(Balance.ARENA_TOP) - 400
	limit_bottom = int(Balance.ARENA_BOTTOM) + 400
	position = _target
	zoom = Vector2(_target_zoom, _target_zoom)
	make_current()


func mode_name() -> String:
	return MODE_NAMES[mode]


func cycle_mode() -> void:
	mode = (mode + 1) % Mode.size()
	if mode == Mode.FREE:
		_free_pos = position


func _process(delta: float) -> void:
	match mode:
		Mode.OVERVIEW:
			_target = Vector2(Balance.CENTRE_X, 340.0)
			_target_zoom = _fit_zoom(Balance.ARENA_RIGHT - Balance.ARENA_LEFT + 200.0)
		Mode.LEADER:
			_update_leader(delta)
			if is_instance_valid(_leader):
				_target = _leader.global_position - Vector2(0, 60)
				_target_zoom = 0.95
			else:
				_target = Vector2(Balance.CENTRE_X, 340.0)
				_target_zoom = _fit_zoom(Balance.ARENA_RIGHT - Balance.ARENA_LEFT + 200.0)
		Mode.FREE:
			var pan := Vector2(
				_axis(KEY_D, KEY_RIGHT) - _axis(KEY_A, KEY_LEFT),
				_axis(KEY_S, KEY_DOWN) - _axis(KEY_W, KEY_UP))
			_free_pos += pan * 900.0 * delta / maxf(_target_zoom, 0.05)
			if Input.is_key_pressed(KEY_Q):
				_target_zoom = maxf(_target_zoom * (1.0 - delta * 1.2), 0.18)
			if Input.is_key_pressed(KEY_E):
				_target_zoom = minf(_target_zoom * (1.0 + delta * 1.2), 2.5)
			_target = _free_pos

	var k: float = clampf(delta * 6.0, 0.0, 1.0)
	position = position.lerp(_target, k)
	var z: float = lerpf(zoom.x, _target_zoom, k)
	zoom = Vector2(z, z)


func _axis(a: int, b: int) -> float:
	return 1.0 if (Input.is_key_pressed(a) or Input.is_key_pressed(b)) else 0.0


func _fit_zoom(world_width: float) -> float:
	return clampf(get_viewport_rect().size.x / world_width, 0.1, 3.0)


## Stick with the current leader for a moment so the camera does not twitch
## between two gleaps that are nose to nose.
func _update_leader(delta: float) -> void:
	_leader_hold -= delta
	if is_instance_valid(_leader) and _leader.get("alive") == true and _leader_hold > 0.0:
		return
	var best: Node2D = null
	var best_d := INF
	for g in get_tree().get_nodes_in_group("gleaps"):
		if not is_instance_valid(g) or g.get("alive") != true:
			continue
		var d: float = g.global_position.distance_to(Balance.CAKE_POS)
		if d < best_d:
			best_d = d
			best = g
	if best:
		_leader = best
		_leader_hold = 1.1
