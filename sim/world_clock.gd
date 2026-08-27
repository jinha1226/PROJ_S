class_name WorldClock
extends RefCounted

const RULESET_ID := "abstract-calendar-v1"
const TIME_UNITS_PER_ABSTRACT_MINUTE := 100
const MINUTES_PER_HOUR := 60
const HOURS_PER_DAY := 24
const DAYS_PER_SEASON := 15
const SEASONS_PER_YEAR := 4


static func project(world_time: int) -> Dictionary:
	assert(world_time >= 0, "World time must be non-negative")
	var absolute_minute: int = world_time / TIME_UNITS_PER_ABSTRACT_MINUTE
	var minute_of_hour: int = absolute_minute % MINUTES_PER_HOUR
	var absolute_hour: int = absolute_minute / MINUTES_PER_HOUR
	var hour_of_day: int = absolute_hour % HOURS_PER_DAY
	var day_index: int = absolute_hour / HOURS_PER_DAY
	var day_of_season: int = day_index % DAYS_PER_SEASON
	var absolute_season: int = day_index / DAYS_PER_SEASON
	var season_index: int = absolute_season % SEASONS_PER_YEAR
	var year_index: int = absolute_season / SEASONS_PER_YEAR
	return {
		"absolute_minute": absolute_minute,
		"minute_of_hour": minute_of_hour,
		"hour_of_day": hour_of_day,
		"day_index": day_index,
		"day_of_season": day_of_season,
		"season_index": season_index,
		"year_index": year_index,
		"period_id": _period_for_hour(hour_of_day),
	}


static func _period_for_hour(hour: int) -> String:
	if hour >= 5 and hour < 7:
		return "DAWN"
	if hour >= 7 and hour < 18:
		return "DAY"
	if hour >= 18 and hour < 20:
		return "DUSK"
	return "NIGHT"
