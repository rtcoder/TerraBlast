extends SceneTree
const Desktop = preload("res://scripts/client/input/desktop_input.gd")
class TemporaryBindings:
	extends "res://scripts/client/input/input_bindings.gd"
	var path := "/tmp/tb-panel-bindings-%s.cfg" % OS.get_process_id()
	func save_settings(_path: String = DEFAULT_PATH) -> Error:
		return super.save_settings(path if _path == DEFAULT_PATH else _path)
class TemporaryPreferences:
	extends "res://scripts/client/settings/client_settings.gd"
	var path := "/tmp/tb-panel-preferences-%s.cfg" % OS.get_process_id()
	func save_to(_path: String = PATH) -> Error:
		return super.save_to(path)
class FakeScene:
	extends Node
	var dispatch_input := false
	func _input(input: InputEvent):
		if dispatch_input:
			load("res://scripts/client/input/desktop_input.gd").handle(self, input)
	var bindings: RefCounted
	var settings_panel: Control
	var scoreboard := Control.new()
	var menu_open := false
	var pause_count := 0
	var jump_count := 0
	var restart_count := 0
	var weapon := 0
	var help_count := 0
	func _toggle_help(): help_count += 1
	func _toggle_pause(): pause_count += 1
	func _try_jump_active_player(): jump_count += 1
	func restart_match(): restart_count += 1
	func _select_weapon(value): weapon = value
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func event(key: int, physical: int = 0) -> InputEventKey:
	var result := InputEventKey.new()
	result.keycode = key
	result.physical_keycode = physical
	result.pressed = true
	return result
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var script = load("res://scripts/client/input/input_bindings.gd")
	check(script != null, "Input bindings model exists")
	if script == null:
		quit(1)
		return
	var bindings = TemporaryBindings.new()
	check(bindings.key_for("move_left") == KEY_A and bindings.key_for("pause") == KEY_P, "Legacy defaults")
	check(bindings.rebind("jump", KEY_J).ok, "Rebind jump")
	check(bindings.matches("jump", event(KEY_J)), "Logical fallback")
	check(bindings.matches("jump", event(KEY_SPACE, KEY_J)), "Physical key precedence")
	check(not bindings.rebind("jump", KEY_W).ok and bindings.key_for("jump") == KEY_J, "Conflict atomic")
	for key in [KEY_ESCAPE, KEY_F1, KEY_F12, KEY_BRACKETLEFT, KEY_BRACKETRIGHT, KEY_LEFT, KEY_UP, KEY_DOWN, KEY_RIGHT, -1, 0, 999999999]:
		check(not bindings.rebind("jump", key).ok, "Reserved or unsafe key rejected: %s" % key)
	check(not bindings.rebind("unknown", KEY_J).ok, "Unknown action rejected")
	var path := "/tmp/terrablast-bindings-%s.cfg" % OS.get_process_id()
	check(bindings.save_settings(path) == OK, "Save bindings")
	var restored = script.new()
	check(restored.load_settings(path) == OK and restored.key_for("jump") == KEY_J, "Persistence roundtrip")
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("bindings", "move_left", KEY_J)
	cfg.save(path)
	check(restored.load_settings(path) != OK and restored.key_for("move_left") == KEY_A, "Invalid file rejected atomically")
	bindings.save_settings(path)
	cfg.load(path)
	cfg.set_value("meta", "version", 1.0)
	cfg.save(path)
	check(restored.load_settings(path) != OK, "Version must be integer")
	bindings.save_settings(path)
	cfg.load(path)
	cfg.set_value("meta", "unexpected", 123)
	cfg.save(path)
	check(restored.load_settings(path) != OK, "Unexpected metadata rejected")
	bindings.save_settings(path)
	cfg.load(path)
	cfg.erase_section_key("bindings", "jump")
	cfg.save(path)
	check(restored.load_settings(path) != OK, "Missing action rejected")
	check(bindings.save_settings("/tmp/nonexistent-tb-folder-%s/bindings.cfg" % OS.get_process_id()) != OK, "Save failure surfaced")
	DirAccess.remove_absolute(path)
	var panel_script = load("res://scripts/client/ui/settings_panel.gd")
	var preferences := TemporaryPreferences.new()
	var panel = panel_script.new()
	root.add_child(panel)
	panel.setup(preferences, bindings)
	panel.show()
	panel.begin_capture("jump")
	var release := event(KEY_K)
	release.pressed = false
	check(panel.capture_event(release, false) and panel.is_capturing(), "Release consumed without binding")
	var echo := event(KEY_K)
	echo.echo = true
	check(panel.capture_event(echo, false) and panel.is_capturing(), "Echo ignored")
	check(panel.capture_event(event(KEY_ESCAPE), false) and not panel.is_capturing(), "Escape cancels capture")
	panel.begin_capture("jump")
	check(panel.capture_event(event(KEY_K), false) and bindings.key_for("jump") == KEY_K, "Capture remaps key")
	panel.begin_capture("jump")
	panel.capture_event(event(KEY_W), false)
	check(panel.is_capturing() and bindings.key_for("jump") == KEY_K, "Conflict keeps capture and binding")
	panel.cancel_capture()
	panel.begin_capture("jump")
	panel.hide()
	check(not panel.is_capturing(), "Closing cancels capture")
	panel.show()
	panel.begin_capture("jump")
	panel.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not panel.is_capturing(), "Focus loss cancels capture")
	var scene := FakeScene.new()
	root.add_child(scene)
	scene.bindings = bindings
	scene.settings_panel = panel
	bindings.rebind("jump", KEY_J)
	bindings.rebind("pause", KEY_O)
	bindings.rebind("scoreboard", KEY_B)
	Desktop.handle(scene, event(KEY_J))
	check(scene.jump_count == 1, "Adapter uses remapped jump")
	Desktop.handle(scene, event(KEY_O))
	check(scene.pause_count == 1, "Adapter uses remapped pause")
	Desktop.handle(scene, event(KEY_B))
	check(scene.scoreboard.visible, "Remapped scoreboard opens")
	scene.menu_open = true
	var up := event(KEY_B)
	up.pressed = false
	Desktop.handle(scene, up)
	check(not scene.scoreboard.visible, "Scoreboard releases while menu open")
	panel.begin_capture("jump")
	Desktop.handle(scene, event(KEY_F2))
	check(panel.is_capturing(), "Capture intercepts reserved global shortcut")
	Desktop.handle(scene, event(KEY_O))
	check(scene.pause_count == 1, "Capture blocks pause")
	Desktop.handle(scene, event(KEY_ESCAPE))
	var editor := LineEdit.new()
	scene.add_child(editor)
	editor.grab_focus()
	check(root.gui_get_focus_owner() == editor, "Regression uses real focused LineEdit")
	scene.menu_open = false
	Desktop.handle(scene, event(KEY_O))
	Desktop.handle(scene, event(KEY_B))
	Desktop.handle(scene, event(KEY_J))
	check(scene.pause_count == 1 and not scene.scoreboard.visible and scene.jump_count == 1, "Typing does not invoke remapped gameplay shortcuts")
	bindings.rebind("pause", KEY_P)
	bindings.rebind("scoreboard", KEY_TAB)
	Desktop.handle(scene, event(KEY_P))
	Desktop.handle(scene, event(KEY_TAB))
	check(scene.pause_count == 1 and not scene.scoreboard.visible, "P and Tab remain editor input")
	var multiline := TextEdit.new()
	scene.add_child(multiline)
	multiline.grab_focus()
	Desktop.handle(scene, event(KEY_P))
	check(scene.pause_count == 1, "TextEdit typing does not pause")
	var spin := SpinBox.new()
	scene.add_child(spin)
	spin.get_line_edit().grab_focus()
	Desktop.handle(scene, event(KEY_TAB))
	check(not scene.scoreboard.visible, "SpinBox child preserves Tab traversal")
	Desktop.handle(scene, event(KEY_F6))
	check(scene.help_count == 1, "Function shortcuts remain available while editing")
	panel.begin_capture("jump")
	Desktop.handle(scene, event(KEY_F6))
	check(panel.is_capturing() and scene.help_count == 1, "Capture remains before editor and function shortcuts")
	Desktop.handle(scene, event(KEY_ESCAPE))
	scene.scoreboard.free()
	scene.free()
	panel.reset_preferences(false)
	check(bindings.key_for("jump") == KEY_SPACE, "Reset restores bindings")
	check(not FileAccess.file_exists(bindings.path) and not FileAccess.file_exists(preferences.path), "persist=false does not write either settings file")
	bindings.path = "/tmp/missing-tb-save-%s/bindings.cfg" % OS.get_process_id()
	panel.show()
	panel.begin_capture("jump")
	panel.capture_event(event(KEY_J))
	check("save failed" in panel.binding_status.text and bindings.key_for("jump") == KEY_J, "Capture reports failed persistence honestly")
	var dispatch_scene := FakeScene.new()
	dispatch_scene.bindings = bindings
	dispatch_scene.settings_panel = panel
	dispatch_scene.dispatch_input = true
	root.add_child(dispatch_scene)
	panel.binding_buttons.jump.grab_focus()
	panel.begin_capture("jump")
	Input.parse_input_event(event(KEY_ENTER))
	await process_frame
	var enter_release := event(KEY_ENTER)
	enter_release.pressed = false
	Input.parse_input_event(enter_release)
	await process_frame
	check(bindings.key_for("jump") == KEY_ENTER and not panel.is_capturing(), "Captured Enter does not reactivate focused GUI button")
	dispatch_scene.scoreboard.free()
	dispatch_scene.free()
	panel.free()
	var legacy_panel = panel_script.new()
	root.add_child(legacy_panel)
	legacy_panel.setup(preferences)
	legacy_panel.reset_preferences(false)
	legacy_panel.free()
	print("Input bindings tests: %d failures" % failures)
	quit(1 if failures else 0)
