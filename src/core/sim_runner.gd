extends Node
## Автолоад "SimRunner": гоняет Simulation из _process.

var sim := Simulation.new(randi())


func _process(delta: float) -> void:
	sim.advance(delta)


const QUICK_SLOT := "quicksave"


func quick_save() -> Error:
	return SaveManager.save(sim, QUICK_SLOT)


func quick_load() -> Error:
	return SaveManager.load_slot(sim, QUICK_SLOT)


## Передача параметров из меню в главную сцену (шаг 25): {"settings": Dictionary} или {"load_slot": String}.
var pending: Dictionary = {}


## Новая симуляция (выход в меню / новая игра): системы старой партии отбрасываются.
func reset() -> void:
	sim = Simulation.new(randi())


func take_pending() -> Dictionary:
	var p := pending
	pending = {}
	return p
