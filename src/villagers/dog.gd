class_name Dog
extends Walker
## Собака героя: отдельная сущность, ходит за героем, не работник. Не умирает.

var immortal := true
## Тревога 0..1. HOOK (погода): VillagerSystem/погода зовёт set_anxious(level) при
## приближении плохой погоды; вид (DogFigure) играет «беспокойство» — метание и
## поскуливание (плейсхолдер: покачивание и подёргивание головы). Логики пока нет.
var anxious_level := 0.0


func set_anxious(level: float) -> void:
	anxious_level = clampf(level, 0.0, 1.0)


func to_dict() -> Dictionary:
	return {"pos": [pos.x, pos.y, pos.z], "facing": facing, "anxious": anxious_level}


func load_dict(d: Dictionary) -> void:
	var p = d.get("pos")
	if p is Array and p.size() == 3:
		pos = Vector3(float(p[0]), float(p[1]), float(p[2]))
	facing = float(d.get("facing", 0.0))
	set_anxious(float(d.get("anxious", 0.0)))
	path.clear()
	path_goal = Vector2i(-1, -1)
