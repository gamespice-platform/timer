class_name GSTimerStoreMemory
extends GSTimerStore

## Records in dictionaries. For tests, a scratch server, and as the reference implementation of the interface.
## The board index is kept sorted on write, not on read: boards are read far more often than written.

## board key -> player id -> record.
var _rows: Dictionary = {}

## board key -> sorted array of records, fastest first.
var _boards: Dictionary = {}

## Newest last. Bounded by [constant GSTimerStore.HISTORY_LIMIT].
var _history: Array[Dictionary] = []

## player id -> {player, name, points, first_seen, last_seen, playtime}.
var _players: Dictionary = {}

## map id -> info dictionary.
var _maps: Dictionary = {}

## "player|board" -> {attempts, completions, time_spent, time_to_first}.
var _progress: Dictionary = {}

## "player|map" -> state.
var _resume: Dictionary = {}


static func _key(
	map_id: StringName, track: int, style_id: StringName, stage: int = 0
) -> String:
	return GSTimerRecord.board_key_of(map_id, track, style_id, stage)



func put(record: GSTimerRecord) -> GSResult:
	if record == null:
		return GSResult.fail(GSError.CODE_INVALID, "No record to store.")

	var board := record.board_key()

	if not _rows.has(board):
		_rows[board] = {}
		_boards[board] = []

	var by_player: Dictionary = _rows[board]
	var board_rows: Array = _boards[board]

	var previous_value: Variant = by_player.get(record.player_id)
	var previous: GSTimerRecord = previous_value if previous_value is GSTimerRecord else null
	var leader: GSTimerRecord = board_rows[0] if not board_rows.is_empty() else null

	var completions := (previous.completions if previous != null else 0) + 1

	if not record.beats(previous):
		# Not an error. Most finished runs are slower than the player's own best; the
		# row stays and only its count moves.
		previous.completions = completions
		return GSResult.success(_put_result(previous, false, leader, completions))

	# Copied in, so a caller that keeps the record it filed cannot change the stored one.
	var stored := record.duplicate_record()
	stored.completions = completions
	record.completions = completions
	by_player[record.player_id] = stored

	if previous != null:
		board_rows.erase(previous)

	board_rows.append(stored)
	GSTimerRecord.sort_fastest_first(board_rows)

	_remember(stored, previous, leader)

	return GSResult.success(_put_result(previous, true, leader, completions))


func _put_result(
	previous: GSTimerRecord, improved: bool, leader: GSTimerRecord, completions: int
) -> Dictionary:
	return {
		"previous": previous.duplicate_record() if previous != null else null,
		"improved": improved,
		"previous_record": leader.duplicate_record() if leader != null else null,
		"completions": completions,
	}


func _remember(
	stored: GSTimerRecord, previous: GSTimerRecord, leader: GSTimerRecord
) -> void:
	_history.append({
		"record": stored.duplicate_record(),
		"previous_time": previous.time if previous != null else -1.0,
		"previous_record_time": leader.time if leader != null else -1.0,
		"was_record": leader == null or stored.time < leader.time
			or (leader.player_id == stored.player_id),
	})
	if _history.size() > HISTORY_LIMIT:
		_history = _history.slice(_history.size() - HISTORY_LIMIT)


func top(
	map_id: StringName, track: int, style_id: StringName,
	limit: int = 10, offset: int = 0, stage: int = 0
) -> GSResult:
	var rows := _board(map_id, track, style_id, stage)
	var out: Array[GSTimerRecord] = []

	for i in range(maxi(offset, 0), mini(offset + limit, rows.size())):
		out.append((rows[i] as GSTimerRecord).duplicate_record())

	return GSResult.success(out)


func best_for(
	map_id: StringName, track: int, style_id: StringName,
	player_id: StringName, stage: int = 0
) -> GSResult:
	var found: Variant = _row(map_id, track, style_id, player_id, stage)
	return GSResult.success(
		(found as GSTimerRecord).duplicate_record() if found is GSTimerRecord else null
	)


func rank_of(
	map_id: StringName, track: int, style_id: StringName,
	player_id: StringName, stage: int = 0
) -> GSResult:
	var found: Variant = _row(map_id, track, style_id, player_id, stage)

	if not (found is GSTimerRecord):
		return GSResult.success(0)

	return GSResult.success(_faster_than(map_id, track, style_id, (found as GSTimerRecord).time, stage) + 1)


func rank_for_time(
	map_id: StringName, track: int, style_id: StringName,
	time: float, stage: int = 0
) -> GSResult:
	return GSResult.success(_faster_than(map_id, track, style_id, time, stage) + 1)


func _faster_than(
	map_id: StringName, track: int, style_id: StringName, time: float, stage: int
) -> int:
	var count := 0
	for record in _board(map_id, track, style_id, stage):
		if (record as GSTimerRecord).time < time:
			count += 1
		else:
			break
	return count


func count_on(
	map_id: StringName, track: int, style_id: StringName, stage: int = 0
) -> GSResult:
	return GSResult.success(_board(map_id, track, style_id, stage).size())


func remove(
	map_id: StringName, track: int, style_id: StringName,
	player_id: StringName, stage: int = 0
) -> GSResult:
	var board := _key(map_id, track, style_id, stage)
	var by_player: Dictionary = _rows.get(board, {})
	var found: Variant = by_player.get(player_id)

	if not (found is GSTimerRecord):
		return GSResult.success(false)

	by_player.erase(player_id)
	(_boards[board] as Array).erase(found)

	return GSResult.success(true)


func set_points(records: Array) -> GSResult:
	var updated := 0
	for record in records:
		if not (record is GSTimerRecord):
			continue
		var found: Variant = _row(
			record.map_id, record.track, record.style_id, record.player_id, record.stage
		)
		if found is GSTimerRecord:
			(found as GSTimerRecord).points = (record as GSTimerRecord).points
			updated += 1
	return GSResult.success(updated)


func records_of(player_id: StringName, filter: Dictionary = {}) -> GSResult:
	var out: Array[GSTimerRecord] = []
	for board in _rows:
		var found: Variant = (_rows[board] as Dictionary).get(player_id)
		if found is GSTimerRecord and _matches(found, filter):
			out.append((found as GSTimerRecord).duplicate_record())
	return GSResult.success(out)


func records_on_map(map_id: StringName) -> GSResult:
	var out: Array[GSTimerRecord] = []
	for board in _boards:
		for record in (_boards[board] as Array):
			if (record as GSTimerRecord).map_id == map_id:
				out.append((record as GSTimerRecord).duplicate_record())
	return GSResult.success(out)


func record_count(player_id: StringName, filter: Dictionary = {}) -> GSResult:
	var count := 0
	for board in _boards:
		var rows: Array = _boards[board]
		if rows.is_empty() or not _matches(rows[0], filter):
			continue
		var best_time: float = (rows[0] as GSTimerRecord).time
		for record in rows:
			if (record as GSTimerRecord).time > best_time:
				break
			if (record as GSTimerRecord).player_id == player_id:
				count += 1
				break
	return GSResult.success(count)


func recent(limit: int = 20, filter: Dictionary = {}) -> GSResult:
	var records_only := bool(filter.get("records_only", true))
	var out: Array[Dictionary] = []
	for i in range(_history.size() - 1, -1, -1):
		if out.size() >= limit:
			break
		var entry: Dictionary = _history[i]
		if records_only and not bool(entry["was_record"]):
			continue
		if not _matches(entry["record"], filter):
			continue
		var copy := entry.duplicate()
		copy["record"] = (entry["record"] as GSTimerRecord).duplicate_record()
		out.append(copy)
	return GSResult.success(out)


## Whether a record passes a [method records_of] / [method recent] filter.
static func _matches(record: GSTimerRecord, filter: Dictionary) -> bool:
	if filter.has("map") and record.map_id != StringName(str(filter["map"])):
		return false
	if filter.has("track") and record.track != int(filter["track"]):
		return false
	if filter.has("style") and record.style_id != StringName(str(filter["style"])):
		return false
	var stage := int(filter.get("stage", 0))
	if stage >= 0 and record.stage != stage:
		return false
	return true


func wipe_board(
	map_id: StringName, track: int, style_id: StringName, stage: int = -1
) -> GSResult:
	var removed := 0
	for board in _boards.keys():
		var rows: Array = _boards[board]
		if rows.is_empty():
			continue
		var sample: GSTimerRecord = rows[0]
		if sample.map_id != map_id or sample.track != track or sample.style_id != style_id:
			continue
		if stage >= 0 and sample.stage != stage:
			continue
		removed += rows.size()
		_boards.erase(board)
		_rows.erase(board)
	return GSResult.success(removed)


func wipe_player(player_id: StringName) -> GSResult:
	var removed := 0
	for board in _rows:
		var by_player: Dictionary = _rows[board]
		var found: Variant = by_player.get(player_id)
		if found is GSTimerRecord:
			by_player.erase(player_id)
			(_boards[board] as Array).erase(found)
			removed += 1
	_history = _history.filter(
		func(e: Dictionary) -> bool: return (e["record"] as GSTimerRecord).player_id != player_id
	)
	_players.erase(player_id)
	for key in _progress.keys():
		if String(key).begins_with(String(player_id) + "|"):
			_progress.erase(key)
	for key in _resume.keys():
		if String(key).begins_with(String(player_id) + "|"):
			_resume.erase(key)
	return GSResult.success(removed)


func wipe_map(map_id: StringName) -> GSResult:
	var removed := 0
	for board in _boards.keys():
		var rows: Array = _boards[board]
		if not rows.is_empty() and (rows[0] as GSTimerRecord).map_id == map_id:
			removed += rows.size()
			_boards.erase(board)
			_rows.erase(board)
	_history = _history.filter(
		func(e: Dictionary) -> bool: return (e["record"] as GSTimerRecord).map_id != map_id
	)
	for key in _progress.keys():
		if String(key).split("|")[1].begins_with(String(map_id) + "/"):
			_progress.erase(key)
	_maps.erase(map_id)
	return GSResult.success(removed)



func note_player(
	player_id: StringName, name: String, seen_at: int, playtime_add: float = 0.0
) -> GSResult:
	var row: Dictionary = _players.get(player_id, {})
	if row.is_empty():
		row = {
			"player": String(player_id), "name": name, "points": 0.0,
			"first_seen": seen_at, "last_seen": seen_at, "playtime": 0.0,
		}
		_players[player_id] = row
	if name != "":
		row["name"] = name
	row["last_seen"] = maxi(int(row["last_seen"]), seen_at)
	row["playtime"] = float(row["playtime"]) + maxf(playtime_add, 0.0)
	return GSResult.success(true)


func player_info(player_id: StringName) -> GSResult:
	var row: Variant = _players.get(player_id)
	return GSResult.success((row as Dictionary).duplicate() if row is Dictionary else null)


func refresh_player_points(
	player_ids: Array, weighting: float = 1.0, limit: int = 0
) -> GSResult:
	for id in player_ids:
		var player_id := StringName(str(id))
		var points: Array[float] = []
		for board in _rows:
			var found: Variant = (_rows[board] as Dictionary).get(player_id)
			if found is GSTimerRecord and (found as GSTimerRecord).stage == 0:
				points.append((found as GSTimerRecord).points)
		var total := GSTimerPoints.weighted_total(points, weighting, limit)
		var row: Dictionary = _players.get(player_id, {})
		if row.is_empty():
			note_player(player_id, "", int(Time.get_unix_time_from_system()))
			row = _players[player_id]
		row["points"] = total
		if row["name"] == "":
			row["name"] = _name_of(player_id)
	return GSResult.success(player_ids.size())


func _name_of(player_id: StringName) -> String:
	for board in _rows:
		var found: Variant = (_rows[board] as Dictionary).get(player_id)
		if found is GSTimerRecord:
			return (found as GSTimerRecord).player_name
	return String(player_id)


func top_players(limit: int = 10, offset: int = 0) -> GSResult:
	var ranked := _ranked_players()
	var out: Array[Dictionary] = []
	for i in range(maxi(offset, 0), mini(offset + limit, ranked.size())):
		out.append(ranked[i])
	return GSResult.success(out)


func player_rank(player_id: StringName) -> GSResult:
	var ranked := _ranked_players()
	for row in ranked:
		if StringName(str(row["player"])) == player_id:
			return GSResult.success({"rank": row["rank"], "total": ranked.size(), "points": row["points"]})
	return GSResult.success({"rank": 0, "total": ranked.size(), "points": 0.0})


## Players with points, best first, with tie-sharing ranks.
func _ranked_players() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id in _players:
		var row: Dictionary = _players[id]
		if float(row["points"]) > 0.0:
			rows.append({"player": row["player"], "name": row["name"], "points": float(row["points"])})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["points"] != b["points"]:
			return a["points"] > b["points"]
		return str(a["player"]) < str(b["player"])
	)
	var rank := 0
	for i in range(rows.size()):
		if i == 0 or rows[i]["points"] != rows[i - 1]["points"]:
			rank = i + 1
		rows[i]["rank"] = rank
	return rows



func put_map(info: Dictionary) -> GSResult:
	var id := StringName(str(info.get("map", "")))
	if id == &"":
		return GSResult.fail(GSError.CODE_INVALID, "A map needs an id.")
	var row: Dictionary = _maps.get(id, {})
	for key in info:
		row[key] = info[key]
	row["map"] = String(id)
	row["updated_at"] = int(Time.get_unix_time_from_system())
	_maps[id] = row
	return GSResult.success(true)


func map_info(map_id: StringName) -> GSResult:
	var row: Variant = _maps.get(map_id)
	return GSResult.success((row as Dictionary).duplicate(true) if row is Dictionary else null)


func maps() -> GSResult:
	var out: Array[Dictionary] = []
	var ids := _maps.keys()
	# By text, as the SQL store's ORDER BY map: sort() orders these StringName keys by
	# where they were interned, which differs per process and is not alphabetical.
	ids.sort_custom(func(x: Variant, y: Variant) -> bool: return str(x) < str(y))
	for id in ids:
		out.append((_maps[id] as Dictionary).duplicate(true))
	return GSResult.success(out)



func note_progress(
	player_id: StringName, map_id: StringName, track: int, style_id: StringName,
	attempts: int, seconds: float, finished: bool
) -> GSResult:
	var key := "%s|%s" % [String(player_id), _key(map_id, track, style_id)]
	var row: Dictionary = _progress.get(key, {
		"attempts": 0, "completions": 0, "time_spent": 0.0, "time_to_first": -1.0,
	})
	row["attempts"] = int(row["attempts"]) + maxi(attempts, 0)
	row["time_spent"] = float(row["time_spent"]) + maxf(seconds, 0.0)
	if finished:
		row["completions"] = int(row["completions"]) + 1
		if float(row["time_to_first"]) < 0.0:
			row["time_to_first"] = row["time_spent"]
	_progress[key] = row
	return GSResult.success(true)


func progress_for(
	player_id: StringName, map_id: StringName, track: int, style_id: StringName
) -> GSResult:
	var row: Variant = _progress.get("%s|%s" % [String(player_id), _key(map_id, track, style_id)])
	return GSResult.success((row as Dictionary).duplicate() if row is Dictionary else null)



func save_resume(player_id: StringName, map_id: StringName, state: Dictionary) -> GSResult:
	_resume["%s|%s" % [String(player_id), String(map_id)]] = state.duplicate(true)
	return GSResult.success(true)


func take_resume(player_id: StringName, map_id: StringName) -> GSResult:
	var key := "%s|%s" % [String(player_id), String(map_id)]
	var state: Variant = _resume.get(key)
	_resume.erase(key)
	return GSResult.success(state if state is Dictionary else null)



func peek_top(
	map_id: StringName, track: int, style_id: StringName,
	limit: int = 10, stage: int = 0
) -> Variant:
	return top(map_id, track, style_id, limit, 0, stage).value


func peek_best(
	map_id: StringName, track: int, style_id: StringName,
	player_id: StringName, stage: int = 0
) -> Variant:
	var found: Variant = _row(map_id, track, style_id, player_id, stage)
	return (found as GSTimerRecord).duplicate_record() if found is GSTimerRecord else false



## Puts a stored row back as it was — no history entry, no completion bump. For a store
## loading its own rows from disk, which is not a finish.
func _insert_loaded(record: GSTimerRecord) -> void:
	var board := record.board_key()
	if not _rows.has(board):
		_rows[board] = {}
		_boards[board] = []
	var by_player: Dictionary = _rows[board]
	var rows: Array = _boards[board]
	var existing: Variant = by_player.get(record.player_id)
	if existing is GSTimerRecord:
		rows.erase(existing)
	by_player[record.player_id] = record
	rows.append(record)
	GSTimerRecord.sort_fastest_first(rows)

func _board(map_id: StringName, track: int, style_id: StringName, stage: int) -> Array:
	var value: Variant = _boards.get(_key(map_id, track, style_id, stage), [])
	return value if value is Array else []


func _row(
	map_id: StringName, track: int, style_id: StringName, player_id: StringName, stage: int
) -> Variant:
	var by_player: Variant = _rows.get(_key(map_id, track, style_id, stage), {})
	return (by_player as Dictionary).get(player_id) if by_player is Dictionary else null


## Every record, for a bulk export or a migration into another store.
func all_records() -> Array[GSTimerRecord]:
	var out: Array[GSTimerRecord] = []
	for board in _boards:
		for record in (_boards[board] as Array):
			out.append(record)
	return out


func clear() -> void:
	_rows.clear()
	_boards.clear()
	_history.clear()
	_players.clear()
	_maps.clear()
	_progress.clear()
	_resume.clear()


func describe() -> Dictionary:
	var out := super.describe()
	out["boards"] = _boards.size()
	var total := 0
	for board in _boards:
		total += (_boards[board] as Array).size()
	out["records"] = total
	out["players"] = _players.size()
	out["maps"] = _maps.size()
	return out
