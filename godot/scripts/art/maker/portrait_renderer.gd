class_name PortraitRenderer
extends Node
## Renders PortraitPainter drawings to Images (needs a real renderer, i.e.
## not --headless). Add it to the scene tree, then `await render(...)`.

const SUPERSAMPLE := 2.0


## Full portrait (pose / outfit / expression) on the spec canvas, transparent background.
func render(recipe: Dictionary, pose: String, outfit: String, expression: String) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(int(PortraitPainter.W * SUPERSAMPLE), int(PortraitPainter.H * SUPERSAMPLE))
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var painter := PortraitPainter.new()
	painter.supersample = SUPERSAMPLE
	vp.add_child(painter)
	add_child(vp)
	painter.configure(recipe, pose, outfit, expression)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(int(PortraitPainter.W), int(PortraitPainter.H), Image.INTERPOLATE_LANCZOS)
	_unpremultiply(img)
	return img


## Face patch: the same drawing, cut to the face region (rest transparent).
func render_face(recipe: Dictionary, pose: String, outfit: String, expression: String) -> Image:
	var full := await render(recipe, pose, outfit, expression)
	var out := Image.create(full.get_width(), full.get_height(), false, Image.FORMAT_RGBA8)
	var rect := PortraitRecipe.face_rect(recipe).intersection(Rect2i(0, 0, full.get_width(), full.get_height()))
	out.blit_rect(full, rect, rect.position)
	return out


## Edges drawn onto a transparent viewport come out darkened (colour already
## multiplied by alpha); restore straight alpha so PNGs have clean edges.
static func _unpremultiply(img: Image) -> void:
	var data := img.get_data()
	var n := data.size()
	var i := 3
	var changed := false
	while i < n:
		var a := data[i]
		if a > 0 and a < 255:
			var f := 255.0 / a
			data[i - 3] = mini(255, int(data[i - 3] * f))
			data[i - 2] = mini(255, int(data[i - 2] * f))
			data[i - 1] = mini(255, int(data[i - 1] * f))
			changed = true
		i += 4
	if changed:
		img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
