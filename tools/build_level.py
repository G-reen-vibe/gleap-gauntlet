#!/usr/bin/env python3
"""Emit scenes/main.tscn.

The .tscn it writes is the shipped, hand-editable source of truth for the level;
this generator exists so the gauntlet stays perfectly mirrored about the centre
and so `load_steps` and node counts can never drift out of sync when the course
is retuned. Run it from the project root:

    python3 tools/build_level.py

Coordinates are Godot 2D world space: +x right, +y down. Ground level is y=700,
anything that falls past y=950 dies, and the cake sits on the central mesa at
(1800, 190).
"""

from pathlib import Path

CENTRE = 1800.0
ARENA_W = 3600.0

# --------------------------------------------------------------------- palettes
KINDS = {
    # kind        body colour                  top-cap colour
    "rock":   ((0.168, 0.192, 0.271, 1.0), (0.298, 0.349, 0.463, 1.0)),
    "plinth": ((0.204, 0.231, 0.318, 1.0), (0.376, 0.427, 0.541, 1.0)),
    "gate":   ((0.231, 0.176, 0.251, 1.0), (0.451, 0.318, 0.412, 1.0)),
    "mesa":   ((0.243, 0.212, 0.302, 1.0), (0.588, 0.478, 0.318, 1.0)),
    "bound":  ((0.098, 0.110, 0.161, 1.0), (0.098, 0.110, 0.161, 1.0)),
}

CAP = 7.0


def rect(name, kind, x1, y1, x2, y2):
    poly = [(x1, y1), (x2, y1), (x2, y2), (x1, y2)]
    cap = [(x1, y1), (x2, y1), (x2, y1 + CAP), (x1, y1 + CAP)]
    return {"name": name, "kind": kind, "poly": poly, "cap": cap}


def shape(name, kind, poly, cap=None):
    return {"name": name, "kind": kind, "poly": poly, "cap": cap}


def mirror(s):
    """Reflect a shape about the centre line and reverse its winding."""
    def flip(pts):
        return [(ARENA_W - x, y) for (x, y) in reversed(pts)]
    return {
        "name": s["name"] + "_r",
        "kind": s["kind"],
        "poly": flip(s["poly"]),
        "cap": flip(s["cap"]) if s["cap"] else None,
    }


# ==============================================================================
# The gauntlet, left half only: tower -> pit -> ramp -> gate wall -> squeeze ->
# staircase over a chasm -> plateau -> leap onto the mushroom mesa.
# ==============================================================================
LEFT = [
    # spawn platform the tower stands on
    rect("plinth", "plinth", 20, 700, 300, 900),
    # opening run
    rect("ground_a", "rock", 300, 700, 520, 900),
    # a 33-degree ramp: gleaps have no walk cycle, so even a slope must be hopped
    shape("ramp", "rock",
          [(520, 700), (660, 610), (660, 900), (520, 900)],
          [(520, 700), (660, 610), (660, 617), (520, 707)]),
    rect("ledge_a", "rock", 660, 610, 780, 900),
    # ---- HOLE 1: 780 .. 960, straight down to the death plane ----
    rect("ground_b", "rock", 960, 700, 1180, 900),
    # ---- THE GATE: a 290px wall. Too tall for a standing hop, so a lineage
    #      either evolves the raw power to arc over it, or learns to grip the face
    #      and climb. The nub is the one concession: a foothold halfway up. ----
    rect("gate_nub", "gate", 1130, 560, 1180, 600),
    rect("gate_wall", "gate", 1180, 410, 1250, 900),
    rect("trench", "rock", 1250, 700, 1470, 900),
    # ---- HOLE 2: 1470 .. 1560, spanned only by the floating staircase ----
    # low ceiling over the trench: the arc out of the gate has to stay flat
    rect("overhang", "gate", 1250, 300, 1500, 360),
    rect("step_1", "rock", 1300, 620, 1370, 660),
    rect("step_2", "rock", 1390, 545, 1460, 585),
    rect("step_3", "rock", 1480, 470, 1550, 510),
    rect("plateau", "rock", 1560, 400, 1660, 900),
    # invisible arena boundary
    rect("bound", "bound", -60, -600, 0, 950),
]

# Shared centrepiece: a mushroom-capped mesa. The overhanging cap means the final
# leap from the plateau has to clear a lip, not just gain height.
CENTREPIECE = [
    rect("mesa_stem", "mesa", 1770, 240, 1830, 900),
    rect("mesa_cap", "mesa", 1720, 200, 1880, 240),
]

SHAPES = LEFT + [mirror(s) for s in LEFT] + CENTREPIECE


# ------------------------------------------------------------------- formatting
def fmt_poly(pts):
    body = ", ".join("%g, %g" % (x, y) for (x, y) in pts)
    return "PackedVector2Array(%s)" % body


def fmt_colour(c):
    return "Color(%g, %g, %g, %g)" % c


def build():
    out = []
    w = out.append

    ext = [
        ('Script', 'res://scripts/arena.gd', '1_arena'),
        ('Script', 'res://scripts/backdrop.gd', '2_backdrop'),
        ('Script', 'res://scripts/cake.gd', '3_cake'),
        ('Script', 'res://scripts/tower.gd', '4_tower'),
        ('Script', 'res://scripts/camera_director.gd', '5_cam'),
        ('Script', 'res://scripts/hud.gd', '6_hud'),
        ('PackedScene', 'res://scenes/gleap.tscn', '7_gleap'),
    ]
    sub_count = 2  # kill volume + cake trigger
    w("[gd_scene load_steps=%d format=3]" % (len(ext) + sub_count + 1))
    w("")
    for kind, path, rid in ext:
        w('[ext_resource type="%s" path="%s" id="%s"]' % (kind, path, rid))
    w("")
    w('[sub_resource type="RectangleShape2D" id="RectangleShape2D_kill"]')
    w("size = Vector2(4400, 300)")
    w("")
    w('[sub_resource type="CircleShape2D" id="CircleShape2D_cake"]')
    # Wide enough that landing anywhere on the mesa cap counts as reaching the
    # cake — the mesa top *is* the goal, and a gleap that sticks the final leap
    # should not lose on a technicality of where its feet ended up.
    w("radius = 80.0")
    w("")

    # ---------------------------------------------------------------- root
    w('[node name="Arena" type="Node2D" groups=["arena"]]')
    w('script = ExtResource("1_arena")')
    w("")
    w('[node name="Backdrop" type="Node2D" parent="."]')
    w('script = ExtResource("2_backdrop")')
    w("")

    # ---------------------------------------------------------------- visuals
    w('[node name="TerrainSkin" type="Node2D" parent="."]')
    w("z_index = -2")
    w("")
    for i, s in enumerate(SHAPES):
        body, cap = KINDS[s["kind"]]
        w('[node name="Skin%02d_%s" type="Polygon2D" parent="TerrainSkin"]' % (i, s["name"]))
        w("color = %s" % fmt_colour(body))
        w("polygon = %s" % fmt_poly(s["poly"]))
        w("")
        if s["cap"] and s["kind"] != "bound":
            w('[node name="Cap%02d_%s" type="Polygon2D" parent="TerrainSkin"]' % (i, s["name"]))
            w("color = %s" % fmt_colour(cap))
            w("polygon = %s" % fmt_poly(s["cap"]))
            w("")

    # ---------------------------------------------------------------- collision
    w('[node name="Terrain" type="StaticBody2D" parent="." groups=["terrain"]]')
    w("collision_layer = 1")
    w("collision_mask = 0")
    w("")
    for i, s in enumerate(SHAPES):
        w('[node name="Col%02d_%s" type="CollisionPolygon2D" parent="Terrain"]' % (i, s["name"]))
        w("polygon = %s" % fmt_poly(s["poly"]))
        w("")

    # ---------------------------------------------------------------- triggers
    w('[node name="KillZone" type="Area2D" parent="."]')
    w("position = Vector2(1800, 1100)")
    w("collision_layer = 0")
    w("collision_mask = 2")
    w("monitorable = false")
    w("")
    w('[node name="CollisionShape2D" type="CollisionShape2D" parent="KillZone"]')
    w('shape = SubResource("RectangleShape2D_kill")')
    w("")

    w('[node name="Cake" type="Area2D" parent="."]')
    w("position = Vector2(1800, 190)")
    w("collision_layer = 0")
    w("collision_mask = 2")
    w("monitorable = false")
    w('script = ExtResource("3_cake")')
    w("")
    w('[node name="CollisionShape2D" type="CollisionShape2D" parent="Cake"]')
    w("position = Vector2(0, -18)")
    w('shape = SubResource("CircleShape2D_cake")')
    w("")

    # ---------------------------------------------------------------- towers
    for name, pos, team, seed in (
        ("TowerLeft", "Vector2(170, 700)", 0, 20260801),
        ("TowerRight", "Vector2(3430, 700)", 1, 913377),
    ):
        w('[node name="%s" type="Node2D" parent="."]' % name)
        w("position = %s" % pos)
        w('script = ExtResource("4_tower")')
        w("team = %d" % team)
        w('gleap_scene = ExtResource("7_gleap")')
        w("spawn_offset = Vector2(46, -26)")
        w("rng_seed = %d" % seed)
        w("")

    # ---------------------------------------------------------------- camera
    w('[node name="Camera2D" type="Camera2D" parent="."]')
    w("position = Vector2(1800, 380)")
    w("zoom = Vector2(0.4, 0.4)")
    w('script = ExtResource("5_cam")')
    w("")

    # ---------------------------------------------------------------- hud
    w('[node name="HUD" type="CanvasLayer" parent="."]')
    w("layer = 10")
    w("")
    w('[node name="Screen" type="Control" parent="HUD"]')
    w("anchors_preset = 15")
    w("anchor_right = 1.0")
    w("anchor_bottom = 1.0")
    w("grow_horizontal = 2")
    w("grow_vertical = 2")
    w("mouse_filter = 2")
    w('script = ExtResource("6_hud")')
    w("")

    def label(name, props, size, align=0, colour="Color(0.86, 0.89, 1, 1)"):
        w('[node name="%s" type="Label" parent="HUD/Screen"]' % name)
        for k, v in props:
            w("%s = %s" % (k, v))
        w("mouse_filter = 2")
        w("horizontal_alignment = %d" % align)
        w("theme_override_font_sizes/font_size = %d" % size)
        w("theme_override_colors/font_color = %s" % colour)
        w("theme_override_colors/font_outline_color = Color(0.02, 0.02, 0.04, 0.85)")
        w("theme_override_constants/outline_size = 5")
        w("")

    label("LeftPanel", [
        ("offset_left", "18.0"), ("offset_top", "84.0"),
        ("offset_right", "440.0"), ("offset_bottom", "300.0"),
    ], 13)

    label("RightPanel", [
        ("anchor_left", "1.0"), ("anchor_right", "1.0"),
        ("offset_left", "-440.0"), ("offset_top", "84.0"),
        ("offset_right", "-18.0"), ("offset_bottom", "300.0"),
        ("grow_horizontal", "0"),
    ], 13, align=2)

    label("Banner", [
        ("anchor_left", "0.5"), ("anchor_right", "0.5"),
        ("offset_left", "-360.0"), ("offset_top", "14.0"),
        ("offset_right", "360.0"), ("offset_bottom", "52.0"),
        ("grow_horizontal", "2"),
    ], 27, align=1)

    label("SubBanner", [
        ("anchor_left", "0.5"), ("anchor_right", "0.5"),
        ("offset_left", "-360.0"), ("offset_top", "50.0"),
        ("offset_right", "360.0"), ("offset_bottom", "74.0"),
        ("grow_horizontal", "2"),
    ], 14, align=1, colour="Color(0.68, 0.72, 0.86, 1)")

    label("Toast", [
        ("anchor_left", "0.5"), ("anchor_right", "0.5"),
        ("anchor_top", "1.0"), ("anchor_bottom", "1.0"),
        ("offset_left", "-500.0"), ("offset_top", "-162.0"),
        ("offset_right", "500.0"), ("offset_bottom", "-136.0"),
        ("grow_horizontal", "2"), ("grow_vertical", "0"),
    ], 15, align=1, colour="Color(1, 0.87, 0.55, 1)")

    label("Help", [
        ("anchor_top", "1.0"), ("anchor_bottom", "1.0"),
        ("offset_left", "18.0"), ("offset_top", "-32.0"),
        ("offset_right", "1100.0"), ("offset_bottom", "-8.0"),
        ("grow_vertical", "0"),
    ], 12, colour="Color(0.6, 0.65, 0.8, 1)")

    return "\n".join(out) + "\n"


if __name__ == "__main__":
    target = Path(__file__).resolve().parent.parent / "scenes" / "main.tscn"
    target.write_text(build())
    print("wrote %s (%d shapes)" % (target, len(SHAPES)))
