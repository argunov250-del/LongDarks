class_name SimSystem
extends RefCounted
## База для систем симуляции. Наследники переопределяют tick.


## dt — игровые секунды шага (шаг * скорость).
func tick(_sim: Simulation, _dt: float) -> void:
	pass


## Сохранение (опционально). Системы с состоянием переопределяют все три.
## Ключ должен быть уникален и стабилен между версиями. Пустой — не сохраняется.
## Внимание: после JSON числа приходят float; целые приводить через SaveManager.to_int().
func get_save_key() -> StringName:
	return &""


func save_state() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	pass
