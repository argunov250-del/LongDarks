class_name Building
extends RefCounted
## Данные одного здания/стройки.

var id: int = 0
var type: StringName = &""
var position := Vector3.ZERO     # y — по рельефу
var rot: float = 0.0
var stage: int = BuildingDefs.Stage.FOUNDATION
var stage_paid: bool = false     # цена текущей стадии уже списана
var progress: float = 0.0        # выполненная работа текущей стадии
var restored: bool = false       # восстановлено из руин (дешевле)
var storage_id: int = 0          # склад/погреб в EconomySystem (0 — нет)
var blocked: StringName = &""    # &"" | &"resources" | &"frozen" — почему стадия стоит


func is_done() -> bool:
	return stage >= BuildingDefs.Stage.DONE


func size() -> Vector2:
	return BuildingDefs.footprint(type)


func xz() -> Vector2:
	return Vector2(position.x, position.z)


func cost_factor() -> float:
	return BuildingDefs.RESTORE_COST_FACTOR if restored else 1.0


func work_factor() -> float:
	return BuildingDefs.RESTORE_WORK_FACTOR if restored else 1.0


func stage_cost() -> Dictionary:
	return BuildingDefs.stage_cost(type, stage, cost_factor())


func stage_work() -> float:
	return BuildingDefs.stage_work(type, stage, work_factor())


## Доля выполненной работы текущей стадии [0,1].
func stage_fraction() -> float:
	if is_done():
		return 1.0
	var w := stage_work()
	return 1.0 if w <= 0.0 else clampf(progress / w, 0.0, 1.0)


func to_dict() -> Dictionary:
	return {
		"id": id, "type": String(type),
		"pos": [position.x, position.y, position.z], "rot": rot,
		"stage": stage, "paid": stage_paid, "progress": progress,
		"restored": restored, "storage_id": storage_id,
	}


static func from_dict(d: Dictionary) -> Building:
	var b := Building.new()
	b.id = SaveManager.to_int(d.get("id"), 0)
	b.type = StringName(String(d.get("type", "")))
	var p = d.get("pos")
	if p is Array and p.size() == 3:
		b.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	b.rot = float(d.get("rot", 0.0))
	b.stage = clampi(SaveManager.to_int(d.get("stage"), 0), 0, BuildingDefs.Stage.DONE)
	b.stage_paid = bool(d.get("paid", false))
	b.progress = float(d.get("progress", 0.0))
	b.restored = bool(d.get("restored", false))
	b.storage_id = SaveManager.to_int(d.get("storage_id"), 0)
	return b
