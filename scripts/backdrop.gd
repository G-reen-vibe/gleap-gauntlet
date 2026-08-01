extends Node2D

## Purely decorative parallax-ish scenery drawn behind the gauntlet.

var _stars: PackedVector2Array = PackedVector2Array()
var _t := 0.0


func _ready() -> void:
	z_index = -20
	z_as_relative = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for i in range(220):
		_stars.append(Vector2(
			rng.randf_range(Balance.ARENA_LEFT - 200.0, Balance.ARENA_RIGHT + 200.0),
			rng.randf_range(Balance.ARENA_TOP - 200.0, 620.0)))
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var l := Balance.ARENA_LEFT - 400.0
	var r := Balance.ARENA_RIGHT + 400.0
	var top := Balance.ARENA_TOP - 400.0
	var bottom := Balance.ARENA_BOTTOM + 400.0

	# sky gradient, faked with a few bands
	var bands := 7
	for i in range(bands):
		var t := float(i) / float(bands - 1)
		var col := Color(0.05, 0.06, 0.11).lerp(Color(0.13, 0.11, 0.22), t)
		var y0 := lerpf(top, bottom, float(i) / float(bands))
		var y1 := lerpf(top, bottom, float(i + 1) / float(bands))
		draw_rect(Rect2(l, y0, r - l, y1 - y0 + 1.0), col)

	# stars
	for i in range(_stars.size()):
		var p := _stars[i]
		var tw := 0.35 + 0.35 * sin(_t * 1.7 + float(i) * 1.31)
		draw_circle(p, 1.1, Color(0.85, 0.9, 1.0, tw))

	# moon over the cake
	draw_circle(Vector2(Balance.CENTRE_X, -300.0), 62.0, Color(0.93, 0.94, 0.88, 0.14))
	draw_circle(Vector2(Balance.CENTRE_X, -300.0), 48.0, Color(0.96, 0.96, 0.90, 0.9))
	draw_circle(Vector2(Balance.CENTRE_X - 16.0, -312.0), 8.0, Color(0.88, 0.88, 0.83))
	draw_circle(Vector2(Balance.CENTRE_X + 14.0, -286.0), 5.0, Color(0.88, 0.88, 0.83))

	# far hills
	for layer in range(2):
		var depth := float(layer)
		var col := Color(0.09, 0.11, 0.18).lerp(Color(0.14, 0.16, 0.24), depth)
		var base_y := 780.0 - depth * 60.0
		var pts := PackedVector2Array()
		pts.append(Vector2(l, bottom))
		var x := l
		var i := 0
		while x < r:
			var amp := 110.0 - depth * 35.0
			var y := base_y - absf(sin(float(i) * 0.9 + depth * 2.1)) * amp
			pts.append(Vector2(x, y))
			x += 190.0 + depth * 60.0
			i += 1
		pts.append(Vector2(r, bottom))
		draw_colored_polygon(pts, col)
