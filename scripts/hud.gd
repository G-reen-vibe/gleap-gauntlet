extends Control

## Readout for the two learning populations plus a minimap of the gauntlet.
## The minimap silhouette is lifted straight from the level's collision polygons,
## so editing the course in main.tscn updates it automatically.

const MAP_W := 760.0
const MAP_H := 78.0
const MAP_MARGIN := 22.0

var arena: Node = null
var _map_polys: Array[PackedVector2Array] = []
var _map_built := false

@onready var left_panel: Label = $LeftPanel
@onready var right_panel: Label = $RightPanel
@onready var banner: Label = $Banner
@onready var subbanner: Label = $SubBanner
@onready var toast: Label = $Toast
@onready var help: Label = $Help


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena = get_tree().get_first_node_in_group("arena")
	help.text = "R next match   SHIFT+R full restart   C camera   F speed   P pause   K save brains   L load   ESC quit"


func _process(_delta: float) -> void:
	if arena == null:
		arena = get_tree().get_first_node_in_group("arena")
		return
	if not _map_built:
		_build_map()

	var towers: Array = arena.call("towers")
	if towers.size() == 2:
		left_panel.text = _panel_text(towers[0])
		right_panel.text = _panel_text(towers[1])
		left_panel.add_theme_color_override("font_color", Balance.team_colour(0))
		right_panel.add_theme_color_override("font_color", Balance.team_colour(1))

	var winner: int = arena.get("winner")
	if winner >= 0:
		banner.text = "%s CLAIMS THE CAKE" % Balance.team_name(winner)
		banner.add_theme_color_override("font_color", Balance.team_colour(winner))
		subbanner.text = "match %d   score  %d – %d   press R to run it again with the same brains" % [
			arena.get("match_index"), arena.get("wins")[0], arena.get("wins")[1]]
	else:
		banner.text = "GLEAP GAUNTLET"
		banner.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
		subbanner.text = "match %d   %02d:%02d   score  %d – %d%s" % [
			arena.get("match_index"),
			int(arena.get("match_time")) / 60, int(arena.get("match_time")) % 60,
			arena.get("wins")[0], arena.get("wins")[1],
			"   [PAUSED]" if arena.get("paused") else ("   x%.0f" % Engine.time_scale)]

	var t: float = arena.get("toast_t")
	toast.text = arena.get("toast") if t > 0.0 else ""
	toast.modulate.a = clampf(t, 0.0, 1.0)

	queue_redraw()


func _panel_text(t: Node) -> String:
	var s: Dictionary = t.call("stats")
	var champ: Genome = s["champion"]
	var best: float = s["best"]
	var best_ever: float = s["best_ever"]
	var bar := _bar(s["energy"] / Balance.ENERGY_MAX, 12)
	var closest: float = s["closest"]
	return "%s TOWER\ngeneration %d   pop %d\nbest %s   all-time %s\nclosest approach %s px\nalive %d/%d   fielded %d   cake %d\nenergy %s  %3.0f\nqueue %d   in play %d   mut x%.2f\nchampion %s\nspawn cost %.0f" % [
		Balance.team_name(s["team"]), s["generation"], Balance.POP_SIZE,
		_num(best), _num(best_ever),
		"—" if closest >= 1e29 else "%.0f" % closest,
		s["alive"], Balance.MAX_ALIVE, s["deployed"], s["arrivals"],
		bar, s["energy"],
		s["queued"], s["pending"], s["mutation"],
		champ.describe(), champ.cost()]


static func _num(v: float) -> String:
	return "—" if v <= -1e29 else "%.0f" % v


static func _bar(ratio: float, width: int) -> String:
	var filled := int(round(clampf(ratio, 0.0, 1.0) * width))
	return "[" + "|".repeat(filled) + ".".repeat(width - filled) + "]"


# ====================================================================== minimap
func _build_map() -> void:
	var terrain := get_tree().get_first_node_in_group("terrain")
	if terrain == null:
		return
	for child in terrain.get_children():
		if child is CollisionPolygon2D:
			var poly: PackedVector2Array = (child as CollisionPolygon2D).polygon
			var world := PackedVector2Array()
			for p in poly:
				world.append((child as CollisionPolygon2D).global_transform * p)
			_map_polys.append(world)
	_map_built = true


func _map_rect() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2(vp.x * 0.5 - MAP_W * 0.5, vp.y - MAP_H - MAP_MARGIN - 26.0, MAP_W, MAP_H)


## World space -> minimap space, clamped to the frame. Nothing here is clipped by
## the renderer, so out-of-bounds geometry (the arena's side walls, a gleap that
## has fallen past the death plane) must be pinned to the edge by hand.
func _to_map(p: Vector2, r: Rect2) -> Vector2:
	var x := inverse_lerp(Balance.ARENA_LEFT, Balance.ARENA_RIGHT, p.x)
	var y := inverse_lerp(-420.0, Balance.DEATH_Y, p.y)
	return Vector2(
		clampf(r.position.x + x * r.size.x, r.position.x, r.end.x),
		clampf(r.position.y + y * r.size.y, r.position.y, r.end.y))


func _draw() -> void:
	var r := _map_rect()
	draw_rect(r.grow(4.0), Color(0.05, 0.06, 0.10, 0.72))
	draw_rect(r.grow(4.0), Color(0.35, 0.40, 0.55, 0.35), false, 1.0)

	for poly in _map_polys:
		var mapped := PackedVector2Array()
		for p in poly:
			mapped.append(_to_map(p, r))
		draw_colored_polygon(mapped, Color(0.30, 0.34, 0.46, 0.9))

	# towers
	draw_circle(_to_map(Balance.TOWER_LEFT_POS, r), 3.5, Balance.team_colour(0))
	draw_circle(_to_map(Balance.TOWER_RIGHT_POS, r), 3.5, Balance.team_colour(1))

	# cake
	var cake_p := _to_map(Balance.CAKE_POS, r)
	draw_circle(cake_p, 4.5, Color(1.0, 0.85, 0.45))
	draw_arc(cake_p, 8.0, 0.0, TAU, 16, Color(1.0, 0.85, 0.45, 0.5), 1.0, true)

	# live creatures
	for g in get_tree().get_nodes_in_group("gleaps"):
		if not is_instance_valid(g) or g.get("alive") != true:
			continue
		var c: Color = Balance.team_colour(g.get("team"))
		draw_circle(_to_map(g.global_position, r), 2.2, c)

	# camera viewport footprint
	var cam := get_viewport().get_camera_2d()
	if cam:
		var half := get_viewport_rect().size * 0.5 / cam.zoom
		var view := Rect2(cam.get_screen_center_position() - half, half * 2.0)
		var a := _to_map(view.position, r)
		var b := _to_map(view.end, r)
		draw_rect(Rect2(a, b - a), Color(1, 1, 1, 0.22), false, 1.0)
