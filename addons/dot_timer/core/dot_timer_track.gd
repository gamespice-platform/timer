class_name DotTimerTrack
extends RefCounted

## Which route through a map a run is on: 0 is the main track, 1 and up are bonuses. There is no
## upper limit: a map may have as many bonuses as it draws. 1..8 is only the community numbering.
## A namespace, not an object: a track is an [code]int[/code] everywhere, as a table column, wire field and array index.

## The main route. Every map has one.
const MAIN := 0

## The first bonus. Every track from here up is a bonus; there is no last one.
const BONUS_FIRST := 1

## The last bonus of the community numbering (1..8). Not a limit: tracks above it are valid,
## stored, replicated and shown like any other. Kept for games that list the usual tracks.
const BONUS_LAST := 8

## One past [constant BONUS_LAST]: the usual tracks, so a menu can read
## [code]for t in range(COUNT)[/code]. Not a limit; see [constant BONUS_LAST].
const COUNT := BONUS_LAST + 1

## Bits of the short wire field. Tracks 0..14 fit in it, exactly as before; [constant WIDE]
## in it means a [constant WIDE_BITS]-bit track follows. See [method write_wire].
const BITS := 4

## The short field's escape value.
const WIDE := (1 << BITS) - 1

## Bits of the long form, for a track of [constant WIDE] or more.
const WIDE_BITS := 31


static func is_valid(track: int) -> bool:
	return track >= MAIN and track < (1 << WIDE_BITS)


static func is_bonus(track: int) -> bool:
	return track >= BONUS_FIRST and is_valid(track)


## The bonus number a track is, or 0 for the main track.
static func bonus_number(track: int) -> int:
	return track if is_bonus(track) else 0


## A track id from a bonus number. [code]of_bonus(2)[/code] is bonus 2. Any number from 1 up;
## anything below 1 is an error and returns -1, never a clamped neighbour.
static func of_bonus(number: int) -> int:
	if number < BONUS_FIRST or not is_valid(number):
		push_error("DotTimerTrack.of_bonus: %d is not a bonus number (1 or more)" % number)
		return -1
	return number


## Writes [param track] to a GameSpice Net bit writer: [constant BITS] bits for 0..14 (the old field,
## unchanged on the wire), else the escape and then [constant WIDE_BITS] bits.
static func write_wire(writer: Variant, track: int) -> void:
	if track >= MAIN and track < WIDE:
		writer.write_uint(track, BITS)
		return
	if not is_valid(track):
		push_error("DotTimerTrack.write_wire: track %d is not a track; sending main" % track)
		writer.write_uint(MAIN, BITS)
		return
	writer.write_uint(WIDE, BITS)
	writer.write_uint(track, WIDE_BITS)


## Reads what [method write_wire] wrote.
static func read_wire(reader: Variant) -> int:
	var track: int = reader.read_uint(BITS)
	if track == WIDE:
		track = reader.read_uint(WIDE_BITS)
	return track


## Bits [method write_wire] spends on [param track].
static func wire_bits(track: int) -> int:
	return BITS if track >= MAIN and track < WIDE else BITS + WIDE_BITS


static func name_of(track: int) -> String:
	if track == MAIN:
		return "Main"
	if is_bonus(track):
		return "Bonus %d" % track
	return "Track %d" % track


## A short label for a HUD column or a chat tag.
static func short_name_of(track: int) -> String:
	if track == MAIN:
		return "main"
	if is_bonus(track):
		return "b%d" % track
	return "t%d" % track


## Parses "main", "bonus", "bonus 3", "b3", "2". [code]-1[/code] when it is none of those.
## -1 rather than falling back to main: a console typo would otherwise set a record on the wrong track.
static func parse(text: String) -> int:
	var cleaned := text.strip_edges().to_lower()

	if cleaned == "" or cleaned == "main" or cleaned == "0":
		return MAIN

	if cleaned == "bonus" or cleaned == "b":
		return BONUS_FIRST

	if cleaned.begins_with("bonus"):
		cleaned = cleaned.substr(5).strip_edges()
	elif cleaned.begins_with("b") and cleaned.length() > 1:
		cleaned = cleaned.substr(1).strip_edges()

	if not cleaned.is_valid_int():
		return -1

	var number := cleaned.to_int()

	return number if is_valid(number) else -1
