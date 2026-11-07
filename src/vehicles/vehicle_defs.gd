class_name VehicleDefs
extends RefCounted
## Vehicle types and ALL vehicle balance (placeholders) — one place.
## Design: design/gdd/vehicles.md. Names are FICTIONAL (no real brands).

const DRIVE := &"drive"   # task category «Вождение» (TaskDefs.DRIVE mirrors it)

const TYPES: Array[StringName] = [&"truck", &"pickup", &"offroad", &"tractor", &"combine", &"excavator", &"bulldozer", &"crane", &"atv", &"snowmobile"]

## role: haul | plow | harvest | assist.  units: carry capacity (items); max_kg: payload;
## tank: litres; fuel_km: L per km (inflated for the small map); work_fuel: L/s while working;
## mud/snow: traction 0..1 (1 = no trouble); cold: warm-up factor in frost;
## work: work-speed mult for plow/harvest; site: {build,dismantle,road} multipliers at a site;
## repair_cost/gain: one workshop step. color: placeholder mesh body colour.
const DEFS := {
	&"truck": {"name": "Грузовик", "role": &"haul", "speed": 5.0, "units": 80, "max_kg": 3000.0, "tank": 120.0, "fuel_km": 3.0, "work_fuel": 0.0,
		"mud": 0.35, "snow": 0.40, "cold": 1.3, "repair_cost": {&"spare_parts": 2}, "color": Color(0.35, 0.45, 0.30)},
	&"pickup": {"name": "Пикап", "role": &"haul", "speed": 6.5, "units": 24, "max_kg": 800.0, "tank": 60.0, "fuel_km": 2.0, "work_fuel": 0.0,
		"mud": 0.45, "snow": 0.50, "cold": 1.0, "repair_cost": {&"spare_parts": 1}, "color": Color(0.70, 0.55, 0.25)},
	&"offroad": {"name": "Бортовой внедорожник", "role": &"haul", "speed": 5.0, "units": 50, "max_kg": 2000.0, "tank": 100.0, "fuel_km": 3.5, "work_fuel": 0.0,
		"mud": 0.70, "snow": 0.70, "cold": 1.0, "repair_cost": {&"spare_parts": 2}, "color": Color(0.55, 0.50, 0.30)},
	&"tractor": {"name": "Трактор", "role": &"plow", "speed": 3.5, "units": 0, "max_kg": 0.0, "tank": 90.0, "fuel_km": 4.0, "work_fuel": 0.004,
		"mud": 0.80, "snow": 0.70, "cold": 1.3, "work": 2.5, "repair_cost": {&"spare_parts": 2}, "color": Color(0.75, 0.30, 0.20)},
	&"combine": {"name": "Комбайн", "role": &"harvest", "speed": 2.8, "units": 0, "max_kg": 0.0, "tank": 150.0, "fuel_km": 6.0, "work_fuel": 0.005,
		"mud": 0.35, "snow": 0.40, "cold": 1.3, "work": 3.0, "repair_cost": {&"spare_parts": 3}, "color": Color(0.80, 0.65, 0.15)},
	&"excavator": {"name": "Экскаватор", "role": &"assist", "speed": 2.2, "units": 0, "max_kg": 0.0, "tank": 140.0, "fuel_km": 6.0, "work_fuel": 0.006,
		"mud": 0.50, "snow": 0.50, "cold": 1.3, "site": {"build": 1.6, "dismantle": 1.8, "road": 1.5}, "repair_cost": {&"spare_parts": 3}, "color": Color(0.85, 0.70, 0.10)},
	&"bulldozer": {"name": "Бульдозер", "role": &"assist", "speed": 2.6, "units": 0, "max_kg": 0.0, "tank": 130.0, "fuel_km": 6.0, "work_fuel": 0.006,
		"mud": 0.85, "snow": 0.85, "cold": 1.3, "site": {"build": 1.4, "dismantle": 1.5, "road": 2.0}, "repair_cost": {&"spare_parts": 3}, "color": Color(0.80, 0.55, 0.10)},
	&"crane": {"name": "Кран", "role": &"assist", "speed": 2.4, "units": 0, "max_kg": 0.0, "tank": 160.0, "fuel_km": 7.0, "work_fuel": 0.005,
		"mud": 0.30, "snow": 0.35, "cold": 1.3, "site": {"build": 1.5, "dismantle": 1.5, "road": 1.0}, "repair_cost": {&"spare_parts": 3}, "color": Color(0.30, 0.50, 0.70)},
	&"atv": {"name": "Вездеход", "role": &"haul", "speed": 4.2, "units": 30, "max_kg": 1200.0, "tank": 110.0, "fuel_km": 4.0, "work_fuel": 0.0,
		"mud": 0.95, "snow": 0.95, "cold": 1.1, "repair_cost": {&"spare_parts": 2, &"scrap_metal": 1}, "color": Color(0.45, 0.55, 0.40)},
	&"snowmobile": {"name": "Снегоход", "role": &"haul", "speed": 7.0, "units": 8, "max_kg": 200.0, "tank": 30.0, "fuel_km": 1.5, "work_fuel": 0.0,
		"mud": 0.40, "snow": 1.00, "cold": 0.5, "repair_cost": {&"spare_parts": 1}, "color": Color(0.80, 0.30, 0.25)},
}

## FICTIONAL model names (per type).
const MODEL_NAMES := {
	&"truck": "Бурун-5", &"pickup": "Шмель-2", &"offroad": "Вьюн-66", &"tractor": "Пахарь-Т", &"combine": "Колос-3",
	&"excavator": "Копач-4", &"bulldozer": "Толкач-Д", &"crane": "Жираф-К", &"atv": "Ёж-ГТ", &"snowmobile": "Снегирь-1",
}

## Start: 4 abandoned vehicles near ruins, different condition and residual fuel (litres).
const START_VEHICLES := [
	{"type": &"pickup", "condition": 0.50, "fuel": 6.0},
	{"type": &"truck", "condition": 0.25, "fuel": 9.0},
	{"type": &"tractor", "condition": 0.35, "fuel": 12.0},
	{"type": &"atv", "condition": 0.10, "fuel": 5.0},
]
const START_RUIN_MIN_GAP := 16.0     # m between start vehicles' ruins
const START_OFFSET := 5.0            # m from the ruin
## Hook: finds in ruins (chance per dismantled ruin, deterministic by cell hash).
const RUIN_FIND_CHANCE := 0.12
const RUIN_FINDS := [
	{"type": &"truck", "weight": 2, "cmin": 0.1, "cmax": 0.4, "fuel": 8.0},
	{"type": &"offroad", "weight": 2, "cmin": 0.1, "cmax": 0.4, "fuel": 8.0},
	{"type": &"combine", "weight": 1, "cmin": 0.05, "cmax": 0.3, "fuel": 10.0},
	{"type": &"excavator", "weight": 1, "cmin": 0.05, "cmax": 0.3, "fuel": 10.0},
	{"type": &"bulldozer", "weight": 1, "cmin": 0.05, "cmax": 0.3, "fuel": 10.0},
	{"type": &"crane", "weight": 1, "cmin": 0.05, "cmax": 0.3, "fuel": 10.0},
	{"type": &"snowmobile", "weight": 2, "cmin": 0.2, "cmax": 0.5, "fuel": 4.0},
]
const MAX_VEHICLES := 14

const DRIVABLE_CONDITION := 0.6      # at/above this the vehicle may drive (workshop repair)
const REPAIR_GAIN := 0.1

## --- Drivers ---
const DRIVER_SPEED_MIN := 0.8        # skill 0
const DRIVER_SPEED_MAX := 1.3        # skill 1
const START_BASE := 2.0              # s, engine start
const START_PER_DEG := 1.2           # s per degree of frost (x type cold factor)
const START_MAX := 90.0
const START_SKILL_RELIEF := 0.4      # skill 1 cuts the delay by 40%
const COOL_TIME := 600.0             # s parked until the engine is cold
const DEFAULT_TEMP := 15.0

## --- Cargo / terrain ---
const UNIT_KG := {&"logs": 40.0, &"planks": 20.0, &"stone": 30.0, &"scrap_metal": 25.0, &"firewood": 10.0, &"spare_parts": 8.0}
const UNIT_KG_DEFAULT := 5.0
const LOAD_SPEED_LOSS := 0.35        # speed lost at full load
const LOAD_SLIP := 0.8               # extra slip at full load
const LOAD_FUEL := 0.5               # extra fuel at full load
const SLIP_SPEED_LOSS := 0.6         # speed lost at slip 1
const STUCK_PER_M := 0.02            # stuck accumulator per metre at slip 1
const STUCK_TIME := 60.0             # s stuck (reduced by driver skill)
const ROAD_SPEED_MULT := 1.5
const ROAD_SLIP_RELIEF := 0.7
const RUT_SLIP_RELIEF := 0.3
const MIN_SPEED_FRAC := 0.15
const MAX_SLOPE := 0.6               # rise/run a vehicle can climb

## --- Missions ---
const HAUL_MIN_IMBALANCE := 0.2
const LOAD_TIME := 6.0
const UNLOAD_TIME := 6.0
const ASSIST_MAX_TIME := 240.0
const MAX_SITE_MULT := 3.0
const MAX_CHAIN := 6
const ARRIVE_RADIUS := 4.0
const FIELD_RADIUS := 2.5
const SITE_RADIUS := 7.0

## --- Roads (player brush) ---
const ROAD_COST := {&"stone": 1}     # per cell
const ROAD_WORK := 6.0
const ROAD_JOB_CAP := 6
const ROAD_PATH_WEIGHT := 0.5

## --- Procedural trails: footpaths (walkers) and ruts (vehicles); decay when unused ---
const FOOT_FULL_PASSES := 12.0
const FOOT_SPEED_BONUS := 0.2
const FOOT_DECAY_PER_DAY := 2.0
const RUT_FULL_PASSES := 8.0
const RUT_SPEED_BONUS := 0.2
const RUT_DECAY_PER_DAY := 1.5
const TRAIL_VISIBLE := 0.25          # level from which a layer is drawn


static func def(type: StringName) -> Dictionary:
	return DEFS.get(type, DEFS[&"truck"])


static func type_name(type: StringName) -> String:
	return def(type)["name"]


static func role(type: StringName) -> StringName:
	return def(type)["role"]


static func unit_kg(res: StringName) -> float:
	return UNIT_KG.get(res, UNIT_KG_DEFAULT)


## Items that fit by count and by payload.
static func capacity_units(type: StringName, res: StringName) -> int:
	var d := def(type)
	return mini(int(d["units"]), int(floor(float(d["max_kg"]) / unit_kg(res))))

## --- Step 19: wear and breakdowns (design/gdd/vehicles.md «Износ и поломки») ---
const PARTS: Array[StringName] = [&"engine", &"tires", &"battery"]
const PART_NAMES := {&"engine": "мотор", &"tires": "шины", &"battery": "аккумулятор"}
const PART_BROKEN_BELOW := 0.15      # part condition below this = «сломан»: the vehicle stops
const PART_WORN_BELOW := 0.5         # below this = «изношен»: limping
## Workshop/field repair step per part (existing resources only).
const PART_REPAIR_COST := {&"engine": {&"spare_parts": 2}, &"tires": {&"scrap_metal": 2}, &"battery": {&"spare_parts": 1, &"scrap_metal": 1}}
const PART_COLORS := {&"ok": Color(0.45, 0.8, 0.4), &"worn": Color(0.95, 0.75, 0.25), &"broken": Color(0.9, 0.3, 0.25)}
## Wear per km (part condition lost).
const ENGINE_WEAR_PER_KM := 0.02
const ENGINE_OVERLOAD_FROM := 0.8    # load fraction from which the engine is overloaded
const ENGINE_OVERLOAD_MULT := 1.5    # extra wear multiplier when overloaded (x load excess)
const ENGINE_WORK_WEAR_PER_S := 0.00004   # working machines (plow/dig) wear the engine
const TIRE_WEAR_PER_KM := 0.03
const TIRE_SLIP_MULT := 2.0          # x slip (mud/snow)
const TIRE_OFFROAD_MULT := 0.5       # no road and no ruts
const TIRE_ROAD_MULT := 0.7          # road spares the tyres
const BATTERY_WEAR_PER_KM := 0.002
const BATTERY_START_WEAR := 0.004    # per start attempt
const BATTERY_FROST_START_MULT := 0.05    # extra start wear per degree of frost
const FROST_DRAIN_BELOW := -5.0      # parked vehicle drains the battery below this temperature
const BATTERY_DRAIN_PER_DEG_DAY := 0.004
## Winter starts: failure chance = cold x per-deg x (1 + weak battery) + worn engine; retries cost time.
const START_FAIL_PER_DEG := 0.012
const START_FAIL_BATTERY := 3.0
const START_FAIL_ENGINE := 0.25
const START_FAIL_SKILL_RELIEF := 0.4
const START_FAIL_MAX := 0.9
const START_MAX_TRIES := 5
const START_RETRY_DELAY := 8.0       # s per failed attempt
## Limp: worn engine slows, worn tyres slip more (continuous below PART_WORN_BELOW).
const LIMP_SPEED := 0.6
const LIMP_SLIP := 0.5
## Accidents (chance per km): base x slope x load x slip x driver skill x worn tyres.
const ACCIDENT_BASE_PER_KM := 0.12
const ACCIDENT_SLOPE_GAIN := 2.0     # at slope = MAX_SLOPE
const ACCIDENT_OVERLOAD_GAIN := 1.5  # x load (grows with slope)
const ACCIDENT_SLIP_GAIN := 1.5
const ACCIDENT_SKILL_NOVICE := 1.6   # skill 0 multiplier
const ACCIDENT_SKILL_EXPERT := 0.4   # skill 1 multiplier
const ACCIDENT_TIRE_GAIN := 1.0      # worn tyres
## Crash damage per part (min..max, scaled by a deterministic roll).
const CRASH_DAMAGE := {&"engine": Vector2(0.25, 0.6), &"tires": Vector2(0.3, 0.7), &"battery": Vector2(0.1, 0.4)}
const CRASH_DAMAGE_SKILL_RELIEF := 0.3
## Field repair (mechanic on site): slower than the workshop, patches up only to FIELD_REPAIR_CAP.
const FIELD_REPAIR_STEP_WORK := 14.0
const FIELD_REPAIR_CAP := 0.6
const FIELD_REPAIR_GAIN := 0.2       # per step (x (1 + 0.5 x mechanic skill))
const FIELD_REPAIR_SKILL_BONUS := 0.5


static func part_name(part: StringName) -> String:
	return PART_NAMES.get(part, String(part))


## Vague state word and colour class for UI: ok | worn | broken.
static func part_state(cond: float) -> StringName:
	if cond < PART_BROKEN_BELOW:
		return &"broken"
	return &"worn" if cond < PART_WORN_BELOW else &"ok"


static func part_word(cond: float, part: StringName = &"") -> String:
	var plural := part == &"tires"
	match part_state(cond):
		&"broken":
			return "сломаны" if plural else "сломан"
		&"worn":
			return "изношены" if plural else "изношен"
	return "исправны" if plural else "исправен"
