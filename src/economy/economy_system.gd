class_name EconomySystem
extends SimSystem
## Реестр складов, глобальные запросы, порча, месторождения.

const TOPIC_RESOURCES_CHANGED := &"resources_changed"

var storages: Array[Storage] = []
var deposits: Deposits
## Внешний флаг (SeasonSystem: холоднее +4 °C): при true порча остановлена везде.
var ambient_cold: bool = false

var _next_id: int = 1
var _sim: Simulation


func _init(world: WorldMap = null) -> void:
	deposits = Deposits.new(world)


func add_storage(s: Storage) -> Storage:
	s.id = _next_id
	_next_id += 1
	storages.append(s)
	_changed()
	return s


func remove_storage(s: Storage) -> void:
	storages.erase(s)
	_changed()


func get_storage(id: int) -> Storage:
	for s in storages:
		if s.id == id:
			return s
	return null


func set_ambient_cold(v: bool) -> void:
	ambient_cold = v


func total(res: StringName) -> int:
	var n := 0
	for s in storages:
		n += s.amount(res)
	return n


func total_free_space() -> int:
	var n := 0
	for s in storages:
		n += s.free_space()
	return n


func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if total(k) < SaveManager.to_int(cost[k], 0):
			return false
	return true


## Атомарно: либо снимает всё, либо ничего.
func consume(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k in cost:
		var left := SaveManager.to_int(cost[k], 0)
		for s in storages:
			if left <= 0:
				break
			left -= s.remove(k, left)
	_changed()
	return true


## Кладёт по складам в порядке регистрации; возвращает фактически добавленное.
func deposit(res: StringName, n: int) -> int:
	if not ResourceDefs.is_warehouse_stockable(res):
		return 0
	var left := n
	for s in storages:
		if left <= 0:
			break
		left -= s.add(res, left)
	var moved := maxi(0, n) - maxi(0, left)
	if moved > 0:
		_changed()
	return moved


func tick(sim: Simulation, dt: float) -> void:
	_sim = sim
	if ambient_cold or dt <= 0.0:
		return
	var days := dt / sim.clock.rate_day_seconds()
	var any := false
	for s in storages:
		if not s.spoil(days).is_empty():
			any = true
	if any:
		_changed()


func _changed() -> void:
	if _sim != null:
		_sim.bus.emit(TOPIC_RESOURCES_CHANGED, {})


func get_save_key() -> StringName:
	return &"economy"


func save_state() -> Dictionary:
	var list := []
	for s in storages:
		list.append(s.to_dict())
	return {
		"next_id": _next_id,
		"ambient_cold": ambient_cold,
		"storages": list,
		"deposits": deposits.to_dict(),
	}


func load_state(d: Dictionary) -> void:
	storages.clear()
	if d.get("storages") is Array:
		for e in d["storages"]:
			if e is Dictionary:
				storages.append(Storage.from_dict(e))
	_next_id = SaveManager.to_int(d.get("next_id"), 1)
	for s in storages:
		_next_id = maxi(_next_id, s.id + 1)
	ambient_cold = bool(d.get("ambient_cold", false))
	if d.get("deposits") is Dictionary:
		deposits.from_dict(d["deposits"])
	_changed()
