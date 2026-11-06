class_name StartState
extends RefCounted
## Стартовое состояние новой игры (шаг 13): ВСЕ константы — здесь.
## Герой и собака (создаёт VillagerSystem.start_new_game), готовая землянка с двором,
## в которой живёт герой, небольшой запас еды и воды в доме и на складе, большой запас дров.
## Игра начинается в конце зимы.

const STORAGE_CAPACITY := 500
## Склад у завода. Еды и воды немного, дров много (зима только уходит, а печи топят до +5 °C).
const STORAGE_RESOURCES := {
	&"logs": 20, &"planks": 10, &"stone": 10, &"scrap_metal": 15,
	&"firewood": 120, &"potato": 6, &"grain": 4, &"spare_parts": 5,
}

const HOUSE_TYPE := &"dugout"
## Место стартового дома: ближайшее к центру посёлка, где дом и двор (с запасом POISON_BUFFER_CELLS)
## не касаются отравленной земли, нет воды/крутого склона/леса под основанием, а лес и вода рядом.
const POISON_BUFFER_CELLS := 4
const FOREST_NEAR_CELLS := 8                    # лес не дальше (от центра дома), клеток
const WATER_NEAR_CELLS := 24                    # вода не дальше, клеток
const SITE_SEARCH_CELLS := 56                   # радиус поиска от центра посёлка, клеток
const HOUSE_FOOD := {&"potato": 8, &"grain": 4}
const HOUSE_WATER := 10
const HOUSE_WOODPILE := 10                      # колотые дрова на поленнице (до ёмкости)
const HOUSE_STOVE := 4                          # дрова в печи (до ёмкости)
const HOUSE_STOVE_LIT := 0.6                    # печь уже топится (остаток закладки 0..1)

const START_SEASON := SeasonDefs.WINTER
const START_SEASON_PROGRESS := 0.8              # последние ~20% зимы


static func create_storage(world: WorldMap, economy: EconomySystem) -> Storage:
	var f := world.factory_cell
	var s := Storage.new(STORAGE_CAPACITY, world.cell_center(f.x, f.y))
	economy.add_storage(s)
	for k in STORAGE_RESOURCES:
		s.add(k, STORAGE_RESOURCES[k])
	return s


## Ставит календарь, землянку с двором и запасами, селит героя. Возвращает id дома (-1 — нет места).
static func populate(construction: ConstructionSystem, villagers: VillagerSystem, seasons: SeasonSystem) -> int:
	if seasons != null:
		seasons.start_at(START_SEASON, START_SEASON_PROGRESS)
	var site := find_house_site(construction, villagers.hub_position())
	if site == Vector3.INF:
		return -1
	var id := construction.place_completed(HOUSE_TYPE, site, 0.0)
	if id <= 0:
		return -1
	var hs := villagers.household
	hs.sync()
	var h := hs.home(id)
	for res in HOUSE_FOOD:
		hs.add_food(id, res, HOUSE_FOOD[res])
	hs.add_water(id, HOUSE_WATER)
	h.woodpile = mini(HOUSE_WOODPILE, hs.woodpile_capacity(id))
	h.stove = mini(HOUSE_STOVE, hs.stove_capacity(id))
	h.burn_left = HOUSE_STOVE_LIT
	var b := construction.get_building(id)
	h.warmth = minf(1.0, NeedsDefs.unheated_warmth(b.type, hs.outdoor_cold) + NeedsDefs.STOVE_HEAT)
	var hero := villagers.get_hero()
	if hero != null:
		hero.home_id = id
		var d := hs.door_pos(b)
		hero.pos = villagers._ground(villagers.pathfinder.nearest_walkable(d + Vector3(1.5, 0.0, 1.0)))
		if villagers.dog != null:
			villagers.dog.pos = villagers._ground(villagers.pathfinder.nearest_walkable(hero.pos + Vector3(-1.5, 0.0, -1.0)))
	return id


## Клетки, которые накрывают дом и двор (по габаритам частей), расширенные на margin клеток.
static func site_cells(world: WorldMap, pos: Vector3, rot: float, margin: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for part in BuildingDefs.world_parts(HOUSE_TYPE, Vector2(pos.x, pos.z), rot):
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in Footprint.corners(part["c"], part["size"], rot):
			lo = lo.min(p)
			hi = hi.max(p)
		var a := world.cell_of(lo.x, lo.y) - Vector2i(margin, margin)
		var b := world.cell_of(hi.x, hi.y) + Vector2i(margin, margin)
		for cz in range(a.y, b.y + 1):
			for cx in range(a.x, b.x + 1):
				var c := Vector2i(cx, cz)
				if not out.has(c):
					out.append(c)
	return out


static func _touches(world: WorldMap, cells: Array[Vector2i], t: int) -> bool:
	for c in cells:
		if c.x >= 0 and c.y >= 0 and c.x < world.size and c.y < world.size and world.cell_type(c.x, c.y) == t:
			return true
	return false


static func _near(world: WorldMap, center: Vector2i, r: int, water: bool) -> bool:
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cx := center.x + dx
			var cz := center.y + dz
			if cx < 0 or cz < 0 or cx >= world.size or cz >= world.size or dx * dx + dz * dz > r * r:
				continue
			var t := world.cell_type(cx, cz)
			if (water and WorldMap.is_water_type(t)) or (not water and t == WorldMap.Terrain.FOREST):
				return true
	return false


## Стартовое место (Vector3.INF — не нашлось): ближайшая к hub подходящая клетка.
## Сначала со всеми условиями, затем без требования «вода рядом», затем без «лес рядом».
static func find_house_site(construction: ConstructionSystem, hub: Vector3) -> Vector3:
	var world := construction.world
	var hc := world.cell_of(hub.x, hub.z)
	var cand: Array[Vector2i] = []
	for dz in range(-SITE_SEARCH_CELLS, SITE_SEARCH_CELLS + 1):
		for dx in range(-SITE_SEARCH_CELLS, SITE_SEARCH_CELLS + 1):
			cand.append(Vector2i(dx, dz))
	cand.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var la := a.length_squared()
		var lb := b.length_squared()
		return la < lb or (la == lb and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	for relax in 3:
		for d in cand:
			var c := hc + d
			if c.x < 0 or c.y < 0 or c.x >= world.size or c.y >= world.size:
				continue
			var p := world.cell_center(c.x, c.y)
			if _touches(world, site_cells(world, p, 0.0, POISON_BUFFER_CELLS), WorldMap.Terrain.POISON):
				continue
			if relax < 2 and not _near(world, c, FOREST_NEAR_CELLS, false):
				continue
			if relax < 1 and not _near(world, c, WATER_NEAR_CELLS, true):
				continue
			if not construction.placement_tree_cells(HOUSE_TYPE, p, 0.0).is_empty():
				continue  # без леса под домом: стартовый дом не ждёт вырубки
			if not construction.validate_placement(HOUSE_TYPE, p, 0.0)["ok"]:
				continue  # вода, крутой склон, край карты, другие здания
			return p
	return Vector3.INF
