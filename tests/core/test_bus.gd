extends "res://tests/test_case.gd"

var log: Array = []
var _bus: EventBus


func _a(p: Dictionary) -> void:
	log.append("a%s" % p.get("v", ""))


func _b(p: Dictionary) -> void:
	log.append("b%s" % p.get("v", ""))


func _unsub_self(_p: Dictionary) -> void:
	log.append("u")
	_bus.unsubscribe(&"t", _unsub_self)


func _unsub_b(_p: Dictionary) -> void:
	_bus.unsubscribe(&"t", _b)


func test_emit_and_unsubscribe() -> void:
	var bus := EventBus.new()
	bus.subscribe(&"t", _a)
	bus.subscribe(&"t", _a)  # дубликат игнорируется
	bus.emit(&"t", {"v": 1})
	assert_eq(log, ["a1"])
	bus.unsubscribe(&"t", _a)
	bus.emit(&"t", {"v": 2})
	assert_eq(log, ["a1"])
	assert_eq(bus.subscriber_count(&"t"), 0)


func test_unsubscribe_during_emit() -> void:
	_bus = EventBus.new()
	_bus.subscribe(&"t", _unsub_self)
	_bus.subscribe(&"t", _b)
	_bus.emit(&"t", {"v": 1})
	_bus.emit(&"t", {"v": 2})
	assert_eq(log, ["u", "b1", "b2"])


func test_unsubscribe_other_during_emit() -> void:
	_bus = EventBus.new()
	_bus.subscribe(&"t", _unsub_b)
	_bus.subscribe(&"t", _b)
	_bus.emit(&"t")
	assert_eq(log, [])  # _b отписан до вызова
