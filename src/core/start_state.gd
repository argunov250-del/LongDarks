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
const HOUSE_OFFSET := Vector3(14.0, 0.0, 0.0)   # от центра посёлка (ищется ближайшее свободное место)
const HOUSE_FOOD := {&"potato": 8, &"grain": 4}
const HOUSE_WATER := 6
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
	var hub := villagers.hub_position()
	var id := -1
	for k in 60:
		var p := hub + HOUSE_OFFSET + Vector3(k * 1.5, 0.0, (k % 5) * 6.0)
		if not construction.placement_tree_cells(HOUSE_TYPE, p, 0.0).is_empty():
			continue  # без леса: стартовый дом не должен ждать вырубки
		id = construction.place_completed(HOUSE_TYPE, p, 0.0)
		if id > 0:
			break
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
