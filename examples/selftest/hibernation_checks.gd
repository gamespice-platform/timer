extends "replay_checks.gd"

## The hibernation section of timer_selftest.gd, split out to keep that file under the size gate.


func _test_hibernation() -> void:
	_section("engine rate follows hibernation")

	var manager := GSTimerManager.new()
	var guard := manager.rate_guard
	var server := _HibernatingServer.new()
	_check(not guard.follow_hibernation(null, manager), "following nothing is refused")
	_check(guard.follow_hibernation(server, manager), "a server with the signal is followed")
	_check(not guard.hibernating, "awake to begin with")
	server.hibernating = true
	server.hibernation_changed.emit(true)
	_check(guard.hibernating, "the signal puts the guard to sleep")
	server.hibernating = false
	server.hibernation_changed.emit(false)
	_check(not guard.hibernating, "and wakes it")
	_check(guard.follow_hibernation(server, manager), "following twice is harmless")
	_check(server.hibernation_changed.get_connections().size() == 1, "and connects once")

	# Asleep, a disagreeing engine is expected: nothing is timed until the server wakes.
	Engine.physics_ticks_per_second = manager.tick_rate + 7
	_check(not manager.tick_rate_matches_engine(), "an engine at another rate disagrees")
	Engine.physics_ticks_per_second = manager.tick_rate
	manager.free()
	_done()


class _HibernatingServer extends RefCounted:
	signal hibernation_changed(hibernating: bool)
	var hibernating: bool = false


	func is_hibernating() -> bool:
		return hibernating
