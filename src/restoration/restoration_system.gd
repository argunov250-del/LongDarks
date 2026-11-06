class_name RestorationSystem
extends SimSystem
## Step 17 land restoration (design/gdd/land-restoration.md): planting + natural spread of forest, water quality,
## poison treatment, soil fertility, and the land_recovery index that feeds wildlife/fish/birds/climate.
## Pure simulation: villagers fetch jobs via jobs() (through FoodSystem.jobs) and call finish().

const TOPIC_CHANGED := &"restoration_changed"

var world: WorldMap
var economy: EconomySystem
var construction: ConstructionSystem
var food: FoodSystem
var climate: ClimateSystem
var seasons: SeasonSystem

var plant_marks: Dictionary = {}      # idx -> true: designated, awaiting a villager
var saplings: Dictionary = {}         # idx -> growth 0..1
var grown: Dictionary = {}            # idx -> true: restored trees (counted for climate); removed when felled
var treat_marks: Dictionary = {}      # idx -> true: poison cell designated for treatment
var treated: Dictionary = {}          # idx -> true: cleansing vegetation planted
var poison: Dictionary = {}           # idx -> level 0..1, only cells that changed (untouched poison = 1.0)
var water_quality: Array[float] = []  # per FoodSystem.bodies index
var soil: float = 0.0                 # extra fertility from recovery, 0..SOIL_MAX
## Test hook: force season (&"" = ask FoodSystem / SeasonSystem).
var season_override: StringName = &""
## Natural forest spread at tree edges (tests switch it off to count only planted cells).
var natural_spread: bool = true

var _sim: Simulation
var _spread_acc := 0.0
var _acc := 0.0
var _recovery := 0.0
var _poison_total := -1


func bind(economy_in: EconomySystem, world_in: WorldMap, construction_in: ConstructionSystem, food_in: FoodSystem, climate_in: ClimateSystem = null, seasons_in: SeasonSystem = null) -> void:
	economy = economy_in
	world = world_in
	construction = construction_in
	food = food_in
	climate = climate_in
	seasons = seasons_in
	if food != null:
		food.restoration = self
		for _b in food.bodies:
			water_quality.append(RestorationDefs.WATER_START)
	if climate != null:
		climate.set_planted_provider(planted_count)
	sync_now()


func attach(sim: Simulation) -> void:
	_sim = sim


# ---------- helpers ----------

func _season() -> StringName:
	if season_override != &"":
		return season_override
	if food != null:
		return food.current_season()
	return seasons.season() if seasons != null else SeasonDefs.SPRING


func _day_s() -> float:
	return _sim.clock.day_seconds() if _sim != null else 86400.0 / 96.0


func _idx(c: Vector2i) -> int:
	return c.y * world.size + c.x


func _cell(i: int) -> Vector2i:
	return Vector2i(i % world.size, i / world.size)


func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < world.size and c.y < world.size


func _occupied() -> Dictionary:
	var occ := {}
	if construction == null:
		return occ
	for b: Building in construction.buildings.values():
		for c in construction.footprint_cells(Vector2(b.position.x, b.position.z), b.size(), b.rot):
			occ[c.y * world.size + c.x] = true
	return occ


# ---------- poison ----------

## Poison level of the cell: 0 for normal land, 1 for untouched poison, in between while healing.
func poison_at(c: Vector2i) -> float:
	if not _in_bounds(c) or world.cell_type(c.x, c.y) != WorldMap.Terrain.POISON:
		return 0.0
	var v: float = poison.get(_idx(c), 1.0)
	return 0.0 if v <= RestorationDefs.POISON_EPS else v


func is_poisoned(c: Vector2i) -> bool:
	return poison_at(c) > 0.0


## Fields / gardens: never on poison; also not on saplings, planted trees or marked cells.
func can_cultivate(c: Vector2i) -> bool:
	if is_poisoned(c):
		return false
	var i := _idx(c)
	return not (saplings.has(i) or plant_marks.has(i) or grown.has(i) or treat_marks.has(i))


## Hook for health: wells inside poison give bad water.
func water_bad_at(pos: Vector3) -> bool:
	return is_poisoned(world.cell_of(pos.x, pos.z))


func poison_cells_total() -> int:
	if _poison_total < 0:
		_poison_total = world.count_type(WorldMap.Terrain.POISON)
	return _poison_total


func poison_cells_active() -> int:
	var healed := 0
	for i in poison:
		if poison[i] <= RestorationDefs.POISON_EPS:
			healed += 1
	return poison_cells_total() - healed


## Poisoned cells (not yet healed, not yet designated/treated) under the brush.
func heal_cells_in_brush(center: Vector3, radius: float, circle: bool) -> Array[Vector2i]:
	return _brush_cells(center, radius, circle, func(c: Vector2i) -> bool:
		return is_poisoned(c) and not treat_marks.has(_idx(c)) and not treated.has(_idx(c)))


func designate_heal(cells: Array[Vector2i]) -> int:
	var n := 0
	for c in cells:
		var i := _idx(c)
		if _in_bounds(c) and is_poisoned(c) and not treat_marks.has(i) and not treated.has(i):
			treat_marks[i] = true
			n += 1
	if n > 0:
		_emit_changed()
	return n


func is_treated(c: Vector2i) -> bool:
	return treated.has(_idx(c))


# ---------- planting ----------

func can_plant(c: Vector2i, occ: Dictionary = {}) -> bool:
	if not _in_bounds(c):
		return false
	var i := _idx(c)
	if saplings.has(i) or plant_marks.has(i) or occ.has(i) or (food != null and food.fields.has(i)):
		return false
	if is_poisoned(c):
		return false
	if construction != null and construction.is_felling(c):
		return false
	match world.cell_type(c.x, c.y):
		WorldMap.Terrain.GROUND:
			return economy.deposits.remaining(c) <= 0
		WorldMap.Terrain.FOREST:
			return economy.deposits.remaining(c) <= 0
		WorldMap.Terrain.POISON:
			return false
	return false


func plant_cells_in_brush(center: Vector3, radius: float, circle: bool) -> Array[Vector2i]:
	var occ := _occupied()
	return _brush_cells(center, radius, circle, func(c: Vector2i) -> bool: return can_plant(c, occ))


func designate_plant(cells: Array[Vector2i]) -> int:
	var occ := _occupied()
	var n := 0
	for c in cells:
		if can_plant(c, occ):
			plant_marks[_idx(c)] = true
			n += 1
	if n > 0:
		_emit_changed()
	return n


func _brush_cells(center: Vector3, radius: float, circle: bool, ok: Callable) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var a := world.cell_of(center.x - radius, center.z - radius)
	var z := world.cell_of(center.x + radius, center.z + radius)
	for cz in range(maxi(a.y, 0), mini(z.y, world.size - 1) + 1):
		for cx in range(maxi(a.x, 0), mini(z.x, world.size - 1) + 1):
			var cell := Vector2i(cx, cz)
			var cc := world.cell_center(cx, cz)
			var dx := absf(cc.x - center.x)
			var dz := absf(cc.z - center.z)
			if ((circle and dx * dx + dz * dz <= radius * radius) or (not circle and maxf(dx, dz) <= radius)) and ok.call(cell):
				out.append(cell)
	return out


## Number of restored tree cells still standing (feeds ClimateSystem; natural start forest is not counted).
func planted_count() -> int:
	return grown.size()


func sapling_count() -> int:
	return saplings.size()


func state_text(c: Vector2i) -> String:
	var i := _idx(c)
	if saplings.has(i):
		return "Саженец растёт"
	if plant_marks.has(i):
		return "Здесь будут сажать лес"
	if is_poisoned(c):
		if treated.has(i):
			return "Земля оживает"
		return "Земля отравлена" + (" (лечение назначено)" if treat_marks.has(i) else "")
	if world.cell_type(c.x, c.y) == WorldMap.Terrain.POISON:
		return "Земля чистая"
	return ""


# ---------- jobs for villagers ----------

func plant_allowed() -> bool:
	return _season() != SeasonDefs.WINTER


func jobs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null or not plant_allowed():
		return out
	var n := 0
	for i in plant_marks:
		out.append({"key": "pl:%d" % i, "cat": TaskDefs.PLANT, "kind": &"plant", "target": i, "pos": world.cell_center(i % world.size, i / world.size), "tcat": TaskDefs.PLANT})
		n += 1
		if n >= RestorationDefs.JOB_CAP:
			break
	n = 0
	for i in treat_marks:
		out.append({"key": "hl:%d" % i, "cat": TaskDefs.HEAL_LAND, "kind": &"heal_land", "target": i, "pos": world.cell_center(i % world.size, i / world.size), "tcat": TaskDefs.HEAL_LAND})
		n += 1
		if n >= RestorationDefs.JOB_CAP:
			break
	return out


## A villager finished the job: planted sapling / cleansing vegetation.
func finish(kind: StringName, target: int) -> void:
	if kind == &"plant" and plant_marks.has(target):
		plant_marks.erase(target)
		saplings[target] = 0.0
	elif kind == &"heal_land" and treat_marks.has(target):
		treat_marks.erase(target)
		treated[target] = true
	else:
		return
	_emit_changed()


# ---------- recovery index ----------

func water_quality_avg() -> float:
	if water_quality.is_empty():
		return RestorationDefs.WATER_START
	var s := 0.0
	for q in water_quality:
		s += q
	return s / water_quality.size()


## 0..1: share of forest (planted), water (above start), poison (healed).
func recovery() -> float:
	return _recovery


func compute_recovery() -> float:
	var forest := minf(1.0, float(grown.size()) / RestorationDefs.FOREST_TARGET_CELLS)
	var water := clampf((water_quality_avg() - RestorationDefs.WATER_START) / (1.0 - RestorationDefs.WATER_START), 0.0, 1.0)
	var total := poison_cells_total()
	var cleaned := 1.0 if total <= 0 else float(total - poison_cells_active()) / total
	return RestorationDefs.W_FOREST * forest + RestorationDefs.W_WATER * water + RestorationDefs.W_POISON * cleaned


## Pushes recovery into wildlife, fish, birds. Called every SYNC_INTERVAL and by tests.
func sync_now() -> void:
	if world == null:
		return
	_recovery = compute_recovery()
	if climate != null:
		climate.land_recovery = _recovery
	if food != null:
		food.land_recovery = lerpf(1.0, RestorationDefs.WILDLIFE_SPEED_MAX, _recovery)
		food.wildlife_cap_mult = 1.0 + RestorationDefs.WILDLIFE_CAP_BONUS * _recovery
		for bi in mini(food.bodies.size(), water_quality.size()):
			food.bodies[bi]["cap"] = food.bodies[bi]["cap0"] * fish_multiplier(water_quality[bi])


static func fish_multiplier(q: float) -> float:
	return lerpf(RestorationDefs.FISH_MULT_MIN, RestorationDefs.FISH_MULT_MAX, clampf(q, 0.0, 1.0))


## Water clarity 0..1 for the view (quality of the cleanest water body nearest... average is enough).
func water_clarity() -> float:
	return water_quality_avg()


## Fertility of a cell: base (burnt) + slow soil recovery - poison.
func soil_fertility(c: Vector2i, base: float) -> float:
	return maxf(0.0, base + soil - poison_at(c) * RestorationDefs.POISON_FERT_PENALTY)


# ---------- tick ----------

func tick(sim: Simulation, dt: float) -> void:
	_sim = sim
	if world == null or dt <= 0.0:
		return
	var days := dt / _day_s()
	var season := _season()
	_grow_saplings(dt)
	if season != SeasonDefs.WINTER:
		_heal_poison(days)
	_clean_water(days)
	soil = minf(RestorationDefs.SOIL_MAX, soil + RestorationDefs.SOIL_GROWTH_PER_DAY * (RestorationDefs.SOIL_BASE_SHARE + _recovery) * days)
	if natural_spread and season != SeasonDefs.WINTER:
		_spread(days)
	_acc += dt
	if _acc >= RestorationDefs.SYNC_INTERVAL:
		_acc = 0.0
		_prune_grown()
		sync_now()


func _season_len() -> float:
	if seasons != null:
		return seasons.duration(SeasonDefs.SUMMER)
	return SeasonDefs.DEFAULT_MINUTES[SeasonDefs.SUMMER] * 60.0


func _grow_saplings(dt: float) -> void:
	if saplings.is_empty() or _season() == SeasonDefs.WINTER:
		return
	var step := dt / (RestorationDefs.SAPLING_GROW_SEASONS * _season_len())
	var done: Array[int] = []
	for i in saplings:
		saplings[i] = minf(1.0, saplings[i] + step)
		if saplings[i] >= 1.0:
			done.append(i)
	for i in done:
		saplings.erase(i)
		if economy.deposits.plant_trees(_cell(i), RestorationDefs.TREES_PER_PLANTED) > 0:
			grown[i] = true
	if not done.is_empty():
		_emit_changed()


func _prune_grown() -> void:
	var dead: Array[int] = []
	for i in grown:
		if economy.deposits.remaining(_cell(i)) <= 0:
			dead.append(i)  # felled: the climate bonus goes away, never cools
	for i in dead:
		grown.erase(i)
	if not dead.is_empty():
		_emit_changed()


func _heal_poison(days: float) -> void:
	if treated.is_empty():
		return
	var changed := false
	for i in treated:
		var v: float = poison.get(i, 1.0)
		if v > RestorationDefs.POISON_EPS:
			poison[i] = maxf(0.0, v - RestorationDefs.POISON_HEAL_PER_DAY * days)
			changed = true
	if changed:
		_emit_changed()


func _clean_water(days: float) -> void:
	for bi in water_quality.size():
		water_quality[bi] = minf(1.0, water_quality[bi] + RestorationDefs.WATER_CLEAN_PER_DAY * (1.0 + RestorationDefs.WATER_CLEAN_RECOVERY * _recovery) * days)


## Natural spread: slow, only into empty cells next to existing trees.
func _spread(days: float) -> void:
	_spread_acc += RestorationDefs.SPREAD_CELLS_PER_DAY * days
	if _spread_acc < 1.0:
		return
	_spread_acc -= 1.0
	if saplings.size() >= RestorationDefs.SPREAD_MAX_SAPLINGS or _sim == null:
		return
	var cands := spread_candidates()
	if cands.is_empty():
		return
	saplings[cands[_sim.rng.randi_range(0, cands.size() - 1)]] = 0.0
	_emit_changed()


## Empty cells adjacent (4-neighbourhood) to a standing tree cell.
func spread_candidates() -> Array[int]:
	var occ := _occupied()
	var seen := {}
	var out: Array[int] = []
	var s := world.size
	for cz in s:
		for cx in s:
			var c := Vector2i(cx, cz)
			if economy.deposits.resource_at(c) != &"logs" or economy.deposits.remaining(c) <= 0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if _in_bounds(n) and not seen.has(_idx(n)) and can_plant(n, occ) and economy.deposits.resource_at(n) == &"":
					seen[_idx(n)] = true
					out.append(_idx(n))
	return out


func _emit_changed() -> void:
	if _sim != null:
		_sim.bus.emit(TOPIC_CHANGED, {})


# ---------- save / load ----------

func get_save_key() -> StringName:
	return &"restoration"


func _keys(d: Dictionary) -> Array:
	return d.keys()


func save_state() -> Dictionary:
	var sp := {}
	for i in saplings:
		sp[str(i)] = saplings[i]
	var po := {}
	for i in poison:
		po[str(i)] = poison[i]
	return {"marks": _keys(plant_marks), "saplings": sp, "grown": _keys(grown), "treat_marks": _keys(treat_marks),
		"treated": _keys(treated), "poison": po, "water": water_quality.duplicate(), "soil": soil, "spread": _spread_acc}


func load_state(d: Dictionary) -> void:
	plant_marks.clear()
	saplings.clear()
	grown.clear()
	treat_marks.clear()
	treated.clear()
	poison.clear()
	for k in d.get("marks", []):
		plant_marks[SaveManager.to_int(k, -1)] = true
	if d.get("saplings") is Dictionary:
		for k in d["saplings"]:
			saplings[SaveManager.to_int(k, -1)] = clampf(float(d["saplings"][k]), 0.0, 1.0)
	for k in d.get("grown", []):
		grown[SaveManager.to_int(k, -1)] = true
	for k in d.get("treat_marks", []):
		treat_marks[SaveManager.to_int(k, -1)] = true
	for k in d.get("treated", []):
		treated[SaveManager.to_int(k, -1)] = true
	if d.get("poison") is Dictionary:
		for k in d["poison"]:
			poison[SaveManager.to_int(k, -1)] = clampf(float(d["poison"][k]), 0.0, 1.0)
	var w: Array = d.get("water", [])
	for i in water_quality.size():
		if i < w.size():
			water_quality[i] = clampf(float(w[i]), 0.0, 1.0)
	soil = clampf(float(d.get("soil", 0.0)), 0.0, RestorationDefs.SOIL_MAX)
	_spread_acc = float(d.get("spread", 0.0))
	sync_now()
	_emit_changed()
