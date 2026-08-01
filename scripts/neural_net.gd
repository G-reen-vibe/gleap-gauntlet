class_name NeuralNet
extends RefCounted

## A tiny Elman (recurrent) network. One hidden layer whose previous activation is
## fed back in, which gives each gleap a short working memory — enough to time a
## crouch, hold a charge across several frames and remember which way it was going
## while airborne. Everything is flat PackedFloat32Arrays so a whole population can
## be crossed over and mutated by slicing numbers.

const IN := 21
const HID := 16
const OUT := 5

## Output channel meanings (read by gleap.gd).
const O_AIM := 0      # tanh   : horizontal aim of the next leap, -1 .. 1
const O_HOLD := 1     # sigmoid: begin / keep charging a hop
const O_RELEASE := 2  # sigmoid: fire the hop now
const O_LEAN := 3     # tanh   : mid-air steering
const O_CLING := 4    # sigmoid: grab the wall being touched

var w1 := PackedFloat32Array()   # HID x IN   input -> hidden
var wr := PackedFloat32Array()   # HID x HID  hidden(t-1) -> hidden
var b1 := PackedFloat32Array()   # HID
var w2 := PackedFloat32Array()   # OUT x HID  hidden -> output
var b2 := PackedFloat32Array()   # OUT

var _h := PackedFloat32Array()   # recurrent state
var _out := PackedFloat32Array()


static func weight_count() -> int:
	return HID * IN + HID * HID + HID + OUT * HID + OUT


func _init() -> void:
	w1.resize(HID * IN)
	wr.resize(HID * HID)
	b1.resize(HID)
	w2.resize(OUT * HID)
	b2.resize(OUT)
	_h.resize(HID)
	_out.resize(OUT)


## Unpack a flat genome chromosome into the weight matrices.
func load_weights(flat: PackedFloat32Array) -> void:
	assert(flat.size() == weight_count())
	var i := 0
	for k in range(w1.size()):
		w1[k] = flat[i]
		i += 1
	for k in range(wr.size()):
		wr[k] = flat[i]
		i += 1
	for k in range(b1.size()):
		b1[k] = flat[i]
		i += 1
	for k in range(w2.size()):
		w2[k] = flat[i]
		i += 1
	for k in range(b2.size()):
		b2[k] = flat[i]
		i += 1


func reset_state() -> void:
	for k in range(_h.size()):
		_h[k] = 0.0


## One forward pass. `inputs` must be NeuralNet.IN long; the returned array is
## reused between calls, so copy it if you need to keep it.
func step(inputs: PackedFloat32Array) -> PackedFloat32Array:
	var next := PackedFloat32Array()
	next.resize(HID)

	for j in range(HID):
		var sum := b1[j]
		var row := j * IN
		for i in range(IN):
			sum += w1[row + i] * inputs[i]
		var rrow := j * HID
		for i in range(HID):
			sum += wr[rrow + i] * _h[i]
		next[j] = _tanh(sum)

	_h = next

	for o in range(OUT):
		var sum := b2[o]
		var row := o * HID
		for j in range(HID):
			sum += w2[row + j] * _h[j]
		# Aim and lean are bipolar steering channels; the rest are gates.
		if o == O_AIM or o == O_LEAN:
			_out[o] = _tanh(sum)
		else:
			_out[o] = 1.0 / (1.0 + exp(-clampf(sum, -30.0, 30.0)))
	return _out


## Snapshot of the hidden layer, used by the HUD brain scope.
func hidden_state() -> PackedFloat32Array:
	return _h


static func _tanh(x: float) -> float:
	# exp() blows up well before tanh saturates; clamp first.
	var c := clampf(x, -20.0, 20.0)
	var e := exp(2.0 * c)
	return (e - 1.0) / (e + 1.0)
