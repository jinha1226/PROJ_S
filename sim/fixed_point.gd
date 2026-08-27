class_name FixedPoint
extends RefCounted

const MIN_VALUE := -9223372036854775807


static func trunc_div(numerator: int, denominator: int) -> int:
	assert(denominator != 0)
	var quotient := absi(numerator) / absi(denominator)
	return -quotient if (numerator < 0) != (denominator < 0) else quotient


static func interpolate(x: int, x0: int, y0: int, x1: int, y1: int) -> int:
	assert(x1 > x0)
	return y0 + trunc_div((x - x0) * (y1 - y0), x1 - x0)


static func weighted_contribution(curve_output: int, signed_weight_milli: int) -> int:
	return trunc_div(curve_output * signed_weight_milli, 1000)
