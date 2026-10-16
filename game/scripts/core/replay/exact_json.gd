class_name ExactJson
extends RefCounted

# Godot's JSON decimal parser can lose one bit even with full_precision output.
# Encode IEEE754 bytes explicitly; never deserialize Variant objects/resources.
const FLOAT_TAG := "$f64"
const MAX_DEPTH := 32

static func encode(value: Variant, depth := 0) -> Variant:
	if depth > MAX_DEPTH:
		return null
	if value is float:
		if not is_finite(value):
			return null
		var bytes := PackedByteArray()
		bytes.resize(8)
		bytes.encode_double(0, value)
		return {FLOAT_TAG: bytes.hex_encode()}
	if value is Array:
		var result := []
		for item in value:
			var encoded: Variant = encode(item, depth + 1)
			if encoded == null:
				return null
			result.append(encoded)
		return result
	if value is Dictionary:
		if value.has(FLOAT_TAG):
			return null
		var result := {}
		for key in value:
			var encoded: Variant = encode(value[key], depth + 1)
			if encoded == null:
				return null
			result[key] = encoded
		return result
	if value is String or value is int or value is bool:
		return value
	return null

static func decode(value: Variant, depth := 0) -> Variant:
	if depth > MAX_DEPTH:
		return null
	if value is Dictionary:
		if value.has(FLOAT_TAG):
			var hex: Variant = value[FLOAT_TAG]
			if value.size() != 1 or not hex is String or hex.length() != 16:
				return null
			for character in hex:
				if not character in "0123456789abcdef":
					return null
			var bytes: PackedByteArray = hex.hex_decode()
			var number := bytes.decode_double(0)
			return number if is_finite(number) else null
		var result := {}
		for key in value:
			var decoded: Variant = decode(value[key], depth + 1)
			if decoded == null:
				return null
			result[key] = decoded
		return result
	if value is Array:
		var result := []
		for item in value:
			var decoded: Variant = decode(item, depth + 1)
			if decoded == null:
				return null
			result.append(decoded)
		return result
	if value is String or value is int or value is bool:
		return value
	if value is float and is_finite(value):
		return value
	return null
