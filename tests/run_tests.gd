extends SceneTree
## Минимальный раннер тестов без зависимостей.
## Запуск: godot --headless --path . -s tests/run_tests.gd
## Находит tests/**/test_*.gd, вызывает методы test_*; наследники TestCase
## используют assert_* из tests/test_case.gd.

const TEST_ROOT := "res://tests"

var _total := 0
var _failed := 0


func _initialize() -> void:
	var files: Array[String] = []
	_collect(TEST_ROOT, files)
	files.sort()
	for path in files:
		_run_file(path)
	print("")
	print("Tests: %d, passed: %d, failed: %d" % [_total, _total - _failed, _failed])
	quit(1 if _failed > 0 else 0)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			out.append(dir_path.path_join(f))


func _run_file(path: String) -> void:
	var script := load(path) as GDScript
	if script == null:
		_total += 1
		_failed += 1
		printerr("FAIL  %s: cannot load script" % path)
		return
	for m in script.get_script_method_list():
		var name: String = m["name"]
		if not name.begins_with("test_"):
			continue
		var inst = script.new()
		_total += 1
		if inst.has_method("_reset"):
			inst._reset()
		inst.call(name)
		var errors: Array = inst.errors if "errors" in inst else []
		if errors.is_empty():
			print("PASS  %s::%s" % [path, name])
		else:
			_failed += 1
			for e in errors:
				printerr("FAIL  %s::%s: %s" % [path, name, e])
