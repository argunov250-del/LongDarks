class_name VehicleModJob
extends Repairable
## A conversion/upgrade of one vehicle as a workshop job (Repairable contract): `condition` is progress 0..1,
## each workshop step costs FuelDefs cost and adds 1/steps. At 1.0 the mod is installed.
## Design: design/gdd/fuel-and-upgrades.md. Progress is saved by ProductionSystem (conditions) -> save mid-conversion.

var vehicle: Vehicle
var kind: StringName
var on_done: Callable
var done := false                       # installed (job awaits cleanup)


func _init(vehicle_in: Vehicle, kind_in: StringName, progress: float = 0.0) -> void:
	vehicle = vehicle_in
	kind = kind_in
	var d := FuelDefs.mod_def(kind_in)
	super._init(StringName("vehicle_%d:mod:%s" % [vehicle_in.id, String(kind_in)]), progress)
	step_cost = (d.get("cost", {}) as Dictionary).duplicate()
	step_gain = 1.0 / float(maxi(1, int(d.get("steps", 1))))


func is_conversion() -> bool:
	return FuelDefs.CONVERSION_DEFS.has(kind)


func on_condition_changed() -> void:
	if condition >= 1.0 and on_done.is_valid():
		on_done.call(self)
