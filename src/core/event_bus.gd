class_name EventBus
extends RefCounted
## Pub/sub по StringName-топикам; payload — Dictionary.
## Обработчик: func(payload: Dictionary) -> void. Безопасно отписываться во время emit.

var _handlers: Dictionary = {}  # StringName -> Array[Callable]


func subscribe(topic: StringName, handler: Callable) -> void:
	var list: Array = _handlers.get(topic, [])
	if not list.has(handler):
		list.append(handler)
	_handlers[topic] = list


func unsubscribe(topic: StringName, handler: Callable) -> void:
	if not _handlers.has(topic):
		return
	# Копия-на-запись: идущий emit продолжает обход старого массива.
	var list: Array = (_handlers[topic] as Array).duplicate()
	list.erase(handler)
	if list.is_empty():
		_handlers.erase(topic)
	else:
		_handlers[topic] = list


func emit(topic: StringName, payload: Dictionary = {}) -> void:
	if not _handlers.has(topic):
		return
	var snapshot: Array = _handlers[topic]
	for h: Callable in snapshot:
		# Отписанный во время emit обработчик больше не вызывается.
		if _handlers.has(topic) and (_handlers[topic] as Array).has(h):
			if h.is_valid():
				h.call(payload)


func subscriber_count(topic: StringName) -> int:
	return (_handlers.get(topic, []) as Array).size()
