class_name Mulberry32
extends RefCounted
## The web game's random numbers. web: gen.js mulberry32(), seedRng(); game.js rngFrom() uses the same.

var a: int = 0


func _init(seed_u32: int = 0) -> void:
	a = seed_u32 & JS.M32


## web: mulberry32 — returns a float in [0, 1).
func next() -> float:
	a = (a + 0x6D2B79F5) & JS.M32
	var t := JS.imul(a ^ (a >> 15), 1 | a)
	t = ((t + JS.imul(t ^ (t >> 7), 61 | t)) & JS.M32) ^ t
	return float((t ^ (t >> 14)) & JS.M32) / 4294967296.0


## web: seedRng(str) — FNV-1a over the string's UTF-16 code units.
static func from_string(s: String) -> Mulberry32:
	var h := 2166136261
	for c in JS.js_char_codes(s):
		h ^= c
		h = JS.imul(h, 16777619)
	return Mulberry32.new(h)


## web: shuffle(a, rng) — Fisher-Yates in place.
func shuffle(arr: Array) -> Array:
	var i := arr.size() - 1
	while i > 0:
		var j := int(floor(next() * (i + 1)))
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
		i -= 1
	return arr
