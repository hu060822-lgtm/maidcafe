class_name PortraitPainter
extends Node2D
## Draws an anime-style half-body portrait from a "recipe" (hair, eyes,
## outfit colours ...) with plain vector shapes. Used by the Portrait Maker
## in the Creator Workshop to create portraits without external tools.
##
## Everything is drawn in a 1024x1536 design space (the art_spec portrait
## canvas); `supersample` scales the drawing up for clean edges.

const W := 1024.0
const H := 1536.0
const CX := 512.0
const LINE := 5.0
const DROP := 56.0                       ## whole figure is shifted down by this
const HEAD_SCALE := 1.15                 ## anime proportions: larger head
const HEAD_PIVOT := Vector2(512, 460)

var recipe: Dictionary = {}
var pose := "stand"
var outfit := "maid"
var expression := "neutral"
var supersample := 2.0

var _skin: Color
var _hair: Color
var _eye: Color


func configure(r: Dictionary, p: String, o: String, e: String) -> void:
	recipe = PortraitRecipe.normalized(r)
	pose = p
	outfit = o
	expression = e
	queue_redraw()


# ------------------------------------------------------------- helpers

func _ol(c: Color) -> Color:
	# coloured outline: darker, slightly desaturated version of the fill
	var o := c.darkened(0.58)
	if c.s < 0.12 and c.v > 0.8:
		o = Color(0.42, 0.36, 0.46)
	o.a = 1.0
	return o


func _smooth(pts: PackedVector2Array, closed: bool, steps := 8) -> PackedVector2Array:
	var n := pts.size()
	var out := PackedVector2Array()
	if n < 3:
		return pts
	var segs := n if closed else n - 1
	for i in segs:
		var p0 := pts[(i - 1 + n) % n] if closed else pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[(i + 1) % n] if closed else pts[mini(i + 1, n - 1)]
		var p3 := pts[(i + 2) % n] if closed else pts[mini(i + 2, n - 1)]
		for s in steps:
			var t := float(s) / steps
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	if not closed:
		out.append(pts[n - 1])
	return out


func _pv(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in a:
		out.append(p)
	return out


func _mirror(a: Array) -> Array:
	var out: Array = []
	for i in range(a.size() - 1, -1, -1):
		out.append(Vector2(2.0 * CX - a[i].x, a[i].y))
	return out


## Symmetric closed outline from its right half (top -> bottom).
func _sym(right: Array) -> Array:
	var left := _mirror(right)
	if absf(right[right.size() - 1].x - CX) < 0.5:
		left.pop_front()
	if absf(right[0].x - CX) < 0.5:
		left.pop_back()
	return right + left


func _fill(pts: PackedVector2Array, c: Color, outline := true, w := LINE) -> void:
	if pts.size() < 3:
		return
	if not Geometry2D.triangulate_polygon(pts).is_empty():
		draw_colored_polygon(pts, c)
	if outline:
		var loop := pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, _ol(c), w, true)


func _shape(a: Array, c: Color, outline := true, w := LINE) -> void:
	_fill(_smooth(_pv(a), true), c, outline, w)


func _poly(a: Array, c: Color, outline := true, w := LINE) -> void:
	_fill(_pv(a), c, outline, w)


func _ellipse_pts(c: Vector2, rx: float, ry: float, n := 36) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var t := TAU * i / n
		out.append(c + Vector2(cos(t) * rx, sin(t) * ry))
	return out


func _ellipse(c: Vector2, rx: float, ry: float, col: Color, outline := true, w := LINE) -> void:
	_fill(_ellipse_pts(c, rx, ry), col, outline, w)


func _line(a: Array, c: Color, w: float, smooth := true) -> void:
	var p := _smooth(_pv(a), false) if smooth and a.size() > 2 else _pv(a)
	draw_polyline(p, c, w, true)
	draw_circle(p[0], w * 0.5, c)
	draw_circle(p[p.size() - 1], w * 0.5, c)


func _limb(a: Array, w: float, c: Color) -> void:
	var p := _smooth(_pv(a), false)
	var oc := _ol(c)
	draw_polyline(p, oc, w + LINE * 2.0, true)
	draw_circle(p[0], w * 0.5 + LINE, oc)
	draw_circle(p[p.size() - 1], w * 0.5 + LINE, oc)
	draw_polyline(p, c, w, true)
	draw_circle(p[0], w * 0.5, c)
	draw_circle(p[p.size() - 1], w * 0.5, c)


func _side(p: Vector2, s: float) -> Vector2:
	# s = +1 keeps the point (viewer's right), -1 mirrors it to the left
	return p if s > 0 else Vector2(2.0 * CX - p.x, p.y)


func _sides(a: Array, s: float) -> Array:
	if s > 0:
		return a
	var out: Array = []
	for p in a:
		out.append(Vector2(2.0 * CX - p.x, p.y))
	return out


# ------------------------------------------------------------- draw

func _draw() -> void:
	if recipe.is_empty():
		return
	_skin = Color(str(recipe["skin"]))
	_hair = Color(str(recipe["hair_color"]))
	_eye = Color(str(recipe["eye_color"]))
	var sc := float(recipe["scale"])
	var t := Transform2D.IDENTITY
	# scale about the bottom centre so shorter characters sit lower in the canvas
	t = t.translated(Vector2(-CX, -H)).scaled(Vector2(sc, sc)).translated(Vector2(CX, H))
	t = t.scaled(Vector2(supersample, supersample))
	draw_set_transform_matrix(t)

	t = t.translated_local(Vector2(0, DROP))
	var head_t := t.translated_local(HEAD_PIVOT).scaled_local(Vector2(HEAD_SCALE, HEAD_SCALE)).translated_local(-HEAD_PIVOT)
	draw_set_transform_matrix(head_t)
	var o: Dictionary = recipe["outfits"].get(outfit, PortraitRecipe.DEFAULT_OUTFIT)
	_hair_back()
	draw_set_transform_matrix(t)
	_body(o)
	draw_set_transform_matrix(head_t)
	_head()
	_face()
	_bangs()
	_accessories(o)
	if str(recipe["hair_back"]) == "braid":
		_braid()


# ---- hair (behind the body)

func _hair_back() -> void:
	var style := str(recipe["hair_back"])
	var shade := _hair.darkened(0.12)
	match style:
		"ponytail":
			_shape([Vector2(640, 150), Vector2(740, 170), Vector2(812, 300), Vector2(822, 520), Vector2(790, 760), Vector2(752, 900),
				Vector2(742, 700), Vector2(716, 480), Vector2(680, 320)], shade)
		"twin-tails":
			for s in [1.0, -1.0]:
				_shape(_sides([Vector2(662, 210), Vector2(770, 235), Vector2(838, 400), Vector2(850, 690), Vector2(812, 930), Vector2(768, 1010),
					Vector2(776, 760), Vector2(752, 520), Vector2(708, 380), Vector2(664, 300)], s), shade)
		"bun":
			for s in [1.0, -1.0]:
				_ellipse(_side(Vector2(628, 112), s), 58, 54, shade)
	var right: Array
	match style:
		"long":
			right = [Vector2(512, 84), Vector2(606, 98), Vector2(676, 165), Vector2(704, 290), Vector2(724, 520), Vector2(744, 800),
				Vector2(736, 1040), Vector2(690, 1130), Vector2(600, 1110), Vector2(512, 1090)]
		"bob":
			right = [Vector2(512, 84), Vector2(606, 98), Vector2(676, 165), Vector2(704, 290), Vector2(712, 420), Vector2(688, 505),
				Vector2(612, 528), Vector2(512, 505)]
		"braid":
			right = [Vector2(512, 84), Vector2(606, 98), Vector2(676, 165), Vector2(702, 290), Vector2(700, 400), Vector2(668, 470),
				Vector2(600, 492), Vector2(512, 480)]
		_:
			right = [Vector2(512, 84), Vector2(606, 98), Vector2(674, 165), Vector2(698, 275), Vector2(692, 365), Vector2(662, 436),
				Vector2(612, 468), Vector2(512, 470)]
	_shape(_sym(right), _hair)


func _braid() -> void:
	var c := _hair
	var y := 470.0
	var x := 652.0
	var i := 0
	while y < 930.0:
		_ellipse(Vector2(x + (8.0 if i % 2 == 0 else -8.0), y), 30 - i * 0.6, 26, c.darkened(0.06 if i % 2 == 0 else 0.0))
		y += 34.0
		x += 1.5
		i += 1
	var rib := Color(str(recipe["outfits"].get(outfit, PortraitRecipe.DEFAULT_OUTFIT).get("ribbon", "#e0607a")))
	_bow(Vector2(x, y - 8.0), 26, rib)
	_shape([Vector2(x - 14, y), Vector2(x + 16, y), Vector2(x + 10, y + 60), Vector2(x - 4, y + 74)], c)


# ---- body & outfit

func _arm_paths() -> Dictionary:
	# returns {"r": [...], "l": [...], "hands": [[center, rx, ry], ...]}
	var r := [Vector2(650, 566), Vector2(676, 800), Vector2(664, 1030)]
	var l := _sides(r, -1.0)
	var hands := [[Vector2(662, 1072), 27.0, 36.0], [Vector2(362, 1072), 27.0, 36.0]]
	match pose:
		"greet":
			r = [Vector2(650, 566), Vector2(672, 790), Vector2(556, 902)]
			l = _sides(r, -1.0)
			hands = [[Vector2(528, 918), 36.0, 28.0], [Vector2(496, 926), 36.0, 28.0]]
		"serve":
			l = [Vector2(374, 566), Vector2(318, 770), Vector2(292, 650)]
			hands = [[Vector2(662, 1072), 27.0, 36.0], [Vector2(288, 618), 30.0, 26.0]]
		"point":
			r = [Vector2(650, 566), Vector2(700, 740), Vector2(800, 640)]
			hands = [[Vector2(826, 618), 30.0, 26.0], [Vector2(362, 1072), 27.0, 36.0]]
	return {"r": r, "l": l, "hands": hands}


func _body(o: Dictionary) -> void:
	var style := str(o.get("style", "classic"))
	var main := Color(str(o.get("main", "#2e2a3a")))
	var accent := Color(str(o.get("accent", "#ffffff")))
	var ribbon := Color(str(o.get("ribbon", "#e0607a")))
	var long_sleeve: bool = style in ["classic", "long", "cardigan", "hoodie", "sporty"]
	var is_maid: bool = style in ["classic", "frill", "long"]
	var arms := _arm_paths()

	if style == "hoodie":
		_shape([Vector2(420, 462), Vector2(604, 462), Vector2(660, 548), Vector2(364, 548)], main.darkened(0.08))

	# neck
	_poly([Vector2(476, 426), Vector2(548, 426), Vector2(556, 524), Vector2(468, 524)], _skin)
	_poly([Vector2(478, 440), Vector2(546, 440), Vector2(538, 478), Vector2(486, 478)], _skin.darkened(0.12), false)

	# skirt / lower body
	var skirt_col := main if is_maid or style in ["blouse", "sailor"] else accent
	if style == "blouse":
		skirt_col = main
	var skirt := _sym([Vector2(512, 820), Vector2(606, 826), Vector2(656, 960), Vector2(726, 1210), Vector2(786, 1560), Vector2(512, 1570)])
	_shape(skirt, skirt_col)
	if not is_maid:
		for x in [-150.0, -75.0, 0.0, 75.0, 150.0]:
			_line([Vector2(CX + x * 0.55, 900), Vector2(CX + x * 1.25, 1540)], _ol(skirt_col), 2.5, false)

	# torso
	var torso_col := main
	if style in ["cardigan", "blouse", "sailor"]:
		torso_col = Color(1, 1, 1) if style != "sailor" else Color(0.98, 0.98, 1.0)
	var torso := _sym([Vector2(512, 500), Vector2(552, 498), Vector2(612, 512), Vector2(654, 538), Vector2(664, 584), Vector2(642, 654),
		Vector2(618, 760), Vector2(608, 850), Vector2(630, 965), Vector2(512, 985)])
	_shape(torso, torso_col)

	if style == "cardigan":
		for s in [1.0, -1.0]:
			_shape(_sides([Vector2(556, 500), Vector2(612, 512), Vector2(654, 538), Vector2(664, 584), Vector2(642, 654), Vector2(618, 760),
				Vector2(608, 850), Vector2(632, 990), Vector2(560, 1000), Vector2(556, 760)], s), main)
		for y in [640.0, 720.0, 800.0]:
			draw_circle(Vector2(CX, y), 7, _ol(torso_col))
	elif style == "hoodie" or style == "sporty":
		_shape([Vector2(430, 860), Vector2(594, 860), Vector2(612, 965), Vector2(412, 965)], main.darkened(0.07))
		if style == "hoodie":
			_line([Vector2(486, 520), Vector2(482, 640)], accent, 6, false)
			_line([Vector2(538, 520), Vector2(542, 640)], accent, 6, false)
		else:
			_line([Vector2(CX, 520), Vector2(CX, 980)], accent, 8, false)
	elif style == "sailor":
		_poly([Vector2(440, 500), Vector2(584, 500), Vector2(620, 560), Vector2(512, 690), Vector2(404, 560)], main)
		_poly([Vector2(478, 500), Vector2(546, 500), Vector2(512, 640)], _skin, false)
		_bow(Vector2(CX, 680), 34, ribbon)
	elif style == "blouse":
		for y in [600.0, 670.0, 740.0]:
			draw_circle(Vector2(CX, y), 6, _ol(torso_col))

	if is_maid:
		_maid_apron(style, accent)

	# collar + ribbon
	if style != "hoodie" and style != "sailor" and style != "sporty":
		for s in [1.0, -1.0]:
			_poly(_sides([Vector2(512, 512), Vector2(556, 494), Vector2(574, 548), Vector2(520, 556)], s), Color(1, 1, 1))
		_bow(Vector2(CX, 548), 30, ribbon)

	# arms
	var sleeve := main if style != "blouse" and style != "sailor" and style != "frill" else torso_col
	if style == "frill":
		sleeve = main
	for key in ["r", "l"]:
		var path: Array = arms[key]
		if long_sleeve:
			_limb(path, 66, sleeve)
		else:
			_limb(path, 54, _skin)
			var mid: Vector2 = path[0].lerp(path[1], 0.42)
			_limb([path[0], path[0].lerp(mid, 0.5), mid], 64, sleeve)
		if is_maid or style == "blouse":
			# puff sleeve
			_ellipse(path[0] + Vector2(6.0 if key == "r" else -6.0, 6), 54, 48, sleeve)
		if long_sleeve and is_maid:
			var wrist: Vector2 = path[2]
			var dir: Vector2 = (path[2] - path[1]).normalized()
			_limb([wrist - dir * 34.0, wrist - dir * 17.0, wrist], 64, accent)
	for h in arms["hands"]:
		_ellipse(h[0], h[1], h[2], _skin)

	if pose == "serve":
		_tray()


func _maid_apron(style: String, white: Color) -> void:
	var frill := style != "long"
	# skirt apron with frills
	if frill:
		for i in 21:
			var t := i / 20.0
			for s in [1.0, -1.0]:
				_ellipse(_side(Vector2(lerpf(598, 704, t), lerpf(866, 1548, t)), s), 19, 19, white, true, 3.0)
	_poly([Vector2(430, 850), Vector2(594, 850), Vector2(700, 1560), Vector2(324, 1560)], white)
	# bib
	if frill:
		for i in 9:
			var t := i / 8.0
			for s in [1.0, -1.0]:
				_ellipse(_side(Vector2(lerpf(580, 596, t), lerpf(580, 838, t)), s), 16, 17, white, true, 3.0)
	_poly([Vector2(446, 566), Vector2(578, 566), Vector2(596, 852), Vector2(428, 852)], white)
	# straps
	for s in [1.0, -1.0]:
		_poly(_sides([Vector2(560, 566), Vector2(590, 566), Vector2(604, 512), Vector2(578, 504)], s), white)
	# waist band
	_poly([Vector2(410, 836), Vector2(614, 836), Vector2(618, 874), Vector2(406, 874)], white)
	# hem frill line
	_line([Vector2(360, 1420), Vector2(664, 1420)], _ol(white), 2.5, false)


func _bow(c: Vector2, size: float, col: Color) -> void:
	for s in [1.0, -1.0]:
		_shape([c, c + Vector2(s * size * 1.5, -size * 0.8), c + Vector2(s * size * 1.7, 0), c + Vector2(s * size * 1.5, size * 0.8)], col, true, 4.0)
	_ellipse(c, size * 0.42, size * 0.46, col.lightened(0.12), true, 4.0)


func _tray() -> void:
	var c := Vector2(262, 596)
	_ellipse(c, 132, 26, Color(0.82, 0.84, 0.9))
	_ellipse(c + Vector2(0, -6), 118, 19, Color(0.93, 0.94, 0.98), false)
	# cup + saucer
	_ellipse(c + Vector2(-30, -12), 44, 10, Color(1, 1, 1), true, 3.0)
	_poly([c + Vector2(-58, -66), c + Vector2(-2, -66), c + Vector2(-10, -16), c + Vector2(-50, -16)], Color(1, 1, 1), true, 4.0)
	_ellipse(c + Vector2(-30, -66), 28, 7, Color(0.55, 0.33, 0.22), true, 3.0)
	# little cake
	_poly([c + Vector2(34, -50), c + Vector2(96, -50), c + Vector2(96, -14), c + Vector2(34, -14)], Color(1.0, 0.95, 0.85), true, 4.0)
	_poly([c + Vector2(34, -56), c + Vector2(96, -56), c + Vector2(96, -44), c + Vector2(34, -44)], Color(1.0, 0.75, 0.8), true, 3.0)
	draw_circle(c + Vector2(65, -64), 10, Color(0.9, 0.2, 0.3))


# ---- head

func _head() -> void:
	for s in [1.0, -1.0]:
		_ellipse(_side(Vector2(638, 338), s), 17, 27, _skin)
	_shape([Vector2(392, 250), Vector2(385, 322), Vector2(402, 388), Vector2(448, 432), Vector2(512, 453), Vector2(576, 432), Vector2(622, 388),
		Vector2(639, 322), Vector2(632, 250), Vector2(590, 185), Vector2(512, 165), Vector2(434, 185)], _skin)


func _expr() -> Dictionary:
	return PortraitRecipe.EXPRESSIONS.get(expression, PortraitRecipe.EXPRESSIONS["neutral"])


func _face() -> void:
	var ex := _expr()
	var shape: Dictionary = PortraitRecipe.EYE_SHAPES.get(str(recipe["eye_shape"]), PortraitRecipe.EYE_SHAPES["round"])
	# blush
	var blush := float(ex["blush"])
	for s in [1.0, -1.0]:
		_ellipse(_side(Vector2(598, 384), s), 34, 17, Color(1.0, 0.45, 0.5, 0.18 + 0.3 * blush), false)
		if blush > 0.8:
			for k in 3:
				var b := _side(Vector2(580 + k * 16, 376), s)
				draw_line(b + Vector2(5, -9), b + Vector2(-5, 9), Color(0.95, 0.35, 0.45, 0.8), 3.0, true)
	# eyes + brows
	for s in [1.0, -1.0]:
		_eye_at(Vector2(CX + s * 66.0, 330), s, ex, shape)
	# nose
	draw_line(Vector2(CX - 2, 378), Vector2(CX + 3, 384), _ol(_skin).lightened(0.25), 3.0, true)
	_mouth(Vector2(CX, 412), str(ex["mouth"]))
	# extras
	for extra in ex.get("extras", []):
		match extra:
			"sweat":
				_shape([Vector2(642, 232), Vector2(656, 262), Vector2(642, 278), Vector2(628, 262)], Color(0.7, 0.88, 1.0), true, 3.0)
			"tears":
				for s in [1.0, -1.0]:
					_ellipse(_side(Vector2(604, 352), s), 9, 12, Color(0.72, 0.9, 1.0, 0.9), true, 2.5)
			"anger":
				var c := Vector2(636, 214)
				for a in 4:
					var d := Vector2.RIGHT.rotated(TAU * a / 4.0 + 0.4)
					_line([c + d * 8.0, c + d * 22.0 + d.orthogonal() * 7.0], Color(0.9, 0.2, 0.25), 5.0, false)


func _eye_at(c: Vector2, s: float, ex: Dictionary, shape: Dictionary) -> void:
	var open := float(ex["open"])
	var rx := float(shape["rx"])
	var ry := float(shape["ry"]) * minf(open, 1.15)
	var lash := _ol(_hair).lerp(Color(0.2, 0.14, 0.18), 0.6)
	var tilt := float(shape["tilt"])
	var mode := str(ex.get("mode", "open"))
	# brows
	var by := c.y - float(shape["ry"]) - 20.0
	var bcol := _hair.darkened(0.4)
	_line([Vector2(c.x - s * rx * 0.7, by + float(ex["brow_in"])), Vector2(c.x + s * rx * 0.85, by + float(ex["brow_out"]))], bcol, 5.0, false)
	if mode == "closed_happy":
		_line([Vector2(c.x - s * rx * 0.9, c.y + 10), Vector2(c.x - s * rx * 0.35, c.y - 14), Vector2(c.x + s * rx * 0.35, c.y - 14), Vector2(c.x + s * rx, c.y + 10)], lash, 7.5)
		return
	if mode == "closed_down":
		_line([Vector2(c.x - s * rx * 0.9, c.y), Vector2(c.x - s * rx * 0.35, c.y + 14), Vector2(c.x + s * rx * 0.35, c.y + 14), Vector2(c.x + s * rx, c.y + tilt * 0.3)], lash, 7.5)
		return
	# sclera
	_ellipse(c, rx, ry, Color(1, 0.99, 0.99), false)
	# iris
	var isc := float(ex.get("iris", 1.0))
	var ic := c + Vector2(float(ex.get("look_x", 0.0)), 2.0 + float(ex.get("look_y", 0.0)))
	var irx := rx * 0.76 * isc
	var iry := ry * 0.97 * isc
	_ellipse(ic, irx, iry, _eye.darkened(0.3), false)
	_ellipse(ic + Vector2(0, iry * 0.32), irx * 0.82, iry * 0.62, _eye.lightened(0.25), false)
	_ellipse(ic + Vector2(0, -iry * 0.05), irx * 0.4, iry * 0.48, _eye.darkened(0.72), false)
	draw_circle(ic + Vector2(-s * irx * 0.36, -iry * 0.48), rx * 0.26 * isc, Color(1, 1, 1))
	draw_circle(ic + Vector2(s * irx * 0.38, iry * 0.42), rx * 0.12 * isc, Color(1, 1, 1, 0.9))
	# upper lid + lashes
	_line([Vector2(c.x - s * rx * 0.92, c.y - ry * 0.5), Vector2(c.x - s * rx * 0.4, c.y - ry + 1.0), Vector2(c.x + s * rx * 0.34, c.y - ry),
		Vector2(c.x + s * rx * 0.92, c.y - ry * 0.55), Vector2(c.x + s * rx * 1.26, c.y - ry * 0.12 + tilt)], lash, 9.0)
	_line([Vector2(c.x - s * rx * 0.45, c.y + ry + 1.0), Vector2(c.x + s * rx * 0.55, c.y + ry + 1.0)], lash.lightened(0.35), 2.5, false)


func _mouth(c: Vector2, kind: String) -> void:
	var col := Color(0.62, 0.3, 0.32)
	match kind:
		"smile":
			_line([c + Vector2(-20, -3), c + Vector2(0, 8), c + Vector2(20, -3)], col, 4.0)
		"laugh":
			_shape([c + Vector2(-27, -6), c + Vector2(27, -6), c + Vector2(19, 15), c + Vector2(0, 24), c + Vector2(-19, 15)], Color(0.8, 0.32, 0.38), true, 3.5)
			_ellipse(c + Vector2(0, 14), 11, 6, Color(1.0, 0.6, 0.62), false)
		"o":
			_ellipse(c + Vector2(0, 2), 9, 12, Color(0.78, 0.34, 0.4), true, 3.0)
		"wavy":
			_line([c + Vector2(-17, 2), c + Vector2(-8, -3), c + Vector2(0, 2), c + Vector2(8, -3), c + Vector2(17, 2)], col, 4.0)
		"sad":
			_line([c + Vector2(-16, 7), c + Vector2(0, -2), c + Vector2(16, 7)], col, 4.0)
		"angry":
			_line([c + Vector2(-15, 6), c + Vector2(-5, 0), c + Vector2(5, 0), c + Vector2(15, 6)], col, 4.5)
		"tired":
			_ellipse(c + Vector2(0, 3), 8, 5, Color(0.78, 0.4, 0.44), true, 3.0)
		"flat":
			_line([c + Vector2(-12, 2), c + Vector2(12, 2)], col, 4.0, false)
		_:
			_line([c + Vector2(-12, 0), c + Vector2(0, 4), c + Vector2(12, 0)], col, 4.0)


func _bangs() -> void:
	var style := str(recipe["bangs"])
	var top := _smooth(_pv([Vector2(384, 300), Vector2(388, 205), Vector2(436, 122), Vector2(512, 92), Vector2(588, 122), Vector2(636, 205), Vector2(640, 300)]), false)
	var bottom: Array
	match style:
		"parted":
			bottom = [Vector2(622, 338), Vector2(600, 300), Vector2(574, 250), Vector2(544, 196), Vector2(512, 158), Vector2(480, 196),
				Vector2(450, 250), Vector2(424, 300), Vector2(402, 338)]
		"side":
			bottom = [Vector2(624, 334), Vector2(608, 296), Vector2(584, 318), Vector2(560, 282), Vector2(524, 306), Vector2(492, 270),
				Vector2(452, 286), Vector2(424, 240), Vector2(404, 330)]
		"wispy":
			bottom = [Vector2(622, 322), Vector2(604, 286), Vector2(582, 306), Vector2(560, 280), Vector2(536, 300), Vector2(512, 314),
				Vector2(488, 300), Vector2(464, 280), Vector2(442, 306), Vector2(420, 286), Vector2(402, 322)]
		_:
			bottom = [Vector2(622, 318), Vector2(606, 292), Vector2(590, 296), Vector2(574, 276), Vector2(552, 296), Vector2(532, 276),
				Vector2(512, 296), Vector2(492, 276), Vector2(472, 296), Vector2(450, 276), Vector2(434, 296), Vector2(418, 292), Vector2(402, 318)]
	var pts := top.duplicate()
	for p in bottom:
		pts.append(p)
	_fill(pts, _hair)
	# side locks
	if bool(recipe.get("side_locks", true)):
		for s in [1.0, -1.0]:
			_shape(_sides([Vector2(616, 236), Vector2(648, 250), Vector2(656, 380), Vector2(644, 470), Vector2(630, 500), Vector2(624, 380)], s), _hair)
	# shine + strands
	_line([Vector2(432, 158), Vector2(470, 134), Vector2(512, 126), Vector2(554, 134), Vector2(592, 158)], Color(1, 1, 1, 0.4), 12.0)
	for x in [-58.0, -20.0, 22.0, 60.0]:
		_line([Vector2(CX + x * 0.4, 102), Vector2(CX + x * (0.75 if style == "parted" else 1.0), 150.0 if style == "parted" else 250.0)], _hair.darkened(0.22), 2.5, false)
	if bool(recipe.get("ahoge", false)):
		_shape([Vector2(506, 100), Vector2(520, 40), Vector2(566, 22), Vector2(548, 56), Vector2(530, 100)], _hair)


func _accessories(o: Dictionary) -> void:
	var acc: Array = recipe.get("accessories", [])
	var ribbon := Color(str(o.get("ribbon", "#e0607a")))
	var style := str(recipe["hair_back"])
	if style == "twin-tails":
		for s in [1.0, -1.0]:
			_bow(_side(Vector2(676, 232), s), 22, ribbon)
	elif style == "ponytail":
		_bow(Vector2(664, 180), 22, ribbon)
	var is_maid: bool = str(o.get("style", "")) in ["classic", "frill", "long"]
	if acc.has("headdress") and is_maid:
		for i in 9:
			var t := i / 8.0
			var a := lerpf(-2.35, -0.79, t)
			_ellipse(Vector2(CX + cos(a) * 150.0, 250 + sin(a) * 168.0), 22, 20, Color(1, 1, 1), true, 3.0)
		_line([Vector2(404, 136), Vector2(456, 104), Vector2(512, 92), Vector2(568, 104), Vector2(620, 136)], Color(1, 1, 1), 16.0)
		_line([Vector2(404, 144), Vector2(456, 112), Vector2(512, 100), Vector2(568, 112), Vector2(620, 144)], _ol(Color(1, 1, 1)), 2.5)
	if acc.has("ribbon"):
		_bow(Vector2(606, 150), 28, ribbon)
	if acc.has("hairclip"):
		_line([Vector2(586, 236), Vector2(618, 250)], ribbon, 9.0, false)
		_line([Vector2(588, 252), Vector2(616, 264)], ribbon.lightened(0.3), 7.0, false)
	if acc.has("flower"):
		var c := Vector2(416, 176)
		for i in 5:
			_ellipse(c + Vector2.RIGHT.rotated(TAU * i / 5.0) * 17.0, 13, 13, Color(1.0, 0.86, 0.9), true, 2.5)
		draw_circle(c, 9, Color(1.0, 0.8, 0.3))
	if acc.has("glasses"):
		var g := Color(0.3, 0.25, 0.3)
		for s in [1.0, -1.0]:
			var pts := _ellipse_pts(Vector2(CX + s * 66.0, 334), 58, 50)
			pts.append(pts[0])
			draw_polyline(pts, g, 4.5, true)
			draw_line(Vector2(CX + s * 124.0, 328), Vector2(CX + s * 132.0, 320), g, 4.5, true)
		draw_line(Vector2(CX - 9, 328), Vector2(CX + 9, 328), g, 4.5, true)
