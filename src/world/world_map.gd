class_name WorldMap
extends SimSystem
## Чистый слой данных карты. Полностью детерминирован по (seed, size, params):
## сохраняются только они, карта пересоздаётся при загрузке.
## Координаты: x,z в метрах, [0, world_size]; y — высота.

enum Terrain { GROUND, RIVER, LAKE, FOREST, RUINS, POISON }

const DEFAULT_SIZE := 128          # клеток по стороне
const DEFAULT_CELL_SIZE := 2.0     # метров на клетку
const WATER_LEVEL := 0.0
const POISON_RADIUS_CELLS := 11.0

var seed_value: int = 0
var size: int = DEFAULT_SIZE
var cell_size: float = DEFAULT_CELL_SIZE
## Параметры генерации (часть сохранения). Ключи: amplitude, forest_threshold.
var params: Dictionary = {}

var heights := PackedFloat32Array()   # (size+1)^2 узлов
var terrain := PackedByteArray()      # size^2 клеток
var factory_cell := Vector2i.ZERO


static func default_params() -> Dictionary:
	return {"amplitude": 9.0, "forest_threshold": 0.12}


func _init(seed_in: int = 0, size_in: int = DEFAULT_SIZE, params_in: Dictionary = {}, cell_size_in: float = DEFAULT_CELL_SIZE) -> void:
	generate(seed_in, size_in, params_in, cell_size_in)


# ---------- запросы ----------

func get_world_size() -> float:
	return size * cell_size


## Границы в плоскости XZ: position=(0,0), size=(world,world).
func get_bounds() -> Rect2:
	return Rect2(0.0, 0.0, get_world_size(), get_world_size())


func node_height(ix: int, iz: int) -> float:
	return heights[clampi(iz, 0, size) * (size + 1) + clampi(ix, 0, size)]


## Билинейная высота; вне карты — по ближайшему краю.
func height_at(x: float, z: float) -> float:
	var fx := clampf(x / cell_size, 0.0, float(size))
	var fz := clampf(z / cell_size, 0.0, float(size))
	var ix := mini(int(fx), size - 1)
	var iz := mini(int(fz), size - 1)
	var tx := fx - ix
	var tz := fz - iz
	var h00 := node_height(ix, iz)
	var h10 := node_height(ix + 1, iz)
	var h01 := node_height(ix, iz + 1)
	var h11 := node_height(ix + 1, iz + 1)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(int(floorf(x / cell_size)), 0, size - 1), clampi(int(floorf(z / cell_size)), 0, size - 1))


func cell_type(cx: int, cz: int) -> int:
	if cx < 0 or cz < 0 or cx >= size or cz >= size:
		return Terrain.GROUND
	return terrain[cz * size + cx]


func cell_type_at(x: float, z: float) -> int:
	var c := cell_of(x, z)
	return terrain[c.y * size + c.x]


func is_water(x: float, z: float) -> bool:
	return is_water_type(cell_type_at(x, z))


static func is_water_type(t: int) -> bool:
	return t == Terrain.RIVER or t == Terrain.LAKE


func count_type(t: int) -> int:
	var n := 0
	for v in terrain:
		if v == t:
			n += 1
	return n


## Детерминированный хеш-шум [0,1) для расстановки объектов (не зависит от порядка вызовов).
func hash01(cx: int, cz: int, salt: int = 0) -> float:
	var h: int = ((cx * 73856093) ^ (cz * 19349663) ^ (salt * 83492791) ^ (seed_value * 2654435761)) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0


func cell_center(cx: int, cz: int) -> Vector3:
	var x := (cx + 0.5) * cell_size
	var z := (cz + 0.5) * cell_size
	return Vector3(x, height_at(x, z), z)


# ---------- генерация ----------

func generate(seed_in: int, size_in: int = DEFAULT_SIZE, params_in: Dictionary = {}, cell_size_in: float = DEFAULT_CELL_SIZE) -> void:
	seed_value = seed_in
	size = maxi(16, size_in)
	cell_size = cell_size_in
	params = default_params()
	params.merge(params_in, true)
	var amp: float = params["amplitude"]
	var forest_thr: float = params["forest_threshold"]
	var n := size
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var hn := FastNoiseLite.new()
	hn.seed = seed_value
	hn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hn.frequency = 1.6 / n
	hn.fractal_octaves = 4
	var fn := FastNoiseLite.new()
	fn.seed = seed_value + 7919
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 3.5 / n
	fn.fractal_octaves = 2
	var wn := FastNoiseLite.new()
	wn.seed = seed_value + 104729
	wn.frequency = 6.0 / n

	# Основной рельеф. Базово слегка выше уровня воды.
	heights.resize((n + 1) * (n + 1))
	for iz in n + 1:
		for ix in n + 1:
			heights[iz * (n + 1) + ix] = 4.5 + hn.get_noise_2d(ix, iz) * amp

	# Завод: выравниваем площадку.
	var fx := rng.randi_range(int(n * 0.2), int(n * 0.8))
	var fz := rng.randi_range(int(n * 0.2), int(n * 0.8))
	factory_cell = Vector2i(fx, fz)
	var plat_h := 4.5
	_blend_disc(float(fx), float(fz), 7.0, 5.0, plat_h)

	# Озеро: вдали от завода.
	var lake := Vector2(float(fx), float(fz))
	for _i in 20:
		lake = Vector2(rng.randf_range(n * 0.15, n * 0.85), rng.randf_range(n * 0.15, n * 0.85))
		if lake.distance_to(Vector2(fx, fz)) > n * 0.3:
			break
	var lake_r := rng.randf_range(n * 0.07, n * 0.11)
	_blend_disc(lake.x, lake.y, lake_r, lake_r * 0.5, -3.5)

	# Река: от верхнего края к нижнему, извилистая.
	var river_x0 := rng.randf_range(n * 0.15, n * 0.85)
	var river_phase := rng.randf() * TAU
	var river_amp := rng.randf_range(n * 0.06, n * 0.14)
	var river_w := 1.8
	var river_path: Array[Vector2] = []
	for iz in n + 1:
		var t := float(iz) / n
		var rx := river_x0 + sin(t * TAU * 1.3 + river_phase) * river_amp + (t - 0.5) * n * 0.2
		river_path.append(Vector2(clampf(rx, 4.0, n - 4.0), iz))
	for p in river_path:
		_blend_disc(p.x, p.y, river_w, river_w * 1.0, -2.0)
	# Возвращаем платформу завода (она всегда суша), если река её задела.
	_blend_disc(float(fx), float(fz), 7.0, 5.0, plat_h)

	# Типы клеток.
	terrain.resize(n * n)
	var river_cells := {}
	for p in river_path:
		river_cells[int(p.y)] = p.x
	for cz in n:
		for cx in n:
			var h := (node_height(cx, cz) + node_height(cx + 1, cz) + node_height(cx, cz + 1) + node_height(cx + 1, cz + 1)) * 0.25
			var t := Terrain.GROUND
			if h <= WATER_LEVEL:
				var rx: float = river_cells.get(cz, -1000.0)
				t = Terrain.RIVER if absf(cx - rx) < river_w * 2.0 else Terrain.LAKE
			elif fn.get_noise_2d(cx, cz) > forest_thr and h < amp * 0.7:
				t = Terrain.FOREST
			terrain[cz * n + cx] = t

	# Отравленная зона вокруг завода (неровный край), только суша.
	var fpos := Vector2(fx + 0.5, fz + 0.5)
	for cz in n:
		for cx in n:
			var i := cz * n + cx
			if is_water_type(terrain[i]):
				continue
			var d := Vector2(cx + 0.5, cz + 0.5).distance_to(fpos)
			var edge := POISON_RADIUS_CELLS + wn.get_noise_2d(cx, cz) * 4.0
			if d < edge:
				terrain[i] = Terrain.POISON

	# Руины завода: кластер 3x3 в центре.
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var cx := fx + dx
			var cz := fz + dz
			if cx >= 0 and cz >= 0 and cx < n and cz < n and not is_water_type(terrain[cz * n + cx]):
				terrain[cz * n + cx] = Terrain.RUINS
	# Разбросанные мелкие руины на сухой земле/в лесу.
	for _k in 14:
		var cx := rng.randi_range(2, n - 3)
		var cz := rng.randi_range(2, n - 3)
		var w := rng.randi_range(1, 2)
		var hh := rng.randi_range(1, 2)
		for dz in hh:
			for dx in w:
				var i := (cz + dz) * n + cx + dx
				if terrain[i] == Terrain.GROUND or terrain[i] == Terrain.FOREST:
					terrain[i] = Terrain.RUINS


## Плавно приводит высоты узлов в радиусе к target (полная сила до r_in, спад до r_in+r_fall).
func _blend_disc(cx: float, cz: float, r_in: float, r_fall: float, target: float) -> void:
	var r_max := r_in + r_fall
	for iz in range(maxi(0, int(cz - r_max)), mini(size, int(cz + r_max) + 1)):
		for ix in range(maxi(0, int(cx - r_max)), mini(size, int(cx + r_max) + 1)):
			var d := Vector2(ix - cx, iz - cz).length()
			if d >= r_max:
				continue
			var w := 1.0 if d <= r_in else 1.0 - smoothstep(0.0, 1.0, (d - r_in) / r_fall)
			var i := iz * (size + 1) + ix
			heights[i] = lerpf(heights[i], target, w)


# ---------- сохранение (SimSystem) ----------

func get_save_key() -> StringName:
	return &"world"


## Хранятся только параметры; сама карта пересоздаётся.
func save_state() -> Dictionary:
	return {
		"seed": str(seed_value),
		"size": size,
		"cell_size": cell_size,
		"params": params.duplicate(),
	}


func load_state(d: Dictionary) -> void:
	var p: Dictionary = d["params"] if d.get("params") is Dictionary else {}
	generate(
		SaveManager.to_int(d.get("seed"), seed_value),
		SaveManager.to_int(d.get("size"), size),
		p,
		float(d.get("cell_size", cell_size)))
