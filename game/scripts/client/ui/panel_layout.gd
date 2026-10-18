extends RefCounted
static func fit(panel: Control, scroll: ScrollContainer, viewport: Vector2, margin := 30.0) -> void:
	scroll.follow_focus = true
	var available := Vector2(maxf(240,viewport.x-margin*2),maxf(140,viewport.y-margin*2-28))
	panel.position = Vector2(margin,margin)
	scroll.custom_minimum_size.x = minf(440,available.x-28)
	var content := scroll.get_child(0) as Control
	scroll.custom_minimum_size.y = minf(content.get_combined_minimum_size().y,available.y)
	panel.custom_minimum_size.x = minf(460,available.x)
	panel.size = Vector2.ZERO
