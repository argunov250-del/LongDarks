class_name Simulation
extends RefCounted
## Ядро симуляции: часы, шина событий, системы, детерминированный RNG.
## Фиксированный шаг с аккумулятором — результат не зависит от частоты кадров.

const STEP_USEC := 100000  # 0.1 с реального времени
const MAX_STEPS_PER_ADVANCE := 1000

var clock := GameClock.new()
var bus := EventBus.new()
var rng := RandomNumberGenerator.new()
var tick_count: int = 0

var _systems: Array[SimSystem] = []
var _acc_usec: int = 0


func _init(seed_value: int = 0) -> void:
	seed_rng(seed_value)


func seed_rng(seed_value: int) -> void:
	rng.seed = seed_value


func get_step_seconds() -> float:
	return float(STEP_USEC) / GameClock.USEC


func register_system(system: SimSystem) -> void:
	if not _systems.has(system):
		_systems.append(system)


func unregister_system(system: SimSystem) -> void:
	_systems.erase(system)


func get_systems() -> Array[SimSystem]:
	return _systems.duplicate()


## Подаёт реальное время кадра; выполняет целое число фиксированных шагов.
## Возвращает число выполненных шагов. На паузе системы не тикают.
func advance(real_delta: float) -> int:
	if real_delta <= 0.0:
		return 0
	_acc_usec += roundi(real_delta * GameClock.USEC)
	var steps := 0
	while _acc_usec >= STEP_USEC and steps < MAX_STEPS_PER_ADVANCE:
		_acc_usec -= STEP_USEC
		steps += 1
		if clock.is_paused():
			continue
		clock.advance(get_step_seconds())
		tick_count += 1
		var dt := get_step_seconds() * clock.get_speed()
		for s in _systems.duplicate():
			s.tick(self, dt)
	if steps == MAX_STEPS_PER_ADVANCE:
		_acc_usec = 0  # защита от спирали смерти
	return steps
