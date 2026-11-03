class_name SaveManager
extends RefCounted
## Сохранения в user://saves/<slot>.json. Атомарная запись: temp-файл + rename.
## Все методы возвращают Error и не падают на битых файлах.

const VERSION := 1
const SAVE_DIR := "user://saves"
const EXT := ".json"


## JSON отдаёт числа как float, а 64-битные значения мы храним строками.
## Принимает int, float или String; при неудаче возвращает fallback.
static func to_int(v, fallback: int = 0) -> int:
	match typeof(v):
		TYPE_INT:
			return v
		TYPE_FLOAT:
			return int(v) if is_finite(v) else fallback
		TYPE_STRING, TYPE_STRING_NAME:
			var s := String(v)
			return s.to_int() if s.is_valid_int() else fallback
	return fallback


static func slot_path(slot_name: String) -> String:
	return SAVE_DIR.path_join(slot_name + EXT)


static func is_valid_slot_name(slot_name: String) -> bool:
	return slot_name != "" and slot_name.is_valid_filename() and not slot_name.begins_with(".")


## HOOK (миграции): приводит данные старой версии к текущей.
## Для версии N+1 добавить ветку, превращающую v(N) в v(N+1). Вернуть {} при неудаче.
static func migrate(data: Dictionary, from_version: int) -> Dictionary:
	if from_version == VERSION:
		return data
	return {}


static func save(sim: Simulation, slot_name: String) -> Error:
	if not is_valid_slot_name(slot_name):
		return ERR_INVALID_PARAMETER
	var err := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if err != OK:
		return err
	var text := JSON.stringify({"version": VERSION, "sim": sim.to_dict()})
	var path := slot_path(slot_name)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	var werr := f.get_error()
	f.close()
	if werr != OK:
		DirAccess.remove_absolute(tmp)
		return werr
	err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		DirAccess.remove_absolute(tmp)
	return err


## Загружает слот в sim. При любой ошибке sim не изменяется.
static func load_slot(sim: Simulation, slot_name: String) -> Error:
	if not is_valid_slot_name(slot_name):
		return ERR_INVALID_PARAMETER
	var path := slot_path(slot_name)
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return FileAccess.get_open_error()
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return ERR_FILE_CORRUPT
	var data: Dictionary = json.data
	if not data.has("version") or not (data["version"] is float or data["version"] is int):
		return ERR_FILE_CORRUPT
	var version := to_int(data["version"], -1)
	if version < 1 or version > VERSION:
		return ERR_FILE_UNRECOGNIZED
	data = migrate(data, version)
	if data.is_empty() or not (data.get("sim") is Dictionary):
		return ERR_FILE_CORRUPT
	sim.from_dict(data["sim"])
	return OK


static func list_slots() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for fn in dir.get_files():
		if fn.ends_with(EXT):
			out.append(fn.trim_suffix(EXT))
	out.sort()
	return out


static func delete_slot(slot_name: String) -> Error:
	if not is_valid_slot_name(slot_name):
		return ERR_INVALID_PARAMETER
	var path := slot_path(slot_name)
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	return DirAccess.remove_absolute(path)
