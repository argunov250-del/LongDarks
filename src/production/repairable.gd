class_name Repairable
extends RefCounted
## КОНТРАКТ ремонтируемого объекта (техника, инструменты — позже).
## Любой объект, который мастерская может чинить, наследует этот класс и
## регистрируется: ProductionSystem.register_repairable(obj).
##
##  repair_id  — уникальный стабильный StringName (ключ в сохранении и очереди).
##  condition  — состояние 0..1 (1 = исправен). Сохраняется ProductionSystem по
##               repair_id; при регистрации сохранённое состояние восстанавливается.
##  get_repair_cost() — цена ОДНОГО шага ремонта (ресурсы, обычно spare_parts/
##               scrap_metal); списывается при старте шага. Можно переопределить.
##  get_repair_gain() — прирост condition за шаг. Можно переопределить.
##  on_condition_changed() — хук после изменения состояния (для владельца).
##
## Очередь ремонта у каждой мастерской: ProductionSystem.queue_repair(workshop_id,
## repair_id). Мастерская берёт голову очереди, шаг за шагом (REPAIR_STEP_TIME)
## тратит запчасти и поднимает condition до 1; нет запчастей — ждёт (stall no_input).

var repair_id: StringName = &""
var condition: float = 1.0
var step_cost: Dictionary = Recipes.REPAIR_STEP_COST.duplicate()
var step_gain: float = Recipes.REPAIR_STEP_GAIN


func _init(id: StringName = &"", condition_in: float = 1.0) -> void:
	repair_id = id
	condition = clampf(condition_in, 0.0, 1.0)


func get_repair_cost() -> Dictionary:
	return step_cost


func get_repair_gain() -> float:
	return step_gain


func needs_repair() -> bool:
	return condition < 1.0 - 0.000001


func apply_repair(gain: float) -> void:
	condition = clampf(condition + gain, 0.0, 1.0)
	if condition > 1.0 - 0.000001:
		condition = 1.0
	on_condition_changed()


func on_condition_changed() -> void:
	pass
