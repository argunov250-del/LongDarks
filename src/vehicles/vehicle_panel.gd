class_name VehiclePanel
extends PanelContainer
## Vehicle panel: part states as vague words + colour (never numbers).
## Design: design/gdd/vehicles.md «Износ и поломки». Rebuilds on TOPIC_CHANGED.

var vs: VehicleSystem
var _box := VBoxContainer.new()
var rows: Array[Label] = []


func setup(vs_in: VehicleSystem, sim: Simulation) -> void:
	vs = vs_in
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	sim.bus.subscribe(VehicleSystem.TOPIC_CHANGED, func(_p: Dictionary) -> void: refresh())
	refresh()


## One label per vehicle: «Бурун-5 — мотор: сломан · шины: исправны · аккумулятор: изношен».
func refresh() -> void:
	for c in _box.get_children():
		c.queue_free()
		_box.remove_child(c)
	rows.clear()
	for v in vs.vehicle_list():
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.text = line_text(v)
		var worst := &"ok"
		for e in vs.part_summary(v):
			if e["state"] == &"broken":
				worst = &"broken"
			elif e["state"] == &"worn" and worst != &"broken":
				worst = &"worn"
		l.add_theme_color_override("font_color", VehicleDefs.PART_COLORS[worst])
		_box.add_child(l)
		rows.append(l)


func line_text(v: Vehicle) -> String:
	var parts := vs.part_summary(v).map(func(e: Dictionary) -> String: return "%s: %s" % [e["name"], e["word"]])
	return "%s — %s" % [VehicleDefs.MODEL_NAMES[v.type], " · ".join(parts)]
