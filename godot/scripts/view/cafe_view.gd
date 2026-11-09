## 3D view of the cafe built from primitive meshes. Reads the simulation; never changes it.
extends Node3D

const Data = preload("res://scripts/core/data.gd")
const Layout = preload("res://scripts/core/layout.gd")

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
	add_child(sun)
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("2b2433")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("f4f0ff")
	e.ambient_light_energy = 0.4
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	_update_camera()

func mat(hex: String, emissive := false, alpha := 1.0) -> StandardMaterial3D:
	var k := "%s|%s|%s" % [hex, emissive, alpha]
	if mats.has(k):
		return mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = 0.85
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = alpha
	if emissive:
		m.emission_enabled = true
		m.emission = Color(hex)
		m.emission_energy_multiplier = 1.4
	mats[k] = m
	return m

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
	return "|".join(parts)

func rebuild_room() -> void:
	_last_furniture_sig = _furniture_sig()
	for c in room.get_children():
		c.queue_free()
	var lay = Layout.new(s.furniture, s.upgrades)
	# floor
	box(room, Vector3(16, 0.1, 10), Vector3(8.5, -0.05, 5.5), "8a6a50")
	for x in range(1, 17):
		for z in range(1, 11):
			if (x + z) % 2 == 0:
				box(room, Vector3(1, 0.012, 1), Vector3(x, 0.006, z), "7a5c44")
	# the street outside the door
	box(room, Vector3(30, 0.05, 4), Vector3(8.5, -0.06, 13.5), "5a5560")
	box(room, Vector3(5, 0.02, 3), Vector3(3, 0.01, 2), "dcd6cc")   # kitchen tiles
	box(room, Vector3(4, 0.02, 3), Vector3(14.5, 0.01, 2), "8a7a9a")  # staff room carpet
	for x in Layout.W:
		for z in Layout.H:
			var c := Vector2i(x, z)
			var k: String = lay.kind_at(c)
			match k:
				"wall":
					var low: bool = z == Layout.H - 1 or x == Layout.W - 1
					var inner: bool = x > 0 and z > 0 and x < Layout.W - 1 and z < Layout.H - 1
					var h := 0.35 if low else (1.3 if inner else 2.4)
					box(room, Vector3(1, h, 1), Vector3(x, h / 2, z), "c8b49a" if not inner else "a89078")
				"door":
					box(room, Vector3(1, 0.04, 1), Vector3(x, 0.02, z), "7a4a3a")
				"kitchen":
					box(room, Vector3(0.96, 0.9, 0.96), Vector3(x, 0.45, z), "c9c4bc")
				"counter":
					box(room, Vector3(0.98, 0.95, 0.9), Vector3(x, 0.475, z), "8a5a3a")
				"desk":
					box(room, Vector3(0.95, 1.0, 0.8), Vector3(x, 0.5, z), "6a3a4a")
					box(room, Vector3(0.3, 0.05, 0.2), Vector3(x, 1.03, z), "f2e6d0")
				"sofa":
					box(room, Vector3(0.95, 0.45, 0.8), Vector3(x, 0.22, z), "b05a6a")
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
	box(room, Vector3(0.9, 0.9, 0.9), Vector3(16, 0.45, 3), "7a5a8a")
	# furniture
	for f in s.furniture:
		_furniture_mesh(f, lay)
	_apply_lighting()

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
				box(n, Vector3(0.45, 0.06, 0.45), Vector3(dx, 0.42, 0), "8a5a3a")
				box(n, Vector3(0.08, 0.5, 0.45), Vector3(dx * 1.22, 0.65, 0), "8a5a3a")
		"sofa_table":
			cyl(n, 0.4, 0.06, Vector3(0, 0.6, 0), "f6efe2")
			cyl(n, 0.07, 0.6, Vector3(0, 0.3, 0), "5a3a2a")
			for dx in [-1, 1]:
				box(n, Vector3(0.7, 0.4, 0.8), Vector3(dx, 0.2, 0), "a04a5a")
				box(n, Vector3(0.2, 0.8, 0.8), Vector3(dx * 1.3, 0.4, 0), "a04a5a")
		"plant":
			cyl(n, 0.22, 0.4, Vector3(0, 0.2, 0), "a0603a", false, 0.28)
			sphere(n, 0.35, Vector3(0, 0.75, 0), "4a8a4a")
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
			box(n, Vector3(0.9, 1.9, 0.5), Vector3(0, 0.95, 0), "6a4a2a")
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
		"partition":
			box(n, Vector3(0.12, 1.6, 0.95), Vector3(0, 0.8, 0), "c8b090")
			box(n, Vector3(0.14, 1.2, 0.7), Vector3(0, 0.85, 0), "f0e6d6")

func _apply_lighting() -> void:
	var e: Environment = env.environment
	match s.get("lighting", "warm"):
		"bright":
			sun.light_color = Color("ffffff")
			sun.light_energy = 0.95
			e.ambient_light_energy = 0.5
		"dim":
			sun.light_color = Color("ffc890")
			sun.light_energy = 0.42
			e.ambient_light_energy = 0.25
		_:
			sun.light_color = Color("fff0e0")
			sun.light_energy = 0.7
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
		# skirt + apron + headdress
		cyl(body, 0.3, 0.35, Vector3(0, 0.3, 0), body_hex, false, 0.18)
		box(body, Vector3(0.26, 0.42, 0.04), Vector3(0, 0.42, 0.2), "fafafa")
		box(body, Vector3(0.3, 0.05, 0.1), Vector3(0, 1.17, 0.02), "fafafa")
	var head := sphere(body, 0.17, Vector3(0, 0.98, 0), "f6d8c0")
	sphere(body, 0.185, Vector3(0, 1.03, -0.04), hair_hex)
	var carry := sphere(body, 0.09, Vector3(0.25, 0.7, 0.15), "ffffff")
	carry.visible = false
	var lbl := Label3D.new()
	lbl.text = name
	lbl.position = Vector3(0, 1.5, 0)
	lbl.font_size = 40
	lbl.pixel_size = 0.0065
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.outline_size = 10
	lbl.modulate = Color("ffffff")
	lbl.no_depth_test = true
	root.add_child(lbl)
	var bub := Label3D.new()
	bub.position = Vector3(0, 1.95, 0)
	bub.font_size = 44
	bub.pixel_size = 0.0065
	bub.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bub.outline_size = 12
	bub.modulate = Color("fff6c8")
	bub.outline_modulate = Color("3a2a3a")
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
	ring.material_override = mat("ffd84a", true)
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
