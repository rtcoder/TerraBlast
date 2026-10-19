extends Control
signal cell_selected(position: Vector3i)
const COLORS := [Color("101b28"),Color("a5794d"),Color("8796a9"),Color("bed5df")]
var world: RefCounted
var definition: RefCounted
var selection := {"kind":"boxes","index":-1}
var layer := 0
var zoom := 1.0
var stale := false
func _ready() -> void:
	custom_minimum_size = Vector2(280,260)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
func present(candidate: RefCounted, validation: Dictionary, selected: Dictionary) -> void:
	definition = candidate.copy()
	selection = selected.duplicate()
	stale = not validation.ok
	if validation.ok: world = validation.arena.world
	layer = clampi(layer,0,definition.size.y-1)
	queue_redraw()
func set_layer(value: int) -> void:
	layer = clampi(value,0,definition.size.y-1) if definition != null else 0
	queue_redraw()
func set_zoom(value: float) -> void:
	zoom = clampf(value,0.25,4.0)
	queue_redraw()
func fit() -> void:
	zoom = 1.0
	queue_redraw()
func cell_size() -> float:
	if definition == null: return 1.0
	return maxf(0.1,minf((size.x-24)/definition.size.x,(size.y-40)/definition.size.z)*zoom)
func map_rect() -> Rect2:
	if definition == null: return Rect2()
	var extent := Vector2(definition.size.x,definition.size.z)*cell_size()
	return Rect2((size-extent)*0.5+Vector2(0,8),extent)
func cell_at_point(point: Vector2) -> Variant:
	var bounds := map_rect()
	if definition == null or not bounds.has_point(point): return null
	var relative := (point-bounds.position)/cell_size()
	return Vector3i(floori(relative.x),layer,floori(relative.y))
func material_at(position: Vector3i) -> int: return world.get_material_id(position) if world != null else 0
func status_text() -> String: return "Stale preview — fix validation errors" if stale else "XZ slice • Y=%d • click to fill position" % layer
func spawn_markers() -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	if definition == null: return markers
	for index in definition.spawns.size():
		var spawn: Dictionary = definition.spawns[index]
		markers.append({"position":Vector3i(spawn.position[0],spawn.position[1],spawn.position[2]),"color":Color("55b8ff") if spawn.team == 1 else Color("ff8b68"),"slot":spawn.get("slot",0),"yaw":float(spawn.get("yaw",0)),"selected":selection.kind == "spawns" and selection.index == index})
	return markers
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var position: Variant = cell_at_point(event.position)
		if position != null: cell_selected.emit(position)
		accept_event()
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("08111d"))
	if definition == null: return
	var bounds := map_rect()
	var step := cell_size()
	if world != null:
		for z in definition.size.z:
			for x in definition.size.x:
				var point := bounds.position+Vector2(x,z)*step
				if Rect2(Vector2.ZERO,size).has_point(point): draw_rect(Rect2(point,Vector2.ONE*step),COLORS[clampi(material_at(Vector3i(x,layer,z)),0,3)])
	draw_rect(bounds,Color("4a718c"),false,1)
	if selection.kind in ["boxes","carves"] and selection.index >= 0 and selection.index < definition.get(selection.kind).size():
		var entry: Dictionary = definition.get(selection.kind)[selection.index]
		var center := bounds.position+Vector2(entry.position[0],entry.position[2])*step
		if selection.kind == "boxes": draw_rect(Rect2(center,Vector2(entry.size[0],entry.size[2])*step),Color("ffe077"),false,2)
		else: draw_arc(center+Vector2.ONE*step*0.5,float(entry.get("radius",1))*step,0,TAU,48,Color("ffe077"),2,true)
	for marker in spawn_markers():
		var center := bounds.position+Vector2(marker.position.x+0.5,marker.position.z+0.5)*step
		var angle := deg_to_rad(marker.yaw)
		draw_circle(center,5 if marker.selected else 3,marker.color)
		draw_line(center,center+Vector2(-sin(angle),-cos(angle))*13,marker.color,2)
		draw_string(ThemeDB.fallback_font,center+Vector2(5,-5),str(marker.slot),HORIZONTAL_ALIGNMENT_LEFT,-1,12,marker.color)
	draw_string(ThemeDB.fallback_font,Vector2(10,18),status_text(),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("ffca7a") if stale else Color("a8bfd0"))
