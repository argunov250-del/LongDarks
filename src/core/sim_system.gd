class_name SimSystem
extends RefCounted
## База для систем симуляции. Наследники переопределяют tick.


## dt — игровые секунды шага (шаг * скорость).
func tick(_sim: Simulation, _dt: float) -> void:
	pass
