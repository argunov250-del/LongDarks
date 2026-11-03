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
