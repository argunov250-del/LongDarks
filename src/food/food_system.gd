class_name FoodSystem
extends SimSystem
## Step 16 food (design/gdd/food.md): fields (season cycle), greenhouses, wildlife, fish
## stock, mushrooms. Pure simulation: villagers fetch jobs via jobs() and call finish().

const TOPIC_CHANGED := &"food_changed"
enum Stage { DESIGNATED, PLOWED, SOWN, RIPE }

var world: WorldMap
var economy: EconomySystem
var construction: ConstructionSystem
var seasons: SeasonSystem
var weather: WeatherSystem
var climate: ClimateSystem

## idx -> {crop, stage, growth 0..1, wsum, gsum}
var fields: Dictionary = {}
## Wildlife regions (see _init_wildlife). Hook for step 17: land_recovery multiplies regen/return speed.
var regions: Array[Dictionary] = []
var bodies: Array[Dictionary] = []            # water bodies: {n, stock, cap, spots}
var greenhouses: Dictionary = {}              # building id -> {progress, ripe, crop}
var picked: Dictionary = {}                   # forest cell idx -> true (mushrooms taken this year)
var land_recovery: float = 1.0
## Step 17 (design/gdd/land-restoration.md): RestorationSystem (optional). Capacity multipliers set by it.
var restoration: RestorationSystem
var wildlife_cap_mult: float = 1.0
var _day_t := 0.0                      # accumulated game days (hunting pressure window)
## Test hooks: force season / progress / water factor (-1 = read the real systems).
var season_override: StringName = &""
var progress_override: float = -1.0
var water_override: float = -1.0

var _sim: Simulation
var _last_season: StringName = &""
var _acc := 0.0
var _plowed_sent := -1
var _forest_sorted: PackedInt32Array = PackedInt32Array()
var _inited := false


func bind(economy_in: EconomySystem, world_in: WorldMap, construction_in: ConstructionSystem, seasons_in: SeasonSystem = null, weather_in: WeatherSystem = null, climate_in: ClimateSystem = null) -> void:
	economy = economy_in
	world = world_in
	construction = construction_in
	seasons = seasons_in
	weather = weather_in
	climate = climate_in
	_init_world()


func attach(sim: Simulation) -> void:
	_sim = sim


static func is_food_kind(kind: StringName) -> bool:
	return kind in [&"field", &"hunt", &"fish", &"forage", &"gpick", &"plant", &"heal_land"]


# ---------- season / water helpers ----------

func current_season() -> StringName:
	if season_override != &"":
		return season_override
	return seasons.season() if seasons != null else SeasonDefs.SPRING


func season_progress() -> float:
	if progress_override >= 0.0:
		return progress_override
	return seasons.progress() if seasons != null else 0.0


func _season_len(s: StringName) -> float:
	return seasons.duration(s) if seasons != null else SeasonDefs.DEFAULT_MINUTES[s] * 60.0


func _day_s() -> float:
	return _sim.clock.day_seconds() if _sim != null else 86400.0 / 96.0


## Current water factor for crops: rain helps, drought hurts.
func water_factor() -> float:
	if water_override >= 0.0:
		return water_override
	if weather != null:
		if weather.is_active(WeatherDefs.DROUGHT):
			return FoodDefs.DROUGHT_WATER
		if weather.is_active() and WeatherDefs.f(weather.current_id(), "rain", 0.0) > 0.0:
			return FoodDefs.RAIN_WATER
	return FoodDefs.NORMAL_WATER


func fertility_at(c: Vector2i) -> float:
	var f := weather.fertility_at(c) if weather != null else 0.0
	return restoration.soil_fertility(c, f) if restoration != null else f


# ---------- init ----------

func _init_world() -> void:
	if world == null:
		return
	_inited = true
	_init_wildlife()
	_init_water()
	var cells: Array[int] = []
	var f := world.factory_cell
	for cz in world.size:
		for cx in world.size:
			if world.cell_type(cx, cz) == WorldMap.Terrain.FOREST:
				cells.append(cz * world.size + cx)
	cells.sort_custom(func(a: int, b: int) -> bool:
		var da := Vector2(a % world.size - f.x, a / world.size - f.y).length_squared()
		var db := Vector2(b % world.size - f.x, b / world.size - f.y).length_squared()
		return da < db or (da == db and a < b))
	_forest_sorted = PackedInt32Array(cells)


func _init_wildlife() -> void:
	regions.clear()
	var per := FoodDefs.REGION_CELLS
	var n := ceili(float(world.size) / per)
	for rz in n:
		for rx in n:
			var cells := PackedInt32Array()
			for cz in range(rz * per, mini((rz + 1) * per, world.size)):
				for cx in range(rx * per, mini((rx + 1) * per, world.size)):
					if world.cell_type(cx, cz) == WorldMap.Terrain.FOREST:
						cells.append(cz * world.size + cx)
			if cells.size() < FoodDefs.MIN_FOREST_CELLS:
				continue
			var sp: StringName = &"deer" if cells.size() >= FoodDefs.DEER_FOREST_CELLS else &"hare"
			var cap := maxf(FoodDefs.CAP_MIN[sp], cells.size() * FoodDefs.CAP_PER_FOREST_CELL[sp])
			var c0 := cells[cells.size() / 2]
			regions.append({"id": regions.size(), "species": sp, "cap": cap, "pop": cap, "gone": false,
				"back_in": 0.0, "hunts": [], "cap0": cap, "pos": world.cell_center(c0 % world.size, c0 / world.size), "target": c0,
				"wander": 0.0, "cells": cells})


func _init_water() -> void:
	bodies.clear()
	var seen := {}
	var s := world.size
	var f := world.factory_cell
	for start in s * s:
		if seen.has(start) or not _is_water_cell(start % s, start / s):
			continue
		var comp: Array[int] = []
		var stack := [start]
		seen[start] = true
		while not stack.is_empty():
			var i: int = stack.pop_back()
			comp.append(i)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = i % s + d.x
				var nz: int = i / s + d.y
				if nx < 0 or nz < 0 or nx >= s or nz >= s:
					continue
				var j := nz * s + nx
				if not seen.has(j) and _is_water_cell(nx, nz):
					seen[j] = true
					stack.append(j)
		var shores := {}
		for i in comp:
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = i % s + d.x
				var nz: int = i / s + d.y
				if nx >= 0 and nz >= 0 and nx < s and nz < s and world.cell_type(nx, nz) == WorldMap.Terrain.GROUND:
					shores[nz * s + nx] = i
		var order: Array = shores.keys()
		order.sort_custom(func(a: int, b: int) -> bool:
			var da := Vector2(a % s - f.x, a / s - f.y).length_squared()
			var db := Vector2(b % s - f.x, b / s - f.y).length_squared()
			return da < db or (da == db and a < b))
		var spots: Array[Dictionary] = []
		for c: int in order:
			var ok := true
			for sp in spots:
				if Vector2(c % s - sp["cell"].x, c / s - sp["cell"].y).length() < FoodDefs.SPOT_SPACING:
					ok = false
			if ok:
				var w: int = shores[c]
				spots.append({"cell": Vector2i(c % s, c / s), "pos": world.cell_center(c % s, c / s), "water": world.cell_center(w % s, w / s)})
				if spots.size() >= FoodDefs.SPOTS_PER_BODY:
					break
		if spots.is_empty():
			continue
		var cap := maxf(FoodDefs.FISH_CAP_MIN, comp.size() * FoodDefs.FISH_PER_BODY_CELL)
		bodies.append({"n": comp.size(), "stock": cap, "cap": cap, "cap0": cap, "spots": spots})


func _is_water_cell(cx: int, cz: int) -> bool:
	var t := world.cell_type(cx, cz)
	return t == WorldMap.Terrain.RIVER or t == WorldMap.Terrain.LAKE


# ---------- fields: designate / queries ----------

## Free ground cells under the brush (forest must be felled first, no buildings, no water).
func field_cells_in_brush(center: Vector3, radius: float, circle: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var occupied := _occupied_cells()
	var a := world.cell_of(center.x - radius, center.z - radius)
	var z := world.cell_of(center.x + radius, center.z + radius)
	for cz in range(maxi(a.y, 0), mini(z.y, world.size - 1) + 1):
		for cx in range(maxi(a.x, 0), mini(z.x, world.size - 1) + 1):
			var cell := Vector2i(cx, cz)
			if not is_field_ground(cell) or occupied.has(cz * world.size + cx):
				continue
			var cc := world.cell_center(cx, cz)
			var dx := absf(cc.x - center.x)
			var dz := absf(cc.z - center.z)
			if (circle and dx * dx + dz * dz <= radius * radius) or (not circle and maxf(dx, dz) <= radius):
				out.append(cell)
	return out


## Ground (or already felled forest) where a field can lie.
func is_field_ground(cell: Vector2i) -> bool:
	match world.cell_type(cell.x, cell.y):
		WorldMap.Terrain.GROUND:
			return restoration == null or restoration.can_cultivate(cell)
		WorldMap.Terrain.FOREST:
			return economy.deposits.remaining(cell) <= 0 and (restoration == null or restoration.can_cultivate(cell))
		WorldMap.Terrain.POISON:
			return restoration != null and restoration.can_cultivate(cell)
	return false


func _occupied_cells() -> Dictionary:
	var occ := {}
	if construction == null:
		return occ
	for b: Building in construction.buildings.values():
		for c in construction.footprint_cells(Vector2(b.position.x, b.position.z), b.size(), b.rot):
			occ[c.y * world.size + c.x] = true
	return occ


## Marks cells as a field with the crop (re-designating an unplowed cell changes the crop). Returns new/changed count.
func designate(cells: Array[Vector2i], crop: StringName) -> int:
	if not FoodDefs.CROPS.has(crop):
		return 0
	var n := 0
	for c in cells:
		if not is_field_ground(c):
			continue
		var i := c.y * world.size + c.x
		if fields.has(i):
			if fields[i]["stage"] == Stage.DESIGNATED and fields[i]["crop"] != crop:
				fields[i]["crop"] = crop
				n += 1
			continue
		fields[i] = {"crop": crop, "stage": Stage.DESIGNATED, "growth": 0.0, "wsum": 0.0, "gsum": 0.0}
		n += 1
	if n > 0:
		_emit_changed()
	return n


func field_at(cell: Vector2i) -> Dictionary:
	return fields.get(cell.y * world.size + cell.x, {})


func plowed_count() -> int:
	var n := 0
	for f in fields.values():
		if f["stage"] >= Stage.PLOWED:
			n += 1
	return n


## What can be done with the cell now (&"" — nothing in this season).
func field_action(idx: int) -> StringName:
	if not fields.has(idx):
		return &""
	var season := current_season()
	var st: int = fields[idx]["stage"]
	if season == SeasonDefs.SPRING:
		if st == Stage.DESIGNATED:
			return &"plow"
		if st == Stage.PLOWED:
			return &"sow"
	elif season == SeasonDefs.AUTUMN and st == Stage.RIPE:
		return &"harvest"
	return &""


## Water factor averaged over the crop's life; before any growth, the current factor.
func cell_water(idx: int) -> float:
	var f: Dictionary = fields[idx]
	var w: float = (f["wsum"] / f["gsum"]) if f["gsum"] > 0.0 else water_factor()
	return clampf(w, FoodDefs.WATER_MIN, FoodDefs.WATER_MAX)


func expected_yield(idx: int) -> int:
	if not fields.has(idx):
		return 0
	var f: Dictionary = fields[idx]
	var fert := fertility_at(Vector2i(idx % world.size, idx / world.size))
	return maxi(1, roundi(FoodDefs.BASE_YIELD[f["crop"]] * (1.0 + fert * FoodDefs.FERTILITY_GAIN) * cell_water(idx)))


func stage_text(idx: int) -> String:
	if not fields.has(idx):
		return ""
	var st: int = fields[idx]["stage"]
	if st == Stage.SOWN:
		return "%s %d%%" % [FoodDefs.STAGE_NAMES_GROWING, roundi(fields[idx]["growth"] * 100.0)]
	return FoodDefs.STAGE_NAMES[st]


## One-line panel text for a field cell: crop, stage, expected yield.
func field_text(cell: Vector2i) -> String:
	var i := cell.y * world.size + cell.x
	if not fields.has(i):
		return ""
	return "Поле: %s, %s, ожидаемый урожай ~%d" % [FoodDefs.CROP_NAMES[fields[i]["crop"]].to_lower(), stage_text(i), expected_yield(i)]


# ---------- greenhouses ----------

func _gh(id: int) -> Dictionary:
	if not greenhouses.has(id):
		greenhouses[id] = {"progress": 0.0, "ripe": 0, "crop": &"vegetables"}
	return greenhouses[id]


func greenhouse_ids() -> Array[int]:
	var out: Array[int] = []
	if construction == null:
		return out
	for id in construction.buildings:
		var b: Building = construction.buildings[id]
		if BuildingDefs.is_greenhouse(b.type) and b.is_done():
			out.append(id)
	out.sort()
	return out


func set_greenhouse_crop(id: int, crop: StringName) -> void:
	if FoodDefs.GREENHOUSE_CROPS.has(crop):
		_gh(id)["crop"] = crop


func greenhouse_text(id: int) -> String:
	var g := _gh(id)
	return "Теплица: %s, рост %d%%, готово %d (растёт круглый год, без отопления)" % [FoodDefs.CROP_NAMES[g["crop"]].to_lower(), roundi(g["progress"] * 100.0), g["ripe"]]


# ---------- wildlife / fish / mushrooms queries ----------

func region_visible_animals(r: Dictionary) -> int:
	return 0 if r["gone"] else int(floor(r["pop"] / FoodDefs.ANIMAL_PER_VISIBLE))


## Vague hint for the hunter task panel: «зверя много / мало / ушёл».
func hunt_hint() -> String:
	var best := -1.0
	for r in regions:
		if not r["gone"] and r["pop"] >= 1.0:
			best = maxf(best, r["pop"] / r["cap"])
	if best < 0.0:
		return "зверь ушёл"
	return "зверя много" if best >= FoodDefs.HINT_MANY else "зверя мало"


func fish_hint() -> String:
	var best := -1.0
	for b in bodies:
		if b["stock"] >= 1.0:
			best = maxf(best, b["stock"] / b["cap"])
	if best < 0.0:
		return "рыбы нет"
	return "рыбы много" if best >= FoodDefs.HINT_MANY else "рыбы мало"


func mushroom_density() -> float:
	var s := current_season()
	if s == SeasonDefs.AUTUMN:
		return FoodDefs.MUSHROOM_DENSITY[&"autumn"]
	if s == SeasonDefs.SUMMER and season_progress() >= FoodDefs.MUSHROOM_SUMMER_FROM:
		return FoodDefs.MUSHROOM_DENSITY[&"summer"]
	return 0.0


func has_mushrooms(idx: int) -> bool:
	var d := mushroom_density()
	if d <= 0.0 or picked.has(idx):
		return false
	var c := Vector2i(idx % world.size, idx / world.size)
	return world.cell_type(c.x, c.y) == WorldMap.Terrain.FOREST and economy.deposits.remaining(c) > 0 \
		and world.hash01(c.x, c.y, FoodDefs.SALT_MUSHROOM) < d


# ---------- jobs for villagers ----------

func _job(key: String, cat: StringName, kind: StringName, target: int, pos: Vector3) -> Dictionary:
	return {"key": key, "cat": cat, "kind": kind, "target": target, "pos": pos, "tcat": cat}


## Open food jobs (no priorities/weather filtering: VillagerSystem does that per category).
func jobs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null:
		return out
	# fields: harvest first, then sow, then plow
	for action in [&"harvest", &"sow", &"plow"]:
		var n := 0
		for i in fields:
			if field_action(i) == action and n < FoodDefs.FIELD_JOB_CAP:
				n += 1
				out.append(_job("fd:%d" % i, TaskDefs.FIELD, &"field", i, world.cell_center(i % world.size, i / world.size)))
	for r in regions:
		if not r["gone"] and r["pop"] >= 1.0:
			out.append(_job("hn:%d" % r["id"], TaskDefs.HUNT, &"hunt", r["id"], r["pos"]))
	for bi in bodies.size():
		if bodies[bi]["stock"] >= 1.0:
			for si in bodies[bi]["spots"].size():
				out.append(_job("fs:%d:%d" % [bi, si], TaskDefs.FISH, &"fish", bi * 10 + si, bodies[bi]["spots"][si]["pos"]))
	if mushroom_density() > 0.0:
		var n := 0
		for i in _forest_sorted:
			if has_mushrooms(i):
				out.append(_job("mu:%d" % i, TaskDefs.FORAGE, &"forage", i, world.cell_center(i % world.size, i / world.size)))
				n += 1
				if n >= FoodDefs.MUSHROOM_JOB_CAP:
					break
	for id in greenhouse_ids():
		var b := construction.get_building(id)
		var g := _gh(id)
		if g["ripe"] > 0:
			out.append(_job("gp:%d" % id, TaskDefs.GREENHOUSE, &"gpick", id, b.position))
	if restoration != null:
		out.append_array(restoration.jobs())
	return out


## Where the work for a job happens; null — target gone.
func site_pos(kind: StringName, target: int) -> Variant:
	if kind == &"plant" or kind == &"heal_land":
		return world.cell_center(target % world.size, target / world.size)
	match kind:
		&"field", &"forage":
			return world.cell_center(target % world.size, target / world.size)
		&"hunt":
			return regions[target]["pos"] if target >= 0 and target < regions.size() else null
		&"fish":
			return bodies[target / 10]["spots"][target % 10]["pos"] if target / 10 < bodies.size() else null
		&"gpick":
			var b := construction.get_building(target)
			return b.position if b != null else null
	return null


func site_radius(kind: StringName) -> float:
	match kind:
		&"hunt":
			return FoodDefs.HUNT_RANGE
		&"fish":
			return FoodDefs.FISH_RANGE
	return 1.4


## Work needed to complete the job now (at rate 1.0).
func work_need(kind: StringName, target: int) -> float:
	if kind == &"plant" or kind == &"heal_land":
		return RestorationDefs.PLANT_WORK if kind == &"plant" else RestorationDefs.HEAL_WORK
	match kind:
		&"field":
			return FoodDefs.WORK.get(field_action(target), 1.0)
	return FoodDefs.WORK.get(kind, 1.0)


## Completes a job: applies world effects, returns what the worker carries ({res, n} or {}).
func finish(kind: StringName, target: int) -> Dictionary:
	if kind == &"plant" or kind == &"heal_land":
		if restoration != null:
			restoration.finish(kind, target)
		return {}
	match kind:
		&"field":
			var a := field_action(target)
			var f: Dictionary = fields.get(target, {})
			if a == &"plow":
				f["stage"] = Stage.PLOWED
			elif a == &"sow":
				f["stage"] = Stage.SOWN
				f["growth"] = 0.0
				f["wsum"] = 0.0
				f["gsum"] = 0.0
			elif a == &"harvest":
				var n := expected_yield(target)
				var crop: StringName = f["crop"]
				f["stage"] = Stage.DESIGNATED
				f["growth"] = 0.0
				_emit_changed()
				return {"res": crop, "n": n}
			_emit_changed()
		&"hunt":
			var r: Dictionary = regions[target]
			if r["gone"] or r["pop"] < 1.0:
				return {}
			r["pop"] -= 1.0
			# decision 3 (approved): the herd leaves when hunted too often, whatever its size
			r["hunts"].append(_day_t)
			if hunt_pressure(r) > FoodDefs.HUNT_PRESSURE_MAX:
				r["gone"] = true
				r["back_in"] = FoodDefs.RETURN_DAYS
			return {"res": &"meat", "n": FoodDefs.MEAT_PER_KILL[r["species"]]}
		&"fish":
			var b: Dictionary = bodies[target / 10]
			if b["stock"] < 1.0:
				return {}
			b["stock"] -= 1.0
			return {"res": &"fish", "n": FoodDefs.FISH_PER_CATCH}
		&"forage":
			if not has_mushrooms(target):
				return {}
			picked[target] = true
			return {"res": &"mushrooms", "n": FoodDefs.MUSHROOM_PER_PICK}
		&"gpick":
			var g := _gh(target)
			var n: int = g["ripe"]
			g["ripe"] = 0
			return {"res": g["crop"], "n": n} if n > 0 else {}
	return {}


## Hunts in this area within the recent window (design/gdd/food.md, decision 3).
func hunt_pressure(r: Dictionary) -> int:
	var hunts: Array = r["hunts"]
	while not hunts.is_empty() and hunts[0] < _day_t - FoodDefs.HUNT_WINDOW_DAYS:
		hunts.pop_front()
	return hunts.size()


# ---------- tick ----------

func tick(sim: Simulation, dt: float) -> void:
	_sim = sim
	if world == null or dt <= 0.0:
		return
	var season := current_season()
	if season != _last_season:
		_on_season_change(season)
		_last_season = season
	var days := dt / _day_s()
	_day_t += days
	_grow_fields(season, dt)
	_tick_greenhouses(days)
	_tick_wildlife(dt, days)
	for b in bodies:
		b["stock"] += FoodDefs.FISH_REGEN_PER_DAY * land_recovery * maxf(b["stock"], FoodDefs.FISH_MIN_BREEDERS) * (1.0 - b["stock"] / b["cap"]) * days
		b["stock"] = clampf(b["stock"], 0.0, b["cap"])
	_acc += dt
	if _acc >= 1.0:
		_acc = 0.0
		_sync_climate()


func _on_season_change(season: StringName) -> void:
	if season == SeasonDefs.WINTER:
		# unharvested / unripe crops and unsown plowing are lost: nothing in winter
		for f in fields.values():
			f["stage"] = Stage.DESIGNATED
			f["growth"] = 0.0
	elif season == SeasonDefs.SPRING:
		picked.clear()
	_emit_changed()


func _grow_fields(season: StringName, dt: float) -> void:
	if season != SeasonDefs.SUMMER and season != SeasonDefs.AUTUMN:
		return
	var w := water_factor()
	var step := FoodDefs.GROW_SPEED * dt / _season_len(SeasonDefs.SUMMER)
	var ripened := false
	for f in fields.values():
		if f["stage"] != Stage.SOWN:
			continue
		f["growth"] = minf(1.0, f["growth"] + step)
		f["wsum"] += w * dt
		f["gsum"] += dt
		if f["growth"] >= 1.0:
			f["stage"] = Stage.RIPE
			ripened = true
	if ripened:
		_emit_changed()


func _tick_greenhouses(days: float) -> void:
	for id in greenhouse_ids():
		var g := _gh(id)
		if g["ripe"] >= FoodDefs.GREENHOUSE_MAX_RIPE:
			continue
		g["progress"] += days / FoodDefs.GREENHOUSE_GROW_DAYS
		if g["progress"] >= 1.0:
			g["progress"] = 0.0
			g["ripe"] = mini(FoodDefs.GREENHOUSE_MAX_RIPE, g["ripe"] + FoodDefs.GREENHOUSE_YIELD)


func _tick_wildlife(dt: float, days: float) -> void:
	for r in regions:
		if r["gone"]:
			r["back_in"] -= days * land_recovery
			if r["back_in"] <= 0.0 and hunt_pressure(r) <= FoodDefs.HUNT_RETURN_PRESSURE:
				r["gone"] = false
				r["hunts"].clear()
				r["pop"] = maxf(r["pop"], r["cap"] * FoodDefs.RETURN_FRACTION)
			continue
		r["cap"] = r["cap0"] * wildlife_cap_mult
		r["pop"] = minf(r["pop"], r["cap"])
		r["pop"] = minf(r["cap"], r["pop"] + FoodDefs.REGEN_PER_DAY * land_recovery * maxf(r["pop"], FoodDefs.MIN_BREEDERS) * (1.0 - r["pop"] / r["cap"]) * days)
		# wander inside the region's forest
		r["wander"] -= dt
		if r["wander"] <= 0.0 and _sim != null:
			r["wander"] = FoodDefs.WANDER_INTERVAL
			var cells: PackedInt32Array = r["cells"]
			for _try in 4:
				var cand := cells[_sim.rng.randi_range(0, cells.size() - 1)]
				r["target"] = cand
				if restoration == null or not restoration.is_poisoned(Vector2i(cand % world.size, cand / world.size)):
					break  # animals avoid poisoned cells
		var tp := world.cell_center(int(r["target"]) % world.size, int(r["target"]) / world.size)
		var d := Vector3(tp.x - r["pos"].x, 0.0, tp.z - r["pos"].z)
		if d.length() > 0.1:
			var step := minf(d.length(), FoodDefs.WANDER_SPEED * dt)
			var np: Vector3 = r["pos"] + d.normalized() * step
			np.y = world.height_at(np.x, np.z)
			r["pos"] = np


func _sync_climate() -> void:
	var n := plowed_count()
	if climate != null and n != _plowed_sent:
		climate.set_plowed_cells(n)
	_plowed_sent = n


func _emit_changed() -> void:
	if _sim != null:
		_sim.bus.emit(TOPIC_CHANGED, {})


# ---------- save / load ----------

func get_save_key() -> StringName:
	return &"food"


func save_state() -> Dictionary:
	var fl := {}
	for i in fields:
		var f: Dictionary = fields[i]
		fl[str(i)] = [String(f["crop"]), f["stage"], f["growth"], f["wsum"], f["gsum"]]
	var rl := []
	for r in regions:
		rl.append([r["pop"], r["gone"], r["back_in"], r["pos"].x, r["pos"].z, r["target"], r["hunts"].duplicate()])
	var bl := []
	for b in bodies:
		bl.append(b["stock"])
	var gl := {}
	for id in greenhouses:
		var g: Dictionary = greenhouses[id]
		gl[str(id)] = [0.0, g["progress"], g["ripe"], String(g["crop"])]
	var pk := []
	for i in picked:
		pk.append(i)
	return {"fields": fl, "regions": rl, "bodies": bl, "greenhouses": gl, "picked": pk,
		"season": String(_last_season), "recovery": land_recovery, "day_t": _day_t}


func load_state(d: Dictionary) -> void:
	fields.clear()
	greenhouses.clear()
	picked.clear()
	if d.get("fields") is Dictionary:
		for k in d["fields"]:
			var a: Array = d["fields"][k]
			if a.size() >= 5 and FoodDefs.CROPS.has(StringName(String(a[0]))):
				fields[SaveManager.to_int(k, -1)] = {"crop": StringName(String(a[0])), "stage": clampi(SaveManager.to_int(a[1], 0), 0, 3),
					"growth": float(a[2]), "wsum": float(a[3]), "gsum": float(a[4])}
	if d.get("regions") is Array:
		var rl: Array = d["regions"]
		for i in mini(rl.size(), regions.size()):
			var a: Array = rl[i]
			if a.size() >= 6:
				var r := regions[i]
				r["pop"] = clampf(float(a[0]), 0.0, r["cap"])
				r["gone"] = bool(a[1])
				r["back_in"] = float(a[2])
				r["pos"] = Vector3(float(a[3]), world.height_at(float(a[3]), float(a[4])), float(a[4]))
				r["target"] = SaveManager.to_int(a[5], r["target"])
				r["hunts"] = []
				if a.size() >= 7 and a[6] is Array:
					for h in a[6]:
						r["hunts"].append(float(h))
	if d.get("bodies") is Array:
		var bl: Array = d["bodies"]
		for i in mini(bl.size(), bodies.size()):
			bodies[i]["stock"] = clampf(float(bl[i]), 0.0, bodies[i]["cap"])
	if d.get("greenhouses") is Dictionary:
		for k in d["greenhouses"]:
			var a: Array = d["greenhouses"][k]
			if a.size() >= 4:
				greenhouses[SaveManager.to_int(k, -1)] = {"progress": float(a[1]), "ripe": SaveManager.to_int(a[2], 0), "crop": StringName(String(a[3]))}
	if d.get("picked") is Array:
		for i in d["picked"]:
			picked[SaveManager.to_int(i, -1)] = true
	_last_season = StringName(String(d.get("season", "")))
	land_recovery = float(d.get("recovery", 1.0))
	_day_t = float(d.get("day_t", 0.0))
	_plowed_sent = -1
	_emit_changed()
