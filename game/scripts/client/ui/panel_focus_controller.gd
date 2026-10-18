extends RefCounted
var previous: WeakRef
func open(panel: Control, initial: Control = null) -> void:
	var focused := panel.get_viewport().gui_get_focus_owner()
	previous = weakref(focused) if focused != null else null
	var controls: Array[Control] = []
	_collect(panel,controls)
	for index in controls.size():
		controls[index].focus_next = controls[index].get_path_to(controls[(index+1)%controls.size()])
		controls[index].focus_previous = controls[index].get_path_to(controls[(index-1+controls.size())%controls.size()])
	if initial != null: initial.grab_focus()
	elif not controls.is_empty(): controls[0].grab_focus()
func close(_panel: Control) -> void:
	if previous != null:
		var control = previous.get_ref()
		if is_instance_valid(control) and control.is_visible_in_tree(): control.grab_focus()
	previous = null
func _collect(node: Node, result: Array[Control]) -> void:
	if node is Control and not node.is_visible_in_tree(): return
	if node is Control and node.focus_mode == Control.FOCUS_ALL and not (node is BaseButton and node.disabled): result.append(node)
	for child in node.get_children(): _collect(child,result)
