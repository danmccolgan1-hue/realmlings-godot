class_name DMath
extends RefCounted
## Maths that give the same answer, bit for bit, on every computer. A multiplayer game stays in step only if every
## copy calculates exactly the same numbers. +, -, *, /, sqrt, floor and the like are exact everywhere, but Godot's
## sin, cos, atan2, exp and pow come from the operating system's maths library, which differs between Windows, Linux
## and macOS in the last bit: enough for a Windows player and a Linux server to drift apart (0.19 server tests).
## These are fdlibm 5.3's functions (Sun Microsystems), the library V8 uses for JavaScript's Math, so they also
## match the web game's numbers. The rules (scripts/sim, scripts/gen, scripts/core) use only these; the views may use
## Godot's own.
## web: V8 src/base/ieee754.cc (fdlibm: k_sin.c, k_cos.c, e_rem_pio2.c, s_sin.c, s_cos.c, s_atan.c, e_atan2.c,
## e_exp.c, e_pow.c)

# ---------------------------------------------------------------------------------------------------- the bits
static var _b: PackedByteArray = _bytes()


static func _bytes() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(8)
	return b


## The high 32 bits of a double, as a signed int (fdlibm's __HI).
static func _hi(x: float) -> int:
	_b.encode_double(0, x)
	return _b.decode_s32(4)


## The low 32 bits, unsigned (fdlibm's __LO).
static func _lo(x: float) -> int:
	_b.encode_double(0, x)
	return _b.decode_u32(0)


## A double from its two words.
static func _make(hi: int, lo: int) -> float:
	_b.encode_u32(4, hi & 0xffffffff)
	_b.encode_u32(0, lo & 0xffffffff)
	return _b.decode_double(0)


static func _with_hi(x: float, hi: int) -> float:
	return _make(hi, _lo(x))


static func _with_lo(x: float, lo: int) -> float:
	return _make(_hi(x), lo)


# ---------------------------------------------------------------------------------------------------- constants
# (built from their exact bit patterns, so no decimal parsing can change them)
static var S1 := _make(0xBFC55555, 0x55555549)
static var S2 := _make(0x3F811111, 0x1110F8A6)
static var S3 := _make(0xBF2A01A0, 0x19C161D5)
static var S4 := _make(0x3EC71DE3, 0x57B1FE7D)
static var S5 := _make(0xBE5AE5E6, 0x8A2B9CEB)
static var S6 := _make(0x3DE5D93A, 0x5ACFD57C)
static var C1 := _make(0x3FA55555, 0x5555554C)
static var C2 := _make(0xBF56C16C, 0x16C15177)
static var C3 := _make(0x3EFA01A0, 0x19CB1590)
static var C4 := _make(0xBE927E4F, 0x809C52AD)
static var C5 := _make(0x3E21EE9E, 0xBDB4B1C4)
static var C6 := _make(0xBDA8FAE9, 0xBE8838D4)
static var INVPIO2 := _make(0x3FE45F30, 0x6DC9C883)
static var PIO2_1 := _make(0x3FF921FB, 0x54400000)
static var PIO2_1T := _make(0x3DD0B461, 0x1A626331)
static var PIO2_2 := _make(0x3DD0B461, 0x1A600000)
static var PIO2_2T := _make(0x3BA3198A, 0x2E037073)
static var PIO2_3 := _make(0x3BA3198A, 0x2E000000)
static var PIO2_3T := _make(0x397B839A, 0x252049C1)
const NPIO2_HW := [0x3FF921FB, 0x400921FB, 0x4012D97C, 0x401921FB, 0x401F6A7A, 0x4022D97C, 0x4025FDBB, 0x402921FB,
	0x402C463A, 0x402F6A7A, 0x4031475C, 0x4032D97C, 0x40346B9C, 0x4035FDBB, 0x40378FDB, 0x403921FB, 0x403AB41B,
	0x403C463A, 0x403DD85A, 0x403F6A7A, 0x40407E4C, 0x4041475C, 0x4042106C, 0x4042D97C, 0x4043A28C, 0x40446B9C,
	0x404534AC, 0x4045FDBB, 0x4046C6CB, 0x40478FDB, 0x404858EB, 0x404921FB]
static var ATANHI := [_make(0x3FDDAC67, 0x0561BB4F), _make(0x3FE921FB, 0x54442D18), _make(0x3FEF730B, 0xD281F69B), _make(0x3FF921FB, 0x54442D18)]
static var ATANLO := [_make(0x3C7A2B7F, 0x222F65E2), _make(0x3C81A626, 0x33145C07), _make(0x3C700788, 0x7AF0CBBD), _make(0x3C91A626, 0x33145C07)]
static var AT := [_make(0x3FD55555, 0x5555550D), _make(0xBFC99999, 0x9998EBC4), _make(0x3FC24924, 0x920083FF),
	_make(0xBFBC71C6, 0xFE231671), _make(0x3FB745CD, 0xC54C206E), _make(0xBFB3B0F2, 0xAF749A6D), _make(0x3FB10D66, 0xA0D03D51),
	_make(0xBFADDE2D, 0x52DEFD9A), _make(0x3FA97B4B, 0x24760DEB), _make(0xBFA2B444, 0x2C6A6C2F), _make(0x3F90AD3A, 0xE322DA11)]
static var PI_O_2 := _make(0x3FF921FB, 0x54442D18)
static var PI_O_4 := _make(0x3FE921FB, 0x54442D18)
static var PI_D := _make(0x400921FB, 0x54442D18)
static var PI_LO := _make(0x3CA1A626, 0x33145C07)
static var O_THRESHOLD := _make(0x40862E42, 0xFEFA39EF)
static var U_THRESHOLD := _make(0xC0874910, 0xD52D3051)
static var LN2HI := [_make(0x3FE62E42, 0xFEE00000), _make(0xBFE62E42, 0xFEE00000)]
static var LN2LO := [_make(0x3DEA39EF, 0x35793C76), _make(0xBDEA39EF, 0x35793C76)]
static var INVLN2 := _make(0x3FF71547, 0x652B82FE)
static var P1 := _make(0x3FC55555, 0x5555553E)
static var P2 := _make(0xBF66C16C, 0x16BEBD93)
static var P3 := _make(0x3F11566A, 0xAF25DE2C)
static var P4 := _make(0xBEBBBD41, 0xC5D26BF1)
static var P5 := _make(0x3E663769, 0x72BEA4D0)
static var TWOM1000 := _make(0x01700000, 0)
static var BP := [1.0, 1.5]
static var DP_H := [0.0, _make(0x3FE2B803, 0x40000000)]
static var DP_L := [0.0, _make(0x3E4CFDEB, 0x43CFD006)]
static var TWO53 := _make(0x43400000, 0)
static var L1 := _make(0x3FE33333, 0x33333303)
static var L2 := _make(0x3FDB6DB6, 0xDB6FABFF)
static var L3 := _make(0x3FD55555, 0x518F264D)
static var L4 := _make(0x3FD17460, 0xA91D4101)
static var L5 := _make(0x3FCD864A, 0x93C9DB65)
static var L6 := _make(0x3FCA7E28, 0x4A454EEF)
static var LG2 := _make(0x3FE62E42, 0xFEFA39EF)
static var LG2_H := _make(0x3FE62E43, 0x00000000)
static var LG2_L := _make(0xBE205C61, 0x0CA86C39)
static var OVT := 8.0085662595372944372e-17
static var CP := _make(0x3FEEC709, 0xDC3A03FD)
static var CP_H := _make(0x3FEEC709, 0xE0000000)
static var CP_L := _make(0xBE3E2FE0, 0x145B01F5)
static var IVLN2 := _make(0x3FF71547, 0x652B82FE)
static var IVLN2_H := _make(0x3FF71547, 0x60000000)
static var IVLN2_L := _make(0x3E54AE0B, 0xF85DDF44)
const HUGE := 1.0e300
const TINY := 1.0e-300


# ---------------------------------------------------------------------------------------------------- sin, cos
static func _ksin(x: float, y: float, iy: int) -> float:
	var ix := _hi(x) & 0x7fffffff
	if ix < 0x3e400000 and int(x) == 0:
		return x
	var z := x * x
	var v := z * x
	var r: float = S2 + z * (S3 + z * (S4 + z * (S5 + z * S6)))
	if iy == 0:
		return x + v * (S1 + z * r)
	return x - ((z * (0.5 * y - v * r) - y) - v * S1)


static func _kcos(x: float, y: float) -> float:
	var ix := _hi(x) & 0x7fffffff
	if ix < 0x3e400000 and int(x) == 0:
		return 1.0
	var z := x * x
	var r: float = z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * C6)))))
	if ix < 0x3FD33333:
		return 1.0 - (0.5 * z - (z * r - x * y))
	var qx := 0.28125 if ix > 0x3fe90000 else _make(ix - 0x00200000, 0)
	var hz := 0.5 * z - qx
	var a := 1.0 - qx
	return a - (hz - (z * r - x * y))


## x reduced by n quarter-turns: [n, y0, y1] with x = n*pi/2 + y0 + y1.
static func _rem_pio2(x: float) -> Array:
	var hx := _hi(x)
	var ix := hx & 0x7fffffff
	if ix <= 0x3fe921fb:
		return [0, x, 0.0]
	if ix < 0x4002d97c:   # |x| < 3pi/4
		if hx > 0:
			var z: float = x - PIO2_1
			if ix != 0x3ff921fb:
				var y0: float = z - PIO2_1T
				return [1, y0, (z - y0) - PIO2_1T]
			z -= PIO2_2
			var y0b: float = z - PIO2_2T
			return [1, y0b, (z - y0b) - PIO2_2T]
		var z2: float = x + PIO2_1
		if ix != 0x3ff921fb:
			var y0c: float = z2 + PIO2_1T
			return [-1, y0c, (z2 - y0c) + PIO2_1T]
		z2 += PIO2_2
		var y0d: float = z2 + PIO2_2T
		return [-1, y0d, (z2 - y0d) + PIO2_2T]
	if ix <= 0x413921fb:   # |x| ~<= 2^19 * pi/2
		var t := absf(x)
		var n := int(t * INVPIO2 + 0.5)
		var fn := float(n)
		var r: float = t - fn * PIO2_1
		var w: float = fn * PIO2_1T
		var y0: float
		if n < 32 and ix != NPIO2_HW[n - 1]:
			y0 = r - w
		else:
			var j := ix >> 20
			y0 = r - w
			var i := j - ((_hi(y0) >> 20) & 0x7ff)
			if i > 16:
				t = r
				w = fn * PIO2_2
				r = t - w
				w = fn * PIO2_2T - ((t - r) - w)
				y0 = r - w
				i = j - ((_hi(y0) >> 20) & 0x7ff)
				if i > 49:
					t = r
					w = fn * PIO2_3
					r = t - w
					w = fn * PIO2_3T - ((t - r) - w)
					y0 = r - w
		var y1: float = (r - y0) - w
		if hx < 0:
			return [-n, -y0, -y1]
		return [n, y0, y1]
	if ix >= 0x7ff00000:
		return [0, x - x, x - x]
	# (huge angles, beyond fdlibm's medium case: never in the rules; reduce by whole turns first, still exact-ish
	# and, above all, the same everywhere)
	var turns := floorf(x / (4.0 * PIO2_1))
	return _rem_pio2(((x - turns * 4.0 * PIO2_1) - turns * 4.0 * PIO2_1T) - turns * 4.0 * PIO2_2T)


static func sin(x: float) -> float:
	var ix := _hi(x) & 0x7fffffff
	if ix <= 0x3fe921fb:
		return _ksin(x, 0.0, 0)
	if ix >= 0x7ff00000:
		return x - x
	var r := _rem_pio2(x)
	match int(r[0]) & 3:
		0:
			return _ksin(r[1], r[2], 1)
		1:
			return _kcos(r[1], r[2])
		2:
			return -_ksin(r[1], r[2], 1)
		_:
			return -_kcos(r[1], r[2])


static func cos(x: float) -> float:
	var ix := _hi(x) & 0x7fffffff
	if ix <= 0x3fe921fb:
		return _kcos(x, 0.0)
	if ix >= 0x7ff00000:
		return x - x
	var r := _rem_pio2(x)
	match int(r[0]) & 3:
		0:
			return _kcos(r[1], r[2])
		1:
			return -_ksin(r[1], r[2], 1)
		2:
			return -_kcos(r[1], r[2])
		_:
			return _ksin(r[1], r[2], 1)


# ---------------------------------------------------------------------------------------------------- atan, atan2
static func atan(x: float) -> float:
	var hx := _hi(x)
	var ix := hx & 0x7fffffff
	var id := -1
	if ix >= 0x44100000:   # |x| >= 2^66
		if ix > 0x7ff00000 or (ix == 0x7ff00000 and _lo(x) != 0):
			return x + x
		return ATANHI[3] + ATANLO[3] if hx > 0 else -ATANHI[3] - ATANLO[3]
	if ix < 0x3fdc0000:   # |x| < 0.4375
		if ix < 0x3e200000 and HUGE + x > 1.0:
			return x
	else:
		x = absf(x)
		if ix < 0x3ff30000:
			if ix < 0x3fe60000:
				id = 0
				x = (2.0 * x - 1.0) / (2.0 + x)
			else:
				id = 1
				x = (x - 1.0) / (x + 1.0)
		elif ix < 0x40038000:
			id = 2
			x = (x - 1.5) / (1.0 + 1.5 * x)
		else:
			id = 3
			x = -1.0 / x
	var z := x * x
	var w := z * z
	var s1: float = z * (AT[0] + w * (AT[2] + w * (AT[4] + w * (AT[6] + w * (AT[8] + w * AT[10])))))
	var s2: float = w * (AT[1] + w * (AT[3] + w * (AT[5] + w * (AT[7] + w * AT[9]))))
	if id < 0:
		return x - x * (s1 + s2)
	var zz: float = ATANHI[id] - ((x * (s1 + s2) - ATANLO[id]) - x)
	return -zz if hx < 0 else zz


static func atan2(y: float, x: float) -> float:
	var hx := _hi(x)
	var ix := hx & 0x7fffffff
	var lx := _lo(x)
	var hy := _hi(y)
	var iy := hy & 0x7fffffff
	var ly := _lo(y)
	if (ix > 0x7ff00000 or (ix == 0x7ff00000 and lx != 0)) or (iy > 0x7ff00000 or (iy == 0x7ff00000 and ly != 0)):
		return x + y
	if hx == 0x3ff00000 and lx == 0:   # x = 1
		return DMath.atan(y)
	var m := ((hy >> 31) & 1) | ((hx >> 30) & 2)
	if iy == 0 and ly == 0:   # y = 0
		match m:
			0, 1:
				return y
			2:
				return PI_D + TINY
			_:
				return -PI_D - TINY
	if ix == 0 and lx == 0:   # x = 0
		return -PI_O_2 - TINY if hy < 0 else PI_O_2 + TINY
	if ix == 0x7ff00000:   # x = inf
		if iy == 0x7ff00000:
			match m:
				0:
					return PI_O_4 + TINY
				1:
					return -PI_O_4 - TINY
				2:
					return 3.0 * PI_O_4 + TINY
				_:
					return -3.0 * PI_O_4 - TINY
		match m:
			0:
				return 0.0
			1:
				return -0.0
			2:
				return PI_D + TINY
			_:
				return -PI_D - TINY
	if iy == 0x7ff00000:
		return -PI_O_2 - TINY if hy < 0 else PI_O_2 + TINY
	var k := (iy - ix) >> 20
	var z: float
	if k > 60:
		z = PI_O_2 + 0.5 * PI_LO
	elif hx < 0 and k < -60:
		z = 0.0
	else:
		z = DMath.atan(absf(y / x))
	match m:
		0:
			return z
		1:
			return -z
		2:
			return PI_D - (z - PI_LO)
		_:
			return (z - PI_LO) - PI_D


# ---------------------------------------------------------------------------------------------------- exp
static func exp(x: float) -> float:
	var hx := _hi(x)
	var xsb := (hx >> 31) & 1
	hx &= 0x7fffffff
	var hi := 0.0
	var lo := 0.0
	var k := 0
	if hx >= 0x40862E42:   # |x| >= 709.78
		if hx >= 0x7ff00000:
			if ((hx & 0xfffff) | _lo(x)) != 0:
				return x + x
			return x if xsb == 0 else 0.0
		if x > O_THRESHOLD:
			return HUGE * HUGE
		if x < U_THRESHOLD:
			return TWOM1000 * TWOM1000
	if hx > 0x3fd62e42:   # |x| > 0.5 ln2
		if hx < 0x3FF0A2B2:   # |x| < 1.5 ln2
			if x == 1.0:   # (V8: Math.exp(1) is exactly Math.E)
				return _make(0x4005BF0A, 0x8B145769)
			hi = x - LN2HI[xsb]
			lo = LN2LO[xsb]
			k = 1 - xsb - xsb
		else:
			k = int(INVLN2 * x + (0.5 if xsb == 0 else -0.5))
			var t := float(k)
			hi = x - t * LN2HI[0]
			lo = t * LN2LO[0]
		x = hi - lo
	elif hx < 0x3e300000:   # |x| < 2^-28
		if HUGE + x > 1.0:
			return 1.0 + x
	else:
		k = 0
	var t2 := x * x
	var c: float = x - t2 * (P1 + t2 * (P2 + t2 * (P3 + t2 * (P4 + t2 * P5))))
	if k == 0:
		return 1.0 - ((x * c) / (c - 2.0) - x)
	var y := 1.0 - ((lo - (x * c) / (2.0 - c)) - hi)
	if k >= -1021:
		return _with_hi(y, _hi(y) + (k << 20))
	return _with_hi(y, _hi(y) + ((k + 1000) << 20)) * TWOM1000


# ---------------------------------------------------------------------------------------------------- pow
static func pow(x: float, y: float) -> float:
	var hx := _hi(x)
	var lx := _lo(x)
	var hy := _hi(y)
	var ly := _lo(y)
	var ix := hx & 0x7fffffff
	var iy := hy & 0x7fffffff
	if (iy | ly) == 0:
		return 1.0
	if ix > 0x7ff00000 or (ix == 0x7ff00000 and lx != 0) or iy > 0x7ff00000 or (iy == 0x7ff00000 and ly != 0):
		return x + y
	# yisint: 0 not an integer, 1 an odd integer, 2 an even integer (only needed when x < 0)
	var yisint := 0
	if hx < 0:
		if iy >= 0x43400000:
			yisint = 2
		elif iy >= 0x3ff00000:
			var k0 := (iy >> 20) - 0x3ff
			if k0 > 20:
				var j0 := ly >> (52 - k0)
				if ((j0 << (52 - k0)) & 0xffffffff) == ly:
					yisint = 2 - (j0 & 1)
			elif ly == 0:
				var j1 := iy >> (20 - k0)
				if (j1 << (20 - k0)) == iy:
					yisint = 2 - (j1 & 1)
	if ly == 0:
		if iy == 0x7ff00000:   # y is +-inf
			if ((ix - 0x3ff00000) | lx) == 0:
				return y - y
			if ix >= 0x3ff00000:
				return y if hy >= 0 else 0.0
			return -y if hy < 0 else 0.0
		if iy == 0x3ff00000:   # y is +-1
			return 1.0 / x if hy < 0 else x
		if hy == 0x40000000:   # y is 2
			return x * x
		if hy == 0x3fe00000 and hx >= 0:   # y is 0.5
			return sqrt(x)
	var ax := absf(x)
	if lx == 0 and (ix == 0x7ff00000 or ix == 0 or ix == 0x3ff00000):   # x is +-0, +-inf, +-1
		var z0 := ax
		if hy < 0:
			z0 = 1.0 / z0
		if hx < 0:
			if ((ix - 0x3ff00000) | yisint) == 0:
				z0 = (z0 - z0) / (z0 - z0)
			elif yisint == 1:
				z0 = -z0
		return z0
	var n := (hx >> 31) + 1
	if (n | yisint) == 0:   # (x < 0) ** non-integer
		return (x - x) / (x - x)
	var s := 1.0
	if (n | (yisint - 1)) == 0:
		s = -1.0
	var t1: float
	var t2: float
	if iy > 0x41e00000:   # |y| > 2^31
		if iy > 0x43f00000:
			if ix <= 0x3fefffff:
				return HUGE * HUGE if hy < 0 else TINY * TINY
			if ix >= 0x3ff00000:
				return HUGE * HUGE if hy > 0 else TINY * TINY
		if ix < 0x3fefffff:
			return s * HUGE * HUGE if hy < 0 else s * TINY * TINY
		if ix > 0x3ff00000:
			return s * HUGE * HUGE if hy > 0 else s * TINY * TINY
		var t := ax - 1.0
		var w := (t * t) * (0.5 - t * (0.3333333333333333333333 - t * 0.25))
		var u: float = IVLN2_H * t
		var v: float = t * IVLN2_L - w * IVLN2
		t1 = _with_lo(u + v, 0)
		t2 = v - (t1 - u)
	else:
		n = 0
		if ix < 0x00100000:
			ax *= TWO53
			n -= 53
			ix = _hi(ax)
		n += (ix >> 20) - 0x3ff
		var j := ix & 0x000fffff
		ix = j | 0x3ff00000
		var k := 0
		if j <= 0x3988E:
			k = 0
		elif j < 0xBB67A:
			k = 1
		else:
			k = 0
			n += 1
			ix -= 0x00100000
		ax = _with_hi(ax, ix)
		var u: float = ax - BP[k]
		var v: float = 1.0 / (ax + BP[k])
		var ss := u * v
		var s_h := _with_lo(ss, 0)
		var t_h := _make(((ix >> 1) | 0x20000000) + 0x00080000 + (k << 18), 0)
		var t_l: float = ax - (t_h - BP[k])
		var s_l := v * ((u - s_h * t_h) - s_h * t_l)
		var s2 := ss * ss
		var r: float = s2 * s2 * (L1 + s2 * (L2 + s2 * (L3 + s2 * (L4 + s2 * (L5 + s2 * L6)))))
		r += s_l * (s_h + ss)
		s2 = s_h * s_h
		t_h = _with_lo(3.0 + s2 + r, 0)
		t_l = r - ((t_h - 3.0) - s2)
		u = s_h * t_h
		v = s_l * t_h + t_l * ss
		var p_h0 := _with_lo(u + v, 0)
		var p_l0 := v - (p_h0 - u)
		var z_h: float = CP_H * p_h0
		var z_l: float = CP_L * p_h0 + p_l0 * CP + DP_L[k]
		var t := float(n)
		t1 = _with_lo(((z_h + z_l) + DP_H[k]) + t, 0)
		t2 = z_l - (((t1 - t) - DP_H[k]) - z_h)
	# split y into y1 + y2 and compute (y1 + y2) * (t1 + t2)
	var y1 := _with_lo(y, 0)
	var p_l := (y - y1) * t1 + y * t2
	var p_h := y1 * t1
	var z := p_l + p_h
	var jz := _hi(z)
	var iz := _lo(z)
	if jz >= 0x40900000:   # z >= 1024
		if ((jz - 0x40900000) | iz) != 0:
			return s * HUGE * HUGE
		if p_l + OVT > z - p_h:
			return s * HUGE * HUGE
	elif (jz & 0x7fffffff) >= 0x4090cc00:   # z <= -1075
		if not ((jz & 0xffffffff) == 0xc090cc00 and iz == 0):
			return s * TINY * TINY
		if p_l <= z - p_h:
			return s * TINY * TINY
	# 2 ** (p_h + p_l)
	var i := jz & 0x7fffffff
	var k2 := (i >> 20) - 0x3ff
	var n2 := 0
	if i > 0x3fe00000:   # |z| > 0.5: n = [z + 0.5]
		n2 = jz + (0x00100000 >> (k2 + 1))
		k2 = ((n2 & 0x7fffffff) >> 20) - 0x3ff
		var tt := _make(n2 & ~(0x000fffff >> k2), 0)
		n2 = ((n2 & 0x000fffff) | 0x00100000) >> (20 - k2)
		if jz < 0:
			n2 = -n2
		p_h -= tt
	var t3 := _with_lo(p_l + p_h, 0)
	var u2: float = t3 * LG2_H
	var v2: float = (p_l - (t3 - p_h)) * LG2 + t3 * LG2_L
	var z2 := u2 + v2
	var w2 := v2 - (z2 - u2)
	var t4 := z2 * z2
	var t5: float = z2 - t4 * (P1 + t4 * (P2 + t4 * (P3 + t4 * (P4 + t4 * P5))))
	var r2 := (z2 * t5) / (t5 - 2.0) - (w2 + z2 * w2)
	z2 = 1.0 - (r2 - z2)
	var j2 := _hi(z2) + (n2 << 20)
	if (j2 >> 20) <= 0:   # (a subnormal answer)
		return s * _scalbn(z2, n2)
	return s * _with_hi(z2, j2)


# x * 2^n by exact steps (only for answers too small to be normal numbers)
static func _scalbn(x: float, n: int) -> float:
	while n > 0:
		x *= 2.0
		n -= 1
	while n < 0:
		x *= 0.5
		n += 1
	return x
