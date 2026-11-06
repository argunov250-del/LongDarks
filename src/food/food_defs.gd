class_name FoodDefs
extends RefCounted
## Step 16 (design/gdd/food.md): all food balance constants in one place (placeholders).

# ---------- fields ----------
const CROPS: Array[StringName] = [&"grain", &"potato", &"rapeseed"]
const CROP_NAMES := {&"grain": "Зерно", &"potato": "Картофель", &"rapeseed": "Рапс", &"vegetables": "Овощи"}
## Base yield of one field cell at fertility 0, normal water.
const BASE_YIELD := {&"grain": 5.0, &"potato": 8.0, &"rapeseed": 4.0}
const FERTILITY_GAIN := 1.0          # yield * (1 + fertility_at * this); burnt cell 0.5 -> x1.5
const GROW_SPEED := 1.15             # growth per summer length (>1: ripe before summer ends)
const RAIN_WATER := 1.4              # water factor while it rains
const DROUGHT_WATER := 0.4           # water factor during drought
const NORMAL_WATER := 1.0
const WATER_MIN := 0.3               # clamp of the average water factor (yield multiplier)
const WATER_MAX := 1.3
const STAGE_NAMES: Array[String] = ["размечено", "вспахано", "посеяно", "созрело"]
const STAGE_NAMES_GROWING := "растёт"
const FIELD_JOB_CAP := 48            # max field jobs offered at a time

# ---------- work (units of work at rate 1.0) ----------
const WORK := {
	&"plow": 4.0, &"sow": 2.5, &"harvest": 3.0, &"hunt": 8.0, &"fish": 7.0,
	&"forage": 5.0, &"gpick": 4.0,
}
const WORK_PICKUP := 1.5             # loading firewood for a greenhouse
const WORK_DELIVER := 1.5

# ---------- greenhouse (grows all year, no heating needed) ----------
const GREENHOUSE_GROW_DAYS := 5.0
const GREENHOUSE_YIELD := 6              # per batch
const GREENHOUSE_MAX_RIPE := 12
const GREENHOUSE_CROPS: Array[StringName] = [&"vegetables", &"potato"]

# ---------- wildlife ----------
const REGION_CELLS := 32
const MIN_FOREST_CELLS := 40
const DEER_FOREST_CELLS := 300
const CAP_PER_FOREST_CELL := {&"deer": 0.03, &"hare": 0.05}
const CAP_MIN := {&"deer": 4.0, &"hare": 5.0}
const MEAT_PER_KILL := {&"deer": 8, &"hare": 2}
const SPECIES_NAMES := {&"deer": "олени", &"hare": "зайцы"}
const REGEN_PER_DAY := 0.06          # logistic rate
const MIN_BREEDERS := 1.0
const HUNT_WINDOW_DAYS := 10.0       # decision 3: hunting pressure = hunts per area within this window
const HUNT_PRESSURE_MAX := 5         # more hunts than this in the window: the herd leaves (any numbers)
const HUNT_RETURN_PRESSURE := 0      # herd returns only when the window is clear of hunts
const RETURN_DAYS := 20.0            # days away before the herd comes back (at recovery 1.0)
const RETURN_FRACTION := 0.4         # of cap on return
const HUNT_RANGE := 6.0
const WANDER_INTERVAL := 18.0        # s between wander targets
const WANDER_SPEED := 1.2            # m/s
const ANIMAL_PER_VISIBLE := 1.0      # pop units per drawn animal
const HINT_MANY := 0.6               # pop/cap fraction for "много"

# ---------- fishing ----------
const FISH_PER_BODY_CELL := 0.5
const FISH_CAP_MIN := 8.0
const FISH_PER_CATCH := 3
const FISH_REGEN_PER_DAY := 0.05
const FISH_MIN_BREEDERS := 1.0
const SPOTS_PER_BODY := 3
const SPOT_SPACING := 6              # cells between spots
const FISH_RANGE := 1.7

# ---------- mushrooms ----------
const MUSHROOM_DENSITY := {&"summer": 0.04, &"autumn": 0.12}
const MUSHROOM_SUMMER_FROM := 0.6    # late summer starts at this season progress
const MUSHROOM_PER_PICK := 4
const MUSHROOM_JOB_CAP := 6
const SALT_MUSHROOM := 417
