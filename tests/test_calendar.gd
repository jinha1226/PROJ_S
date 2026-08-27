extends "res://tests/test_case.gd"

const WorldClock = preload("res://sim/world_clock.gd")


func test_abstract_minute_changes_on_100_unit_boundary() -> bool:
	check_eq(WorldClock.project(99).absolute_minute, 0, "before minute")
	check_eq(WorldClock.project(100).absolute_minute, 1, "at minute")
	check_eq(WorldClock.project(199).absolute_minute, 1, "inside minute")
	check_eq(WorldClock.project(200).absolute_minute, 2, "second minute")
	return finish()


func test_day_period_boundaries() -> bool:
	var unit_per_hour := 60 * 100
	for row in [[0, "NIGHT"], [5, "DAWN"], [7, "DAY"], [18, "DUSK"], [20, "NIGHT"]]:
		check_eq(WorldClock.project(row[0] * unit_per_hour).period_id, row[1],
			"period at %02d:00" % row[0])
	return finish()


func test_season_and_year_are_zero_based_projections() -> bool:
	var unit_per_day := 24 * 60 * 100
	var day14 = WorldClock.project(14 * unit_per_day)
	var day15 = WorldClock.project(15 * unit_per_day)
	var day59 = WorldClock.project(59 * unit_per_day)
	var day60 = WorldClock.project(60 * unit_per_day)
	check_eq([day14.season_index, day14.day_of_season], [0, 14], "last day season zero")
	check_eq([day15.season_index, day15.day_of_season], [1, 0], "season boundary")
	check_eq([day59.year_index, day59.season_index], [0, 3], "last season year zero")
	check_eq([day60.year_index, day60.season_index, day60.day_of_season], [1, 0, 0], "year boundary")
	return finish()
