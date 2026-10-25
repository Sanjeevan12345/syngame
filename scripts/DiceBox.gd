extends Node3D
# The stone-and-gold box the Pasa sticks are thrown into, built from blocks in
# code: a cracked earthen floor, grey stone walls of coursed bricks under a
# capstone row with gold blocks in the middle of each side, gold corner pillars
# and gold braces across the inner corners.
# Blocks have bevelled edges that catch the light, and vertex shading stands in
# for ambient occlusion (the Mobile renderer has no SSAO): block bottoms and the
# floor along the walls are darker. Each block varies a little in tint, texture
# placement and angle so the masonry looks hand-laid.
# The walls' inner faces line up with dice_main's ContainerCollision (+/-4.9).
# Stone textures: Poly Haven (CC0).

const INNER: float = 4.9 # Inner face of the walls
const OUTER: float = 6.0 # Outer face of the walls
const COURSE_HEIGHT: float = 0.8 # Two brick courses under the capstones
const CAP_BOTTOM: float = 1.6
const CAP_TOP: float = 2.3
const PILLAR_TOP: float = 2.6
const PILLAR_SIZE: float = 1.6
const GAP: float = 0.06 # Mortar joint between blocks
const STONE_BEVEL: float = 0.08
const GOLD_BEVEL: float = 0.06

const FLOOR_TINT = Color(0.6, 0.5, 0.41)
const STONE_TINT = Color(0.88, 0.88, 0.88)
const BRICK_TINT = Color(0.68, 0.68, 0.7)
const MORTAR_COLOR = Color(0.1, 0.09, 0.08)
const GOLD_COLOR = Color(0.95, 0.64, 0.18)

const STONE_UV_SCALE: float = 0.35
const FLOOR_UV_SCALE: float = 0.6
const GOLD_UV_SCALE: float = 0.5

# Fake ambient occlusion: how dark a block's foot is, and the floor at a wall
const BLOCK_FOOT_SHADE: float = 0.68
const FLOOR_WALL_SHADE: float = 0.3
const FLOOR_SHADE_REACH: float = 2.4 # How far the floor darkening spreads from a wall

var floor_material: StandardMaterial3D
var stone_material: StandardMaterial3D
var mortar_material: StandardMaterial3D
var gold_material: StandardMaterial3D
var rng := RandomNumberGenerator.new()

func _ready():
	rng.seed = 2041 # Same masonry every game
	make_materials()
	build_floor()
	for side in 4:
		build_wall(side)
	for corner in 4:
		build_corner(corner)
	add_lighting()

func make_materials():
	floor_material = textured_material("cracked_concrete")
	stone_material = textured_material("concrete_floor_worn_001")

	mortar_material = StandardMaterial3D.new()
	mortar_material.albedo_color = MORTAR_COLOR
	mortar_material.roughness = 1.0

	# Worn gold: the stone's normal and roughness maps give it dents and scuffs
	gold_material = StandardMaterial3D.new()
	gold_material.vertex_color_use_as_albedo = true
	gold_material.metallic = 0.92
	gold_material.roughness = 0.42
	gold_material.roughness_texture = load("res://assets/textures/dice_box/concrete_floor_worn_001_rough_1k.jpg")
	gold_material.normal_enabled = true
	gold_material.normal_texture = load("res://assets/textures/dice_box/concrete_floor_worn_001_nor_gl_1k.jpg")
	gold_material.normal_scale = 0.5

# Tint and shading come from vertex colors, so one material serves every block
func textured_material(texture_name: String) -> StandardMaterial3D:
	var base = "res://assets/textures/dice_box/%s_%s_1k.jpg"
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = load(base % [texture_name, "diff"])
	material.roughness_texture = load(base % [texture_name, "rough"])
	material.normal_enabled = true
	material.normal_texture = load(base % [texture_name, "nor_gl"])
	return material

func build_floor():
	# Dark plinth under everything, so the joints read as shadow
	add_box(Vector3(0, -0.35, 0), Vector3(OUTER * 2 + 0.3, 0.5, OUTER * 2 + 0.3), mortar_material)

	# A grid, so the darkening along the walls can be painted into its vertices
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells = 28
	var step = INNER * 2 / cells
	for row in cells:
		for col in cells:
			var corners = [Vector2(col, row), Vector2(col + 1, row), Vector2(col + 1, row + 1), Vector2(col, row + 1)]
			var points: Array = []
			for c in corners:
				points.append(Vector3(-INNER + c.x * step, 0, -INNER + c.y * step))
			for i in [0, 1, 2, 0, 2, 3]:
				var p: Vector3 = points[i]
				var to_wall = INNER - maxf(absf(p.x), absf(p.z))
				var shade = lerpf(FLOOR_WALL_SHADE, 1.0, smoothstep(0.0, FLOOR_SHADE_REACH, to_wall))
				st.set_color(FLOOR_TINT * shade)
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(p.x, p.z) * FLOOR_UV_SCALE)
				st.add_vertex(p)
	st.generate_tangents()
	var floor_mesh = MeshInstance3D.new()
	floor_mesh.mesh = st.commit()
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)

# Side 0 runs along -Z, then each side turns a quarter around the box
func build_wall(side: int):
	var wall = Node3D.new()
	wall.rotation.y = side * PI / 2
	add_child(wall)

	var depth = OUTER - INNER
	var center_z = -(INNER + OUTER) / 2
	var span = OUTER * 2 - PILLAR_SIZE * 2 # Between the corner pillars
	var start = -span / 2

	# Mortar core fills the wall; blocks sit just proud of it with gaps between
	add_box(Vector3(0, CAP_TOP / 2, center_z), Vector3(span, CAP_TOP - 0.02, depth - 0.04), mortar_material, wall)

	# Two courses of bricks in running bond
	var brick_lengths = [[1.5, 1.6, 1.5, 1.7, 1.4, 1.3], [0.8, 1.6, 1.5, 1.6, 1.5, 1.6, 0.4]]
	for course in 2:
		var x = start
		var y = COURSE_HEIGHT * (course + 0.5)
		for length in brick_lengths[course]:
			length = minf(length, start + span - x)
			if length > GAP:
				add_block(Vector3(x + length / 2, y, center_z),
					Vector3(length - GAP, COURSE_HEIGHT - GAP, depth), stone_material, BRICK_TINT, wall)
			x += length

	# Capstones overhang both faces a little; the middle one is gold
	var cap_lengths = [span * 0.34, span * 0.32, span * 0.34]
	var x = start
	for i in cap_lengths.size():
		var length = cap_lengths[i]
		var at = Vector3(x + length / 2, (CAP_BOTTOM + CAP_TOP) / 2, center_z)
		var size = Vector3(length - GAP, CAP_TOP - CAP_BOTTOM, depth + 0.2)
		if i == 1:
			add_block(at, size, gold_material, GOLD_COLOR, wall)
		else:
			add_block(at, size, stone_material, STONE_TINT, wall)
		x += length

	# Thin gold band along the inner face, just under the capstones
	add_block(Vector3(0, CAP_BOTTOM - 0.12, -INNER + 0.03), Vector3(span, 0.16, 0.06), gold_material, GOLD_COLOR, wall)

func build_corner(corner: int):
	var holder = Node3D.new()
	holder.rotation.y = corner * PI / 2
	add_child(holder)

	var center = OUTER - PILLAR_SIZE / 2
	var pillar_center = Vector3(center, 0, -center)
	# Stone lower pillar between a gold foot and a taller gold crown
	add_block(pillar_center + Vector3(0, 0.25, 0), Vector3(PILLAR_SIZE + 0.1, 0.5, PILLAR_SIZE + 0.1),
		gold_material, GOLD_COLOR, holder)
	add_block(pillar_center + Vector3(0, (0.5 + CAP_BOTTOM) / 2, 0),
		Vector3(PILLAR_SIZE - 0.1, CAP_BOTTOM - 0.5 - GAP, PILLAR_SIZE - 0.1), stone_material, STONE_TINT, holder)
	add_block(pillar_center + Vector3(0, (CAP_BOTTOM + PILLAR_TOP) / 2, 0),
		Vector3(PILLAR_SIZE + 0.15, PILLAR_TOP - CAP_BOTTOM, PILLAR_SIZE + 0.15), gold_material, GOLD_COLOR, holder)

	# Gold brace set diagonally across the inner corner, from the floor to the band
	var brace_size = Vector3(1.2, CAP_BOTTOM, 0.12)
	var brace = MeshInstance3D.new()
	brace.mesh = bevelled_box(brace_size, GOLD_BEVEL * 0.5, GOLD_COLOR, GOLD_UV_SCALE)
	brace.material_override = gold_material
	brace.position = Vector3(INNER - 0.42, CAP_BOTTOM / 2, -INNER + 0.42)
	brace.rotation.y = -PI / 4
	holder.add_child(brace)

	# The brace juts into the throwing area, so the sticks bounce off it
	var body = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = brace_size
	shape.transform = brace.transform
	body.add_child(shape)
	holder.add_child(body)

# A bevelled block with a little hand-laid irregularity: tint, texture offset and a slight twist
func add_block(at: Vector3, size: Vector3, material: Material, tint: Color, parent: Node3D):
	var is_gold = material == gold_material
	var variation = rng.randf_range(0.97, 1.03) if is_gold else rng.randf_range(0.88, 1.08)
	var block = MeshInstance3D.new()
	block.mesh = bevelled_box(size, GOLD_BEVEL if is_gold else STONE_BEVEL, tint * variation,
		GOLD_UV_SCALE if is_gold else STONE_UV_SCALE)
	block.material_override = material
	block.position = at
	block.rotation.y = rng.randf_range(-0.006, 0.006)
	parent.add_child(block)

# Plain box for hidden filler (mortar core, plinth)
func add_box(at: Vector3, size: Vector3, material: Material, parent: Node3D = self):
	var box = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	mesh.material = material
	box.mesh = mesh
	box.position = at
	parent.add_child(box)

# A box with chamfered edges: 6 inset faces, 12 bevel strips and 8 corner
# triangles. Vertex colors carry the tint, darkened toward the block's foot.
# UVs are projected per face with a random offset so no two blocks match.
func bevelled_box(size: Vector3, bevel: float, tint: Color, uv_scale: float) -> ArrayMesh:
	var half = size / 2
	var b = minf(bevel, minf(half.x, minf(half.y, half.z)) * 0.5)
	var uv_offset = Vector2(rng.randf_range(0, 10), rng.randf_range(0, 10))
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Where the face on `axis` meets the corner in direction s
	var face_point = func(axis: int, s: Vector3) -> Vector3:
		var p = Vector3(s.x * (half.x - b), s.y * (half.y - b), s.z * (half.z - b))
		p[axis] = s[axis] * half[axis]
		return p

	var polygons: Array = []
	var loop = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for axis in 3:
		var others = [(axis + 1) % 3, (axis + 2) % 3]
		for sign_value in [-1.0, 1.0]:
			var face: Array = []
			for l in loop:
				var s = Vector3.ZERO
				s[axis] = sign_value
				s[others[0]] = l.x
				s[others[1]] = l.y
				face.append(face_point.call(axis, s))
			polygons.append(face)
		# Bevel strips running along `axis`
		for l in loop:
			var s_low = Vector3.ZERO
			s_low[others[0]] = l.x
			s_low[others[1]] = l.y
			s_low[axis] = -1
			var s_high = s_low
			s_high[axis] = 1
			polygons.append([face_point.call(others[0], s_low), face_point.call(others[0], s_high),
				face_point.call(others[1], s_high), face_point.call(others[1], s_low)])
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				var s = Vector3(x, y, z)
				polygons.append([face_point.call(0, s), face_point.call(1, s), face_point.call(2, s)])

	for points in polygons:
		var centroid = Vector3.ZERO
		for p in points:
			centroid += p
		centroid /= points.size()
		var normal = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
		if normal.dot(centroid) < 0:
			points.reverse()
			normal = -normal
		# Godot treats clockwise triangles as front-facing
		points.reverse()
		var abs_normal = normal.abs()
		for i in range(1, points.size() - 1):
			for p in [points[0], points[i], points[i + 1]]:
				var uv: Vector2
				if abs_normal.x >= abs_normal.y and abs_normal.x >= abs_normal.z:
					uv = Vector2(p.z, -p.y)
				elif abs_normal.y >= abs_normal.z:
					uv = Vector2(p.x, p.z)
				else:
					uv = Vector2(p.x, -p.y)
				var height = (p.y + half.y) / size.y
				st.set_color(tint * lerpf(BLOCK_FOOT_SHADE, 1.0, sqrt(height)))
				st.set_normal(normal)
				st.set_uv(uv * uv_scale + uv_offset)
				st.add_vertex(p)
	st.generate_tangents()
	return st.commit()

# Warm key light with soft shadows, a cool fill from the far side, and a low
# ember glow, under filmic tone mapping. The gold also reflects a warm sky.
# The background stays clear, keeping the dice viewport transparent over the board.
func add_lighting():
	var key = DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.89, 0.72)
	key.light_energy = 1.3
	key.shadow_enabled = true
	key.shadow_blur = 1.5
	key.light_angular_distance = 2.5 # Softer shadow edges
	add_child(key)
	key.look_at_from_position(Vector3(-4, 10, 6), Vector3.ZERO, Vector3.UP)

	var fill = DirectionalLight3D.new()
	fill.light_color = Color(0.62, 0.7, 0.9)
	fill.light_energy = 0.3
	add_child(fill)
	fill.look_at_from_position(Vector3(6, 5, -6), Vector3.ZERO, Vector3.UP)

	var ember = OmniLight3D.new()
	ember.light_color = Color(1.0, 0.45, 0.15)
	ember.light_energy = 1.2
	ember.omni_range = 9.0
	ember.position = Vector3(7.5, 1.5, 5.5)
	add_child(ember)

	var sky_material = ProceduralSkyMaterial.new()
	# Bright overhead and dim at the horizon: gold tops shine, their sides fall darker
	sky_material.sky_top_color = Color(0.72, 0.62, 0.48)
	sky_material.sky_horizon_color = Color(0.45, 0.32, 0.18)
	sky_material.sky_curve = 0.3
	sky_material.ground_bottom_color = Color(0.12, 0.08, 0.04)
	sky_material.ground_horizon_color = Color(0.4, 0.28, 0.15)
	var sky = Sky.new()
	sky.sky_material = sky_material

	var environment = Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(1.0, 0.86, 0.68)
	environment.ambient_light_energy = 0.4
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	var world_environment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
