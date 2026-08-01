extends Area2D

## The treasured cake. First gleap to touch it wins the match for its tower.

signal claimed(team: int, gleap: Node)

var claimed_by := -1
var _t := 0.0
var _pop := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	z_index = 3   # behind the creatures, so a winning gleap is not hidden by it


func _process(delta: float) -> void:
	_t += delta
	_pop = maxf(_pop - delta * 1.6, 0.0)
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if not (body is Gleap):
		return
	var g: Gleap = body
	if not g.alive:
		return
	_pop = 1.0
	if claimed_by < 0:
		claimed_by = g.team
	g.on_reached_cake()
	claimed.emit(g.team, g)


func _draw() -> void:
	var bob := sin(_t * 2.0) * 3.0
	var s := 1.0 + _pop * 0.35
	draw_set_transform(Vector2(0, bob), 0.0, Vector2(s, s))

	# glow
	var glow := Color(1.0, 0.85, 0.45, 0.10 + 0.05 * sin(_t * 3.0))
	if claimed_by >= 0:
		glow = Balance.team_colour(claimed_by)
		glow.a = 0.22
	for i in range(4):
		draw_circle(Vector2(0, -14), 44.0 + i * 13.0, Color(glow.r, glow.g, glow.b, glow.a * (1.0 - i * 0.22)))

	# plate
	draw_rect(Rect2(-30, 4, 60, 6), Color(0.72, 0.75, 0.85))
	# bottom tier
	draw_rect(Rect2(-24, -14, 48, 18), Color(0.95, 0.83, 0.62))
	draw_rect(Rect2(-24, -18, 48, 6), Color(0.98, 0.55, 0.62))
	# top tier
	draw_rect(Rect2(-15, -34, 30, 16), Color(0.95, 0.83, 0.62))
	draw_rect(Rect2(-15, -38, 30, 6), Color(0.98, 0.55, 0.62))
	# icing drips
	for i in range(5):
		var x := -20.0 + i * 10.0
		draw_circle(Vector2(x, -12), 3.4, Color(0.98, 0.55, 0.62))
	# candle
	draw_rect(Rect2(-2, -52, 4, 14), Color(0.98, 0.98, 1.0))
	var flame := 3.0 + sin(_t * 9.0) * 0.8
	draw_circle(Vector2(0, -55), flame, Color(1.0, 0.78, 0.25))
	draw_circle(Vector2(0, -56), flame * 0.5, Color(1.0, 0.97, 0.75))
	# cherries
	draw_circle(Vector2(-7, -41), 3.0, Color(0.9, 0.25, 0.3))
	draw_circle(Vector2(7, -41), 3.0, Color(0.9, 0.25, 0.3))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
