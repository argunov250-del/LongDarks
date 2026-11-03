class_name Storage
extends RefCounted
## Склад: позиция, вместимость (в единицах), содержимое (целые количества).
## Дробная порча копится в _spoil_acc и списывается целыми единицами.

var id: int = 0
var position := Vector3.ZERO
var capacity: int = 0
var cellar: bool = false  # погреб — без порчи
var cold: bool = false    # холодный склад — без порчи
var contents: Dictionary = {}  # StringName -> int (>0)

var _spoil_acc: Dictionary = {}  # StringName -> float


func _init(capacity_in: int = 0, position_in: Vector3 = Vector3.ZERO, cellar_in: bool = false, cold_in: bool = false) -> void:
	capacity = capacity_in
	position = position_in
	cellar = cellar_in
	cold = cold_in


func used() -> int:
	var n := 0
	for k in contents:
		n += contents[k]
	return n


func free_space() -> int:
	return maxi(0, capacity - used())


func amount(res: StringName) -> int:
	return contents.get(res, 0)


func has(res: StringName, n: int = 1) -> bool:
	return amount(res) >= n


func preserves() -> bool:
	return cellar or cold


## Кладёт не больше свободного места; возвращает фактически добавленное.
func add(res: StringName, n: int) -> int:
	if n <= 0 or not ResourceDefs.exists(res):
		return 0
	var moved := mini(n, free_space())
	if moved > 0:
		contents[res] = amount(res) + moved
	return moved


## Забирает не больше имеющегося; возвращает фактически снятое.
func remove(res: StringName, n: int) -> int:
	if n <= 0:
		return 0
	var have := amount(res)
	var moved := mini(n, have)
	if moved <= 0:
		return 0
	if moved == have:
		contents.erase(res)
		_spoil_acc.erase(res)
	else:
		contents[res] = have - moved
	return moved


## Порча за долю игровых суток. Возвращает {res: потерянные единицы}.
func spoil(days: float) -> Dictionary:
	var lost := {}
	if preserves() or days <= 0.0:
		return lost
	for res in contents.keys():
		var rate := ResourceDefs.spoil_rate(res)
		if rate <= 0.0:
			continue
		var acc: float = _spoil_acc.get(res, 0.0) + float(contents[res]) * rate * days
		var whole := int(acc)
		if whole > 0:
			acc -= whole
			lost[res] = remove(res, whole)
		if contents.has(res):
			_spoil_acc[res] = acc
	return lost


func to_dict() -> Dictionary:
	var c := {}
	for k in contents:
		c[String(k)] = contents[k]
	var a := {}
	for k in _spoil_acc:
		a[String(k)] = _spoil_acc[k]
	return {
		"id": id,
		"pos": [position.x, position.y, position.z],
		"capacity": capacity,
		"cellar": cellar,
		"cold": cold,
		"contents": c,
		"spoil_acc": a,
	}


static func from_dict(d: Dictionary) -> Storage:
	var s := Storage.new(SaveManager.to_int(d.get("capacity"), 0))
	s.id = SaveManager.to_int(d.get("id"), 0)
	var p = d.get("pos")
	if p is Array and p.size() == 3:
		s.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	s.cellar = bool(d.get("cellar", false))
	s.cold = bool(d.get("cold", false))
	if d.get("contents") is Dictionary:
		for k in d["contents"]:
			var n := SaveManager.to_int(d["contents"][k], 0)
			if n > 0 and ResourceDefs.exists(StringName(k)):
				s.contents[StringName(k)] = n
	if d.get("spoil_acc") is Dictionary:
		for k in d["spoil_acc"]:
			if s.contents.has(StringName(k)):
				s._spoil_acc[StringName(k)] = float(d["spoil_acc"][k])
	return s
