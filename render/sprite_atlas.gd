extends RefCounted

## Builds the one creature atlas at startup: eight 16x16 frames, plain greyscale
## bodies so the instanced colour carries the individual's tint. Frames are
## action states, not behaviours: idle, two walk frames, eat, drink, rest, flee.
## Animation is action, rendered. There is no shelter-building frame because
## there is no shelter-building action.

const FRAME_W := 16
const FRAME_COUNT := 8

const BODY := Color(0.93, 0.92, 0.89, 1.0)
const OUTLINE := Color(0.14, 0.13, 0.12, 1.0)
const EYE := Color(0.08, 0.07, 0.06, 1.0)
const LEG := Color(0.62, 0.60, 0.56, 1.0)


static func build() -> ImageTexture:
	var img := Image.create(FRAME_W * FRAME_COUNT, FRAME_W, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	for frame in FRAME_COUNT:
		_draw_frame(img, frame * FRAME_W, frame)
	return ImageTexture.create_from_image(img)


static func _draw_frame(img: Image, ox: int, frame: int) -> void:
	var body_x := 8.0
	var body_y := 9.2
	var body_rx := 4.4
	var body_ry := 3.7
	var legs := [5.0, 10.0]
	var frame_legs := 0

	match frame:
		3:  # eat: head down, body leaning
			body_y = 10.2
		4:  # drink: head down at the water line
			body_y = 10.4
		5:  # rest: flattened
			body_y = 10.9
			body_rx = 5.3
			body_ry = 2.4
		6:  # flee: low runner, legs stretched
			body_y = 10.1
			body_rx = 5.0
			body_ry = 2.9
			frame_legs = 2
		1:  # walk frame A
			frame_legs = 1
		2:  # walk frame B
			frame_legs = -1
		_:
			pass

	# Feet first so the body overlaps them.
	if frame != 5:
		var left_y := body_y + body_ry - 1.0 + float(frame_legs) * 0.6
		var right_y := body_y + body_ry - 1.0 - float(frame_legs) * 0.6
		_rect(img, ox + int(legs[0]) - 1, int(left_y), 2, 3, LEG)
		_rect(img, ox + int(legs[1]) - 1, int(right_y), 2, 3, LEG)

	_ellipse(img, ox, body_x, body_y + 0.8, body_rx + 0.8, body_ry + 0.8, OUTLINE)
	_ellipse(img, ox, body_x, body_y, body_rx, body_ry, BODY)

	if frame == 5:
		# Closed eye: a single line, the universal read of rest.
		_rect(img, ox + 5, int(body_y), 2, 1, EYE)
		_rect(img, ox + 9, int(body_y), 2, 1, EYE)
		return

	var eye_y := int(body_y - 1.2)
	_put(img, ox + 6, eye_y, EYE)
	_put(img, ox + 9, eye_y, EYE)
	if frame == 3 or frame == 4:
		# Mouth pixel, lower on the body while feeding.
		_rect(img, ox + 7, int(body_y + 2.0), 2, 1, OUTLINE)


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_put(img, xx, yy, c)


static func _ellipse(img: Image, ox: int, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	var x0 := int(floor(cx - rx))
	var x1 := int(ceil(cx + rx))
	var y0 := int(floor(cy - ry))
	var y1 := int(ceil(cy + ry))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var nx := (float(x) + 0.5 - cx) / maxf(rx, 0.001)
			var ny := (float(y) + 0.5 - cy) / maxf(ry, 0.001)
			if nx * nx + ny * ny <= 1.0:
				_put(img, ox + x, y, c)


static func _put(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, c)
