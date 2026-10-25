class_name SaveSystem
# Reads and writes saved games: one JSON file per slot in user://saves/.
# Holds no game logic; MainBoard builds and applies the save data.

const SLOT_COUNT: int = 3
const SAVE_DIR = "user://saves"
const VERSION: int = 1

static func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]

static func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))

static func has_any_save() -> bool:
	for slot in range(1, SLOT_COUNT + 1):
		if has_save(slot):
			return true
	return false

static func write(slot: int, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file = FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("Could not write save slot %d: %s" % [slot, FileAccess.get_open_error()])
		return false
	data["version"] = VERSION
	data["saved_at"] = Time.get_datetime_string_from_system(false, true)
	file.store_string(JSON.stringify(data, "\t"))
	return true

# Empty when the slot is unused or the file can't be read
static func read(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(slot_path(slot)))
	if not parsed is Dictionary or int(parsed.get("version", 0)) != VERSION:
		push_warning("Save slot %d is unreadable or from another version" % slot)
		return {}
	return parsed

# One-line summary for the slot picker, e.g. "3 players - P2 to throw - 2026-10-25 14:03"
static func describe(slot: int) -> String:
	var data = read(slot)
	if data.is_empty():
		return "Empty"
	return "%d players - P%d to throw - %s" % [
		int(data.player_count), int(data.active_player) + 1, str(data.saved_at).left(16)]
