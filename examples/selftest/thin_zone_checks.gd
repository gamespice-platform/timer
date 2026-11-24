extends "zone_rule_checks.gd"

## The hull-aware thin-zone advisory, a section of timer_selftest.gd, which extends this.


## [method GSTimerZoneSet.thin_zones] with a hull extent: kinds that fire on hull overlap are judged as that much thicker.
func _test_thin_zone_hull() -> void:
	_section("thin zones, hull-aware")

	var pit := GSTimerZoneSet.new()
	pit.add(GSTimerZone.make(GSTimerZone.Kind.RESPAWN).set_box(
		Vector3(-32.0, 0.0, -32.0), Vector3(32.0, 0.4, 32.0)
	))
	var wall := GSTimerZoneSet.new()
	wall.add(GSTimerZone.make(GSTimerZone.Kind.START).set_box(
		Vector3.ZERO, Vector3(0.05, 3.0, 3.0)
	))

	_check(
		pit.thin_zones(67.0, 60, 40.0, 0.0).size() == 1,
		"a zero hull extent changes nothing"
	)
	_check(
		pit.thin_zones(67.0, 60, 40.0, 0.61).is_empty(),
		"a 40 cm RESPAWN pit is not flagged once a 61 cm hull overlaps it (1.01 m > 0.67 m per tick)"
	)
	_check(
		pit.thin_zones(67.0, 60, 40.0, 0.1).size() == 1,
		"and is still flagged when the hull is too small to catch it"
	)
	_check(
		wall.thin_zones(30.0, 128, 0.0, 0.61).size() == 1,
		"a thin START zone is flagged whatever the hull: it is not a hull-overlap kind"
	)
	_done()
