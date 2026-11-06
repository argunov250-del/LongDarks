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
var host_id: int = 0             # сарай: id дома, во дворе которого он стоит (0 — нет)
var storage_id: int = 0          # склад/погреб в EconomySystem (0 — нет)
var blocked: StringName = &""    # &"" | &"resources" | &"frozen" | &"flood" — почему стадия стоит
## Погода (шаг 14). burning/flooded — рабочие флаги (WeatherSystem пересчитывает), damaged и ремонт сохраняются.
var burning: bool = false        # горит: не работает
var flooded: bool = false        # стоит в воде паводка: не работает
var damaged: bool = false        # не потушили: не работает, пока жители не отремонтируют
var repair_paid: bool = false    # материалы ремонта списаны
var repair_progress: float = 0.0 # выполненная работа ремонта


func is_done() -> bool:
	return stage >= BuildingDefs.Stage.DONE


## Здание готово и работает (не горит, не повреждено, не затоплено).
func operational() -> bool:
	return is_done() and not burning and not damaged and not flooded


## Цена ремонта поврежденного здания: доля полной цены (округление вверх).
func repair_cost() -> Dictionary:
	var out := {}
	var total := BuildingDefs.total_cost(type, cost_factor())
	for k in total:
		var n := int(ceil(float(total[k]) * WeatherDefs.REPAIR_COST_FRACTION - 0.0001))
		if n > 0:
			out[k] = n
	return out


## Работа ремонта: доля суммарной работы стадий.
func repair_work() -> float:
	var w := 0.0
	for s in BuildingDefs.Stage.DONE:
		w += BuildingDefs.stage_work(type, s, work_factor())
	return maxf(1.0, w * WeatherDefs.REPAIR_WORK_FRACTION)


func size() -> Vector2:
	return BuildingDefs.footprint(type)


## Мировые прямоугольники (основание и двор): [{"c": Vector2, "size": Vector2, "kind": StringName}].
func world_parts() -> Array[Dictionary]:
	return BuildingDefs.world_parts(type, xz(), rot)


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
		"restored": restored, "storage_id": storage_id, "host": host_id,
		"damaged": damaged, "rpaid": repair_paid, "rprog": repair_progress,
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
	b.host_id = SaveManager.to_int(d.get("host"), 0)
	b.damaged = bool(d.get("damaged", false))
	b.repair_paid = bool(d.get("rpaid", false))
	b.repair_progress = float(d.get("rprog", 0.0))
	return b
