class_name AutoSave
extends SimSystem
## Автосохранение: при смене игровых суток и при сворачивании приложения (Android).
## Дизайн: design/gdd/modes-difficulty.md. save_fn: Callable() -> Error (внедряется).

signal saved

var save_fn: Callable
var save_count := 0
var _last_day := -1


func resync(sim: Simulation) -> void:
	_last_day = sim.clock.get_day()


func tick(sim: Simulation, _dt: float) -> void:
	var day := sim.clock.get_day()
	if _last_day < 0:
		_last_day = day
		return
	if day != _last_day:
		_last_day = day
		trigger()


## Вызывать из NOTIFICATION_APPLICATION_PAUSED.
func on_app_paused() -> void:
	trigger()


func trigger() -> Error:
	if not save_fn.is_valid():
		return ERR_UNCONFIGURED
	var err: Error = save_fn.call()
	if err == OK:
		save_count += 1
		saved.emit()
	return err
