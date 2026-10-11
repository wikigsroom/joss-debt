extends RefCounted
## Explicit, serialized stream; renderer and audio never consume gameplay randomness.

var state: int = 1

func _init(seed_value: int = 1) -> void:
	state = posmod(seed_value, 2147483646) + 1

func next_int() -> int:
	state = (state * 48271) % 2147483647
	return state

func unit() -> float:
	return float(next_int() - 1) / 2147483646.0

func between(low: int, high: int) -> int:
	return low + int(unit() * (high - low + 1))

func choose(values: Array):
	return values[between(0, values.size() - 1)] if not values.is_empty() else null

func shuffle(values: Array) -> Array:
	var result = values.duplicate()
	for i in range(result.size() - 1, 0, -1):
		var j = between(0, i)
		var held = result[i]
		result[i] = result[j]
		result[j] = held
	return result

func weighted(values: Array, weights: Array):
	var total = 0.0
	for value in weights:
		total += maxf(0.0, float(value))
	if total <= 0.0:
		return null
	var point = unit() * total
	for i in values.size():
		point -= maxf(0.0, float(weights[i]))
		if point < 0.0:
			return values[i]
	return values.back()
