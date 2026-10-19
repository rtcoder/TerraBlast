extends SceneTree
const Library = preload("res://scripts/core/storage/local_archive_library.gd")
const Replay = preload("res://scripts/core/replay/match_replay.gd")
class InterruptedLibrary extends Library:
	var writes := 0
	func _save_encoded(kind: String, title: String, encoded: Dictionary) -> Dictionary:
		writes += 1
		if writes == 2: return failure("injected_write_failure")
		return super._save_encoded(kind,title,encoded)
var failures := 0
var checks := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run")
func zip(path: String, rows: Dictionary) -> void:
	var writer := ZIPPacker.new()
	writer.open(path)
	for name in rows:
		writer.start_file(name)
		writer.write_file(str(rows[name]).to_utf8_buffer())
		writer.close_file()
	writer.close()
func run() -> void:
	if not FileAccess.file_exists("res://scripts/core/storage/archive_bundle.gd"):
		check(false,"S34 archive bundle must exist")
		quit(1)
		return
	var Bundle = load("res://scripts/core/storage/archive_bundle.gd")
	var tmp := "/private/tmp" if OS.get_name() == "macOS" else "/tmp"
	var folder := tmp.path_join("terrablast-bundle19-%s" % OS.get_process_id())
	var library := Library.new(folder.path_join("source"))
	var target := Library.new(folder.path_join("target"))
	var runner = load("res://scripts/core/rules/match_factory.gd").from_definition(load("res://scripts/core/workshop/workshop_document.gd").new().snapshot(),2)
	var recorder := Replay.new()
	recorder.capture(runner)
	recorder.tick(runner,0.25)
	var saved := library.save_replay("Zażółć replay",recorder,runner)
	var session := library.save_session("Checkpoint",runner,{"mode":"hotseat","difficulty":"normal","human_team":1})
	var path := folder.path_join("portable.zip")
	check(saved.ok and session.ok and Bundle.export_bundle(library,[saved.id,session.id],path).ok,"S34 two exact archive payloads exported")
	var before := target.list_entries()
	var inspected: Dictionary = Bundle.inspect(path)
	check(inspected.ok and inspected.entries.size() == 2 and target.list_entries() == before,"S37 inspection without writes")
	var reader := ZIPReader.new()
	reader.open(path)
	check(reader.get_files().size() == 3 and reader.file_exists("manifest.json") and reader.file_exists("entries/"+saved.id+".json"),"S36 ZIP canonical members")
	var manifest: Dictionary = JSON.parse_string(reader.read_file("manifest.json").get_string_from_utf8())
	var original_payload: Dictionary = library._read(saved.id).envelope.payload
	var imported: Dictionary = Bundle.import_bundle(target,path)
	check(imported.ok and imported.ids.size() == 2 and saved.id not in imported.ids and session.id not in imported.ids,"S40 import new IDs")
	var exact := false
	for id in imported.ids:
		var entry := target._read(id)
		if entry.envelope.metadata.kind == "replay": exact = entry.envelope.payload == original_payload and entry.envelope.metadata.title == "Zażółć replay"
	check(exact,"S40 exact payload and Unicode title preserved")
	var tampered := {"manifest.json":JSON.stringify(manifest)}
	for file in reader.get_files():
		if file != "manifest.json": tampered[file] = reader.read_file(file).get_string_from_utf8() + " "
	reader.close()
	var bad_path := folder.path_join("bad.zip")
	zip(bad_path,tampered)
	check(not Bundle.inspect(bad_path).ok and not Bundle.import_bundle(target,bad_path).ok and target.list_entries().entries.size() == 2,"S35 tampered hash whole import rejected")
	zip(bad_path,{"manifest.json":JSON.stringify(manifest),"../escape.json":"{}"})
	check(not Bundle.inspect(bad_path).ok,"S38 traversal rejected")
	zip(bad_path,{"manifest.json":JSON.stringify(manifest),"/absolute.json":"{}"})
	check(not Bundle.inspect(bad_path).ok,"S38 absolute path rejected")
	zip(bad_path,{"manifest.json":JSON.stringify(manifest),"unknown.txt":"{}"})
	check(not Bundle.inspect(bad_path).ok,"S38 unknown member rejected")
	var many := {}
	for index in 22: many["file%s" % index] = "{}"
	zip(bad_path,many)
	check(not Bundle.inspect(bad_path).ok,"S39 ZIP member count limit")
	var duplicate := ZIPPacker.new()
	duplicate.open(bad_path)
	for index in 2:
		duplicate.start_file("manifest.json")
		duplicate.write_file("{}".to_utf8_buffer())
		duplicate.close_file()
	duplicate.close()
	check(not Bundle.inspect(bad_path).ok,"S38 duplicate filenames rejected")

	var bytes := FileAccess.get_file_as_bytes(path)
	var oversized := bytes.duplicate()
	for cursor in range(bytes.size()-46):
		if bytes.decode_u32(cursor) == 0x02014b50:
			oversized.encode_u32(cursor+24,32*1024*1024+1)
			break
	var oversized_file := FileAccess.open(bad_path,FileAccess.WRITE)
	oversized_file.store_buffer(oversized)
	oversized_file.close()
	check(not Bundle.inspect(bad_path).ok,"S39 declared single inflate budget checked before decompression")
	var total_bomb := bytes.duplicate()
	for cursor in range(bytes.size()-46):
		if bytes.decode_u32(cursor) == 0x02014b50: total_bomb.encode_u32(cursor+24,31*1024*1024)
	var bomb_file := FileAccess.open(bad_path,FileAccess.WRITE)
	bomb_file.store_buffer(total_bomb)
	bomb_file.close()
	check(not Bundle.inspect(bad_path).ok,"S39 total inflate budget checked before JSON decoding")
	var interrupted := InterruptedLibrary.new(folder.path_join("interrupted"))
	check(not Bundle.import_bundle(interrupted,path).ok and interrupted.writes == 2 and DirAccess.get_files_at(interrupted.base_path).is_empty(),"S41 second write failure rolls back actual first file")
	DirAccess.remove_absolute(interrupted.base_path)
	var linked := folder.path_join("linked.zip")
	var directory := DirAccess.open(folder)
	check(directory.create_link(path,"linked.zip") == OK and not Bundle.inspect(linked).ok,"S36 symlink bundle source rejected")
	DirAccess.remove_absolute(linked)
	var existing: String = FileAccess.get_file_as_string(path)
	check(not Bundle.export_bundle(library,[saved.id],path).ok and FileAccess.get_file_as_string(path) == existing,"S36 no overwrite by default")
	check(not Bundle.export_bundle(library,[saved.id],library.base_path.path_join("bundle.zip")).ok,"S36 library outputs protected")
	var full := Library.new(folder.path_join("full"))
	DirAccess.make_dir_recursive_absolute(full.base_path)
	for index in 99:
		var filename := ("%032x" % index)+".json"
		FileAccess.open(full.base_path.path_join(filename),FileAccess.WRITE).close()
	check(not Bundle.import_bundle(full,path).ok and DirAccess.get_files_at(full.base_path).size() == 99,"S41 capacity failure no partial import")
	for destination in [library,target,full]:
		for file in DirAccess.get_files_at(destination.base_path): DirAccess.remove_absolute(destination.base_path.path_join(file))
		DirAccess.remove_absolute(destination.base_path)
	for file in [path,bad_path]: DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(folder)
	print("Archive bundle: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
