class_name ModeDefs
extends RefCounted
## Режимы и сложность (шаг 25). Баланс — только здесь. Дизайн: design/gdd/modes-difficulty.md.

const SANDBOX := &"sandbox"
const CAREER := &"career"
## Карьера (шаг 26): каркас глав, design/gdd/career.md.
const MODES := {
	SANDBOX: {"name": "Песочница", "enabled": true, "desc": "Без сюжета, бесконечная игра"},
	CAREER: {"name": "Карьера", "enabled": true, "desc": "4 главы с заданиями, в конце титры"},
}
const MODE_ORDER: Array[StringName] = [SANDBOX, CAREER]

const PEACEFUL := &"peaceful"
const NORMAL := &"normal"
const AGGRESSIVE := &"aggressive"
const NEIGHBOUR_ORDER: Array[StringName] = [PEACEFUL, NORMAL, AGGRESSIVE]
const NEIGHBOUR_MODES := {
	PEACEFUL: {"name": "Мирные", "aggression_mult": 0.4, "incident_mult": 0.3},
	NORMAL: {"name": "Обычные", "aggression_mult": 1.0, "incident_mult": 1.0},
	AGGRESSIVE: {"name": "Агрессивные", "aggression_mult": 1.5, "incident_mult": 2.0},
}

const EASY := &"easy"
const MEDIUM := &"medium"
const HARD := &"hard"
const CUSTOM := &"custom"
const PRESET_ORDER: Array[StringName] = [EASY, MEDIUM, HARD]
const PRESETS := {
	EASY: {"name": "Лёгкая", "winter_mult": 0.7, "neighbour_mode": PEACEFUL, "weather_mult": 0.7},
	MEDIUM: {"name": "Обычная", "winter_mult": 1.0, "neighbour_mode": NORMAL, "weather_mult": 1.0},
	HARD: {"name": "Суровая", "winter_mult": 1.4, "neighbour_mode": AGGRESSIVE, "weather_mult": 1.5},
}
const DEFAULT_PRESET := MEDIUM
const WINTER_MULT_RANGE := Vector2(0.5, 2.0)
const WEATHER_MULT_RANGE := Vector2(0.25, 2.0)
const SLIDER_STEP := 0.05


static func preset_name(id: StringName) -> String:
	return String(PRESETS[id]["name"]) if PRESETS.has(id) else "Своя"
