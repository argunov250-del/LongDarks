class_name FuelDefs
extends RefCounted
## Fuel chains, engine kinds, conversions and upgrades — ALL step-20 balance (placeholders) in one place.
## Design: design/gdd/fuel-and-upgrades.md. Chains themselves (recipes) live in Recipes, buildings in BuildingDefs.

## --- Engines: every vehicle type has a native engine; found vehicles only have old-fuel residue ---
const DIESEL := &"diesel"
const PETROL := &"petrol"
const ENGINE_NAMES := {&"diesel": "дизельный", &"petrol": "бензиновый"}
const ENGINE_OF := {
	&"truck": &"diesel", &"pickup": &"petrol", &"offroad": &"diesel", &"tractor": &"diesel", &"combine": &"diesel",
	&"excavator": &"diesel", &"bulldozer": &"diesel", &"crane": &"diesel", &"atv": &"petrol", &"snowmobile": &"petrol",
}

## --- Conversions (workshop) ---
const NO_CONVERSION := &""
const BIOFUEL := &"biofuel"
const GASGEN := &"gasgen"
const CONVERSIONS: Array[StringName] = [&"biofuel", &"gasgen"]
## name; steps (one step = Recipes.REPAIR_STEP_TIME of mechanic work); cost per step; accepted settlement fuels.
const CONVERSION_DEFS := {
	&"biofuel": {"name": "Биотопливо", "steps": 6, "cost": {&"spare_parts": 1, &"scrap_metal": 1}, "accepts": [&"biodiesel", &"alcohol"]},
	&"gasgen": {"name": "Газогенератор", "steps": 10, "cost": {&"spare_parts": 1, &"scrap_metal": 2}, "accepts": [&"firewood"]},
}
## Native engines run biodiesel with no conversion (diesel only); petrol engines need a conversion for settlement fuel.
const NATIVE_ACCEPTS := {&"diesel": [&"biodiesel"], &"petrol": []}

## Litre-equivalents per resource unit (a unit in storage = this much in the tank/hopper).
const LITRES_PER_UNIT := {&"biodiesel": 10.0, &"alcohol": 8.0, &"firewood": 4.0}

## Gas generator: slower, thirstier, small hopper (needs frequent wood stops).
const GASGEN_SPEED := 0.7
const GASGEN_FUEL_MULT := 1.5        # litre-equivalents per km vs the native engine
const GASGEN_HOPPER := 0.4           # hopper = this fraction of the tank

## --- Refuelling (physical trip to the nearest storage holding an accepted fuel) ---
const REFUEL_BELOW := 0.3            # plan a refuel trip when the tank is below this fraction
const REFUEL_TIME := 8.0             # s at the storage (a gas generator is loaded with wood by hand, same time)

## --- Upgrades (workshop) ---
const UPGRADES: Array[StringName] = [&"chains", &"insulation", &"headlights"]
const UPGRADE_DEFS := {
	&"chains": {"name": "Цепи", "steps": 4, "cost": {&"scrap_metal": 2}},
	&"insulation": {"name": "Утепление", "steps": 5, "cost": {&"spare_parts": 1}},
	&"headlights": {"name": "Фары", "steps": 4, "cost": {&"spare_parts": 1, &"scrap_metal": 1}},
}
const CHAINS_SLIP_MULT := 0.55       # mud/snow slip with chains
const INSULATION_FAIL_MULT := 0.5    # winter start failure chance
const INSULATION_DELAY_MULT := 0.7   # winter warm-up time
const INSULATION_DRAIN_MULT := 0.5   # parked battery drain in frost
const INSULATION_COOL_MULT := 2.0    # engine stays warm this much longer
const NIGHT_SPEED := 0.7             # speed at night without headlights
const NIGHT_SPEED_LIGHTS := 0.95     # with headlights
const NIGHT_ACCIDENT := 1.4          # accident chance multiplier at night
const NIGHT_ACCIDENT_LIGHTS := 1.05

## --- Waste and manure (biogas inputs) ---
const WASTE_PER_SPOILED := 1         # waste units per spoiled food unit
const MANURE_PERIOD := 90.0          # s per manure unit per cow
const NOTE_NO_WORKSHOP := "нужна мастерская"


static func engine_of(type: StringName) -> StringName:
	return ENGINE_OF.get(type, DIESEL)


static func engine_name(engine: StringName) -> String:
	return ENGINE_NAMES.get(engine, String(engine))


## Fuels a vehicle with this engine and conversion can burn.
static func accepted(engine: StringName, conversion: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	var src: Array = CONVERSION_DEFS[conversion]["accepts"] if CONVERSION_DEFS.has(conversion) else NATIVE_ACCEPTS.get(engine, [])
	for r in src:
		out.append(r)
	return out


static func accepts(engine: StringName, conversion: StringName, res: StringName) -> bool:
	return accepted(engine, conversion).has(res)


static func litres_per_unit(res: StringName) -> float:
	return float(LITRES_PER_UNIT.get(res, 0.0))


## Mod (conversion or upgrade) data: {name, steps, cost}; empty if unknown.
static func mod_def(kind: StringName) -> Dictionary:
	if CONVERSION_DEFS.has(kind):
		return CONVERSION_DEFS[kind]
	return UPGRADE_DEFS.get(kind, {})


static func mod_name(kind: StringName) -> String:
	return String(mod_def(kind).get("name", String(kind)))


## Whole cost of a mod (step cost x steps) for UI.
static func mod_total_cost(kind: StringName) -> Dictionary:
	var d := mod_def(kind)
	var out := {}
	for k in d.get("cost", {}):
		out[k] = int(d["cost"][k]) * int(d["steps"])
	return out
