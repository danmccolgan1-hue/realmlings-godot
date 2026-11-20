class_name SaveCodec
extends RefCounted
## Lossless JSON for game state: ints stay ints, floats keep every bit (stored as their 64-bit pattern, so a loaded
## game continues exactly as the saved one would have), Dictionaries keep their key types. Only plain data:
## null, bool, int, float, String/StringName, Array, Dictionary. Anything else is refused.
##
## Encoding: int -> JSON number (beyond 2^53: "i<digits>"); float -> "f<int64 bits>"; String -> "s<text>"; Array -> [..];
## Dictionary -> {"d": [[key, value], ...]}.


static func encode(v):
	match typeof(v):
		TYPE_NIL, TYPE_BOOL:
			return v
		TYPE_INT:   # JSON numbers are doubles: big ones go as text
			return v if absi(v) < 9007199254740992 else "i%d" % v
		TYPE_FLOAT:
			var b := PackedByteArray()
			b.resize(8)
			b.encode_double(0, v)
			return "f%d" % b.decode_s64(0)
		TYPE_STRING, TYPE_STRING_NAME:
			return "s" + str(v)
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var out := []
			for x in v:
				out.append(encode(x))
			return out
		TYPE_DICTIONARY:
			var pairs := []
			for k in v:
				pairs.append([encode(k), encode(v[k])])
			return {"d": pairs}
	push_error("SaveCodec: can't save a value of type %s" % type_string(typeof(v)))
	return null


static func decode(v):
	match typeof(v):
		TYPE_NIL, TYPE_BOOL:
			return v
		TYPE_INT, TYPE_FLOAT:   # JSON numbers are always our ints
			return int(v)
		TYPE_STRING:
			if v.begins_with("f"):
				var b := PackedByteArray()
				b.resize(8)
				b.encode_s64(0, int(v.substr(1)))
				return b.decode_double(0)
			if v.begins_with("i"):
				return int(v.substr(1))
			return v.substr(1)
		TYPE_ARRAY:
			var out := []
			for x in v:
				out.append(decode(x))
			return out
		TYPE_DICTIONARY:
			var d := {}
			for kv in v.get("d", []):
				d[decode(kv[0])] = decode(kv[1])
			return d
	return null


static func to_text(v) -> String:
	return JSON.stringify(encode(v))


static func from_text(text: String):
	var j = JSON.parse_string(text)
	return null if j == null else decode(j)
