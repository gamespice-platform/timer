class_name GSTimerEngineRateGuard
extends RefCounted

## Warns when an authoritative timer counts at a rate other than the engine's, except while the server hibernates.
## An empty GameSpice Server idles the engine at its `hibernate_tickrate` (a few Hz) on purpose and restores the rate on waking, so a map change then must not claim every time will be wrong. Follow the server with [method follow_hibernation] (or call [method set_hibernating]); waking runs the check once.

const CHANNEL := "timer.manager"

## True while the server idles an empty room at a reduced physics rate.
var hibernating: bool = false


## Logs the warning when [param manager] is authoritative, awake and disagrees with the engine. A MIRRORING timer counts at the rate the server told it by design, so a warning there would be false.
func check(manager: GSTimerManager) -> void:
	if not manager.authoritative or hibernating or manager.tick_rate_matches_engine():
		return

	GSLog.warn(
		CHANNEL,
		"the timer's tick rate does not match the engine's physics rate; "
		+ "every time this server files will be wrong by their ratio",
		{"timer": manager.tick_rate, "engine": Engine.physics_ticks_per_second}
	)


## Tells the guard its server is hibernating (true) or awake (false). On waking, runs [method check] for [param manager] so a real disagreement is still reported once somebody can be timed.
func set_hibernating(on: bool, manager: GSTimerManager = null) -> void:
	if on == hibernating:
		return

	hibernating = on

	if not on and manager != null:
		check(manager)


## Follows a server's hibernation from its `hibernation_changed(bool)` signal and its current state. Duck-typed (no GameSpice Server names); returns false if the object has no such signal. Safe to call twice.
func follow_hibernation(server: Object, manager: GSTimerManager = null) -> bool:
	if server == null or not server.has_signal("hibernation_changed"):
		return false

	var on_change := set_hibernating.bind(manager) if manager != null else set_hibernating

	if not server.is_connected("hibernation_changed", on_change):
		server.connect("hibernation_changed", on_change)

	if server.has_method("is_hibernating"):
		set_hibernating(bool(server.call("is_hibernating")), manager)

	return true
