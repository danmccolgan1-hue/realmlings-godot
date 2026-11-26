extends RefCounted
## Multiplayer stays in step only if every copy of the game calculates the same numbers, on any computer
## (scripts/core/dmath.gd): the rules never call the operating system's sin, cos, atan2, exp or pow, and DMath gives
## exactly the known answers (sin, cos, atan2, exp: V8's own; pow: fdlibm's), bit for bit.

## [function, x hi, x lo, y hi, y lo, answer hi, answer lo]
const KNOWN := [
	["sin", 1069128089, 2576980378, 0, 0, 1069125294, 3414936364],
	["cos", 1069128089, 2576980378, 0, 0, 1072682770, 4188542912],
	["sin", 1072693248, 0, 0, 0, 1072360788, 2399735022],
	["cos", 1072693248, 0, 0, 0, 1071729192, 263521932],
	["sin", 1073741824, 0, 0, 0, 1072503030, 3939611718],
	["cos", 1073741824, 0, 0, 0, 3218776614, 1465086469],
	["sin", 1074528256, 0, 0, 0, 3218502459, 2126144031],
	["cos", 1074528256, 0, 0, 0, 3220043636, 62986847],
	["sin", 3223126016, 0, 0, 0, 3219805869, 3056215993],
	["cos", 3223126016, 0, 0, 0, 1071787119, 1356611518],
	["sin", 1079582720, 0, 0, 0, 3214914552, 860295153],
	["cos", 1079582720, 0, 0, 0, 1072692242, 2913914562],
	["sin", 1086856406, 3367254360, 0, 0, 3219556309, 2299098277],
	["cos", 1086856406, 3367254360, 0, 0, 1072085324, 1002316984],
	["sin", 1093567616, 0, 0, 0, 3218499147, 627628135],
	["cos", 1093567616, 0, 0, 0, 1072560607, 2567361324],
	["sin", 3241599840, 0, 0, 0, 3219151385, 4190079852],
	["cos", 3241599840, 0, 0, 0, 3219882417, 50453174],
	["sin", 1072243195, 1413754136, 0, 0, 1072079006, 1719614412],
	["cos", 1072243195, 1413754136, 0, 0, 1072079006, 1719614413],
	["sin", 1074340347, 1413754136, 0, 0, 1017226790, 856972295],
	["cos", 1074340347, 1413754136, 0, 0, 3220176896, 0],
	["atan2", 1072693248, 0, 1073741824, 0, 1071492199, 90291023],
	["atan2", 3221749760, 0, 1074790400, 0, 3219429263, 2737217249],
	["atan2", 1075052544, 0, 3222798336, 0, 1073976104, 1665651318],
	["atan2", 3223060480, 0, 3223322624, 0, 3221447121, 1659247499],
	["atan2", 1062232653, 3539053052, 1083129856, 0, 1051772663, 2696275815],
	["atan2", 1083129856, 0, 1062232653, 3539053052, 1073291770, 1205121805],
	["atan2", 0, 0, 3220176896, 0, 1074340347, 1413754136],
	["atan2", 2147483648, 0, 3220176896, 0, 3221823995, 1413754136],
	["exp", 3224633344, 0, 0, 0, 1042396294, 1442017895],
	["exp", 3220176896, 0, 0, 0, 1071090518, 908914488],
	["exp", 3218289459, 858993459, 0, 0, 1072149704, 1774418949],
	["exp", 1070176665, 2576980378, 0, 0, 1072925405, 2656611469],
	["exp", 1072693248, 0, 0, 0, 1074118410, 2333366121],
	["exp", 1075183616, 0, 0, 0, 1080989220, 1327610870],
	["exp", 1077805056, 0, 0, 0, 1118007367, 183249133],
	["exp", 1082515456, 0, 0, 0, 2131596381, 4109954190],
	["pow", 1072798105, 2576980378, 1075576832, 0, 1073688049, 4217011927],
	["pow", 1072588390, 1717986918, 1076363264, 0, 1071729313, 1024615446],
	["pow", 1072745676, 3435973837, 1074266112, 0, 1072858529, 3401614099],
	["pow", 1071099412, 2061584302, 1073563566, 343597384, 1069858819, 881560161],
	["pow", 1074003968, 0, 3221880832, 0, 1068109622, 3804311454],
	["pow", 1072273817, 2576980378, 1071644672, 900719925, 1072471845, 3137919039],
	["pow", 1075576832, 0, 1069547520, 0, 1072981997, 2709682886]
]


func run() -> Array:
	var errs := []
	var b := PackedByteArray()
	b.resize(8)
	var mk := func(h, l):
		b.encode_u32(4, int(h))
		b.encode_u32(0, int(l))
		return b.decode_double(0)
	for c in KNOWN:
		var x: float = mk.call(c[1], c[2])
		var y: float = mk.call(c[3], c[4])
		var want: float = mk.call(c[5], c[6])
		var got: float
		match str(c[0]):
			"sin": got = DMath.sin(x)
			"cos": got = DMath.cos(x)
			"atan2": got = DMath.atan2(x, y)
			"exp": got = DMath.exp(x)
			_: got = DMath.pow(x, y)
		if var_to_bytes(got) != var_to_bytes(want):
			errs.append("dmath: %s(%s, %s) = %s, want %s (bit for bit)" % [c[0], x, y, got, want])
	# the rules use only DMath for these (a plain sin() would let a Windows player and a Linux server drift apart)
	var re := RegEx.new()
	re.compile("(?<![\\w.])(sin|cos|tan|asin|acos|atan|atan2|pow|exp|log|sinh|cosh|tanh)\\(")
	for dir in ["res://scripts/sim/", "res://scripts/gen/", "res://scripts/core/"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd") or f == "dmath.gd":
				continue
			var lines := FileAccess.get_file_as_string(dir + f).split("\n")
			for i in lines.size():
				var ln: String = lines[i].strip_edges()
				if ln.begins_with("#") or ln.begins_with("func ") or ln.begins_with("static func "):
					continue
				var m := re.search(ln.split("#")[0] if not ln.contains("\"") else ln)
				if m != null:
					errs.append("dmath: %s%s:%d calls %s() from the system's maths library: use DMath.%s()" % [dir, f, i + 1, m.get_string(1), m.get_string(1)])
	return errs
