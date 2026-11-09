class_name PortraitTextures
extends RefCounted
## Safe texture loading for art assets.
##
## Imported resources are loaded through ResourceLoader. Freshly generated
## PNGs that the editor has not imported yet (common in an AI-art workflow)
## are read with Image.load_from_file in development builds. Any failure
## returns null instead of raising, so a single bad file can't crash the game.

static var _cache: Dictionary = {}
static var _warned: Dictionary = {}
static var _silhouette: Texture2D = null


static func load_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		var res = ResourceLoader.load(path)
		if res is Texture2D:
			tex = res
	if tex == null and FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(path) == OK and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		_warn_once(path, "PortraitTextures: could not load '%s', using fallback" % path)
	_cache[path] = tex
	return tex


static func clear_cache() -> void:
	_cache = {}


static func _warn_once(key: String, msg: String) -> void:
	if not _warned.has(key):
		_warned[key] = true
		push_warning(msg)


## Procedural grey silhouette used when a character has no usable image.
## It is intentionally plain and is always shown with a "MISSING" label in
## debug builds, so it can never be mistaken for finished art.
static func silhouette(width := 256, height := 384) -> Texture2D:
	if _silhouette != null:
		return _silhouette
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := Color(0.42, 0.42, 0.48, 0.85)
	var cx := width * 0.5
	# head
	var hr := width * 0.17
	var hy := height * 0.2
	# shoulders / body
	for y in height:
		for x in width:
			var dx := x - cx
			var dy := y - hy
			var inside := dx * dx + dy * dy <= hr * hr
			if not inside and y > height * 0.33:
				var t := clampf((y - height * 0.33) / (height * 0.2), 0.0, 1.0)
				var half := lerpf(width * 0.12, width * 0.42, t)
				inside = absf(dx) <= half
			elif not inside and y > hy + hr * 0.6 and y <= height * 0.33:
				inside = absf(dx) <= width * 0.07  # neck
			if inside:
				img.set_pixel(x, y, col)
	_silhouette = ImageTexture.create_from_image(img)
	return _silhouette
