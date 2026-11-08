class_name GameSession
extends RefCounted
## Партия: сохранение/загрузка именованных слотов с метаданными, автосохранение.

const AUTOSAVE_SLOT := "autosave"

var sim: Simulation
var settings: GameSettings
var seasons: SeasonSystem
var villagers: VillagerSystem
var autosave := AutoSave.new()


func _init(sim_in: Simulation, settings_in: GameSettings, seasons_in: SeasonSystem, villagers_in: VillagerSystem) -> void:
	sim = sim_in
	settings = settings_in
	seasons = seasons_in
	villagers = villagers_in
	autosave.save_fn = func() -> Error: return save(AUTOSAVE_SLOT, "Автосохранение")
	sim.register_system(autosave)


func meta(display_name: String) -> Dictionary:
	return {"name": display_name, "saved_at": int(Time.get_unix_time_from_system()),
		"season": String(seasons.season()) if seasons != null else "", "day": sim.clock.get_day(),
		"population": villagers.population() if villagers != null else 0,
		"mode": String(settings.mode) if settings != null else "", "preset": String(settings.preset) if settings != null else ""}


func save(slot: String, display_name: String = "") -> Error:
	return SaveManager.save(sim, slot, meta(display_name if display_name != "" else slot))


func load_slot(slot: String) -> Error:
	var err := SaveManager.load_slot(sim, slot)
	if err == OK:
		autosave.resync(sim)
	return err
