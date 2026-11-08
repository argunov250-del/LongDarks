class_name DriveSettings
extends RefCounted
## Player settings of manual driving, stored in user://settings.cfg (NOT in the game save).
## Design: design/gdd/manual-driving.md.

const DEFAULT_PATH := "user://settings.cfg"
const SECTION := "driving"

var path: String
var scheme: StringName = ManualDriveDefs.DEFAULT_SCHEME
var tilt_neutral := Vector3.ZERO


func _init(path_in: String = DEFAULT_PATH) -> void:
	path = path_in


## Unknown schemes are refused. Returns true if the value changed.
func set_scheme(s: StringName) -> bool:
	if not ManualDriveDefs.SCHEMES.has(s) or s == scheme:
		return false
	scheme = s
	return true


func save() -> Error:
	var cf := ConfigFile.new()
	cf.load(path)  # keep other sections
	cf.set_value(SECTION, "scheme", String(scheme))
	cf.set_value(SECTION, "tilt_neutral", tilt_neutral)
	return cf.save(path)


## Missing/corrupt file or unknown values -> defaults.
func load() -> Error:
	scheme = ManualDriveDefs.DEFAULT_SCHEME
	tilt_neutral = Vector3.ZERO
	var cf := ConfigFile.new()
	var err := cf.load(path)
	if err != OK:
		return err
	var s := StringName(String(cf.get_value(SECTION, "scheme", String(ManualDriveDefs.DEFAULT_SCHEME))))
	if ManualDriveDefs.SCHEMES.has(s):
		scheme = s
	var n = cf.get_value(SECTION, "tilt_neutral", Vector3.ZERO)
	if n is Vector3:
		tilt_neutral = n
	return OK
