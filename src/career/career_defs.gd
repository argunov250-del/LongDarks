class_name CareerDefs
extends RefCounted
## Карьера (шаг 26): формат данных, валидация, типы условий. Дизайн: design/gdd/career.md.
## Содержимое глав (сюжет, тексты) живёт ТОЛЬКО в data/career/chapters.json.

const DATA_PATH := "res://data/career/chapters.json"

## Типы условий. Источник: &"event" — счётчик событий шины за главу; &"poll" — проверка состояния игры.
const T_BUILD := &"build"                  # event: params {building, count}
const T_HARVEST := &"harvest"              # event: params {resource ("" — любая), count} — собрано с полей
const T_REPAIR := &"repair"                # event: params {count, prefix?} — завершённые ремонты в мастерской
const T_EVENT := &"event"                  # event: params {topic, count, field?, value?} — любой топик шины
const T_POPULATION := &"population"        # poll: params {count}
const T_SURVIVE := &"survive_until"        # poll: params {season, year}
const T_RELATION := &"relation"            # poll: params {min, neighbour?}
const T_RESOURCE := &"resource"            # poll: params {resource, count} — запас на складах
const KINDS := {
	T_BUILD: &"event", T_HARVEST: &"event", T_REPAIR: &"event", T_EVENT: &"event",
	T_POPULATION: &"poll", T_SURVIVE: &"poll", T_RELATION: &"poll", T_RESOURCE: &"poll",
}
## Обязательные поля params по типам: имя -> тип (TYPE_*).
const REQUIRED := {
	T_BUILD: {"building": TYPE_STRING, "count": TYPE_FLOAT},
	T_HARVEST: {"count": TYPE_FLOAT},
	T_REPAIR: {"count": TYPE_FLOAT},
	T_EVENT: {"topic": TYPE_STRING, "count": TYPE_FLOAT},
	T_POPULATION: {"count": TYPE_FLOAT},
	T_SURVIVE: {"season": TYPE_STRING, "year": TYPE_FLOAT},
	T_RELATION: {"min": TYPE_FLOAT},
	T_RESOURCE: {"resource": TYPE_STRING, "count": TYPE_FLOAT},
}
## Ключи start_state главы (необязательные).
const START_KEYS: Array[String] = ["resources", "season", "season_progress"]


## Разбирает словарь данных. Возвращает {chapters: Array[Dictionary], credits: Dictionary, errors: Array[String]}.
## Некорректные главы/цели отбрасываются и попадают в errors — без падений.
static func parse(data: Variant) -> Dictionary:
	var errors: Array[String] = []
	var chapters: Array[Dictionary] = []
	var credits := {"title": "Титры", "thanks": "Спасибо за игру", "speed": 60.0, "entries": []}
	if not data is Dictionary:
		errors.append("корень данных — не объект")
		return {"chapters": chapters, "credits": credits, "errors": errors}
	var d: Dictionary = data
	if d.get("chapters") is Array:
		var seen := {}
		var seen_obj := {}
		for i in (d["chapters"] as Array).size():
			var ch := _parse_chapter(d["chapters"][i], i, seen, seen_obj, errors)
			if not ch.is_empty():
				chapters.append(ch)
	else:
		errors.append("нет массива chapters")
	if chapters.is_empty() and errors.is_empty():
		errors.append("chapters пуст")
	if d.get("credits") is Dictionary:
		var c: Dictionary = d["credits"]
		credits["title"] = str(c.get("title", credits["title"]))
		credits["thanks"] = str(c.get("thanks", credits["thanks"]))
		credits["speed"] = maxf(float(c.get("speed", credits["speed"])), 1.0) if _is_num(c.get("speed", 60.0)) else 60.0
		if c.get("entries") is Array:
			for e in c["entries"]:
				if e is Dictionary:
					credits["entries"].append({"role": str(e.get("role", "")), "name": str(e.get("name", ""))})
				else:
					errors.append("credits.entries: элемент не объект")
	return {"chapters": chapters, "credits": credits, "errors": errors}


static func _is_num(v: Variant) -> bool:
	return v is float or v is int


static func _parse_chapter(raw: Variant, idx: int, seen: Dictionary, seen_obj: Dictionary, errors: Array[String]) -> Dictionary:
	if not raw is Dictionary:
		errors.append("глава #%d: не объект" % idx)
		return {}
	var r: Dictionary = raw
	var id := str(r.get("id", ""))
	if id == "":
		errors.append("глава #%d: нет id" % idx)
		return {}
	if seen.has(id):
		errors.append("глава %s: повторный id" % id)
		return {}
	seen[id] = true
	var objectives: Array[Dictionary] = []
	if r.get("objectives") is Array:
		for j in (r["objectives"] as Array).size():
			var o := _parse_objective(r["objectives"][j], id, j, seen_obj, errors)
			if not o.is_empty():
				objectives.append(o)
	if objectives.is_empty():
		errors.append("глава %s: нет корректных целей" % id)
		return {}
	var start: Dictionary = {}
	if r.get("start_state") is Dictionary:
		for k in r["start_state"]:
			if START_KEYS.has(str(k)):
				start[str(k)] = r["start_state"][k]
			else:
				errors.append("глава %s: неизвестный ключ start_state %s" % [id, str(k)])
	return {"id": id, "title": str(r.get("title", id)), "intro": str(r.get("intro", "")),
		"outro": str(r.get("outro", "")), "objectives": objectives, "start_state": start}


static func _parse_objective(raw: Variant, chapter: String, j: int, seen_obj: Dictionary, errors: Array[String]) -> Dictionary:
	var where := "глава %s, цель #%d" % [chapter, j]
	if not raw is Dictionary:
		errors.append("%s: не объект" % where)
		return {}
	var r: Dictionary = raw
	var id := str(r.get("id", ""))
	if id == "":
		errors.append("%s: нет id" % where)
		return {}
	if seen_obj.has(id):
		errors.append("%s: повторный id цели %s" % [where, id])
		return {}
	var type := StringName(str(r.get("type", "")))
	if not KINDS.has(type):
		errors.append("%s: неизвестный тип условия «%s»" % [where, str(type)])
		return {}
	var params: Dictionary = r["params"] if r.get("params") is Dictionary else {}
	var req: Dictionary = REQUIRED[type]
	for k in req:
		if not params.has(k):
			errors.append("%s: нет params.%s" % [where, k])
			return {}
		var v: Variant = params[k]
		if (req[k] == TYPE_FLOAT and not _is_num(v)) or (req[k] == TYPE_STRING and not v is String):
			errors.append("%s: params.%s неверного типа" % [where, k])
			return {}
	if type == T_SURVIVE and not SeasonDefs.ORDER.has(StringName(params["season"])):
		errors.append("%s: неизвестный сезон «%s»" % [where, params["season"]])
		return {}
	if type == T_BUILD and not BuildingDefs.exists(StringName(params["building"])):
		errors.append("%s: неизвестное здание «%s»" % [where, params["building"]])
		return {}
	seen_obj[id] = true
	return {"id": id, "type": type, "text": str(r.get("text", id)), "params": params}


## Загружает и разбирает файл. Ошибки чтения попадают в errors.
static func load_file(path: String = DATA_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return parse(null).merged({"errors": ["файл не найден: " + path]}, true)
	var txt := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(txt) != OK:
		return parse(null).merged({"errors": ["JSON: строка %d: %s" % [json.get_error_line(), json.get_error_message()]]}, true)
	return parse(json.data)


## Нужное число для условия (count/min).
static func target(obj: Dictionary) -> float:
	var p: Dictionary = obj["params"]
	return float(p.get("count", p.get("min", 1.0)))
