class_name SaveGameService
extends RefCounted

const SAVE_VERSION := 1
const SLOT_COUNT := 3
const SAVE_DIRECTORY := "user://saves"


static func save_slot(
	slot: int,
	world_data: Dictionary,
	view_data: Dictionary,
	storage_directory: String = SAVE_DIRECTORY
) -> Dictionary:
	if slot < 1 or slot > SLOT_COUNT:
		return {"ok": false, "error": "INVALID_SLOT"}
	var directory_path := ProjectSettings.globalize_path(storage_directory)
	var directory_error := DirAccess.make_dir_recursive_absolute(directory_path)
	if directory_error != OK:
		return {"ok": false, "error": "CREATE_DIRECTORY_FAILED", "code": directory_error}
	var metadata := {
		"slot": slot,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"tick": int(world_data.get("integrity", {}).get("tick", 0)),
		"checksum": str(world_data.get("integrity", {}).get("checksum", "")),
	}
	var envelope := {
		"format": "AURORA_SAVE_FILE",
		"version": SAVE_VERSION,
		"metadata": metadata,
		"world": world_data,
		"view": view_data,
	}
	var final_path := _slot_path(slot, storage_directory)
	var temporary_path := final_path + ".tmp"
	var backup_path := final_path + ".bak"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "OPEN_FOR_WRITE_FAILED"}
	file.store_string(JSON.stringify(envelope, "  ", true, true))
	file.flush()
	file.close()
	if FileAccess.file_exists(final_path):
		if FileAccess.file_exists(backup_path):
			DirAccess.remove_absolute(backup_path)
		var backup_error := DirAccess.rename_absolute(final_path, backup_path)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary_path)
			return {"ok": false, "error": "BACKUP_SAVE_FAILED", "code": backup_error}
	var rename_error := DirAccess.rename_absolute(temporary_path, final_path)
	if rename_error != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(backup_path, final_path)
		return {"ok": false, "error": "FINALIZE_SAVE_FAILED", "code": rename_error}
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	return {"ok": true, "metadata": metadata, "path": final_path}


static func load_slot(slot: int, storage_directory: String = SAVE_DIRECTORY) -> Dictionary:
	if slot < 1 or slot > SLOT_COUNT:
		return {"ok": false, "error": "INVALID_SLOT"}
	var path := _slot_path(slot, storage_directory)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "EMPTY_SLOT"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "OPEN_FOR_READ_FAILED"}
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not json.data is Dictionary:
		return {"ok": false, "error": "INVALID_JSON"}
	var envelope: Dictionary = json.data
	if str(envelope.get("format", "")) != "AURORA_SAVE_FILE" or (
		int(envelope.get("version", 0)) != SAVE_VERSION
	):
		return {"ok": false, "error": "UNSUPPORTED_SAVE_VERSION"}
	if not envelope.get("world", {}) is Dictionary or not envelope.get("view", {}) is Dictionary:
		return {"ok": false, "error": "INVALID_SAVE_STRUCTURE"}
	return {
		"ok": true,
		"metadata": envelope.get("metadata", {}).duplicate(true),
		"world": envelope.world.duplicate(true),
		"view": envelope.view.duplicate(true),
		"path": path,
	}


static func get_slot_metadata(
	slot: int, storage_directory: String = SAVE_DIRECTORY
) -> Dictionary:
	var loaded := load_slot(slot, storage_directory)
	if not bool(loaded.get("ok", false)):
		return {"slot": slot, "empty": true}
	var metadata: Dictionary = loaded.metadata
	metadata["empty"] = false
	return metadata


static func _slot_path(slot: int, storage_directory: String) -> String:
	return "%s/slot_%d.json" % [storage_directory, slot]
