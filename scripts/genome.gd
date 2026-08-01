class_name Genome
extends RefCounted

## A crafted creature: a body recipe plus the brain chromosome that drives it.
## Towers breed these — the body genes decide what the gleap physically *can* do
## and cost to field, the weight chromosome decides what it actually does.

## Body gene ranges. Order matters: it is the layout of `body`.
const GENE_NAMES := ["size", "power", "charge_rate", "air_control", "bounce", "grip", "hue"]
const GENE_MIN := [0.70, 0.75, 0.70, 0.00, 0.00, 0.00, 0.00]
const GENE_MAX := [1.45, 1.30, 1.60, 1.00, 0.45, 1.00, 1.00]

const G_SIZE := 0
const G_POWER := 1
const G_CHARGE_RATE := 2
const G_AIR_CONTROL := 3
const G_BOUNCE := 4
const G_GRIP := 5
const G_HUE := 6

var body := PackedFloat32Array()
var weights := PackedFloat32Array()

var scores: Array[float] = []   # fitness from recent runs
var runs := 0                   # lifetime evaluations
var lineage := 0                # generation this genome was born in
var id := 0


func _init() -> void:
	body.resize(GENE_NAMES.size())
	weights.resize(NeuralNet.weight_count())


# ------------------------------------------------------------------ derivations
static func gene_min(index: int) -> float:
	return GENE_MIN[index]

static func gene_max(index: int) -> float:
	return GENE_MAX[index]

func gene(index: int) -> float:
	return body[index]

func radius() -> float:
	return Balance.BASE_RADIUS * body[G_SIZE]

## Heavier creatures leap less high for the same muscle.
func jump_velocity() -> float:
	return Balance.JUMP_V * body[G_POWER] / sqrt(body[G_SIZE])

func hop_speed() -> float:
	return Balance.HOP_H * body[G_POWER] / sqrt(body[G_SIZE])

func charge_seconds() -> float:
	return Balance.MAX_CHARGE / body[G_CHARGE_RATE]

func gravity_scale() -> float:
	# Bigger bodies fall a touch harder, which makes them punchier but less floaty.
	return lerpf(0.92, 1.14, inverse_lerp(gene_min(G_SIZE), gene_max(G_SIZE), body[G_SIZE]))

func cling_capacity() -> float:
	return 0.90 + body[G_GRIP] * 2.40

## Energy the parent tower must pay to field this creature.
func cost() -> float:
	return 16.0 \
		+ body[G_SIZE] * 11.0 \
		+ body[G_POWER] * 14.0 \
		+ body[G_CHARGE_RATE] * 4.0 \
		+ body[G_AIR_CONTROL] * 7.0 \
		+ body[G_GRIP] * 6.0

func colour(team: int) -> Color:
	# Team hue dominates; the hue gene shifts the individual within the team band.
	var base := Balance.team_colour(team)
	var h := base.h + (body[G_HUE] - 0.5) * 0.11
	return Color.from_hsv(fposmod(h, 1.0), clampf(base.s * lerpf(0.75, 1.05, body[G_HUE]), 0.0, 1.0), \
		clampf(base.v * lerpf(0.86, 1.06, body[G_POWER] - 0.4), 0.0, 1.0))


# -------------------------------------------------------------------- bookkeeping
func fitness() -> float:
	if scores.is_empty():
		return -INF
	var total := 0.0
	for s in scores:
		total += s
	return total / scores.size()

func record(score: float) -> void:
	scores.append(score)
	runs += 1
	while scores.size() > Balance.EVALS_PER_GENOME:
		scores.pop_front()

func evaluated() -> bool:
	return scores.size() >= Balance.EVALS_PER_GENOME

func describe() -> String:
	return "size %.2f  pow %.2f  chg %.2f  air %.2f  bnc %.2f  grip %.2f" % [
		body[G_SIZE], body[G_POWER], body[G_CHARGE_RATE],
		body[G_AIR_CONTROL], body[G_BOUNCE], body[G_GRIP]]


# ------------------------------------------------------------------- generation
static func random_new(rng: RandomNumberGenerator) -> Genome:
	var g := Genome.new()
	for i in range(GENE_NAMES.size()):
		g.body[i] = rng.randf_range(gene_min(i), gene_max(i))
	for i in range(g.weights.size()):
		g.weights[i] = rng.randfn(0.0, 0.8)
	return g


static func crossover(a: Genome, b: Genome, rng: RandomNumberGenerator) -> Genome:
	var child := Genome.new()
	# Body: blend crossover so recipes drift smoothly instead of snapping.
	for i in range(GENE_NAMES.size()):
		var t := rng.randf_range(-0.25, 1.25)
		child.body[i] = clampf(lerpf(a.body[i], b.body[i], t), gene_min(i), gene_max(i))
	# Brain: uniform crossover keeps useful sub-circuits intact more often than
	# a single cut point would for a matrix laid out row-major.
	for i in range(child.weights.size()):
		child.weights[i] = a.weights[i] if rng.randf() < 0.5 else b.weights[i]
	child.lineage = maxi(a.lineage, b.lineage) + 1
	return child


func mutate(rng: RandomNumberGenerator, scale: float = 1.0) -> void:
	for i in range(GENE_NAMES.size()):
		if rng.randf() < Balance.BODY_MUTATE_RATE * scale:
			var span := gene_max(i) - gene_min(i)
			body[i] = clampf(body[i] + rng.randfn(0.0, Balance.BODY_MUTATE_SIGMA * span * scale),
				gene_min(i), gene_max(i))
	for i in range(weights.size()):
		if rng.randf() < Balance.MUTATE_RATE * scale:
			weights[i] = clampf(weights[i] + rng.randfn(0.0, Balance.MUTATE_SIGMA * scale), -6.0, 6.0)


func clone() -> Genome:
	var c := Genome.new()
	c.body = body.duplicate()
	c.weights = weights.duplicate()
	c.lineage = lineage
	return c


func build_brain() -> NeuralNet:
	var net := NeuralNet.new()
	net.load_weights(weights)
	return net


# ---------------------------------------------------------------- serialisation
func to_dict() -> Dictionary:
	return {
		"body": Array(body),
		"weights": Array(weights),
		"lineage": lineage,
		"fitness": fitness(),
	}


static func from_dict(d: Dictionary) -> Genome:
	var g := Genome.new()
	var b: Array = d.get("body", [])
	for i in range(mini(b.size(), g.body.size())):
		g.body[i] = float(b[i])
	var w: Array = d.get("weights", [])
	if w.size() != g.weights.size():
		return g  # incompatible brain shape — keep the fresh zeros
	for i in range(g.weights.size()):
		g.weights[i] = float(w[i])
	g.lineage = int(d.get("lineage", 0))
	return g
