class_name Household
extends RefCounted
## Запас одного дома (или столовой): поленница, печь, вода, еда, огород, сарай.
## Только данные; правила — в HouseholdSystem. Для столовой используются food и water.

const GARDEN_EMPTY := &"empty"
const GARDEN_GROWING := &"growing"
const GARDEN_RIPE := &"ripe"

var id: int = 0                 # id здания
var kind: StringName = &"house" # &"house" | &"canteen"
var woodpile: int = 0           # колотые дрова на поленнице
var stove: int = 0              # дрова в печи
var water: int = 0
var water_cap: int = HouseholdDefs.HOUSE_WATER_CAPACITY
var food: Storage               # еда (картофель, овощи, яйца, молоко, ...)
var garden_state: StringName = GARDEN_EMPTY
var garden_progress: float = 0.0
var garden_crop: StringName = &"potato"  # культура текущего цикла (чередуется)
var barn: bool = false
var warmth: float = 0.5         # тепло в доме 0..1 (шаг 11)
var burn_left: float = 0.0      # остаток текущей закладки дров в печи, 0..1 (>0 — печь горит)
var egg_acc: float = 0.0
var milk_acc: float = 0.0


func _init(id_in: int = 0, kind_in: StringName = &"house") -> void:
	id = id_in
	kind = kind_in
	if kind == &"canteen":
		food = Storage.new(HouseholdDefs.CANTEEN_FOOD_CAPACITY)
		water_cap = HouseholdDefs.CANTEEN_WATER_CAPACITY
	else:
		food = Storage.new(HouseholdDefs.HOUSE_FOOD_CAPACITY)
		water_cap = HouseholdDefs.HOUSE_WATER_CAPACITY


func lit() -> bool:
	return burn_left > 0.0


func garden_fraction() -> float:
	match garden_state:
		GARDEN_RIPE:
			return 1.0
		GARDEN_GROWING:
			return clampf(garden_progress / HouseholdDefs.GARDEN_GROW_TIME, 0.0, 1.0)
	return 0.0


func to_dict() -> Dictionary:
	return {
		"id": id, "kind": String(kind), "woodpile": woodpile, "stove": stove, "water": water,
		"food": food.to_dict(), "garden": String(garden_state), "garden_progress": garden_progress,
		"crop": String(garden_crop), "barn": barn, "egg_acc": egg_acc, "milk_acc": milk_acc,
		"warmth": warmth, "burn_left": burn_left,
	}


static func from_dict(d: Dictionary) -> Household:
	var h := Household.new(SaveManager.to_int(d.get("id"), 0), &"canteen" if String(d.get("kind", "house")) == "canteen" else &"house")
	h.woodpile = maxi(0, SaveManager.to_int(d.get("woodpile"), 0))
	h.stove = maxi(0, SaveManager.to_int(d.get("stove"), 0))
	h.water = clampi(SaveManager.to_int(d.get("water"), 0), 0, h.water_cap)
	if d.get("food") is Dictionary:
		var f := Storage.from_dict(d["food"])
		f.capacity = h.food.capacity
		h.food = f
	var g := StringName(String(d.get("garden", "empty")))
	h.garden_state = g if [GARDEN_EMPTY, GARDEN_GROWING, GARDEN_RIPE].has(g) else GARDEN_EMPTY
	h.garden_progress = float(d.get("garden_progress", 0.0))
	var crop := StringName(String(d.get("crop", "potato")))
	h.garden_crop = crop if HouseholdDefs.GARDEN_CROPS.has(crop) else &"potato"
	h.barn = bool(d.get("barn", false))
	h.egg_acc = float(d.get("egg_acc", 0.0))
	h.milk_acc = float(d.get("milk_acc", 0.0))
	h.warmth = clampf(float(d.get("warmth", 0.5)), 0.0, 1.0)
	h.burn_left = clampf(float(d.get("burn_left", 0.0)), 0.0, 1.0)
	return h
