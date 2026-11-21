extends "replay_checks.gd"

## The zone, checkpoint, rules, points and time-formatting sections of timer_selftest.gd,
## which extends this.


func _test_zone_geometry() -> void:
	_section("zone geometry")

	var box := GSTimerZone.make(GSTimerZone.Kind.START)
	box.set_box(Vector3(4.0, 0.0, 4.0), Vector3(0.0, -2.0, 0.0))

	_check(
		box.from == Vector3(0.0, -2.0, 0.0) and box.to == Vector3(4.0, 0.0, 4.0),
		"set_box normalises the corners whichever way round they are given",
		"%s .. %s" % [str(box.from), str(box.to)]
	)
	_check(box.contains(Vector3(2.0, -1.0, 2.0)), "and contains a point inside")
	_check(not box.contains(Vector3(5.0, -1.0, 2.0)), "and not one outside")

	# Half-open on the upper bound, so two zones sharing a face do not both fire.
	_check(box.contains(Vector3(0.0, -2.0, 0.0)), "the lower corner is inside")
	_check(not box.contains(Vector3(4.0, 0.0, 4.0)), "the upper corner is not")

	_check_near(
		box.signed_distance(Vector3(6.0, -1.0, 2.0)), 2.0, 0.0001,
		"the signed distance outside is the gap"
	)
	_check(
		box.signed_distance(Vector3(2.0, -1.0, 2.0)) < 0.0,
		"and is negative inside"
	)

	var sphere := GSTimerZone.make(GSTimerZone.Kind.END)
	sphere.set_sphere(Vector3(10.0, 0.0, 0.0), 3.0)

	_check(sphere.contains(Vector3(12.0, 0.0, 0.0)), "a sphere contains a near point")
	_check(not sphere.contains(Vector3(14.0, 0.0, 0.0)), "and not a far one")
	_check_near(
		sphere.signed_distance(Vector3(15.0, 0.0, 0.0)), 2.0, 0.0001,
		"and its signed distance is exact"
	)

	# A 2D zone is one whose third axis is unbounded, which is the one thing a 2D
	# game has to get right and the one place it is easy to get wrong.
	var flat := GSTimerZone.make(GSTimerZone.Kind.START)
	flat.set_box(Vector3(0.0, 0.0, 0.0), Vector3(10.0, 10.0, 0.0))

	_check(
		not flat.contains(Vector3(5.0, 5.0, 0.0)),
		"a zero-thickness box contains nothing, which is the 2D trap"
	)

	flat.flatten_for_2d()

	_check(
		flat.contains(Vector3(5.0, 5.0, 0.0)),
		"and flatten_for_2d is what fixes it"
	)
	_done()


func _test_zone_set_round_trip() -> void:
	_section("zone sets survive JSON")

	var set := _corridor()
	set.meta["tier"] = 4

	var parsed := GSTimerZoneSet.from_json(set.to_json())

	_check(parsed.ok, "a zone set round-trips through JSON",
		parsed.error.message if not parsed.ok else "")

	if not parsed.ok:
		return

	var back: GSTimerZoneSet = parsed.value

	_check(back.zones.size() == set.zones.size(), "with every zone")
	_check(back.map_id == set.map_id, "and the map id")
	_check(int(back.meta.get("tier", 0)) == 4, "and the metadata")
	_check(
		back.fingerprint() == set.fingerprint(),
		"and the same fingerprint",
		"%s vs %s" % [back.fingerprint(), set.fingerprint()]
	)

	# The fingerprint is what a records table is keyed against, so it must ignore a
	# comment and must not ignore a moved finish line.
	var commented := _corridor()
	commented.zones[0].comment = "the start"

	_check(
		commented.fingerprint() == _corridor().fingerprint(),
		"a mapper's comment does not change the fingerprint"
	)

	var moved := _corridor()
	moved.zones[1].from.x += 1.0

	_check(
		moved.fingerprint() != _corridor().fingerprint(),
		"but moving the finish line does"
	)

	var newer := GSTimerZoneSet.from_dictionary({"format": 999, "zones": []})
	_check(not newer.ok, "a file from a newer format is refused")
	_done()


func _test_zone_index() -> void:
	_section("the zone index")

	var set := _corridor()
	var index := GSTimerZoneIndex.of(set)

	var found: Array[GSTimerZone] = []

	index.zones_at(Vector3(2.0, 0.0, 0.0), found)
	_check(found.size() == 1, "a point in the start finds one zone", str(found.size()))
	_check(
		found.size() == 1 and found[0].kind == GSTimerZone.Kind.START,
		"and it is the start"
	)

	index.zones_at(Vector3(50.0, 0.0, 0.0), found)
	_check(found.is_empty(), "a point in open corridor finds none")

	index.zones_at(Vector3(98.0, 0.0, 0.0), found)
	_check(
		found.size() == 1 and found[0].kind == GSTimerZone.Kind.END,
		"and a point in the finish finds the finish"
	)

	# A map-wide volume goes on the "always test" list rather than into a hundred
	# thousand cells.
	var wide := _corridor()
	var gravity := GSTimerZone.make(GSTimerZone.Kind.GRAVITY)
	gravity.number = 0.5
	gravity.set_box(Vector3(-5000.0, -5000.0, -5000.0), Vector3(5000.0, 5000.0, 5000.0))
	wide.add(gravity)

	var wide_index := GSTimerZoneIndex.of(wide)
	wide_index.zones_at(Vector3(50.0, 0.0, 0.0), found)

	_check(found.size() == 1, "a map-wide zone is still found in open space")
	_check(
		int(wide_index.describe()["everywhere"]) == 1,
		"without being written into every cell"
	)
	_done()


func _test_checkpoints() -> void:
	_section("practice checkpoints")

	var style := GSTimerStyle.new()
	style.minimum_time = 0.0
	style.allow_checkpoints = true

	var timer := GSTimer.new()
	timer.authoritative = true
	timer.bind(_corridor(), 128)
	timer.style = style

	var sample := GSTimerSample.new()
	sample.grounded = true

	for i in range(1400):
		sample.position = Vector3(2.0 + float(i) * 0.1, 0.0, 0.0)
		sample.velocity = Vector3(12.8, 0.0, 0.0)

		if i == 200:
			timer.note_checkpoint_used()

		timer.tick(sample)

	_check(timer.runs_finished == 1, "the run finishes")
	_check(timer.run.used_checkpoints, "and is flagged as having used a checkpoint")
	_check(
		timer.can_record(timer.run).ok,
		"and a style that allows them files it, flagged"
	)

	# On a style that does not allow them at all, using one abandons the run rather
	# than timing four more minutes that can never be filed.
	style.allow_checkpoints = false

	var strict := GSTimer.new()
	strict.authoritative = true
	strict.bind(_corridor(), 128)
	strict.style = style

	var sample2 := GSTimerSample.new()
	sample2.grounded = true

	for i in range(400):
		sample2.position = Vector3(2.0 + float(i) * 0.1, 0.0, 0.0)
		sample2.velocity = Vector3(12.8, 0.0, 0.0)

		if i == 100:
			strict.note_checkpoint_used()

		strict.tick(sample2)

	_check(
		strict.runs_finished == 0,
		"a style that forbids them abandons the run instead"
	)
	_done()


func _test_effect_zones() -> void:
	_section("effect zones")

	var set := _corridor()

	var gravity := GSTimerZone.make(GSTimerZone.Kind.GRAVITY)
	gravity.number = 0.4
	gravity.set_box(Vector3(20.0, -2.0, -4.0), Vector3(40.0, 8.0, 4.0))
	set.add(gravity)

	var no_jump := GSTimerZone.make(GSTimerZone.Kind.NO_JUMP)
	no_jump.set_box(Vector3(60.0, -2.0, -4.0), Vector3(70.0, 8.0, 4.0))
	set.add(no_jump)

	var timer := GSTimer.new()
	timer.bind(set, 128)

	var changes := [0]
	timer.effects_changed.connect(func() -> void: changes[0] += 1)

	var sample := GSTimerSample.new()
	sample.grounded = true

	var seen_gravity := false
	var seen_no_jump := false
	var both_at_once := false

	for i in range(1100):
		sample.position = Vector3(-2.0 + float(i) * 0.1, 0.0, 0.0)
		sample.velocity = Vector3(12.8, 0.0, 0.0)
		timer.tick(sample)

		if timer.is_inside(GSTimerZone.Kind.GRAVITY):
			seen_gravity = true
			if timer.is_inside(GSTimerZone.Kind.NO_JUMP):
				both_at_once = true

		if timer.is_inside(GSTimerZone.Kind.NO_JUMP):
			seen_no_jump = true

	_check(seen_gravity, "the gravity zone comes into force")
	_check(seen_no_jump, "and so does the no-jump zone")
	_check(not both_at_once, "and they do not overlap, as drawn")
	_check(changes[0] == 4, "four changes: two entries and two exits", "%d" % changes[0])
	_check(
		timer.active_effects().is_empty(),
		"and nothing is in force at the end of the corridor"
	)
	_done()


func _test_rules() -> void:
	_section("velocity rules")

	var fast := Vector3(30.0, -10.0, 40.0)
	var clamped := GSTimerRules.clamp_prespeed(fast, 25.0)

	_check_near(
		Vector2(clamped.x, clamped.z).length(), 25.0, 0.001,
		"prespeed caps the horizontal speed"
	)
	_check_near(
		clamped.y, -10.0, 0.0001,
		"and leaves the fall alone, or a player dropping in would hang in the air"
	)

	_check(
		GSTimerRules.clamp_prespeed(fast, 0.0) == fast,
		"a limit of zero does nothing"
	)
	_check(
		GSTimerRules.clamp_prespeed(Vector3(1.0, 0.0, 0.0), 25.0)
			== Vector3(1.0, 0.0, 0.0),
		"and a slow player is untouched"
	)

	var flat := GSTimerRules.clamp_prespeed_2d(Vector3(30.0, 40.0, 7.0), 25.0)
	_check_near(
		Vector2(flat.x, flat.y).length(), 25.0, 0.001,
		"the 2D form caps the XY plane instead"
	)

	var push_zone := GSTimerZone.make(GSTimerZone.Kind.PUSH)
	push_zone.direction = Vector3(0.0, 100.0, 0.0)

	var pushed := GSTimerRules.apply_push(Vector3.ZERO, push_zone, 1.0 / 128.0)
	_check_near(pushed.y, 100.0 / 128.0, 0.0001, "a push adds acceleration for a tick")

	_check(
		GSTimerRules.may_start(true, true, false),
		"a grounded living player may start"
	)
	_check(
		not GSTimerRules.may_start(false, true, false),
		"an airborne one may not, unless the style allows it"
	)
	_check(
		not GSTimerRules.may_start(true, false, true),
		"and a dead one never may"
	)
	_done()


func _test_points() -> void:
	_section("ranking points")

	var style := GSTimerStyle.new()

	var tier1 := style.points_for(60.0, 1, 60.0)
	var tier10 := style.points_for(60.0, 10, 60.0)

	_check(
		tier10 > tier1 * 20.0,
		"a tier 10 map is worth far more than twenty tier 1 maps' worth of one run",
		"%.1f vs %.1f" % [tier10, tier1]
	)

	var record := style.points_for(30.0, 5, 30.0)
	var double := style.points_for(60.0, 5, 30.0)

	_check(record > double, "the record scores more than twice its time")
	_check(
		double > record * 0.5,
		"but a slow completion is still worth well over half",
		"%.1f vs %.1f" % [double, record]
	)

	var far := style.points_for(3000.0, 5, 30.0)
	_check(far > 0.0, "and an appalling one is still worth something", "%.2f" % far)

	style.ranked = false
	_check(style.points_for(30.0, 5, 30.0) == 0.0, "an unranked style scores nothing")

	style.ranked = true
	style.points_multiplier = 2.0
	_check_near(
		style.points_for(30.0, 5, 30.0), record * 2.0, 0.001,
		"and the multiplier scales it"
	)

	_check_near(
		style.minimum_time_for(GSTimerTrack.MAIN), 3.5, 0.001,
		"the main-track floor is the long one"
	)
	_check_near(
		style.minimum_time_for(GSTimerTrack.of_bonus(1)), 0.5, 0.001,
		"and a bonus has its own"
	)
	_done()


func _test_time_formatting() -> void:
	_section("time formatting")

	_check(GSTimerRun.format_time(0.0) == "0:00.000", "zero")
	_check(GSTimerRun.format_time(9.2) == "0:09.200", "under a minute")
	_check(GSTimerRun.format_time(83.456) == "1:23.456", "over a minute")
	_check(GSTimerRun.format_time(3723.5) == "1:02:03.500", "over an hour")

	_check(
		GSTimerRun.format_time(-1.25, true) == "-0:01.250",
		"a negative split reads as ahead"
	)
	_check(
		GSTimerRun.format_time(1.25, true) == "+0:01.250",
		"and a positive one as behind"
	)

	# Three decimals, always: these leaderboards are decided by thousandths, and a
	# display that rounded to two would make ties out of runs that were not tied.
	_check(
		GSTimerRun.format_time(9.2001) != GSTimerRun.format_time(9.2011),
		"a millisecond is visible"
	)
	_done()
