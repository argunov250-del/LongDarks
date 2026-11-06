class_name WeatherFx
extends RefCounted
## Фабрики простых эффектов погоды (шаг 14), дёшево для мобильных: CPUParticles3D без текстур.


static func _unshaded(color: Color, additive: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


## Огонь с дымом: радиус r (м), высота пламени h.
static func make_fire(r: float, h: float, amount: int = 18, with_light: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "Fire"
	var p := CPUParticles3D.new()
	p.name = "Flames"
	p.amount = amount
	p.lifetime = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = r
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0, 1.5, 0)
	p.initial_velocity_min = h * 0.6
	p.initial_velocity_max = h * 1.2
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.3, 0.95))
	g.set_color(1, Color(0.8, 0.1, 0.0, 0.0))
	g.add_point(0.4, Color(1.0, 0.4, 0.05, 0.8))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(r * 1.4 + 0.3, r * 1.4 + 0.3)
	p.mesh = q
	p.material_override = _unshaded(Color.WHITE, true)
	root.add_child(p)
	var smoke := CPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.amount = maxi(6, amount / 3)
	smoke.lifetime = 2.4
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = r * 0.6
	smoke.position.y = h * 0.8
	smoke.direction = Vector3.UP
	smoke.spread = 20.0
	smoke.gravity = Vector3(0.6, 1.2, 0)
	smoke.initial_velocity_min = 0.8
	smoke.initial_velocity_max = 1.6
	var sg := Gradient.new()
	sg.set_color(0, Color(0.15, 0.14, 0.14, 0.55))
	sg.set_color(1, Color(0.25, 0.25, 0.25, 0.0))
	smoke.color_ramp = sg
	var sq := QuadMesh.new()
	sq.size = Vector2(r * 2.0 + 0.6, r * 2.0 + 0.6)
	smoke.mesh = sq
	smoke.material_override = _unshaded(Color.WHITE)
	root.add_child(smoke)
	if with_light:
		var light := OmniLight3D.new()
		light.light_color = WeatherDefs.FIRE_COLOR
		light.light_energy = 1.2
		light.omni_range = r * 3.0 + 3.0
		light.position.y = h * 0.5
		root.add_child(light)
	return root


## Падающие частицы (снег/дождь) в коробке box; wind — боковой снос, fall — скорость падения.
static func make_precip(kind: StringName, amount: int, box: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Precip_" + String(kind)
	p.amount = amount
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box * 0.5
	p.local_coords = false
	p.direction = Vector3.DOWN
	p.spread = 3.0
	p.draw_order = CPUParticles3D.DRAW_ORDER_INDEX
	if kind == &"snow":
		p.lifetime = 5.0
		var m := SphereMesh.new()
		m.radius = 0.07
		m.height = 0.14
		m.radial_segments = 4
		m.rings = 2
		p.mesh = m
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1, 1, 1, 0.9)
		p.material_override = mat
	else:
		p.lifetime = 1.0
		var m := BoxMesh.new()
		m.size = Vector3(0.025, 0.9, 0.025)
		p.mesh = m
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.75, 0.82, 0.95, 0.55)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		p.material_override = mat
	p.emitting = false
	return p


## Сажа на повреждённом здании: тёмная полупрозрачная коробка чуть больше основания.
static func make_soot(size: Vector2, height: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Soot"
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x + 0.15, height + 0.1, size.y + 0.15)
	mi.mesh = bm
	mi.position.y = height * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.04, 0.04, 0.62)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	mi.material_override = mat
	return mi
