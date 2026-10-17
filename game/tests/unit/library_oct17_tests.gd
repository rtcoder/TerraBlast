extends SceneTree
const Factory = preload("res://scripts/core/rules/match_factory.gd")
const Replay = preload("res://scripts/core/replay/match_replay.gd")
var failures := 0
var temporary_root := "/private/tmp" if OS.get_name() == "macOS" else "/tmp"
var base := temporary_root.path_join("terrablast-library-test-" + str(OS.get_process_id()))
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	check(ResourceLoader.exists("res://scripts/core/storage/local_archive_library.gd"), "Local library implemented")
	if failures == 0:
		behavior()
	print("library_oct17: %d failures" % failures)
	quit(1 if failures else 0)
func behavior() -> void:
	var library = load("res://scripts/core/storage/local_archive_library.gd").new(base)
	var runner = Factory.create_match(2)
	var recorder = Replay.new()
	recorder.capture(runner)
	recorder.tick(runner, 0.12345678901234567)
	var options := {"mode":"solo","difficulty":"normal","human_team":1}
	var velocities := {"blue_1":Vector3(1.23,4.56,7.89),"red_1":Vector3.ZERO}
	var saved: Dictionary = library.save_session("Checkpoint", runner, options, velocities)
	check(saved.ok, "Save session")
	if not saved.ok: return
	var restored: Dictionary = library.load_entry(saved.id)
	check(restored.ok and restored.kind == "session" and restored.velocities == velocities and restored.options == options and Replay.state_hash(restored.runner) == Replay.state_hash(runner), "Exact state options velocities roundtrip")
	var replay: Dictionary = library.save_replay("Replay", recorder, runner)
	check(replay.ok and library.load_entry(replay.id).ok, "Verified replay roundtrip")
	check(library.list_entries().entries.size() == 2 and library.list_entries("session").entries.size() == 1, "Listing filters kinds")
	check(library.rename_entry(saved.id, "Renamed").ok and library.load_entry(saved.id).metadata.title == "Renamed", "Atomic rename preserves payload")
	for title in ["", " ", "a".repeat(49), "bad\nname", "bad\u007fname"]:
		check(not library.rename_entry(saved.id, title).ok, "Reject invalid title")
	for id in ["../escape", "", saved.id + "/other", "A".repeat(32)]:
		check(not library.load_entry(id).ok and not library.delete_entry(id).ok and not library.rename_entry(id,"Title").ok, "Reject unsafe identifier")
	var archive = load("res://scripts/core/replay/replay_archive.gd")
	var session = load("res://scripts/core/replay/session_store.gd")
	check(archive.decode(archive.encode(recorder,runner).payload).ok, "Replay dictionary codec")
	check(session.decode(session.encode(runner,options,velocities).payload).ok, "Session dictionary codec")
	var source := base.path_join("source.json")
	check(archive.save(source,recorder,runner) == OK and library.import_file("replay",source,"Imported").ok, "Import verified standalone replay")
	DirAccess.remove_absolute(source)
	var invalid := base.path_join("f".repeat(32) + ".json")
	write(invalid,"{broken")
	var listing: Dictionary = library.list_entries()
	check(not listing.ok and listing.entries.size() == 3 and listing.errors.size() == 1, "Corrupt entry surfaced alongside valid metadata")
	check(not library.load_entry("f".repeat(32)).ok, "Malformed envelope rejected")
	var file := FileAccess.open(invalid,FileAccess.WRITE)
	file.seek(32 * 1024 * 1024)
	file.store_8(0)
	file.close()
	check(library.load_entry("f".repeat(32)).reason == "file_too_large", "Bounded before parsing")
	DirAccess.remove_absolute(invalid)
	# Metadata browsing must not execute or validate replay actions.
	var replay_path: String = base.path_join(replay.id + ".json")
	var original := FileAccess.get_file_as_string(replay_path)
	var envelope: Dictionary = JSON.parse_string(original)
	envelope.payload.expected_hash = "0".repeat(64)
	write(replay_path,JSON.stringify(envelope))
	check(library.list_entries("replay").ok and not library.load_entry(replay.id).ok, "List reads metadata without simulating invalid payload")
	write(replay_path,original)
	var external := base + "-outside.json"
	write(external,"untouched")
	var linked_id := "e".repeat(32)
	var directory := DirAccess.open(base)
	check(directory.create_link(external, linked_id + ".json") == OK, "Create symlink fixture")
	check(not library.load_entry(linked_id).ok and not library.rename_entry(linked_id,"Link").ok and not library.delete_entry(linked_id).ok, "Symlink entry cannot be read changed or deleted")
	check(FileAccess.get_file_as_string(external) == "untouched", "Symlink target untouched")
	DirAccess.remove_absolute(base.path_join(linked_id + ".json"))
	DirAccess.remove_absolute(external)
	var directory_id := "d".repeat(32)
	DirAccess.make_dir_recursive_absolute(base.path_join(directory_id + ".json"))
	check(not library.delete_entry(directory_id).ok and DirAccess.dir_exists_absolute(base.path_join(directory_id + ".json")), "Delete refuses directories even with entry-shaped names")
	DirAccess.remove_absolute(base.path_join(directory_id + ".json"))
	var link_base := base + "-link"
	check(DirAccess.open(base.get_base_dir()).create_link(base,link_base.get_file()) == OK, "Create linked base fixture")
	var linked_library = load("res://scripts/core/storage/local_archive_library.gd").new(link_base)
	check(not linked_library.save_session("Unsafe",runner,options).ok and not linked_library.list_entries().ok, "Symlink base rejected")
	DirAccess.remove_absolute(link_base)
	var mismatched = Factory.create_match(2)
	check(not library.save_replay("Mismatch",recorder,mismatched).ok, "Save verifies replay hash")
	check(library.delete_entry(saved.id).ok and not library.load_entry(saved.id).ok, "Delete removes only selected entry")
	for filename in DirAccess.get_files_at(base): DirAccess.remove_absolute(base.path_join(filename))
	# Count malformed owned entries too; they cannot bypass the storage budget.
	for i in range(100): write(base.path_join("%032x.json" % i),"{}")
	check(not library.save_session("Full",runner,options).ok, "100 entry storage cap")
	for filename in DirAccess.get_files_at(base): DirAccess.remove_absolute(base.path_join(filename))
	DirAccess.remove_absolute(base)
func write(path: String, content: String) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(content)
	file.close()
