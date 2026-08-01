extends Node2D

## Match director. Owns the rules, the hotkeys and the running score; the towers
## own the learning and the creatures own the hopping.

signal match_ended(team: int)

const TIME_SCALES := [1.0, 2.0, 4.0]

var winner := -1
var match_time := 0.0
var match_index := 1
var wins := [0, 0]
var paused := false
var scale_index := 0
var toast := ""
var toast_t := 0.0

@onready var cake: Area2D = $Cake
@onready var tower_left: Tower = $TowerLeft
@onready var tower_right: Tower = $TowerRight
@onready var kill_zone: Area2D = $KillZone
@onready var cam: Camera2D = $Camera2D
@onready var hud: CanvasLayer = $HUD


var _log_timer := 0.0
var _headless := false
var _shot_at := -1.0
var _shot_path := "user://gauntlet.png"
var _shot_taken := false
## Seconds to linger on a win before starting the next match by itself. Off for a
## human at the keyboard (they press R); on when headless, or a training run would
## stall forever the first time somebody reaches the cake.
var _rematch_delay := -1.0
var _rematch_t := 0.0


func _ready() -> void:
	add_to_group("arena")
	cake.claimed.connect(_on_cake_claimed)
	kill_zone.body_entered.connect(_on_kill_zone_entered)
	Engine.time_scale = TIME_SCALES[scale_index]
	# With no window there is nothing to watch, so print the same numbers the HUD
	# would show. Handy for long unattended training runs:
	#   godot --headless --quit-after 20000
	_headless = DisplayServer.get_name() == "headless"
	if _headless:
		_rematch_delay = 6.0
	_parse_cmdline()
	_toast("Gleap Gauntlet — brains start at random. Give them a few generations.")


## Unattended capture, for docs and for eyeballing a build without sitting there:
##   godot --path . -- --shot=45 --shot-out=/tmp/gauntlet.png
func _parse_cmdline() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_at = float(a.substr(7))
		elif a.begins_with("--shot-out="):
			_shot_path = a.substr(11)
		elif a.begins_with("--cam="):
			var names: Array = ["leader", "overview", "free"]
			var want_cam := names.find(a.substr(6))
			if want_cam >= 0:
				cam.set("mode", want_cam)
		elif a.begins_with("--rematch="):
			_rematch_delay = float(a.substr(10))   # 0 or less disables
		elif a.begins_with("--speed="):
			var want := float(a.substr(8))
			for i in range(TIME_SCALES.size()):
				if is_equal_approx(TIME_SCALES[i], want):
					scale_index = i
			Engine.time_scale = TIME_SCALES[scale_index]


func _capture(quit_after: bool) -> void:
	if _shot_taken:
		return
	_shot_taken = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_shot_path)
	print("screenshot -> %s (%s)" % [_shot_path, "ok" if err == OK else str(err)])
	if quit_after:
		get_tree().quit()
	else:
		_shot_taken = false
		_toast("Screenshot saved to %s" % _shot_path)


func _process(delta: float) -> void:
	if winner < 0:
		match_time += delta
	toast_t = maxf(toast_t - delta / maxf(Engine.time_scale, 0.001), 0.0)
	if winner >= 0 and _rematch_delay > 0.0:
		_rematch_t += delta
		if _rematch_t >= _rematch_delay:
			_rematch_t = 0.0
			reset_match(false)
	if _shot_at > 0.0 and match_time >= _shot_at and not _shot_taken:
		_capture(true)
	if _headless:
		_log_timer += delta
		if _log_timer >= 10.0:
			_log_timer = 0.0
			_print_status()


func _print_status() -> void:
	var parts := PackedStringArray()
	for t in towers():
		var s: Dictionary = t.call("stats")
		parts.append("%s gen%d best %s closest %s alive %d fielded %d cake %d" % [
			Balance.team_name(s["team"]), s["generation"],
			"—" if s["best"] <= -1e29 else "%.0f" % s["best"],
			"—" if s["closest"] >= 1e29 else "%.0f" % s["closest"],
			s["alive"], s["deployed"], s["arrivals"]])
	print("[t=%6.1fs] %s   |   %s" % [match_time, parts[0], parts[1]])


func is_running() -> bool:
	return winner < 0 and not paused


# ======================================================================== rules
func _on_cake_claimed(team: int, _g: Node) -> void:
	if winner >= 0:
		return
	winner = team
	wins[team] += 1
	_toast("%s reaches the cake! Press R for the next match — the brains carry over." \
		% Balance.team_name(team))
	if _headless:
		print("*** %s CLAIMS THE CAKE at t=%.1fs — score %d-%d" % [
			Balance.team_name(team), match_time, wins[0], wins[1]])
		_print_status()
	match_ended.emit(team)


func _on_kill_zone_entered(body: Node2D) -> void:
	if body is Gleap:
		(body as Gleap).kill(true)


func reset_match(hard: bool = false) -> void:
	if hard:
		Engine.time_scale = 1.0
		get_tree().reload_current_scene()
		return
	for t in [tower_left, tower_right]:
		t.clear_creatures()
	for g in get_tree().get_nodes_in_group("gleaps"):
		if is_instance_valid(g):
			g.queue_free()
	cake.claimed_by = -1
	winner = -1
	match_time = 0.0
	_rematch_t = 0.0
	match_index += 1
	_toast("Match %d. Populations kept — generation %d vs %d." \
		% [match_index, tower_left.generation, tower_right.generation])


# ======================================================================== input
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).keycode
	match k:
		KEY_R:
			reset_match((event as InputEventKey).shift_pressed)
		KEY_C:
			cam.call("cycle_mode")
			_toast("Camera: %s" % cam.call("mode_name"))
		KEY_F:
			scale_index = (scale_index + 1) % TIME_SCALES.size()
			if not paused:
				Engine.time_scale = TIME_SCALES[scale_index]
			_toast("Simulation speed x%.0f" % TIME_SCALES[scale_index])
		KEY_P, KEY_SPACE:
			paused = not paused
			Engine.time_scale = 0.0 if paused else TIME_SCALES[scale_index]
			_toast("Paused" if paused else "Resumed")
		KEY_K:
			var a := tower_left.save_champion()
			var b := tower_right.save_champion()
			_toast("Champions saved to %s / %s" % [a.get_file(), b.get_file()])
		KEY_L:
			var ok := tower_left.load_champion()
			var ok2 := tower_right.load_champion()
			_toast("Champions loaded (%s / %s)" % ["ok" if ok else "none", "ok" if ok2 else "none"])
		KEY_F12:
			_capture(false)
		KEY_ESCAPE:
			get_tree().quit()


func _toast(msg: String) -> void:
	toast = msg
	toast_t = 6.0


func towers() -> Array:
	return [tower_left, tower_right]
