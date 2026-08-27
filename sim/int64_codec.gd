class_name Int64Codec
extends RefCounted

const POSITIVE_LIMIT := "9223372036854775807"
const NEGATIVE_MAGNITUDE_LIMIT := "9223372036854775808"


static func is_canonical(value: Variant) -> bool:
	if not (value is String) or value.is_empty():
		return false
	var negative: bool = value.begins_with("-")
	var digits: String = value.substr(1) if negative else value
	if digits.is_empty() or (digits != "0" and digits.begins_with("0")):
		return false
	if negative and digits == "0":
		return false
	for index in range(digits.length()):
		var code := digits.unicode_at(index)
		if code < 48 or code > 57:
			return false
	var limit := NEGATIVE_MAGNITUDE_LIMIT if negative else POSITIVE_LIMIT
	return digits.length() < limit.length() or (digits.length() == limit.length() and digits <= limit)


static func parse(value: Variant, label: String) -> int:
	assert(is_canonical(value), "%s must be a canonical signed 64-bit decimal string" % label)
	return int(value)
