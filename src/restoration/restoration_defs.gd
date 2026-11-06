class_name RestorationDefs
extends RefCounted
## Step 17 (design/gdd/land-restoration.md): all land-restoration balance constants in one place (placeholders).

# ---------- forest ----------
const SAPLING_GROW_SEASONS := 2.0     # seasons until a sapling becomes harvestable trees
const TREES_PER_PLANTED := 4          # trees (logs) on a grown planted cell
const PLANT_WORK := 3.0               # work units (rate 1.0) to plant one sapling
const HEAL_WORK := 4.0                # work units to plant cleansing vegetation on a poison cell
const SPREAD_CELLS_PER_DAY := 0.15    # natural spread: new saplings per game day (whole map, edges only)
const SPREAD_MAX_SAPLINGS := 40       # natural spread pauses while this many saplings are growing
const JOB_CAP := 48                   # max planting / treatment jobs offered at a time
const FOREST_TARGET_CELLS := 150      # planted trees that count as «forest fully restored» (recovery share)

# ---------- water ----------
const WATER_START := 0.3333           # initial quality of every river / lake (0 dirty .. 1 clean)
const WATER_CLEAN_PER_DAY := 0.004    # base cleaning speed
const WATER_CLEAN_RECOVERY := 3.0     # extra speed multiplier at full land recovery (x(1 + this * recovery))
const FISH_MULT_MIN := 0.5            # fish capacity multiplier at quality 0
const FISH_MULT_MAX := 2.0            # ... at quality 1 (1.0 at WATER_START)

# ---------- poison ----------
const POISON_HEAL_PER_DAY := 0.05     # poison level drop per day on a treated cell (non-winter)
const POISON_EPS := 0.02              # level at or below this counts as healed
const POISON_FERT_PENALTY := 0.5      # fertility lost per poison level

# ---------- soil / wildlife ----------
const SOIL_GROWTH_PER_DAY := 0.002    # x (SOIL_BASE_SHARE + recovery)
const SOIL_BASE_SHARE := 0.2
const SOIL_MAX := 0.5                 # max extra fertility from recovery (burnt-field bonus is 0.5)
const WILDLIFE_CAP_BONUS := 1.0       # +100% wildlife capacity at full recovery
const WILDLIFE_SPEED_MAX := 3.0       # regen/return speed multiplier at full recovery (1.0 at none)

# ---------- recovery index weights (sum 1) ----------
const W_FOREST := 0.5
const W_WATER := 0.25
const W_POISON := 0.25
const SYNC_INTERVAL := 1.0            # s between pushing numbers to other systems
