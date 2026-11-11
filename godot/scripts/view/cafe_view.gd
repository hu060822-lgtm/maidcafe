## 3D view of the cafe built from primitive meshes. Reads the simulation; never changes it.
extends Node3D

const Data = preload("res://scripts/core/data.gd")
const Layout = preload("res://scripts/core/layout.gd")
const LD = preload("res://scripts/core/life_data.gd")
const MaidTheme = preload("res://scripts/view/maid_theme.gd")

## Anime look: toon (cel) shading with a soft rim light, plus an inverted-hull outline on solid meshes.
const TOON := true
const OUTLINE_GROW := 0.035

signal cell_clicked(cell: Vector2i, button: int)
signal agent_clicked(kind: String, id: String)

var s: Dictionary
var sim = null
var cam: Camera3D
var sun: DirectionalLight3D
var env: WorldEnvironment
var room := Node3D.new()
var agents_root := Node3D.new()
var overlay := Node3D.new()
var ghost := Node3D.new()
var agent_nodes := {}      # id -> {root, body, head, name, bubble, carry}
var mess_nodes := {}
var mats := {}
var yaw := -0.3
var pitch := 1.0
var dist := 23.5
var target := Vector3(8.5, 0, 5.5)
var dragging := false
var panning := false
var show_debug := false
var show_heat := false
var selected_id := ""
var _last_furniture_sig := ""

func _ready() -> void:
	add_child(room)
	add_child(agents_root)
	add_child(overlay)
	add_child(ghost)
	cam = Camera3D.new()
	cam.fov = 42
	cam.h_offset = -2.4
	add_child(cam)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.55
	sun.shadow_blur = 1.5
	add_child(sun)
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("f6dde6")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("fff1f6")
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	_update_camera()

func mat(hex: String, emissive := false, alpha := 1.0, outline := true) -> StandardMaterial3D:
	var k := "%s|%s|%s|%s" % [hex, emissive, alpha, outline]
	if mats.has(k):
		return mats[k]
	var m := StandardMaterial3D.new()
	# colours are picked as they should look on screen; the lighting brightens them, so start from linear
	m.albedo_color = Color(hex).srgb_to_linear() if TOON else Color(hex)
	m.roughness = 0.85
	if TOON:
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.roughness = 1.0
		m.metallic_specular = 0.2
		m.rim_enabled = true
		m.rim = 0.35
		m.rim_tint = 0.6
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = alpha
	if emissive:
		m.emission_enabled = true
		m.emission = Color(hex)
		m.emission_energy_multiplier = 1.4
	if TOON and outline and alpha >= 1.0 and not emissive:
		m.next_pass = _outline_mat(Color(hex))
	mats[k] = m
	return m

## Dark, slightly tinted version of the surface colour, drawn as a grown back-face shell.
func _outline_mat(c: Color) -> StandardMaterial3D:
	var key := "outline|" + c.to_html(false)
	if mats.has(key):
		return mats[key]
	var o := StandardMaterial3D.new()
	o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	o.cull_mode = BaseMaterial3D.CULL_FRONT
	o.grow = true
	o.grow_amount = OUTLINE_GROW
	var d := c.darkened(0.62)
	d = d.lerp(Color("5b2a3f"), 0.35)
	o.albedo_color = d
	mats[key] = o
	return o

func box(parent: Node3D, size: Vector3, pos: Vector3, hex: String, emissive := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat(hex, emissive)
	parent.add_child(mi)
	return mi

func cyl(parent: Node3D, r: float, h: float, pos: Vector3, hex: String, emissive := false, top := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r if top < 0 else top
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 16
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat(hex, emissive)
	parent.add_child(mi)
	return mi

func sphere(parent: Node3D, r: float, pos: Vector3, hex: String, emissive := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.position = pos
	mi.material_override = mat(hex, emissive)
	parent.add_child(mi)
	return mi

# ---------------------------------------------------------------- room
func set_state(p_s: Dictionary) -> void:
	s = p_s
	rebuild_room()

func _furniture_sig() -> String:
	var parts := []
	for f in s.furniture:
		parts.append("%s%s%d,%d" % [f.id, f.type, int(f.x), int(f.z)])
	parts.append(str(s.upgrades))
	parts.append(str(s.vase_water))
	parts.append(s.lighting)
	parts.append(String(s.get("decor", "")))
	return "|".join(parts)

func rebuild_room() -> void:
	_last_furniture_sig = _furniture_sig()
	for c in room.get_children():
		c.queue_free()
	var lay = Layout.new(s.furniture, s.upgrades)
	# floor
	box(room, Vector3(16, 0.1, 10), Vector3(8.5, -0.05, 5.5), "efcfb6")
	for x in range(1, 17):
		for z in range(1, 11):
			if (x + z) % 2 == 0:
				var tile := box(room, Vector3(1, 0.012, 1), Vector3(x, 0.006, z), "f2b3c6")
				tile.material_override = mat("f2b3c6", false, 1.0, false)
	# the street outside the door
	box(room, Vector3(30, 0.05, 4), Vector3(8.5, -0.06, 13.5), "c9bcc6")
	box(room, Vector3(5, 0.02, 3), Vector3(3, 0.01, 2), "dfe9f0")   # kitchen tiles
	box(room, Vector3(4, 0.02, 3), Vector3(14.5, 0.01, 2), "d9c6ea")  # staff room carpet
	for x in Layout.W:
		for z in Layout.H:
			var c := Vector2i(x, z)
			var k: String = lay.kind_at(c)
			match k:
				"wall":
					var low: bool = z == Layout.H - 1 or x == Layout.W - 1
					var inner: bool = x > 0 and z > 0 and x < Layout.W - 1 and z < Layout.H - 1
					var h := 0.35 if low else (1.3 if inner else 2.4)
					box(room, Vector3(1, h, 1), Vector3(x, h / 2, z), "f4b4c8" if not inner else "e99ab3")
				"door":
					box(room, Vector3(1, 0.04, 1), Vector3(x, 0.02, z), "eab08c")
				"kitchen":
					box(room, Vector3(0.96, 0.9, 0.96), Vector3(x, 0.45, z), "f4f1ee")
				"counter":
					box(room, Vector3(0.98, 0.95, 0.9), Vector3(x, 0.475, z), "f2c9a8")
				"desk":
					box(room, Vector3(0.95, 1.0, 0.8), Vector3(x, 0.5, z), "f39ab8")
					box(room, Vector3(0.3, 0.05, 0.2), Vector3(x, 1.03, z), "f2e6d0")
				"sofa":
					box(room, Vector3(0.95, 0.45, 0.8), Vector3(x, 0.22, z), "f19ab4")
	# windows on the back wall
	for x in [3, 8, 14]:
		box(room, Vector3(1.6, 1.0, 0.05), Vector3(x, 1.4, 0.52), "9ad0f0" if s.weather != "rain" else "6a8aa0", true)
	# stations
	for st in lay.stations:
		var c: Vector2i = st.cell
		if st.kind == "stove":
			box(room, Vector3(0.7, 0.04, 0.7), Vector3(c.x, 0.92, c.y), "2a2a2a")
			cyl(room, 0.18, 0.03, Vector3(c.x, 0.95, c.y), "aa3a2a", true)
		else:
			box(room, Vector3(0.5, 0.5, 0.45), Vector3(c.x, 1.15, c.y), "3a3a40" if not s.upgrades.coffee_machine else "b0b0b8")
	# shelves in kitchen / staff room
	box(room, Vector3(0.9, 0.9, 0.9), Vector3(16, 0.45, 3), "b99ad0")
	# furniture
	for f in s.furniture:
		_furniture_mesh(f, lay)
	_decor_meshes()
	_apply_lighting()

## Seasonal decoration: a garland along the back wall and small ornaments by the windows (purely visual).
func _decor_meshes() -> void:
	var d: String = s.get("decor", "")
	if d == "" or not LD.DECOR.has(d):
		return
	var col: String = LD.DECOR[d].color
	for i in 15:
		var x := 1.5 + i
		var y := 2.05 - absf(sin(i * 0.9)) * 0.18
		sphere(room, 0.09, Vector3(x, y, 0.6), col if i % 2 == 0 else "fff4e0", true)
	for x in [3, 8, 14]:
		match d:
			"spring":
				for k in 3:
					sphere(room, 0.07, Vector3(x - 0.5 + k * 0.5, 1.95, 0.58), "f8c0d0", true)
			"summer":
				cyl(room, 0.07, 0.18, Vector3(x, 1.85, 0.62), "80c8e8", true)
			"autumn":
				sphere(room, 0.14, Vector3(x + 0.9, 0.12, 0.8), "e08040", true)
			"winter":
				box(room, Vector3(0.18, 0.18, 0.04), Vector3(x, 2.0, 0.58), "f0e8a0", true)

func _furniture_mesh(f: Dictionary, lay) -> void:
	var x := float(f.x)
	var z := float(f.z)
	var n := Node3D.new()
	n.position = Vector3(x, 0, z)
	room.add_child(n)
	match f.type:
		"table":
			cyl(n, 0.38, 0.06, Vector3(0, 0.72, 0), "f2e6d0")
			cyl(n, 0.06, 0.7, Vector3(0, 0.35, 0), "6a4a3a")
			for dx in [-1, 1]:
				box(n, Vector3(0.45, 0.06, 0.45), Vector3(dx, 0.42, 0), "f08fb0")
				box(n, Vector3(0.08, 0.5, 0.45), Vector3(dx * 1.22, 0.65, 0), "fbe3ea")
		"sofa_table":
			cyl(n, 0.4, 0.06, Vector3(0, 0.6, 0), "f6efe2")
			cyl(n, 0.07, 0.6, Vector3(0, 0.3, 0), "5a3a2a")
			for dx in [-1, 1]:
				box(n, Vector3(0.7, 0.4, 0.8), Vector3(dx, 0.2, 0), "e57c9b")
				box(n, Vector3(0.2, 0.8, 0.8), Vector3(dx * 1.3, 0.4, 0), "e57c9b")
		"plant":
			cyl(n, 0.22, 0.4, Vector3(0, 0.2, 0), "a0603a", false, 0.28)
			sphere(n, 0.35, Vector3(0, 0.75, 0), "79c27f")
		"lamp":
			cyl(n, 0.04, 1.5, Vector3(0, 0.75, 0), "3a3a3a")
			cyl(n, 0.25, 0.3, Vector3(0, 1.55, 0), "ffd890", true, 0.12)
			var l := OmniLight3D.new()
			l.position = Vector3(0, 1.4, 0)
			l.light_color = Color("ffcf8a")
			l.omni_range = 3.5
			l.light_energy = 0.8
			n.add_child(l)
		"gramophone":
			box(n, Vector3(0.6, 0.7, 0.6), Vector3(0, 0.35, 0), "5a3a2a")
			cyl(n, 0.05, 0.4, Vector3(0, 0.9, 0.1), "c8a040", false, 0.3)
		"plush":
			sphere(n, 0.4, Vector3(0, 0.4, 0), "c89a6a")
			sphere(n, 0.28, Vector3(0, 0.95, 0), "c89a6a")
			sphere(n, 0.1, Vector3(-0.2, 1.18, 0), "c89a6a")
			sphere(n, 0.1, Vector3(0.2, 1.18, 0), "c89a6a")
		"vase":
			var wilted := int(s.vase_water.get(f.id, 0)) >= 2
			box(n, Vector3(0.6, 0.6, 0.6), Vector3(0, 0.3, 0), "e8e0d0")
			cyl(n, 0.13, 0.4, Vector3(0, 0.8, 0), "f6f6ff")
			for i in 5:
				var a := i * TAU / 5.0
				sphere(n, 0.1, Vector3(cos(a) * 0.14, 1.12 - (0.18 if wilted else 0.0), sin(a) * 0.14), "8a7a5a" if wilted else ["f5a0b5", "fff0a0", "f0f0ff"][i % 3])
		"crystal":
			cyl(n, 0.05, 1.6, Vector3(0, 0.8, 0), "6a5a9a")
			sphere(n, 0.25, Vector3(0, 1.7, 0), "a0e0ff", true)
		"photo":
			box(n, Vector3(0.9, 1.6, 0.08), Vector3(0, 0.8, -0.35), "f5c0d0")
			box(n, Vector3(0.6, 0.6, 0.02), Vector3(0, 1.2, -0.3), "ffffff", true)
		"stage":
			box(n, Vector3(2, 0.3, 2), Vector3(0.5, 0.15, 0.5), "7a3a5a")
			box(n, Vector3(2, 0.04, 0.1), Vector3(0.5, 0.32, 1.45), "ffd0e0", true)
		"bookshelf":
			box(n, Vector3(0.9, 1.9, 0.5), Vector3(0, 0.95, 0), "c99a6e")
			var cols := ["a04a4a", "4a6aa0", "e0c060", "4a8a5a", "8a5aa0", "d0d0c0"]
			for row in 4:
				for i in 5:
					box(n, Vector3(0.12, 0.32, 0.38), Vector3(-0.3 + i * 0.15, 0.3 + row * 0.42, 0.04), cols[(row * 5 + i * 7 + int(x)) % cols.size()])
		"display":
			box(n, Vector3(0.9, 0.8, 0.6), Vector3(0, 0.4, 0), "6a4a5a")
			var gm := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.85, 0.6, 0.55)
			gm.mesh = bm
			gm.position = Vector3(0, 1.1, 0)
			gm.material_override = mat("d0f0ff", false, 0.35)
			n.add_child(gm)
			sphere(n, 0.1, Vector3(-0.2, 0.95, 0), "f5a0b5")
			sphere(n, 0.1, Vector3(0.15, 0.95, 0), "fff0a0")
		"ribbon_arch":
			for dx in [-0.42, 0.42]:
				cyl(n, 0.05, 1.7, Vector3(dx, 0.85, 0), "ffffff")
			var arch := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.37
			tm.outer_radius = 0.47
			arch.mesh = tm
			arch.rotation_degrees = Vector3(90, 0, 0)
			arch.position = Vector3(0, 1.7, 0)
			arch.material_override = mat("ff8fb5")
			n.add_child(arch)
			sphere(n, 0.1, Vector3(-0.12, 2.15, 0.04), "ff6f9c")
			sphere(n, 0.1, Vector3(0.12, 2.15, 0.04), "ff6f9c")
			sphere(n, 0.06, Vector3(0, 2.15, 0.06), "ffd1e0")
		"tea_cart":
			box(n, Vector3(0.8, 0.05, 0.5), Vector3(0, 0.75, 0), "f6efe2")
			box(n, Vector3(0.8, 0.05, 0.5), Vector3(0, 0.35, 0), "f6efe2")
			for cx in [-0.36, 0.36]:
				for cz in [-0.2, 0.2]:
					cyl(n, 0.025, 0.75, Vector3(cx, 0.38, cz), "c9a46a")
			cyl(n, 0.12, 0.18, Vector3(-0.15, 0.87, 0), "ffffff", false, 0.09)
			cyl(n, 0.13, 0.02, Vector3(0.18, 0.79, 0), "ffb3cf")
			sphere(n, 0.06, Vector3(0.18, 0.85, 0), "fbe3c8")
		"partition":
			box(n, Vector3(0.12, 1.6, 0.95), Vector3(0, 0.8, 0), "c8b090")
			box(n, Vector3(0.14, 1.2, 0.7), Vector3(0, 0.85, 0), "f0e6d6")

func _apply_lighting() -> void:
	var e: Environment = env.environment
	match s.get("lighting", "warm"):
		"bright":
			sun.light_color = Color("ffffff")
			sun.light_energy = 0.7
			e.ambient_light_energy = 0.45
		"dim":
			sun.light_color = Color("ffc8a0")
			sun.light_energy = 0.38
			e.ambient_light_energy = 0.26
		_:
			sun.light_color = Color("fff0e6")
			sun.light_energy = 0.48
			e.ambient_light_energy = 0.38
	if s.get("weather", "") == "rain":
		sun.light_energy *= 0.7

# ---------------------------------------------------------------- agents
func set_sim(p_sim) -> void:
	sim = p_sim
	for id in agent_nodes.keys():
		agent_nodes[id].root.queue_free()
	agent_nodes.clear()
	for id in mess_nodes.keys():
		mess_nodes[id].queue_free()
	mess_nodes.clear()

func _make_agent(id: String, kind: String, body_hex: String, hair_hex: String, name: String) -> Dictionary:
	var root := Node3D.new()
	agents_root.add_child(root)
	var body := Node3D.new()
	root.add_child(body)
	var torso := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.2
	cm.height = 0.8
	torso.mesh = cm
	torso.position = Vector3(0, 0.45, 0)
	torso.material_override = mat(body_hex)
	body.add_child(torso)
	if kind == "maid":
		# flared skirt with a frilly hem, apron with a bow, headdress (chibi proportions)
		cyl(body, 0.34, 0.38, Vector3(0, 0.3, 0), body_hex, false, 0.17)
		cyl(body, 0.36, 0.05, Vector3(0, 0.12, 0), "ffffff", false, 0.35)
		box(body, Vector3(0.26, 0.42, 0.04), Vector3(0, 0.42, 0.2), "ffffff")
		sphere(body, 0.07, Vector3(-0.07, 0.6, -0.21), "ff8fb5")
		sphere(body, 0.07, Vector3(0.07, 0.6, -0.21), "ff8fb5")
		box(body, Vector3(0.36, 0.06, 0.12), Vector3(0, 1.3, 0.04), "ffffff")
		sphere(body, 0.045, Vector3(0, 1.3, 0.12), "ff8fb5")
	var head := sphere(body, 0.23, Vector3(0, 1.02, 0), "ffe3d3")
	sphere(body, 0.245, Vector3(0, 1.08, -0.05), hair_hex)
	# big anime eyes with a highlight, and blush
	for sx in [-1, 1]:
		var eye := sphere(body, 0.045, Vector3(sx * 0.085, 1.0, 0.2), "3a2238")
		eye.scale = Vector3(0.8, 1.25, 0.5)
		eye.material_override = mat("3a2238", false, 1.0, false)
		var hi := sphere(body, 0.016, Vector3(sx * 0.085 + 0.012, 1.025, 0.222), "ffffff", true)
		hi.material_override = mat("ffffff", true, 1.0, false)
		var bl := sphere(body, 0.035, Vector3(sx * 0.14, 0.95, 0.18), "ff9fb8")
		bl.scale = Vector3(1.2, 0.6, 0.4)
		bl.material_override = mat("ff9fb8", false, 0.7)
	var carry := sphere(body, 0.09, Vector3(0.25, 0.7, 0.15), "ffffff")
	carry.visible = false
	var lbl := Label3D.new()
	lbl.text = name
	lbl.position = Vector3(0, 1.5, 0)
	lbl.font_size = 40
	lbl.pixel_size = 0.0065
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.outline_size = 12
	lbl.font = MaidTheme.font()
	lbl.position.y = 1.62
	lbl.modulate = Color("ffffff")
	lbl.outline_modulate = Color("d94f82") if kind == "maid" else Color("6b4a5a")
	lbl.no_depth_test = true
	root.add_child(lbl)
	var bub := Label3D.new()
	bub.position = Vector3(0, 1.95, 0)
	bub.font_size = 44
	bub.pixel_size = 0.0065
	bub.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bub.outline_size = 12
	bub.font = MaidTheme.font()
	bub.position.y = 2.05
	bub.modulate = Color("fff8f3")
	bub.outline_modulate = Color("8f3a5e")
	bub.no_depth_test = true
	bub.width = 420
	bub.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	root.add_child(bub)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.32
	tm.outer_radius = 0.4
	ring.mesh = tm
	ring.position = Vector3(0, 0.03, 0)
	ring.material_override = mat("ff8fb5", true)
	ring.visible = false
	root.add_child(ring)
	var d := {"root": root, "body": body, "head": head, "name": lbl, "bubble": bub, "carry": carry, "ring": ring, "kind": kind, "seen": true}
	agent_nodes[id] = d
	return d

func _process(_dt: float) -> void:
	if s.is_empty():
		return
	if _furniture_sig() != _last_furniture_sig:
		rebuild_room()
	if sim == null:
		return
	for id in agent_nodes:
		agent_nodes[id].seen = false
	for w in sim.workers:
		var key: String = w.id
		var d: Dictionary = agent_nodes.get(key, {})
		if d.is_empty():
			var body := "2a2a44"
			var hair := "3a2a2a"
			if w.kind == "maid":
				hair = Data.MAIDS[w.maid_id].hair
				body = {"koharu": "3a2a4a", "rin": "1e2236", "shizuku": "2a3a5a", "yukino": "403a50", "kaede": "4a2020"}.get(w.maid_id, "2a2a44")
			else:
				body = "4a5a6a"
			d = _make_agent(key, w.kind, body, hair, w.name)
		_sync(d, w, w.kind == "maid" and sim.s.maids[w.maid_id].role == "off" and sim.mode == "business")
		var dbg := ""
		if show_debug or selected_id == key:
			dbg = "\n[%s]" % w.activity
		d.name.text = w.name + dbg
		d.carry.visible = w.carrying != ""
		if w.carrying != "" and Data.DISHES.has(w.carrying):
			d.carry.material_override = mat(Data.DISHES[w.carrying].color)
	for p in sim.parties:
		for m in p.members:
			var key: String = m.id
			var d: Dictionary = agent_nodes.get(key, {})
			if d.is_empty():
				d = _make_agent(key, "cust", m.color, m.hair, m.name)
			_sync(d, m, false)
			var extra := ""
			if show_debug or selected_id == key:
				extra = "\n%s %d" % [p.state, int(m.sat)]
			d.name.text = m.name + extra
			d.carry.visible = m.pose == "photo"
	for id in agent_nodes.keys():
		if not agent_nodes[id].seen:
			agent_nodes[id].root.queue_free()
			agent_nodes.erase(id)
	# messes
	var live := {}
	for ms in sim.messes:
		live[ms.id] = true
		if not mess_nodes.has(ms.id):
			var mi := cyl(agents_root, 0.3, 0.01, Vector3(ms.cell.x, 0.01, ms.cell.y), "6a8ab0" if ms.get("rain", false) else "7a4a2a")
			mess_nodes[ms.id] = mi
	for id in mess_nodes.keys():
		if not live.has(id):
			mess_nodes[id].queue_free()
			mess_nodes.erase(id)

func _sync(d: Dictionary, a, hidden: bool) -> void:
	d.seen = true
	var root: Node3D = d.root
	root.visible = not hidden or true
	var y := 0.0
	if a is Object and a.get("sitting") == true:
		y = -0.2
	if not a.inside and a.get("party_id") != null:
		# customers outside walk along the street
		y = 0.0
	if a.get("performing") == true:
		y = 0.3 + absf(sin(Time.get_ticks_msec() / 180.0)) * 0.08
	root.position = Vector3(a.pos.x, y, a.pos.y)
	d.body.rotation.y = a.facing
	if a.moving:
		d.body.position.y = absf(sin(Time.get_ticks_msec() / 110.0)) * 0.04
	else:
		d.body.position.y = 0.0
	d.bubble.text = a.bubble
	d.ring.visible = selected_id == a.id

# ---------------------------------------------------------------- overlays
func set_heat(on: bool, heat: Dictionary) -> void:
	show_heat = on
	for c in overlay.get_children():
		c.queue_free()
	if not on:
		return
	var mx := 0.1
	for k in heat:
		mx = maxf(mx, float(heat[k]))
	for k in heat:
		var p: PackedStringArray = String(k).split(",")
		var v := float(heat[k]) / mx
		var col := Color(1.0, 1.0 - v, 0.2, 0.25 + v * 0.5)
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.95, 0.95)
		mi.mesh = pm
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		mi.position = Vector3(int(p[0]), 0.05, int(p[1]))
		overlay.add_child(mi)

## Furniture placement preview.
func set_ghost(type: String, cell: Vector2i, ok: bool) -> void:
	for c in ghost.get_children():
		c.queue_free()
	if type == "":
		return
	for off in Data.FURNITURE[type].fp:
		var mi := box(ghost, Vector3(0.95, 0.1, 0.95), Vector3(cell.x + off[0], 0.06, cell.y + off[1]), "60e080" if ok else "e06060", true)
		mi.material_override = mat("60e080" if ok else "e06060", true, 0.6)

# ---------------------------------------------------------------- camera & picking
func _update_camera() -> void:
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.position = target + off
	cam.look_at(target, Vector3.UP)

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb: InputEventMouseButton = ev
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			dist = clampf(dist - 1.0, 6.0, 30.0)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			dist = clampf(dist + 1.0, 6.0, 30.0)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_pick(mb.position, MOUSE_BUTTON_LEFT)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_pick(mb.position, MOUSE_BUTTON_RIGHT)
	elif ev is InputEventMouseMotion:
		var mm: InputEventMouseMotion = ev
		if dragging:
			if mm.shift_pressed:
				var right := cam.global_transform.basis.x
				var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
				target += (-right * mm.relative.x + fwd * mm.relative.y) * 0.02
			else:
				yaw -= mm.relative.x * 0.008
				pitch = clampf(pitch + mm.relative.y * 0.006, 0.35, 1.45)
			_update_camera()
	elif ev is InputEventKey and ev.pressed:
		match ev.keycode:
			KEY_Q:
				yaw += 0.15
				_update_camera()
			KEY_E:
				yaw -= 0.15
				_update_camera()

func screen_to_cell(pos: Vector2) -> Vector2i:
	var from := cam.project_ray_origin(pos)
	var dir := cam.project_ray_normal(pos)
	if absf(dir.y) < 0.0001:
		return Vector2i(-1, -1)
	var t := -from.y / dir.y
	var hit := from + dir * t
	return Vector2i(roundi(hit.x), roundi(hit.z))

func _pick(pos: Vector2, button: int) -> void:
	# agents first (closest to the ray on screen)
	var best := ""
	var bd := 40.0
	for id in agent_nodes:
		var root: Node3D = agent_nodes[id].root
		var sp := cam.unproject_position(root.global_position + Vector3(0, 0.8, 0))
		var dd := sp.distance_to(pos)
		if dd < bd:
			bd = dd
			best = id
	if best != "" and button == MOUSE_BUTTON_LEFT:
		agent_clicked.emit(agent_nodes[best].kind, best)
		return
	var c := screen_to_cell(pos)
	cell_clicked.emit(c, button)
