extends Node
## Автолоад "SimRunner": гоняет Simulation из _process.

var sim := Simulation.new(randi())


func _process(delta: float) -> void:
	sim.advance(delta)
