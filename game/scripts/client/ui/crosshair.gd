extends Control
var radius := 16.0
var contrast := false
func _ready(): mouse_filter = MOUSE_FILTER_IGNORE
func configure(value: float, high_contrast: bool) -> void:
	radius = clampf(value,8,32)
	contrast = high_contrast
	queue_redraw()
func _draw():
	if contrast:
		draw_line(Vector2(-radius,0),Vector2(radius,0),Color.BLACK,6)
		draw_line(Vector2(0,-radius),Vector2(0,radius),Color.BLACK,6)
	draw_line(Vector2(-radius,0),Vector2(radius,0),Color.WHITE,2)
	draw_line(Vector2(0,-radius),Vector2(0,radius),Color.WHITE,2)
