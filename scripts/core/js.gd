class_name JS
## Bit-exact stand-ins for the JavaScript number operations the web game relies on, so ported code gives the same
## results from the same seed. GDScript ints are 64-bit: 32-bit JavaScript integer math is done on uint32 values
## (0 … 2^32 - 1), which is the same bit pattern as the int32 values JavaScript works with.

const M32 := 0xFFFFFFFF


## Math.imul(a, b) as a uint32 bit pattern (inputs are uint32 bit patterns).
static func imul(a: int, b: int) -> int:
	a &= M32
	b &= M32
	var lo := a * (b & 0xFFFF)
	var hi := ((a * (b >> 16)) & 0xFFFF) << 16
	return (lo + hi) & M32


## Math.hypot(x, y), V8's algorithm (scaled Kahan sum), which can differ in the last bit from sqrt(x*x + y*y).
static func hypot(x: float, y: float) -> float:
	var ax := absf(x)
	var ay := absf(y)
	if is_inf(ax) or is_inf(ay):
		return INF
	if is_nan(ax) or is_nan(ay):
		return NAN
	var mx := ax if ax > ay else ay
	if mx == 0.0:
		return 0.0
	var s := 0.0
	var comp := 0.0
	var n := ax / mx
	var summand := n * n - comp
	var prelim := s + summand
	comp = (prelim - s) - summand
	s = prelim
	n = ay / mx
	summand = n * n - comp
	prelim = s + summand
	comp = (prelim - s) - summand
	s = prelim
	return sqrt(s) * mx


## Math.round: rounds half up (toward +infinity).
static func round_js(x: float) -> float:
	return floorf(x + 0.5)


## +x.toFixed(digits): JavaScript rounds the exact binary value half away from zero; then the decimal string is
## read back as the nearest double. Exact for |x| < 2^52 / 10^digits.
static func to_fixed(x: float, digits: int) -> float:
	if is_nan(x) or is_inf(x):
		return x
	if x < 0.0:
		return -to_fixed(-x, digits)
	var p := 1
	for _i in digits:
		p *= 10
	# x = mant * 2^exp exactly, with mant a 53-bit integer
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, x)
	var bits := bytes.decode_s64(0)
	var e := (bits >> 52) & 0x7FF
	var mant := bits & 0xFFFFFFFFFFFFF
	if e == 0:
		e = 1
	else:
		mant |= 1 << 52
	var exp2 := e - 1075
	if exp2 >= 0:
		return x   # an integer already
	var sh := -exp2
	if sh > 62:
		return 0.0 if x * p < 0.5 else 1.0 / p
	var scaled := mant * p   # < 2^53 * 1000 < 2^63 for digits <= 3
	var q := scaled >> sh
	var rem := scaled - (q << sh)
	if rem * 2 >= (1 << sh):
		q += 1
	return float(q) / float(p)


## A stable sort (like JavaScript's) in place. cmp(a, b) returns a number: < 0 puts a first, > 0 puts b first.
static func stable_sort(arr: Array, cmp: Callable) -> Array:
	var n := arr.size()
	if n < 2:
		return arr
	if n <= 12:
		for i in range(1, n):
			var v = arr[i]
			var j := i - 1
			while j >= 0 and cmp.call(arr[j], v) > 0:
				arr[j + 1] = arr[j]
				j -= 1
			arr[j + 1] = v
		return arr
	var tmp := arr.duplicate()
	_merge_sort(arr, tmp, 0, n, cmp)
	return arr


static func _merge_sort(a: Array, tmp: Array, lo: int, hi: int, cmp: Callable) -> void:
	if hi - lo <= 12:
		for i in range(lo + 1, hi):
			var v = a[i]
			var j := i - 1
			while j >= lo and cmp.call(a[j], v) > 0:
				a[j + 1] = a[j]
				j -= 1
			a[j + 1] = v
		return
	var mid := (lo + hi) >> 1
	_merge_sort(a, tmp, lo, mid, cmp)
	_merge_sort(a, tmp, mid, hi, cmp)
	if cmp.call(a[mid - 1], a[mid]) <= 0:
		return
	var i := lo
	var j := mid
	var k := lo
	while i < mid and j < hi:
		if cmp.call(a[j], a[i]) < 0:
			tmp[k] = a[j]
			j += 1
		else:
			tmp[k] = a[i]
			i += 1
		k += 1
	while i < mid:
		tmp[k] = a[i]
		i += 1
		k += 1
	while j < hi:
		tmp[k] = a[j]
		j += 1
		k += 1
	for t in range(lo, hi):
		a[t] = tmp[t]


## Stable sort by a precomputed numeric key per element (ascending). Faster than stable_sort with a Callable.
static func sort_by_key(arr: Array, keys: Array) -> Array:
	var idx := range(arr.size())
	stable_sort(idx, func(x, y): return keys[x] - keys[y])
	var out := []
	out.resize(arr.size())
	for i in idx.size():
		out[i] = arr[idx[i]]
	return out


## The UTF-16 code units JavaScript's charCodeAt(0) sees for each character of `for (const c of str)`.
static func js_char_codes(s: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in s.length():
		var cp := s.unicode_at(i)
		if cp > 0xFFFF:
			out.append(0xD800 + ((cp - 0x10000) >> 10))   # only the first code unit: charCodeAt(0)
		else:
			out.append(cp)
	return out


## V8's Array.prototype.sort (as in Chromium 157, which the fixtures come from) with a comparator that ignores its
## arguments (`() => r() - 0.5`), for arrays under 64 items. Up to 15 items: a binary insertion sort from the second
## item. 16 to 63: TimSort makes one run (the first ascending or strictly descending stretch, reversed if
## descending), then extends it with a binary insertion sort. Each comparison draws one number from `r`.
static func sort_random(a: Array, r) -> Array:
	var n := a.size()
	assert(n < 64, "sort_random: only short arrays")
	if n < 2:
		return a
	var cmp := func() -> float: return r.next() - 0.5
	var run := 1
	if n <= 15:
		return _bis_random(a, cmp, 1)
	# CountAndMakeRun(0, n)
	run = 2
	var desc: bool = cmp.call() < 0
	for idx in range(2, n):
		var order: float = cmp.call()
		if desc:
			if order >= 0:
				break
		elif order < 0:
			break
		run += 1
	if desc:
		var part := a.slice(0, run)
		part.reverse()
		for i in run:
			a[i] = part[i]
	return _bis_random(a, cmp, run)


static func _bis_random(a: Array, cmp: Callable, run: int) -> Array:
	var n := a.size()
	# BinaryInsertionSort(0, run, n)
	for start in range(run, n):
		var pivot = a[start]
		var left := 0
		var right := start
		while left < right:
			var mid := left + ((right - left) >> 1)
			if cmp.call() < 0:
				right = mid
			else:
				left = mid + 1
		var p := start
		while p > left:
			a[p] = a[p - 1]
			p -= 1
		a[left] = pivot
	return a
